# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Ops::BuilderRefresh (P104): the standalone corpus-wide builder pass —
# timeline, facet, kind — over a LIVE catalog, in rebuild's own order
# and with rebuild's own arguments. Exists because rebuilds are
# owner-fired inter-phase steps (owner rule 2026-09-26): a phase whose
# changes are builder-side (facet_map/kind_map rules, timeline lanes)
# refreshes projections through THIS seam, never by firing a rebuild.
class BuilderRefreshTest < Minitest::Test
  include StoreTestDB

  # Shipped config maps + an EMPTY canonical tree: the projections under
  # test are catalog-side (facet_map/kind rules over metadata_json); the
  # canonical-backed walks (KR-Catalog, nabu-places, hiero cone) are the
  # rebuild suite's business and only cost minutes here.
  HybridConfig = Struct.new(:config_dir, :canonical_dir, :fulltext_path, keyword_init: true) do
    # The local shelves resolve beside the empty canonical tree (the
    # silver-date replay asks for local-dates).
    def source_workdir(slug) = File.join(canonical_dir, "shelves", slug)
    def artifact_scripts_path = File.join(config_dir, "artifact_scripts.yml")
  end

  # No fulltext file: the lemma rollup honestly stays empty, the
  # catalog-only rollups (language mix/curve) still project.
  def hybrid_config(dir)
    HybridConfig.new(config_dir: File.expand_path("../../config", __dir__),
                     canonical_dir: dir, fulltext_path: File.join(dir, "fulltext.sqlite3"))
  end

  def setup
    @catalog = store_test_db
    @source = Nabu::Store::Source.create(
      slug: "seal", name: "SEAL", adapter_class: "X", license: "x",
      license_class: "attribution", upstream_url: "x", enabled: true
    )
    @doc = Nabu::Store::Document.create(
      source_id: @source.id, urn: "urn:nabu:seal:1", title: "t",
      language: "akk", canonical_path: "x", content_sha256: "0" * 64,
      metadata_json: JSON.generate("genre" => "hymn", "period" => "Old Babylonian",
                                   "collection" => "CDLI", "provenance" => "Nippur")
    )
  end

  def test_refresh_runs_all_three_builders_and_reports
    # A REAL reporter, not nil: builder tick calls must honor the
    # ProgressReporter arity contract (the first live run caught a
    # one-string tick that nil-progress tests let through).
    reporter = Nabu::ProgressReporter.new(on_stage: ->(_l, _e = nil) {},
                                          on_load_tick: ->(_p, _e) {})
    summary = Dir.mktmpdir do |dir|
      Nabu::Ops::BuilderRefresh.run(catalog: @catalog, config: hybrid_config(dir),
                                    progress: reporter)
    end
    facets = @catalog[:document_facets].where(document_id: @doc.id).select_map(:facet)
    assert_includes facets, "genre", "the facet_map projection ran"
    assert_operator summary.facets.rows, :>=, 1
    refute_nil summary.timeline
    refute_nil summary.kinds
    refute_nil summary.passage_facets, "the passage-grain facet lane rides the refresh"
    refute_nil summary.entry_facets, "the dictionary-entry facet lane rides the refresh"
  end

  # The passage-grain lane re-projects under the shipped passage_fields
  # (sillok's subject classes) like the document lane does.
  def test_refresh_projects_passage_facets
    sillok = Nabu::Store::Source.create(slug: "sillok", name: "Sillok", adapter_class: "X", license: "x",
                                        license_class: "attribution", upstream_url: "x", enabled: true)
    doc = Nabu::Store::Document.create(source_id: sillok.id, urn: "urn:nabu:sillok:waa_001", title: "t",
                                       language: "lzh", canonical_path: "x", content_sha256: "1" * 64)
    Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:nabu:sillok:waa_001:1", sequence: 1,
                                language: "lzh", text: "t", text_normalized: "t", content_sha256: "x",
                                revision: 1, annotations_json: JSON.generate("subject_classes" => ["인물(人物)"]))
    summary = Dir.mktmpdir do |dir|
      Nabu::Ops::BuilderRefresh.run(catalog: @catalog, config: hybrid_config(dir))
    end
    assert_equal 1, summary.passage_facets.rows
    assert_equal [%w[subject 인물(人物)]], @catalog[:passage_facet_values].select_map(%i[facet value])
  end

  # The dictionary-entry lane re-projects under the shipped entry_fields
  # (JMdict's domain labels) the same way.
  def test_refresh_projects_entry_facets
    edrdg = Nabu::Store::Source.create(slug: "edrdg", name: "EDRDG", adapter_class: "X", license: "x",
                                       license_class: "attribution", upstream_url: "x", enabled: true)
    jmdict = Nabu::Store::Dictionary.create(source_id: edrdg.id, slug: "jmdict", title: "JMdict", language: "jpn")
    Nabu::Store::DictionaryEntry.create(dictionary_id: jmdict.id, urn: "urn:nabu:dict:jmdict:1", entry_id: "1",
                                        key_raw: "1", headword: "仏", headword_folded: "仏", body: "b",
                                        content_sha256: "x", annotations_json: JSON.generate("field" => ["Buddhism"]))
    summary = Dir.mktmpdir do |dir|
      Nabu::Ops::BuilderRefresh.run(catalog: @catalog, config: hybrid_config(dir))
    end
    assert_equal 1, summary.entry_facets.rows
    assert_equal [%w[domain Buddhism]], @catalog[:entry_facet_values].select_map(%i[facet value])
  end

  # P121-2: the lemma attestation rollups ride the refresh (last, after
  # the timeline they bucket by).
  def test_refresh_rebuilds_the_lemma_rollups
    Nabu::Store::Passage.create(document_id: @doc.id, urn: "urn:nabu:seal:1:1", sequence: 1,
                                language: "akk", text: "t", text_normalized: "t", content_sha256: "x")
    summary = Dir.mktmpdir { |dir| Nabu::Ops::BuilderRefresh.run(catalog: @catalog, config: hybrid_config(dir)) }
    assert_equal 1, summary.lemma_rollups.mix_rows
    assert_equal 0, summary.lemma_rollups.lemma_rows, "no fulltext file: the honest empty lemma rollup"
    assert_equal "akk", @catalog[:language_mix].where(document_id: @doc.id).get(:languages)
  end

  # The artifact-script lane rides the refresh (the replay-hole fix,
  # 2026-10-13): the timeline builder drops EVERY axis row, and before
  # this the refresh never re-derived the artifact-script rows — only a
  # full rebuild restored them. The shipped config maps elephantine's
  # phn documents to the Phoenician artifact script.
  def test_refresh_rederives_the_artifact_script_lane
    source = Nabu::Store::Source.create(
      slug: "elephantine", name: "Elephantine", adapter_class: "X", license: "x",
      license_class: "open", upstream_url: "x", enabled: true
    )
    doc = Nabu::Store::Document.create(
      source_id: source.id, urn: "urn:nabu:elephantine:1", title: "t",
      language: "phn", canonical_path: "x", content_sha256: "1" * 64
    )
    Dir.mktmpdir { |dir| Nabu::Ops::BuilderRefresh.run(catalog: @catalog, config: hybrid_config(dir)) }
    row = @catalog[:document_axes].where(document_id: doc.id, axis_source: "artifact-script").first
    refute_nil row, "the refresh must re-derive the artifact-script axis lane the timeline drop removed"
  end

  # P122-1: the timeline builder drops every axis row — an ARMED
  # silver-date shelf re-projects behind it; an unarmed one stays out.
  def test_refresh_replays_the_armed_silver_date_lane
    Dir.mktmpdir do |dir|
      config = hybrid_config(dir)
      shelf = Nabu::DateShelf.new(dir: config.source_workdir(Nabu::DateShelf::SLUG))
      shelf.append_batch!(records: [Nabu::DateShelf::Record.new(
        urn: "urn:nabu:seal:1", not_before: -1800, not_after: -1700, basis: "model",
        estimator: "chronos", estimator_version: "0.3", confidence: nil, note: nil, generated_at: nil
      )])
      silver = -> { @catalog[:document_axes].where(axis_source: Nabu::Store::SilverDates::AXIS_SOURCE).count }

      Nabu::Ops::BuilderRefresh.run(catalog: @catalog, config: config)
      assert_equal 0, silver.call, "an unarmed shelf never reaches the timeline"

      shelf.arm!
      2.times { Nabu::Ops::BuilderRefresh.run(catalog: @catalog, config: config) }
      assert_equal 1, silver.call, "the armed lane survives the timeline's drop, once"
    end
  end

  # The AES ← AED title join rides the refresh beside the derge titles
  # (a cross-source post-load pass: f(canonical/aed + loaded aes rows)).
  def test_refresh_titles_aes_documents_from_the_aed_headers
    source = Nabu::Store::Source.create(
      slug: "aes", name: "AES", adapter_class: "X", license: "x",
      license_class: "attribution", upstream_url: "x", enabled: true
    )
    doc = Nabu::Store::Document.create(
      source_id: source.id, urn: "urn:nabu:aes:bbawarchive:26BP5JT5RZEDHDDU2R5TMUBD24",
      language: "egy", canonical_path: "x", content_sha256: "2" * 64
    )
    summary = Dir.mktmpdir do |dir|
      File.symlink(File.join(Nabu::TestSupport::FIXTURES_ROOT, "aes", "aed"), File.join(dir, "aed"))
      Nabu::Ops::BuilderRefresh.run(catalog: @catalog, config: hybrid_config(dir))
    end
    assert_equal "pBerlin P 21002 verso (99 E)", @catalog[:documents].where(id: doc.id).get(:title)
    assert_equal 1, summary.aes_titles.titled
  end

  # The honkoku <- NDL catalog join runs FIRST, so the same refresh
  # projects the record it writes: author/subject facets + a dated row.
  def test_refresh_joins_the_ndl_catalog_record_before_projecting_it
    source = Nabu::Store::Source.create(
      slug: "honkoku", name: "honkoku", adapter_class: "X", license: "x",
      license_class: "attribution", upstream_url: "x", enabled: true
    )
    doc = Nabu::Store::Document.create(
      source_id: source.id, urn: "urn:nabu:honkoku:p:m", language: "jpn", canonical_path: "x",
      content_sha256: "3" * 64,
      metadata_json: JSON.generate("manifest" => "https://dl.ndl.go.jp/api/iiif/2532153/manifest.json")
    )
    summary = Dir.mktmpdir do |dir|
      File.symlink(File.join(Nabu::TestSupport::FIXTURES_ROOT, "ndl-kotenseki"), File.join(dir, "ndl-kotenseki"))
      Nabu::Ops::BuilderRefresh.run(catalog: @catalog, config: hybrid_config(dir))
    end
    assert_equal 1, summary.honkoku_ndl.joined
    assert_equal %w[倭玉篇 辞書],
                 @catalog[:document_facets].where(document_id: doc.id,
                                                  facet: "subject").order(:value).select_map(:value)
    assert_equal [1605, 1605], @catalog[:document_axes].where(document_id: doc.id).get(%i[not_before not_after])
  end

  def test_refresh_is_reprojection_not_accretion
    Dir.mktmpdir do |dir|
      config = hybrid_config(dir)
      Nabu::Ops::BuilderRefresh.run(catalog: @catalog, config: config)
      first = @catalog[:document_facets].count
      Nabu::Ops::BuilderRefresh.run(catalog: @catalog, config: config)
      assert_equal first, @catalog[:document_facets].count, "re-running never accretes"
    end
  end
end
