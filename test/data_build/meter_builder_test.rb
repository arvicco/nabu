# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"
require "digest"

# The grc/meter builder (P52-2) — the flagship fold-in dataset: Hypotactic's
# Greek scansions (CC BY 4.0) published as rows citable at urn:cts:greekLit
# grain. The load-bearing design rule under test: Primary_Text is ALWAYS the
# Greek line from Hypotactic's own TSV bytes, never the Perseus/First1K
# passage bytes (those corpora are CC BY-SA — embedding their text would
# contaminate this CC BY dataset; anchoring is URN + Passage_SHA256 only).
#
# Fixture facts (hand-censused 2026-07-29 from the real fixtures):
#   tsv/HHAphrodite.tsv — 293 lines (the whole hymn, verbatim);
#   tsv/iliad1.tsv — 10 lines (upstream rows 12-16 + 371-375; rows 7-10
#   repeat rows 2-5 byte-for-byte — the formulaic-repetition dedup case).
#   Seeded held passages: hymn lines 1, 2 (Perseus-spelled variant), 9 under
#   perseus-greek + line 3 under a first1k-greek edition, plus the six
#   distinct iliad lines → 14 matched lines, 10 anchored passages,
#   289 unmatched, 2 mapped works.
#   WORK_MAP crosswalk: 79 filenames → 86 (filename, work) pairs
#   (nicander spans 2 works, callimachusHymns 6, callimachusEp 2).
class DataBuildMeterBuilderTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("hypotactic")

  COLUMNS = %w[ID URN Passage_SHA256 Primary_Text Meter Pattern Caesura Tier Source].freeze

  HYMN_URN = "urn:cts:greekLit:tlg0013.tlg005.perseus-grc2"
  HYMN_1K_URN = "urn:cts:greekLit:tlg0013.tlg005.1st1K-grc1"
  ILIAD_URN = "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2"

  # Real HHAphrodite lines, VERBATIM from the fixture TSV (hand-pinned).
  L1 = "μοῦσά μοι ἔννεπε ἔργα πολυχρύσου Ἀφροδίτης,"
  L2 = "Κύπριδος, ἥτε θεοῖσιν ἐπὶ γλυκὺν ἵμερον ὦρσε"
  L3 = "καί τ᾽ἐδαμάσσατο φῦλα καταθνητῶν ἀνθρώπων"
  L9 = "οὐ γὰρ οἱ εὔαδεν ἔργα πολυχρύσου Ἀφροδίτης,"
  # Perseus spells line 2 with a final ano teleia — DIFFERENT bytes than the
  # TSV, same folded text: the provenance pin's tell.
  PERSEUS_L2 = "Κύπριδος, ἥτε θεοῖσιν ἐπὶ γλυκὺν ἵμερον ὦρσε·"

  LINES_READ = 303
  MATCHED_LINES = 14
  UNMATCHED_LINES = 289
  ANCHORED_PASSAGES = 10
  CROSSWALK_FILENAMES = 79
  CROSSWALK_PAIRS = 86

  # The fixture-canonical builder: the production default resolves
  # canonical_dir from the box config; tests inject the rigged tree (the
  # segmentation TestSliceBuilder precedent — the constructor seam exists
  # exactly for this).
  class TestMeterBuilder < Nabu::DataBuild::MeterBuilder
    class << self
      attr_accessor :canonical_dir
    end

    def initialize
      super(canonical_dir: self.class.canonical_dir)
    end
  end

  # -- rig -------------------------------------------------------------------

  def sources_yml
    <<~YAML
      hypotactic:
        adapter: Nabu::Adapters::Hypotactic
        kind: module
        wired: false
        sync_policy: manual
      perseus-greek:
        adapter: Nabu::Adapters::Perseus
        wired: true
        sync_policy: manual
      first1k-greek:
        adapter: Nabu::Adapters::First1kGreek
        wired: true
        sync_policy: manual
    YAML
  end

  def with_build_env
    Dir.mktmpdir("nabu-meter") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      FileUtils.cp_r(FIXTURES, File.join(canonical, "hypotactic"))
      # The anchor corpora cones: content-identity stand-ins (the guard
      # compares identity strings, not passage bytes).
      %w[perseus-greek first1k-greek].each do |slug|
        FileUtils.mkdir_p(File.join(canonical, slug))
        File.write(File.join(canonical, slug, "MARKER"), "#{slug} canonical stand-in\n")
      end
      sources = File.join(root, "sources.yml")
      File.write(sources, sources_yml)
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      catalog = store_test_db
      seed_catalog!(catalog, canonical)
      TestMeterBuilder.canonical_dir = canonical
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources),
                                           catalog: catalog)
      yield root, runner, catalog, canonical
    ensure
      TestMeterBuilder.canonical_dir = nil
    end
  end

  # Sources with recorded ingest identities + Perseus/First1K-shaped grc
  # passages (the hypotactic_meter_test rig, with real content shas).
  def seed_catalog!(catalog, canonical)
    hypotactic = create_source!(slug: "hypotactic", adapter: "Nabu::Adapters::Hypotactic")
    perseus = create_source!(slug: "perseus-greek", adapter: "Nabu::Adapters::Perseus")
    first1k = create_source!(slug: "first1k-greek", adapter: "Nabu::Adapters::First1kGreek")

    seed_work!(perseus, HYMN_URN, hymn_passages, title: "Hymn 5 To Aphrodite")
    seed_work!(first1k, HYMN_1K_URN, { "#{HYMN_1K_URN}:3" => L3 }, title: "Hymn 5 To Aphrodite")
    seed_work!(perseus, ILIAD_URN, iliad_passages, title: "Iliad")

    { hypotactic => "hypotactic", perseus => "perseus-greek", first1k => "first1k-greek" }
      .each do |source, slug|
      identity = Nabu::DerivationFingerprint.canonical_identity(File.join(canonical, slug))
      source.update(last_ingest_identity: identity)
    end
    catalog
  end

  def create_source!(slug:, adapter:)
    Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: adapter,
                               license_class: "attribution")
  end

  def hymn_passages
    { "#{HYMN_URN}:1" => L1, "#{HYMN_URN}:2" => PERSEUS_L2, "#{HYMN_URN}:9" => L9,
      "#{HYMN_URN}:999" => "οὐδέν τι τοιοῦτον" }
  end

  # The iliad1 fixture's six DISTINCT lines (rows 7-10 repeat rows 2-5).
  def iliad_passages
    lines = File.readlines(File.join(FIXTURES, "tsv", "iliad1.tsv"), encoding: "UTF-8")
                .map { |line| line.split("\t").first }
    %w[1.12 1.13 1.14 1.15 1.16 1.371].zip(lines[0..5])
                                      .to_h { |citation, text| ["#{ILIAD_URN}:#{citation}", text] }
  end

  def seed_work!(source, doc_urn, passages, title:)
    doc = Nabu::Store::Document.create(source_id: source.id, urn: doc_urn, title: title,
                                       language: "grc", metadata_json: "{}",
                                       content_sha256: Digest::SHA256.hexdigest(doc_urn),
                                       revision: 1, withdrawn: false)
    passages.each_with_index do |(urn, text), i|
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: urn, sequence: i, language: "grc",
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: "grc"),
        content_sha256: Digest::SHA256.hexdigest(text), revision: 1, withdrawn: false
      )
    end
  end

  # The registry feature with the builder swapped for the fixture rig.
  def test_feature
    real = Nabu::DataBuild.feature("grc/meter")
    Nabu::DataBuild::Feature.new(
      slug: real.slug, language: real.language, title: real.title, status: :available,
      tier: real.tier, anchoring: real.anchoring, inputs: real.inputs,
      canonical_cones: real.canonical_cones, rationale: real.rationale,
      maintenance: real.maintenance, builder: TestMeterBuilder
    )
  end

  def build!(root, runner, into: File.join(root, "nabu-data"))
    summary = runner.run(feature: test_feature, into: into)
    [summary, summary.out_dir]
  end

  def read_csv(dir, name = "meter.csv")
    CSV.read(File.join(dir, name), headers: true)
  end

  def read_manifest(dir)
    JSON.parse(File.read(File.join(dir, "datapackage.json")))
  end

  # -- the registry flip -----------------------------------------------------

  def test_the_feature_is_available_with_the_builder_wired
    feature = Nabu::DataBuild.feature("grc/meter")
    assert feature.available?, "P52-2 lands grc/meter :available"
    assert_equal Nabu::DataBuild::MeterBuilder, feature.builder
    assert_equal "gold-derived", feature.tier
    assert_equal "passage-urn", feature.anchoring
    assert_equal %w[hypotactic perseus-greek first1k-greek], feature.inputs,
                 "anchors point INTO the greekLit corpora — their ingest state is a real input"
    assert_equal feature.inputs, feature.canonical_cones
  end

  # -- the anchored rows -----------------------------------------------------

  def test_meter_rows_anchor_scansions_to_held_passages
    with_build_env do |root, runner, catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir)

      assert_equal COLUMNS, table.headers
      assert_equal ANCHORED_PASSAGES, table.size, "one row per anchored passage (hand-censused 10)"
      assert(table.all? { |row| row["Tier"] == "gold-derived" })
      assert(table.all? { |row| row["Source"] == "hypotactic" })

      shas = catalog[:passages].select_hash(:urn, :content_sha256)
      table.each do |row|
        assert_equal shas.fetch(row["URN"]), row["Passage_SHA256"],
                     "#{row['URN']}: Passage_SHA256 must be the catalog passage's content sha"
      end

      l1 = table.find { |row| row["URN"] == "#{HYMN_URN}:1" }
      refute_nil l1
      assert_equal L1, l1["Primary_Text"]
      assert_equal "dactylic hexameter", l1["Meter"]
      assert_equal "-u u -uu -u u--- uu--", l1["Pattern"]
      assert_equal "feminine penthemimeral", l1["Caesura"]

      # Line 9 is the lyric line with an EMPTY caesura column — an honest
      # empty cell, never an invented value.
      l9 = table.find { |row| row["URN"] == "#{HYMN_URN}:9" }
      assert_equal "lyric", l9["Meter"]
      assert_equal "", l9["Caesura"].to_s, "the lyric line's caesura is an honest empty cell"

      # The unscanned held passage gets NO row.
      assert_nil(table.find { |row| row["URN"] == "#{HYMN_URN}:999" })
    end
  end

  def test_primary_text_is_hypotactic_bytes_never_perseus
    with_build_env do |root, runner, catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir)

      # The tell: Perseus spells line 2 with a trailing ano teleia; the match
      # is by fold, so the two byte strings DIFFER — and the published text
      # must be the TSV's, while the sha still names the Perseus bytes.
      row = table.find { |r| r["URN"] == "#{HYMN_URN}:2" }
      refute_nil row, "the differently-punctuated Perseus line still anchors (fold match)"
      assert_equal L2, row["Primary_Text"], "Primary_Text is Hypotactic's TSV line, byte for byte"
      catalog_text = catalog[:passages].where(urn: "#{HYMN_URN}:2").get(:text)
      assert_equal PERSEUS_L2, catalog_text
      refute_equal catalog_text, row["Primary_Text"],
                   "the CC BY-SA Perseus bytes must never enter the CC BY dataset"
      assert_equal Digest::SHA256.hexdigest(PERSEUS_L2), row["Passage_SHA256"],
                   "the anchor still names the exact Perseus passage bytes"

      # The provenance sweep: EVERY published text is a verbatim TSV line.
      tsv_lines = Dir.glob(File.join(FIXTURES, "tsv", "*.tsv")).flat_map do |path|
        Nabu::HypotacticMeter.parse_tsv(path).map { |line| line[:text] }
      end.to_set
      table.each do |r|
        assert_includes tsv_lines, r["Primary_Text"],
                        "#{r['URN']}: Primary_Text must come from the hypotactic TSV bytes"
      end
    end
  end

  def test_a_first1k_edition_is_a_first_class_anchor_target
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      row = read_csv(out_dir).find { |r| r["URN"] == "#{HYMN_1K_URN}:3" }
      refute_nil row, "greekLit anchors span perseus-greek AND first1k-greek editions"
      assert_equal L3, row["Primary_Text"]
    end
  end

  def test_repeated_formulaic_lines_dedupe_to_one_row_per_passage
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir)

      iliad = table.select { |row| row["URN"].start_with?("#{ILIAD_URN}:") }
      assert_equal 6, iliad.size, "10 fixture lines resolve onto 6 passages — one row each"
      assert_equal(1, iliad.count { |row| row["URN"] == "#{ILIAD_URN}:1.13" })

      eval_block = read_manifest(out_dir).dig("nabu", "eval")
      assert_equal MATCHED_LINES, eval_block.fetch("matched_lines"),
                   "a repeated line still COUNTS as matched — only the row dedupes"
    end
  end

  # -- IDs / PK honesty ------------------------------------------------------

  def test_ids_are_unique_and_the_primary_keys_are_honest
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir)
      ids = table.map { |row| row["ID"] }
      assert_equal ids.size, ids.uniq.size
      assert(ids.all? { |id| id.match?(Nabu::DataBuild::CsvWriter::ID_PATTERN) })

      manifest = read_manifest(out_dir)
      meter = manifest["resources"].find { |resource| resource["name"] == "meter" }
      assert_equal ["ID"], meter.dig("schema", "primaryKey")
      works = manifest["resources"].find { |resource| resource["name"] == "works" }
      assert_equal %w[Filename Work], works.dig("schema", "primaryKey")
    end
  end

  # -- the crosswalk sidecar -------------------------------------------------

  def test_works_csv_publishes_the_filename_to_cts_crosswalk
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      works = read_csv(out_dir, "works.csv")

      assert_equal %w[ID Filename Work URN_Prefix Source], works.headers
      assert_equal CROSSWALK_PAIRS, works.size, "86 (filename, work) pairs (hand-censused)"
      assert_equal CROSSWALK_FILENAMES, works.map { |row| row["Filename"] }.uniq.size

      iliad7 = works.find { |row| row["Filename"] == "iliad7" }
      assert_equal "tlg0012.tlg001", iliad7["Work"]
      assert_equal "urn:cts:greekLit:tlg0012.tlg001.", iliad7["URN_Prefix"]

      nicander = works.select { |row| row["Filename"] == "nicander" }
      assert_equal %w[tlg0022.tlg001 tlg0022.tlg002], nicander.map { |row| row["Work"] }.sort,
                   "one TSV spanning two held works publishes two pairs"

      hhymns = works.find { |row| row["Filename"] == "HHymns" }
      assert_equal "tlg0013", hhymns["Work"]
      assert_equal "urn:cts:greekLit:tlg0013.", hhymns["URN_Prefix"],
                   "a textgroup entry resolves at textgroup grain — the prefix documents it"
    end
  end

  # -- the eval census -------------------------------------------------------

  def test_the_manifest_publishes_the_resolution_census_in_band
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      manifest = read_manifest(out_dir)

      eval_block = manifest.dig("nabu", "eval")
      refute_nil eval_block, "the matched/unmatched census is the honesty stat — it rides the manifest"
      assert_equal 2, eval_block.fetch("files")
      assert_equal LINES_READ, eval_block.fetch("lines_read")
      assert_equal MATCHED_LINES, eval_block.fetch("matched_lines")
      assert_equal UNMATCHED_LINES, eval_block.fetch("unmatched_lines")
      assert_in_delta MATCHED_LINES.to_f / LINES_READ, eval_block.fetch("match_rate"), 0.0001
      assert_equal 2, eval_block.fetch("mapped_works")
      assert_equal 0, eval_block.fetch("unmapped_works")
      assert_equal ANCHORED_PASSAGES, eval_block.fetch("passages")
      assert_equal [], eval_block.fetch("malformed_files")
      assert_match(/folded-text/, eval_block.fetch("against"))

      readme = File.read(File.join(out_dir, "README.md"))
      assert_includes readme, MATCHED_LINES.to_s
      assert_includes readme, UNMATCHED_LINES.to_s
      assert_match(/Passage_SHA256/, readme, "the README states the anchoring contract")
      assert_match(/CC BY-SA/, readme, "the README states why no Perseus text is embedded")
    end
  end

  def test_the_manifest_declares_the_inputs_and_dataset_license_honestly
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      manifest = read_manifest(out_dir)

      assert_equal [{ "name" => "CC-BY-4.0",
                      "path" => "https://creativecommons.org/licenses/by/4.0/" }],
                   manifest["licenses"]
      inputs = manifest.dig("nabu", "derivation", "inputs")
      assert_equal %w[first1k-greek hypotactic perseus-greek], inputs.keys.sort
      titles = manifest["sources"].map { |source| source["title"] }
      assert(titles.any? { |title| title.include?("Hypotactic") })
      assert(titles.any? { |title| title.include?("Perseus") })
      by_sa = manifest["sources"].select { |source| source.dig("licenses", 0, "name").to_s.include?("BY-SA") }
      assert_equal 2, by_sa.size, "the two anchor corpora declare their BY-SA license openly"

      languages = read_csv(out_dir, "languages.csv")
      assert_equal([%w[grc anci1242]], languages.map { |row| row.values_at("ID", "Glottocode") })

      recipe = manifest.dig("nabu", "derivation", "recipe")
      %w[folded-text Primary_Text CC-BY-SA works.csv].each do |claim|
        assert_includes recipe, claim, "the recipe states the derivation and the provenance rule"
      end
    end
  end

  def test_building_twice_is_byte_identical
    with_build_env do |root, runner, _catalog|
      _summary, first_dir = build!(root, runner, into: File.join(root, "first"))
      _summary, second_dir = build!(root, runner, into: File.join(root, "second"))
      files = Dir.children(first_dir).sort
      assert_equal files, Dir.children(second_dir).sort
      files.each do |name|
        assert_equal File.binread(File.join(first_dir, name)), File.binread(File.join(second_dir, name)),
                     "#{name} must be byte-identical across rebuilds"
      end
    end
  end

  # -- census at the builder grain (malformed + unmapped files) ---------------

  def test_malformed_and_unmapped_files_are_censused_never_fatal
    Dir.mktmpdir("nabu-meter-census") do |root|
      canonical = File.join(root, "canonical")
      tsv = File.join(canonical, "hypotactic", "tsv")
      FileUtils.mkdir_p(tsv)
      FileUtils.cp(File.join(FIXTURES, "tsv", "HHAphrodite.tsv"), tsv)
      File.write(File.join(tsv, "Broken.tsv"), "onecol\tscansion\tmeter\n")
      File.write(File.join(tsv, "HHDionysus.tsv"),
                 "τάδε\t-u\tdactylic hexameter\t\nκαί\t-u\tlyric\t\n")

      catalog = store_test_db
      perseus = create_source!(slug: "perseus-greek", adapter: "Nabu::Adapters::Perseus")
      seed_work!(perseus, HYMN_URN, { "#{HYMN_URN}:1" => L1 }, title: "Hymn 5 To Aphrodite")

      out_dir = File.join(root, "out")
      FileUtils.mkdir_p(out_dir)
      result = Nabu::DataBuild::MeterBuilder.new(canonical_dir: canonical)
                                            .build(catalog: catalog, out_dir: out_dir)
      assert_equal ["Broken.tsv"], result.evaluation.fetch("malformed_files"),
                   "an unparseable file is censused BY NAME, never fatal to the batch"
      assert_equal 1, result.evaluation.fetch("unmapped_works"),
                   "a TSV with no crosswalk entry censuses as an unmapped work"
      assert_equal 1, result.evaluation.fetch("matched_lines")
      assert_equal 295, result.evaluation.fetch("lines_read"), "293 hymn + 2 unmapped lines"
    end
  end

  # -- refusals --------------------------------------------------------------

  def test_the_builder_refuses_without_a_catalog
    Dir.mktmpdir("nabu-meter") do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::MeterBuilder.new(canonical_dir: dir).build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
      assert_empty Dir.children(dir), "a refusal must write nothing"
    end
  end

  def test_the_builder_refuses_a_missing_scansion_tree
    Dir.mktmpdir("nabu-meter") do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::MeterBuilder.new(canonical_dir: File.join(dir, "canonical"))
                                     .build(catalog: store_test_db, out_dir: dir)
      end
      assert_match(/sync hypotactic/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_the_builder_refuses_when_nothing_anchors
    Dir.mktmpdir("nabu-meter") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      FileUtils.cp_r(FIXTURES, File.join(canonical, "hypotactic"))
      out_dir = File.join(root, "out")
      FileUtils.mkdir_p(out_dir)
      error = assert_raises(Nabu::DataBuild::Error) do
        # an empty catalog: no greekLit passage can anchor a single line
        Nabu::DataBuild::MeterBuilder.new(canonical_dir: canonical)
                                     .build(catalog: store_test_db, out_dir: out_dir)
      end
      assert_match(/perseus-greek/, error.message)
      assert_empty Dir.children(out_dir), "a refusal must write nothing"
    end
  end

  def test_the_stale_ingest_guard_covers_the_anchor_corpora
    with_build_env do |root, runner, _catalog, canonical|
      # canonical/perseus-greek advances after the recorded ingest: the
      # Passage_SHA256 anchors would cite bytes the manifest cannot name.
      File.write(File.join(canonical, "perseus-greek", "drifted.xml"), "<TEI/>\n")
      error = assert_raises(Nabu::DataBuild::Error) { build!(root, runner) }
      assert_match(/perseus-greek/, error.message)
      assert_match(/changed since/, error.message)
    end
  end
end
