# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"

# hbo/form-lemma — the Biblical Hebrew form→lemma table swept from the
# OSHB (Open Scriptures Hebrew Bible) token annotations in the catalog,
# the san/form-lemma mold transposed: one row per distinct
# (Form, Lemma, Morph) attestation tuple, Lemma = OSHB's augmented
# Strong's id VERBATIM ("c/d/776", "1254 a"), Morph = the OSHM code.
#
# Every expectation below is counted from the real oshb fixtures
# (test/fixtures/oshb — Gen 1 + 31, Ruth 1, Ps 23, Jer 10; 1,903
# running-text word tokens): 17 are Aramaic (OSHM `A` prefix — Gen
# 31:47's two words, Jer 10:11) and are EXCLUDED from a Hebrew table;
# 1,886 Hebrew lemma-bearing tokens remain, at 1,398 distinct
# (Form, Lemma, Morph) tuples over 494 distinct head lemmas (the
# composite's final segment: 7225 for "b/7225"). The 3 ketiv/qere
# sites contribute their running-text ketiv token; the 3 qere readings
# are apparatus and excluded.
#
# THE EXCLUSION THAT MATTERS: the catalog also holds BHSA Hebrew (CC
# BY-NC — license class nc); it must contribute NOTHING. The builder
# reads the oshb source alone and refuses an oshb row whose class is not
# publishable.
class DataBuildHboFormLemmaBuilderTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("oshb")

  FORM_COLUMNS = %w[ID Language_ID Form Lemma Head_Lemma Morph Count Source].freeze
  FORM_PRIMARY_KEY = %w[Form Lemma Morph].freeze
  LEMMA_COLUMNS = %w[ID Language_ID Head_Lemma Count].freeze

  HEBREW_TOKENS = 1_886
  DISTINCT_TUPLES = 1_398
  DISTINCT_HEAD_LEMMAS = 494
  ARAMAIC_TOKENS = 17
  QERE_READINGS = 3

  # -- rig -------------------------------------------------------------------

  def load_oshb_catalog(db)
    source = Nabu::Store::Source.create(
      slug: "oshb", name: Nabu::Adapters::Oshb.manifest.name,
      adapter_class: "Nabu::Adapters::Oshb", license_class: "open"
    )
    loader = Nabu::Store::Loader.new(db: db, source: source, ledger: nil)
    loader.load_from(Nabu::Adapters::Oshb.new, workdir: FIXTURES)
    source.update(last_ingest_identity: Nabu::DerivationFingerprint.canonical_identity(FIXTURES))
    db
  end

  # A BHSA-shaped nc lane in the same catalog: Hebrew documents whose
  # tokens carry lemmas. A row from here reaching the CSV is the defect.
  def plant_bhsa
    bhsa = Nabu::Store::Source.create(slug: "bhsa", name: "BHSA", adapter_class: "TestAdapter",
                                      license_class: "nc")
    doc = Nabu::Store::Document.create(source_id: bhsa.id, urn: "urn:nabu:bhsa:genesis", title: "Genesis",
                                       language: "hbo", content_sha256: "x", revision: 1)
    tokens = [{ "form" => "BHSAFORM", "lemma" => "BHSALEMMA", "morph" => "HNcmsa", "lang" => "hbo" },
              { "form" => "בְּרֵאשִׁ֖ית", "lemma" => "b/7225", "morph" => "HR/Ncfsa", "lang" => "hbo" }]
    Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:nabu:bhsa:genesis:1.1", sequence: 0,
                                language: "hbo", text: "t", text_normalized: "t", content_sha256: "x",
                                revision: 1, annotations_json: JSON.generate({ "tokens" => tokens }))
  end

  def with_build_env(bhsa: false)
    Dir.mktmpdir("nabu-hbo-form-lemma") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      FileUtils.cp_r(FIXTURES, File.join(canonical, "oshb"))
      sources = File.join(root, "sources.yml")
      File.write(sources, "oshb:\n  adapter: Nabu::Adapters::Oshb\n  wired: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      catalog = load_oshb_catalog(store_test_db)
      plant_bhsa if bhsa
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources),
                                           catalog: catalog)
      yield root, runner, catalog
    end
  end

  def feature
    Nabu::DataBuild.feature("hbo/form-lemma")
  end

  def build!(root, runner, into: File.join(root, "nabu-data"))
    summary = runner.run(feature: feature, into: into)
    [summary, summary.out_dir]
  end

  def read_csv(dir, name)
    CSV.read(File.join(dir, name), headers: true, encoding: "UTF-8")
  end

  def find_row(table, match)
    table.find { |row| match.all? { |column, value| row[column] == value } }
  end

  # -- registration ----------------------------------------------------------

  def test_the_feature_is_registered_available_with_the_builder_wired
    refute_nil feature
    assert feature.available?
    assert_equal Nabu::DataBuild::HboFormLemmaBuilder, feature.builder
    assert_equal ["oshb"], feature.inputs, "OSHB alone — BHSA (nc) is never an input"
    assert_equal ["oshb"], feature.canonical_cones
    assert_equal "CC-BY-4.0", feature.license
    assert_equal "hbo", feature.language_code
    assert_equal "Biblical Hebrew", feature.language.name
    %w[BHSA NC NFC Strong OSHM].each do |claim|
      assert_includes feature.rationale, claim, "the rationale states the #{claim} posture"
    end
  end

  # -- the dataset against fixture counts -----------------------------------

  def test_build_aggregates_the_hebrew_tuples_exactly
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")

      assert_equal FORM_COLUMNS, table.headers
      assert_equal DISTINCT_TUPLES, table.size, "one row per distinct (Form, Lemma, Morph) tuple"
      assert_equal(HEBREW_TOKENS, table.sum { |row| Integer(row["Count"]) })
      assert(table.all? { |row| row["Language_ID"] == "hbo" })
      assert(table.all? { |row| row["Source"] == "oshb" })
      assert(table.all? { |row| row["ID"].match?(Nabu::DataBuild::CsvWriter::ID_PATTERN) })

      # Gen 1:1's first word, end to end: the composite augmented Strong's
      # lemma verbatim, the content Strong's number split off the prefixes.
      row = find_row(table, "Lemma" => "b/7225")
      refute_nil row
      assert_equal [fixture_word("Gen", "01xeN"), "7225", "HR/Ncfsa"],
                   row.values_at("Form", "Head_Lemma", "Morph")
      row = find_row(table, "Lemma" => "c/d/776", "Morph" => "HC/Td/Ncbsa")
      refute_nil row
      assert_equal "776", row["Head_Lemma"]
      # Homograph letters are part of the Strong's identity, kept verbatim.
      row = find_row(table, "Form" => fixture_word("Gen", "01Nvk"))
      # Gen 1 has three bara' — two with munah (01Nvk, 01PUg), one with
      # merkha (01SAE): accents are part of the verbatim form, so 2 here.
      assert_equal ["1254 a", "1254 a", "2"], row.values_at("Lemma", "Head_Lemma", "Count")
      assert_equal 45, table.select { |r| r["Lemma"] == "853" && r["Morph"] == "HTo" }
                            .map { |r| Integer(r["Count"]) }.max,
                   "the fixture's most frequent tuple: the object marker 'et (853), 45 attestations"
    end
  end

  # A word's bytes straight from the fixture by its immutable OSHB id —
  # never a typed literal, which can silently carry a different mark order
  # (the very hazard hbo's NFC exemption exists for).
  def fixture_word(book, id)
    xml = File.read(File.join(FIXTURES, "wlc", "#{book}.xml"), encoding: "UTF-8")
    word = xml[%r{<w [^>]*id="#{id}"[^>]*>([^<]+)</w>}, 1]
    refute_nil word, "fixture word #{id} must exist in #{book}.xml"
    word.delete("/")
  end

  def test_aramaic_tokens_and_qere_readings_are_excluded_and_censused
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")

      assert(table.none? { |row| row["Morph"].start_with?("A") }, "no OSHM Aramaic morph in a Hebrew table")
      assert_nil find_row(table, "Form" => fixture_word("Gen", "01LA6")),
                 "Gen 31:47's Aramaic word never mints a row"
      assert_nil find_row(table, "Lemma" => "3026 b")
      # Ketiv/qere (Jer 10:17): the running-text ketiv counts, the qere
      # apparatus reading does not.
      refute_nil find_row(table, "Form" => fixture_word("Jer", "24yxB"), "Lemma" => "3427")
      assert_nil find_row(table, "Form" => fixture_word("Jer", "24EMh"))

      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      census = manifest.dig("nabu", "eval")
      assert_equal HEBREW_TOKENS, census["hebrew_tokens_counted"]
      assert_equal ARAMAIC_TOKENS, census["aramaic_tokens_excluded"]
      assert_equal QERE_READINGS, census["qere_readings_excluded"]
      assert_equal 0, census["lemma_less_tokens_excluded"]
    end
  end

  def test_forms_are_carried_byte_verbatim_never_nfc_normalized
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      forms = read_csv(out_dir, "form-lemma.csv").map { |row| row["Form"] }
      unstable = forms.reject { |form| form.unicode_normalize(:nfc) == form }
      refute_empty unstable, "the WLC mark order (dagesh before vowel) must survive — hbo is NFC-exempt"
      fixture_words = Dir[File.join(FIXTURES, "wlc", "*.xml")].map { |path| File.read(path, encoding: "UTF-8") }
                                                              .join.delete("/")
      unstable.first(20).each { |form| assert_includes fixture_words, form, "#{form} is the fixture's own bytes" }
    end
  end

  def test_bhsa_hebrew_in_the_same_catalog_contributes_nothing
    with_build_env(bhsa: true) do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")
      assert_nil find_row(table, "Lemma" => "BHSALEMMA"), "an nc BHSA row must never surface"
      assert_equal HEBREW_TOKENS, table.sum { |row| Integer(row["Count"]) },
                   "BHSA's copy of an OSHB-shaped token adds nothing to any count"

      census = JSON.parse(File.read(File.join(out_dir, "datapackage.json"))).dig("nabu", "eval")
      assert_equal({ "bhsa" => 1 }, census["excluded_hebrew_documents"],
                   "the exclusion is censused, not silent")
      sources = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))["sources"]
      assert_equal 1, sources.size
      assert_includes sources.first["title"], "Open Scriptures Hebrew Bible"
    end
  end

  def test_the_declared_primary_key_matches_the_grain_and_morph_is_load_bearing
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")
      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      resource = manifest["resources"].find { |r| r["name"] == "form-lemma" }
      assert_equal FORM_PRIMARY_KEY, resource.dig("schema", "primaryKey")
      tuples = table.map { |row| row.values_at(*FORM_PRIMARY_KEY) }
      assert_equal tuples.size, tuples.uniq.size
      yom = table.select { |row| row["Form"] == "י֥וֹם" && row["Lemma"] == "3117" }
      assert_equal [%w[HNcmsa 5], %w[HNcmsc 1]], yom.map { |row| row.values_at("Morph", "Count") }.sort,
                   "the same (Form, Lemma) split by OSHM morph — Morph is load-bearing in the key"
    end
  end

  def test_the_lemmas_sidecar_aggregates_per_head_lemma
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "lemmas.csv")
      assert_equal LEMMA_COLUMNS, table.headers
      assert_equal DISTINCT_HEAD_LEMMAS, table.size
      assert_equal(HEBREW_TOKENS, table.sum { |row| Integer(row["Count"]) })
      # 776 ('erets) re-buckets every prefixed spelling: 776, d/776, c/d/776...
      assert_equal "32", find_row(table, "Head_Lemma" => "776")["Count"]
      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      lemmas = manifest["resources"].find { |r| r["name"] == "lemmas" }
      assert_equal ["Head_Lemma"], lemmas.dig("schema", "primaryKey")
    end
  end

  def test_the_manifest_describes_the_derivation_honestly
    with_build_env do |root, runner, _catalog|
      summary, out_dir = build!(root, runner)
      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      assert_equal "hbo-form-lemma", manifest["name"]
      assert_equal "none", manifest.dig("nabu", "anchoring", "kind")
      assert_match(/\A\h{64}\z/, manifest.dig("nabu", "derivation", "inputs", "oshb", "canonical_sha"))
      recipe = manifest.dig("nabu", "derivation", "recipe")
      ["oshb", "Aramaic", "qere", "NFC", "Form, Lemma, Morph"].each do |claim|
        assert_includes recipe, claim
      end
      assert_equal summary.rows, manifest.dig("nabu", "counts", "rows")
      bib = File.read(File.join(out_dir, "sources.bib"))
      assert_includes bib, "@misc{oshb,"
      assert_includes bib, "https://github.com/openscriptures/morphhb"
      languages = read_csv(out_dir, "languages.csv")
      assert_equal([["hbo", "Biblical Hebrew", "bibl1238", "hbo"]],
                   languages.map { |row| row.values_at("ID", "Name", "Glottocode", "ISO639P3code") })
      assert_includes File.read(File.join(out_dir, "README.md")), "pd.read_csv"
    end
  end

  def test_building_twice_is_byte_identical
    with_build_env do |root, runner, _catalog|
      _summary, first = build!(root, runner, into: File.join(root, "first"))
      _summary, second = build!(root, runner, into: File.join(root, "second"))
      Dir.children(first).sort.each do |name|
        assert_equal File.binread(File.join(first, name)), File.binread(File.join(second, name)), name
      end
    end
  end

  # -- refusals --------------------------------------------------------------

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::HboFormLemmaBuilder.new.build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_refuses_a_catalog_without_oshb_rows
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::HboFormLemmaBuilder.new.build(catalog: store_test_db, out_dir: dir)
      end
      assert_match(/sync oshb/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_refuses_an_oshb_row_whose_license_class_is_not_publishable
    with_build_env do |_root, _runner, catalog|
      catalog[:sources].where(slug: "oshb").update(license_class: "nc")
      Dir.mktmpdir do |dir|
        error = assert_raises(Nabu::DataBuild::Error) do
          Nabu::DataBuild::HboFormLemmaBuilder.new.build(catalog: catalog, out_dir: dir)
        end
        assert_match(/not publishable/, error.message)
        assert_empty Dir.children(dir)
      end
    end
  end
end
