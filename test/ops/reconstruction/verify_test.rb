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
end
