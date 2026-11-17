# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"
require "nabu/ops/reconstruction/verify"

# `nabu reconstruct verify`: the probe battery against the published
# census — census diff, per-source presence, one FTS canary per live
# source, and the MCP tools' data homes on disk. In-memory catalog +
# fulltext built by the real Indexer; a temp tree for the homes.
class ReconstructionVerifyTest < Minitest::Test
  include StoreTestDB

  Verify = Nabu::Ops::Reconstruction::Verify

  def entry(slug, wired: true)
    Nabu::SourceRegistry::Entry.new(slug: slug, adapter_class_name: "TestAdapter", wired: wired,
                                    sync_policy: "manual")
  end

  def setup
    @catalog = store_test_db
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    @tmp = Dir.mktmpdir("nabu-reconstruct-verify")
    @registry = Nabu::SourceRegistry.new([entry("greek"), entry("chinese"), entry("empty"), entry("dict"),
                                          entry("offline", wired: false)])
    load_source("greek", [["urn:g:1", "grc", ["μῆνιν ἄειδε θεὰ Πηληϊάδεω Ἀχιλῆος οὐλομένην, ἣ μυρί᾽ Ἀχαιοῖς",
                                              "short"]]])
    load_source("chinese", [["urn:c:1", "lzh", ["天地玄黃宇宙洪荒日月盈昃辰宿列張寒來暑往秋收冬藏閏餘成歲律呂調陽雲騰致雨露結為霜金生麗水玉出崑岡劍號巨闕珠稱夜光"]]])
    Nabu::Store::Source.create(slug: "empty", name: "Empty", adapter_class: "TestAdapter", license_class: "open")
    dict = Nabu::Store::Source.create(slug: "dict", name: "Dict", adapter_class: "TestAdapter",
                                      license_class: "open")
    @catalog[:dictionaries].insert(source_id: dict.id, slug: "dict-lex", title: "Lex", language: "grc")
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
  end

  def teardown
    @fulltext.disconnect
    FileUtils.remove_entry(@tmp)
  end

  def load_source(slug, documents)
    source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "open")
    docs = documents.map do |urn, language, texts|
      doc = Nabu::Document.new(urn: urn, title: urn, language: language, canonical_path: "#{urn}.xml")
      texts.each_with_index do |text, i|
        doc << Nabu::Passage.new(urn: "#{urn}:#{i}", sequence: i, language: language, text: text,
                                 text_normalized: Nabu::Normalize.search_form(text, language: language))
      end
      doc
    end
    Nabu::Store::Loader.new(db: @catalog, source: source).load(docs)
  end

  def write_census(documents:, passages:, language_codes:, live_sources:)
    path = File.join(@tmp, "census.yml")
    File.write(path, YAML.dump("documents" => documents, "passages" => passages,
                               "language_codes" => language_codes, "live_sources" => live_sources))
    path
  end

  def verify(census_path: write_census(documents: 2, passages: 3, language_codes: 2, live_sources: 4),
             capabilities: { "capabilities" => {}, "layers" => {} }, homes: nil)
    Verify.new(registry: @registry, catalog: @catalog, fulltext: @fulltext, census_path: census_path,
               capabilities: capabilities, tools: { "nabu_search" => {} },
               homes: homes || Verify::Homes.new(project_root: @tmp, db_dir: File.join(@tmp, "db"),
                                                 local_dir: File.join(@tmp, "local"),
                                                 canonical_dir: File.join(@tmp, "canonical")))
  end

  def test_the_census_diff_matches_and_never_fails_unstrict
    result = verify.run

    assert_equal([["documents", 2, 2], ["passages", 3, 3], ["language_codes", 2, 2], ["live_sources", 4, 4]],
                 result.census.map { |row| [row.name, row.committed, row.live] })
    refute(result.census.any?(&:drift?))
  end

  def test_census_drift_is_reported_and_strict_fails_on_it
    result = verify(census_path: write_census(documents: 5, passages: 3, language_codes: 2,
                                              live_sources: 4)).run
    drifted = result.census.select(&:drift?)
    assert_equal ["documents"], drifted.map(&:name)
    assert_equal(-3, drifted.first.delta)
    refute result.failed?(strict: false), "drift is expected when the library moved — report, not fail"
    assert result.failed?(strict: true)
    assert_match(/documents\s+5\s+2\s+DRIFT -3/, Verify.render(result))
  end

  def test_a_missing_census_file_is_an_honest_hint
    result = verify(census_path: File.join(@tmp, "absent.yml")).run
    assert_nil result.census.first.committed
    assert_match(/no committed census/, Verify.render(result))
  end

  def test_presence_lists_live_sources_holding_nothing
    result = verify.run
    assert_equal ["empty"], result.missing_sources, "dict holds entries; offline is unwired"
  end

  def test_fts_canaries_hit_for_indexed_sources_including_cjk
    canaries = verify.run.canaries.to_h { |canary| [canary.slug, canary.status] }
    assert_equal :hit, canaries["greek"]
    assert_equal :hit, canaries["chinese"], "a spaceless run probes as a prefix term"
    assert_equal :no_documents, canaries["empty"]
  end

  def test_a_broken_index_slice_is_a_reported_miss
    greek = @catalog[:passages].where(urn: "urn:g:1:0").get(:id)
    @fulltext[:passages_fts].where(Sequel.lit("rowid") => greek).delete

    result = verify.run
    assert_equal ["greek"], result.canaries.select { |canary| canary.status == :miss }.map(&:slug)
    assert result.failed?(strict: true)
    refute result.failed?(strict: false)
    assert_match(/canary MISS.*greek/m, Verify.render(result))
  end

  def test_no_fulltext_index_is_a_whole_battery_miss_not_a_crash
    result = Verify.new(registry: @registry, catalog: @catalog, fulltext: nil,
                        census_path: write_census(documents: 2, passages: 3, language_codes: 2, live_sources: 4),
                        capabilities: { "capabilities" => {}, "layers" => {} }, tools: {},
                        homes: nil).run
    assert(result.canaries.all? { |canary| %i[no_index no_documents].include?(canary.status) })
  end

  def test_home_parsing_expands_placeholders_and_the_slash_shorthand
    assert_equal ["canonical/", []], Verify::Homes.parse("canonical/<slug>/")
    assert_equal ["db/catalog.sqlite3", %w[dictionaries dictionary_entries dictionary_citations entry_facets]],
                 Verify::Homes.parse("db/catalog.sqlite3 (dictionaries, dictionary_entries/citations, entry_facets)")
  end

  def test_a_source_of_passageless_documents_is_named_not_probed
    source = Nabu::Store::Source.create(slug: "meta", name: "Meta", adapter_class: "TestAdapter",
                                        license_class: "open")
    Nabu::Store::Document.create(source_id: source.id, urn: "urn:m:1", title: "m", language: "grc",
                                 content_sha256: "x", revision: 1, withdrawn: false)
    @registry = Nabu::SourceRegistry.new([entry("meta")])

    result = verify.run
    assert_equal [:no_passages], result.canaries.map(&:status)
    assert_match(/documents without passages: meta/, Verify.render(result))
  end

  def test_capability_homes_check_files_and_tables_per_mcp_tool
    FileUtils.mkdir_p(File.join(@tmp, "db"))
    db_path = File.join(@tmp, "db", "catalog.sqlite3")
    db = Sequel.sqlite(db_path)
    db.create_table(:documents) { primary_key :id }
    db.disconnect
    FileUtils.mkdir_p(File.join(@tmp, "canonical"))
    capabilities = {
      "capabilities" => { "search" => { "surfaces" => { "mcp" => ["nabu_search"] },
                                        "layers" => %w[catalog canonical shelf] } },
      "layers" => {
        "catalog" => { "home" => "db/catalog.sqlite3 (documents, passages)" },
        "canonical" => { "home" => "canonical/<slug>/" },
        "shelf" => { "home" => "local/shelves/local-notes/" }
      }
    }
    result = verify(capabilities: capabilities).run
    assert_equal({ "nabu_search" => ["catalog: db/catalog.sqlite3 lacks table passages",
                                     "shelf: local/shelves/local-notes/ absent"] },
                 result.capability_gaps)
    assert result.failed?(strict: true)
  end

  # --- against: the reference box's private manifest -------------------

  def phrase_of(urn)
    Verify.phrase(@catalog[:passages].first(urn: urn)[:text_search])
  end

  def manifest_source(transport, documents, passages, canary_urn = nil, phrase: nil)
    row = { "transport" => transport, "documents" => documents, "passages" => passages }
    row["canary"] = { "urn" => canary_urn, "phrase" => phrase || phrase_of(canary_urn) } if canary_urn
    row
  end

  def manifest(sources = nil)
    sources ||= { "greek" => manifest_source("carried", 1, 2, "urn:g:1:0"),
                  "chinese" => manifest_source("resynced", 1, 1, "urn:c:1:0"),
                  "empty" => manifest_source("carried", 0, 0),
                  "dict" => manifest_source("carried", 0, 0) }
    { "schema" => 1, "reference" => { "commit" => "abc1234def", "as_of" => "2026-11-10" },
      "census" => { "documents" => 2, "passages" => 3, "language_codes" => 2, "live_sources" => 4 },
      "sources" => sources, "trees" => [] }
  end

  def against(manifest_hash = manifest)
    Verify.new(registry: @registry, catalog: @catalog, fulltext: @fulltext, census_path: nil,
               capabilities: { "capabilities" => {}, "layers" => {} }, tools: { "nabu_search" => {} },
               homes: nil, against: manifest_hash).run
  end

  # A capability home absent on BOTH boxes is parity, not failure: the
  # reference records its own absent layers, and strict fails only on a
  # gap the reference did not share — otherwise a box that perfectly
  # reproduces a reference which never ran an enrichment could never go
  # strict-green.
  def test_a_capability_gap_shared_with_the_reference_is_parity_not_failure
    capabilities = { "capabilities" => { "search" => { "surfaces" => { "mcp" => ["nabu_search"] },
                                                       "layers" => %w[shelf] } },
                     "layers" => { "shelf" => { "home" => "local/shelves/local-notes/" } } }
    homes = Verify::Homes.new(project_root: @tmp, db_dir: File.join(@tmp, "db"),
                              local_dir: File.join(@tmp, "local"), canonical_dir: File.join(@tmp, "canonical"))
    run = lambda do |manifest_hash|
      Verify.new(registry: @registry, catalog: @catalog, fulltext: @fulltext, census_path: nil,
                 capabilities: capabilities, tools: { "nabu_search" => {} }, homes: homes,
                 against: manifest_hash).run
    end

    shared = run.call(manifest.merge("capability_homes" => { "absent" => ["shelf"] }))
    refute shared.failed?(strict: true), "a gap the reference shares is parity"
    assert_empty shared.capability_gaps
    assert_match(/absent on the reference too/, Verify.render(shared))

    unshared = run.call(manifest)
    assert unshared.failed?(strict: true), "a gap the reference did not share stays failure-class"
    refute_empty unshared.capability_gaps
  end

  def test_against_an_exact_carried_reference_passes_strict
    result = against
    assert_equal({ "greek" => :exact, "chinese" => :exact, "empty" => :exact, "dict" => :exact },
                 result.source_rows.to_h { |row| [row.slug, row.status] })
    assert_equal({ "greek" => :hit, "chinese" => :hit }, result.canaries.to_h { |c| [c.slug, c.status] })
    refute result.failed?(strict: true)
    card = Verify.render(result)
    assert_match(/against reference abc1234def \(as of 2026-11-10\)/, card)
    assert_match(/documents\s+2\s+2\s+=/, card, "the census diffs the manifest's census")
    assert_match(/summary: 0 failure-class finding\(s\).*0 expected drift\(s\)/, card)
  end

  def test_a_carried_count_mismatch_is_failure_class
    result = against(manifest("greek" => manifest_source("carried", 1, 5, "urn:g:1:0")))
    row = result.source_rows.first
    assert_equal :mismatch, row.status
    assert row.failure?
    refute result.failed?(strict: false)
    assert result.failed?(strict: true)
    assert_match(/greek\s+carried\s+documents 1 → 1 =, passages 5 → 2 MISMATCH -3/, Verify.render(result))
  end

  def test_resynced_drift_passes_strict_and_renders_the_delta
    result = against(manifest("greek" => manifest_source("resynced", 3, 2, "urn:g:1:0"),
                              "chinese" => manifest_source("resynced", 1, 1, "urn:c:1:0")))
    assert_equal :drift, result.source_rows.first.status
    refute result.failed?(strict: true), "upstream moved since the stamp — expected, never a strict failure"
    card = Verify.render(result)
    assert_match(/greek\s+resynced\s+documents 3 → 1 drift -2, passages 2 → 2 =/, card)
    assert_match(/summary: 0 failure-class finding\(s\).*1 expected drift\(s\)/, card)
  end

  def test_canaries_resolve_the_urn_to_the_targets_own_passage
    # The chinese phrase does occur in the index — but on another passage.
    # Pinned to greek's own passage id, it must miss.
    result = against(manifest("greek" => manifest_source("carried", 1, 2, "urn:g:1:0",
                                                         phrase: phrase_of("urn:c:1:0"))))
    canary = result.canaries.first
    assert_equal :miss, canary.status
    assert result.failed?(strict: true), "a carried canary miss is failure-class"
    assert_match(/canary MISS \(carried — failure\): greek urn:g:1:0/, Verify.render(result))
  end

  def test_canaries_probe_by_the_targets_rowid_not_the_references
    @catalog[:passages].where(urn: "urn:g:1:0").update(id: 9001)
    @fulltext[:passages_fts].delete
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    manifest_hash = manifest("greek" => manifest_source("carried", 1, 2, "urn:g:1:0").tap do |row|
      row["canary"]["id"] = 1 # a reference box's rowid travelling along is never trusted
    end)
    assert_equal :hit, against(manifest_hash).canaries.first.status
  end

  def test_an_absent_urn_is_its_own_status
    result = against(manifest("greek" => manifest_source("carried", 1, 2).merge(
      "canary" => { "urn" => "urn:g:gone", "phrase" => "\"a b c d\"" }
    )))
    assert_equal :absent, result.canaries.first.status
    assert result.failed?(strict: true)
    assert_match(/canary ABSENT \(carried — failure\): greek urn:g:gone/, Verify.render(result))
  end

  def test_a_resynced_canary_miss_is_reported_drift_not_failure
    result = against(manifest("chinese" => manifest_source("resynced", 1, 1, "urn:c:1:0",
                                                           phrase: phrase_of("urn:g:1:0"))))
    assert_equal :miss, result.canaries.first.status
    refute result.failed?(strict: true)
    card = Verify.render(result)
    assert_match(/canary MISS \(resynced — drift\): chinese urn:c:1:0/, card)
    assert_match(/summary: 0 failure-class finding\(s\).*1 expected drift\(s\)/, card)
  end

  def test_missing_sources_fail_and_new_sources_inform
    result = against(manifest("greek" => manifest_source("carried", 1, 2, "urn:g:1:0"),
                              "vanished" => manifest_source("resynced", 4, 9, "urn:v:1:0", phrase: "\"x\"")))
    assert_equal :missing, result.source_rows.find { |row| row.slug == "vanished" }.status
    assert_equal %w[chinese dict empty], result.new_sources.sort
    assert_equal ["greek"], result.canaries.map(&:slug), "a missing source probes no canary"
    assert result.failed?(strict: true), "a missing source fails even when resynced"
    card = Verify.render(result)
    assert_match(/vanished\s+resynced\s+missing/, card)
    assert_match(/new since the reference: chinese, dict, empty/, card)
  end

  def test_against_mode_does_not_fail_strict_on_census_drift_or_empty_presence
    hash = manifest
    hash["census"]["documents"] = 99
    result = against(hash)
    assert(result.census.any?(&:drift?))
    assert_equal ["empty"], result.missing_sources
    refute result.failed?(strict: true)
  end

  def test_manifest_loading_rejects_other_schemas
    path = File.join(@tmp, "manifest.yml")
    File.write(path, YAML.dump(manifest.merge("schema" => 2)))
    error = assert_raises(Verify::ManifestError) { Verify.load_manifest(path) }
    assert_match(/schema 2.*expects schema 1/, error.message)

    File.write(path, YAML.dump(manifest))
    assert_equal "abc1234def", Verify.load_manifest(path).dig("reference", "commit")
    assert_raises(Verify::ManifestError) { Verify.load_manifest(File.join(@tmp, "absent.yml")) }
  end
end
