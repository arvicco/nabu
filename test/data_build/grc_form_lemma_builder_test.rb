# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"

# grc/form-lemma — the Ancient Greek form→lemma table swept from the GLAUx
# token annotations in the catalog (the hbo/form-lemma mold): one row per
# distinct (Form, Lemma, Postag) tuple, Postag = the AGDT 9-place tag
# VERBATIM, with the total Count and the Manual_Count of attestations from
# hand-annotated sentences (GLAUx's per-sentence analysis="manual").
#
# Every expectation below is counted from the real glaux fixtures
# (test/fixtures/glaux — 0003-002 + 0004-002, 88 sentences, all
# analysis="auto"): 1,072 lemma-bearing tokens at 754 distinct tuples over
# 522 lemmas; 208 punctuation tokens and 16 artificial elliptic nodes carry
# no lemma and mint nothing.
#
# THE EXCLUSIONS THAT MATTER: the catalog holds other Greek gold — PROIEL
# (CC BY-NC-SA, license class nc) — and GLAUx itself carries per-document
# nc overrides (its PROIEL- and Gorman-annotated texts, NC source texts).
# Neither may contribute: the sweep reads the glaux source alone and gates
# each document's EFFECTIVE license class.
class DataBuildGrcFormLemmaBuilderTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("glaux")

  FORM_COLUMNS = %w[ID Language_ID Form Lemma Postag Count Manual_Count Source].freeze
  FORM_PRIMARY_KEY = %w[Form Lemma Postag].freeze
  LEMMA_COLUMNS = %w[ID Language_ID Lemma Count Manual_Count].freeze

  LEMMA_TOKENS = 1_072
  DISTINCT_TUPLES = 754
  DISTINCT_LEMMAS = 522

  KAI = { "id" => "1", "form" => "καὶ", "lemma" => "καί", "postag" => "c--------" }.freeze
  PLANTED = { "id" => "2", "form" => "PLANTED", "lemma" => "PLANTEDLEMMA", "postag" => "n-s---nn-" }.freeze

  # -- rig -------------------------------------------------------------------

  def load_glaux_catalog(db)
    source = Nabu::Store::Source.create(
      slug: "glaux", name: Nabu::Adapters::Glaux.manifest.name,
      adapter_class: "Nabu::Adapters::Glaux", license_class: "attribution"
    )
    loader = Nabu::Store::Loader.new(db: db, source: source, ledger: nil)
    loader.load_from(Nabu::Adapters::Glaux.new, workdir: FIXTURES)
    source.update(last_ingest_identity: Nabu::DerivationFingerprint.canonical_identity(FIXTURES))
    db
  end

  def plant_document(source_id:, urn:, tokens:, analysis:, license_override: nil)
    doc = Nabu::Store::Document.create(source_id: source_id, urn: urn, title: "planted", language: "grc",
                                       content_sha256: "x", revision: 1, license_override: license_override)
    annotations = { "tokens" => tokens, "analysis" => analysis }.compact
    Nabu::Store::Passage.create(document_id: doc.id, urn: "#{urn}:1", sequence: 0, language: "grc",
                                text: "t", text_normalized: "t", content_sha256: "x", revision: 1,
                                annotations_json: JSON.generate(annotations))
  end

  # A hand-annotated sentence in a publishable glaux text (the AGDT /
  # Pedalion shape): it counts, and counts as manual.
  def plant_manual_sentence(catalog)
    glaux = catalog[:sources].where(slug: "glaux").get(:id)
    plant_document(source_id: glaux, urn: "urn:nabu:glaux:9999-001", tokens: [KAI], analysis: "manual")
  end

  # The two lanes that must contribute NOTHING: a glaux text carrying an nc
  # override (the PROIEL-annotated Herodotus shape) and the PROIEL source.
  def plant_exclusions(catalog)
    glaux = catalog[:sources].where(slug: "glaux").get(:id)
    plant_document(source_id: glaux, urn: "urn:nabu:glaux:0016-001", tokens: [PLANTED, KAI],
                   analysis: "manual", license_override: "nc")
    proiel = Nabu::Store::Source.create(slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter",
                                        license_class: "nc")
    plant_document(source_id: proiel.id, urn: "urn:nabu:proiel:hdt", tokens: [PLANTED, KAI], analysis: nil)
  end

  def with_build_env(manual: false, exclusions: false)
    Dir.mktmpdir("nabu-grc-form-lemma") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      FileUtils.cp_r(FIXTURES, File.join(canonical, "glaux"))
      sources = File.join(root, "sources.yml")
      File.write(sources, "glaux:\n  adapter: Nabu::Adapters::Glaux\n  wired: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      catalog = load_glaux_catalog(store_test_db)
      plant_manual_sentence(catalog) if manual
      plant_exclusions(catalog) if exclusions
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources),
                                           catalog: catalog)
      yield root, runner, catalog
    end
  end

  def feature
    Nabu::DataBuild.feature("grc/form-lemma")
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

  def census(out_dir)
    JSON.parse(File.read(File.join(out_dir, "datapackage.json"))).dig("nabu", "eval")
  end

  # -- registration ----------------------------------------------------------

  def test_the_feature_is_registered_available_with_the_builder_wired
    refute_nil feature
    assert feature.available?
    assert_equal Nabu::DataBuild::GrcFormLemmaBuilder, feature.builder
    assert_equal ["glaux"], feature.inputs, "GLAUx alone — PROIEL (nc) is never an input"
    assert_equal ["glaux"], feature.canonical_cones
    assert_equal "CC-BY-SA-4.0", feature.license
    assert_equal "silver", feature.tier, "GLAUx is automatically annotated — the table is silver"
    assert_equal "grc", feature.language_code
    assert_equal "Ancient Greek", feature.language.name
    %w[PROIEL Gorman Manual_Count AGDT automatic].each do |claim|
      assert_includes feature.rationale, claim, "the rationale states the #{claim} posture"
    end
  end

  # -- the dataset against fixture counts -----------------------------------

  def test_build_aggregates_the_tuples_exactly
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")

      assert_equal FORM_COLUMNS, table.headers
      assert_equal DISTINCT_TUPLES, table.size, "one row per distinct (Form, Lemma, Postag) tuple"
      assert_equal(LEMMA_TOKENS, table.sum { |row| Integer(row["Count"]) })
      assert(table.all? { |row| row["Manual_Count"] == "0" }, "the fixture sentences are all analysis=auto")
      assert(table.all? { |row| row["Language_ID"] == "grc" })
      assert(table.all? { |row| row["Source"] == "glaux" })
      assert(table.all? { |row| row["ID"].match?(Nabu::DataBuild::CsvWriter::ID_PATTERN) })

      assert_equal "32", find_row(table, "Form" => "καὶ", "Lemma" => "καί", "Postag" => "c--------")["Count"]
      assert_equal "1", find_row(table, "Form" => "μνῆμα", "Lemma" => "μνῆμα", "Postag" => "n-s---nn-")["Count"]
      # Elision is the edition's own: δ’ keeps its apostrophe, lemma δέ.
      assert_equal "14", find_row(table, "Form" => "δ’", "Lemma" => "δέ")["Count"]
      assert_nil find_row(table, "Lemma" => "E"), "artificial elliptic nodes never mint a row"
      assert(table.none? { |row| row["Postag"].start_with?("u") }, "punctuation carries no lemma")
    end
  end

  def test_the_postag_is_load_bearing_in_the_key
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")
      soma = table.select { |row| row["Form"] == "σῶμα" && row["Lemma"] == "σῶμα" }
      assert_equal %w[n-s---na- n-s---nn-], soma.map { |row| row["Postag"] }.sort,
                   "accusative and nominative σῶμα share Form and Lemma — Postag splits them"
      tuples = table.map { |row| row.values_at(*FORM_PRIMARY_KEY) }
      assert_equal tuples.size, tuples.uniq.size
      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      resource = manifest["resources"].find { |r| r["name"] == "form-lemma" }
      assert_equal FORM_PRIMARY_KEY, resource.dig("schema", "primaryKey")
    end
  end

  def test_hand_annotated_sentences_count_in_both_columns
    with_build_env(manual: true) do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      row = find_row(read_csv(out_dir, "form-lemma.csv"), "Form" => "καὶ", "Lemma" => "καί")
      assert_equal %w[33 1], row.values_at("Count", "Manual_Count")
      lemma = find_row(read_csv(out_dir, "lemmas.csv"), "Lemma" => "καί")
      assert_equal "1", lemma["Manual_Count"]
      eval = census(out_dir)
      assert_equal LEMMA_TOKENS + 1, eval["lemma_tokens_counted"]
      assert_equal 1, eval["manual_tokens_counted"]
    end
  end

  def test_forms_and_lemmas_are_the_catalogs_own_nfc_bytes
    with_build_env do |root, runner, catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")
      stored = catalog[:passages].select_map(:annotations_json).flat_map do |json|
        JSON.parse(json)["tokens"].map { |token| [token["form"], token["lemma"]] }
      end
      table.each do |row|
        assert_includes stored, [row["Form"], row["Lemma"]]
        assert_equal row["Form"].unicode_normalize(:nfc), row["Form"], "grc is NFC-normal — no exemption"
      end
    end
  end

  def test_the_lemmas_sidecar_aggregates_per_lemma
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "lemmas.csv")
      assert_equal LEMMA_COLUMNS, table.headers
      assert_equal DISTINCT_LEMMAS, table.size
      assert_equal(LEMMA_TOKENS, table.sum { |row| Integer(row["Count"]) })
      # ὁ re-buckets every article form (ten distinct: ὁ, τὸν, τοῦ, ...).
      assert_equal "36", find_row(table, "Lemma" => "ὁ")["Count"]
      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      lemmas = manifest["resources"].find { |r| r["name"] == "lemmas" }
      assert_equal ["Lemma"], lemmas.dig("schema", "primaryKey")
    end
  end

  def test_the_census_names_every_skipped_token
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      eval = census(out_dir)
      assert_equal LEMMA_TOKENS, eval["lemma_tokens_counted"]
      assert_equal 0, eval["manual_tokens_counted"]
      assert_equal 208, eval["punctuation_tokens_excluded"]
      assert_equal 16, eval["artificial_tokens_excluded"]
      assert_equal 0, eval["lemma_less_words_excluded"]
      assert_equal({ "auto" => 88 }, eval["sentences_by_analysis"])
      assert_equal({}, eval["license_excluded_documents"])
    end
  end

  def test_proiel_and_nc_overridden_glaux_texts_contribute_nothing
    with_build_env(exclusions: true) do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")
      assert_nil find_row(table, "Lemma" => "PLANTEDLEMMA"), "no nc Greek row may surface"
      assert_equal "32", find_row(table, "Form" => "καὶ", "Lemma" => "καί")["Count"],
                   "the nc lanes' copies of a GLAUx-shaped token add nothing"
      assert_equal(LEMMA_TOKENS, table.sum { |row| Integer(row["Count"]) })

      eval = census(out_dir)
      assert_equal({ "nc" => 1 }, eval["license_excluded_documents"])
      assert_equal({ "proiel" => 1 }, eval["excluded_greek_documents"], "the exclusion is censused, not silent")
      sources = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))["sources"]
      assert_equal 1, sources.size
      assert_includes sources.first["title"], "GLAUx"
    end
  end

  def test_the_manifest_describes_the_derivation_honestly
    with_build_env do |root, runner, _catalog|
      summary, out_dir = build!(root, runner)
      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      assert_equal "grc-form-lemma", manifest["name"]
      assert_equal "CC-BY-SA-4.0", manifest.dig("licenses", 0, "name")
      assert_match(/\A\h{64}\z/, manifest.dig("nabu", "derivation", "inputs", "glaux", "canonical_sha"))
      recipe = manifest.dig("nabu", "derivation", "recipe")
      ["glaux", "PROIEL", "nc", "manual", "Form, Lemma, Postag"].each { |claim| assert_includes recipe, claim }
      assert_equal summary.rows, manifest.dig("nabu", "counts", "rows")
      bib = File.read(File.join(out_dir, "sources.bib"))
      assert_includes bib, "@misc{glaux,"
      assert_includes bib, "10.18653/v1/2021.lchange-1.6"
      languages = read_csv(out_dir, "languages.csv")
      assert_equal([["grc", "Ancient Greek", "anci1242", "grc"]],
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
        Nabu::DataBuild::GrcFormLemmaBuilder.new.build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_refuses_a_catalog_without_glaux_rows
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::GrcFormLemmaBuilder.new.build(catalog: store_test_db, out_dir: dir)
      end
      assert_match(/sync glaux/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_refuses_a_glaux_row_whose_license_class_is_not_publishable
    with_build_env do |_root, _runner, catalog|
      catalog[:sources].where(slug: "glaux").update(license_class: "nc")
      Dir.mktmpdir do |dir|
        error = assert_raises(Nabu::DataBuild::Error) do
          Nabu::DataBuild::GrcFormLemmaBuilder.new.build(catalog: catalog, out_dir: dir)
        end
        assert_match(/not publishable/, error.message)
        assert_empty Dir.children(dir)
      end
    end
  end
end
