# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"

# non/form-lemma — the Old Norse form→lemma table swept from Menota's gold
# token annotations in the catalog (the hbo/form-lemma mold transposed to
# Menota-TEI): one row per distinct (Level, Form, Lemma, Msa) tuple.
#
# THE LEVEL DECISION: Menota transcribes each word at up to three levels
# (me:facs facsimile, me:dipl diplomatic, me:norm normalized) under ONE
# lemma + me:msa analysis. The levels are not a fixed pair — the
# dipl-only documents (AM 243 b α, Strengleikar) carry lemmatized words
# with NO normalized level, so a "Form = norm, Diplomatic = dipl" layout
# would leave keys empty. Each lemmatized token therefore contributes one
# count per level it attests, the Level column naming which; per-level
# Count sums equal the tokens attesting that level.
#
# Every expectation below is counted from the real menota fixtures
# (test/fixtures/menota — 13 documents): 1,317 lemmatized words in the
# Old West Norse documents (isl 783, nor 534) → 1,915 distinct tuples
# (facs 619, dipl 762, norm 534) over 424 lemmas; per-level token counts
# facs 993, dipl 1,317 (every lemmatized fixture word has a dipl
# reading), norm 1,025. 135 lemma-less words and 209 punctuation tokens
# mint nothing. Holm A 80 (Old Swedish, swe) is OUT of scope — Glottolog
# files Old Swedish/Old Danish under Swedish/Danish, not Old Norse — and
# is censused.
class DataBuildNonFormLemmaBuilderTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("menota")

  FORM_COLUMNS = %w[ID Language_ID Level Form Lemma Msa Count Source].freeze
  FORM_PRIMARY_KEY = %w[Level Form Lemma Msa].freeze
  LEMMA_COLUMNS = %w[ID Language_ID Lemma Count].freeze

  LEMMATIZED_TOKENS = 1_317
  DISTINCT_TUPLES = 1_915
  DISTINCT_LEMMAS = 424
  LEVEL_TOKENS = { "facs" => 993, "dipl" => 1_317, "norm" => 1_025 }.freeze
  LEVEL_ROWS = { "facs" => 619, "dipl" => 762, "norm" => 534 }.freeze

  # -- rig -------------------------------------------------------------------

  def load_menota_catalog(db)
    source = Nabu::Store::Source.create(
      slug: "menota", name: Nabu::Adapters::Menota.manifest.name,
      adapter_class: "Nabu::Adapters::Menota", license_class: "attribution"
    )
    loader = Nabu::Store::Loader.new(db: db, source: source, ledger: nil)
    loader.load_from(Nabu::Adapters::Menota.new(delay: 0), workdir: FIXTURES)
    source.update(last_ingest_identity: Nabu::DerivationFingerprint.canonical_identity(FIXTURES))
    db
  end

  def tokens_json(tokens) = JSON.generate({ "tokens" => tokens })

  def plant_document(source_id:, slug:, language:, tokens:, license_override: nil)
    doc = Nabu::Store::Document.create(source_id: source_id, urn: "urn:nabu:#{slug}:planted-#{language}",
                                       title: "planted", language: language, content_sha256: "x",
                                       revision: 1, license_override: license_override)
    Nabu::Store::Passage.create(document_id: doc.id, urn: "#{doc.urn}:1", sequence: 0, language: language,
                                text: "t", text_normalized: "t", content_sha256: "x", revision: 1,
                                annotations_json: tokens_json(tokens))
  end

  PLANTED_TOKEN = { "kind" => "w", "lemma" => "PLANTEDLEMMA", "msa" => "xNC", "dipl" => "PLANTED",
                    "norm" => "PLANTED", "text_level" => "dipl" }.freeze

  # Three lanes that must contribute NOTHING: an Old Danish menota document
  # (East Norse, out of scope), an nc-overridden menota document, and
  # another source's Old Norse.
  def plant_exclusions(catalog)
    menota = catalog[:sources].where(slug: "menota").get(:id)
    plant_document(source_id: menota, slug: "menota", language: "dan", tokens: [PLANTED_TOKEN])
    plant_document(source_id: menota, slug: "menota", language: "isl", tokens: [PLANTED_TOKEN],
                   license_override: "nc")
    other = Nabu::Store::Source.create(slug: "other-norse", name: "Other", adapter_class: "TestAdapter",
                                       license_class: "attribution")
    plant_document(source_id: other.id, slug: "other-norse", language: "non", tokens: [PLANTED_TOKEN])
  end

  def with_build_env(exclusions: false)
    Dir.mktmpdir("nabu-non-form-lemma") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      FileUtils.cp_r(FIXTURES, File.join(canonical, "menota"))
      sources = File.join(root, "sources.yml")
      File.write(sources, "menota:\n  adapter: Nabu::Adapters::Menota\n  wired: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      catalog = load_menota_catalog(store_test_db)
      plant_exclusions(catalog) if exclusions
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources),
                                           catalog: catalog)
      yield root, runner, catalog
    end
  end

  def feature
    Nabu::DataBuild.feature("non/form-lemma")
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
    assert_equal Nabu::DataBuild::NonFormLemmaBuilder, feature.builder
    assert_equal ["menota"], feature.inputs
    assert_equal ["menota"], feature.canonical_cones
    assert_equal "CC-BY-SA-4.0", feature.license, "Menota is CC BY-SA 4.0 — share-alike carries"
    assert_equal "gold-derived", feature.tier
    assert_equal "non", feature.language_code
    assert_equal "Old Norse", feature.language.name
    ["facsimile", "diplomatic", "normalized", "Level", "Old Swedish", "CC BY-SA"].each do |claim|
      assert_includes feature.rationale, claim, "the rationale states the #{claim} posture"
    end
  end

  # -- the dataset against fixture counts -----------------------------------

  def test_build_aggregates_the_level_tuples_exactly
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")

      assert_equal FORM_COLUMNS, table.headers
      assert_equal DISTINCT_TUPLES, table.size, "one row per distinct (Level, Form, Lemma, Msa) tuple"
      assert(table.all? { |row| row["Language_ID"] == "non" })
      assert(table.all? { |row| row["Source"] == "menota" })
      assert(table.all? { |row| row["ID"].match?(Nabu::DataBuild::CsvWriter::ID_PATTERN) })
      LEVEL_ROWS.each do |level, rows|
        level_rows = table.select { |row| row["Level"] == level }
        assert_equal rows, level_rows.size, "#{level} distinct tuples"
        assert_equal LEVEL_TOKENS.fetch(level), level_rows.sum { |row| Integer(row["Count"]) },
                     "#{level}: the per-level counts sum to the tokens attesting that level"
      end
      assert_equal %w[dipl facs norm], table.map { |row| row["Level"] }.uniq.sort

      # The normalized level: Old Norse orthography, the dictionary-facing form.
      assert_equal "56", find_row(table, "Level" => "norm", "Form" => "ok", "Lemma" => "ok",
                                         "Msa" => "xCC")["Count"]
      assert_equal "17", find_row(table, "Level" => "norm", "Form" => "var", "Lemma" => "vera",
                                         "Msa" => "xVB fF tPT mIN p3 nS vA")["Count"]
      # Case is the manuscript's own: the norm level capitalizes a
      # sentence-initial Konungrinn, kept verbatim beside konungrinn.
      refute_nil find_row(table, "Level" => "norm", "Form" => "Konungrinn", "Lemma" => "konungr")
      assert_equal "7", find_row(table, "Level" => "norm", "Form" => "konungrinn", "Lemma" => "konungr")["Count"]
      # The diplomatic level carries the scribal spelling (konungrin, one n).
      assert_equal "8", find_row(table, "Level" => "dipl", "Form" => "konungrin", "Lemma" => "konungr")["Count"]
    end
  end

  def test_dipl_only_documents_contribute_dipl_rows_without_a_normalized_twin
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")
      # AM 243 b α (Konungs skuggsjá) is lemmatized at the dipl level only:
      # its w16100 konongum (Msa "xNC nP gM cD sI", the encoder's own
      # feature order) has no facs or norm reading.
      rows = table.select { |row| row["Lemma"] == "konungr" && row["Msa"] == "xNC nP gM cD sI" }
      assert_equal([%w[dipl konongum 1]], rows.map { |row| row.values_at("Level", "Form", "Count") })
    end
  end

  def test_msa_is_load_bearing_in_the_key
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")
      kastala = table.select { |row| row["Level"] == "norm" && row["Form"] == "kastala" }
      assert_equal [["xNC gM nS cD sI", "1"], ["xNC gM nS cG sI", "2"]],
                   kastala.map { |row| row.values_at("Msa", "Count") }.sort,
                   "the same (Level, Form, Lemma) split by me:msa — genitive and dative kastala"
      tuples = table.map { |row| row.values_at(*FORM_PRIMARY_KEY) }
      assert_equal tuples.size, tuples.uniq.size
      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      resource = manifest["resources"].find { |r| r["name"] == "form-lemma" }
      assert_equal FORM_PRIMARY_KEY, resource.dig("schema", "primaryKey")
    end
  end

  def test_the_lemmas_sidecar_counts_tokens_once_each
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "lemmas.csv")
      assert_equal LEMMA_COLUMNS, table.headers
      assert_equal DISTINCT_LEMMAS, table.size
      assert_equal(LEMMATIZED_TOKENS, table.sum { |row| Integer(row["Count"]) },
                   "a token counts once in the sidecar, however many levels it attests")
      assert_equal "78", find_row(table, "Lemma" => "ok")["Count"]
      assert_equal "57", find_row(table, "Lemma" => "vera")["Count"]
    end
  end

  def test_forms_are_carried_verbatim_including_mufi_private_use_characters
    with_build_env do |root, runner, catalog|
      _summary, out_dir = build!(root, runner)
      forms = read_csv(out_dir, "form-lemma.csv").select { |row| row["Level"] == "facs" }.map { |row| row["Form"] }
      stored = catalog[:passages].select_map(:annotations_json).flat_map do |json|
        JSON.parse(json)["tokens"].to_a.filter_map { |token| token["facs"] }
      end
      pua = forms.grep(/\p{Co}/)
      refute_empty pua, "MUFI private-use facsimile glyphs survive into the table"
      forms.each { |form| assert_includes stored, form, "#{form.inspect} is the catalog's own facs bytes" }
    end
  end

  def test_the_census_names_every_exclusion
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      eval = census(out_dir)
      assert_equal LEMMATIZED_TOKENS, eval["lemmatized_tokens_counted"]
      assert_equal LEVEL_TOKENS, eval["level_tokens"]
      assert_equal({ "isl" => 783, "nor" => 534 }, eval["tokens_by_document_language"])
      assert_equal 135, eval["lemma_less_words_excluded"]
      assert_equal 209, eval["punctuation_tokens_skipped"]
      assert_equal({ "swe" => 1 }, eval["out_of_scope_documents_by_language"],
                   "Holm A 80 (Old Swedish) is outside Old Norse and censused")
      assert_equal({}, eval["license_excluded_documents"])
    end
  end

  def test_east_norse_nc_and_other_source_lanes_contribute_nothing
    with_build_env(exclusions: true) do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")
      assert_nil find_row(table, "Lemma" => "PLANTEDLEMMA")
      assert_nil find_row(read_csv(out_dir, "lemmas.csv"), "Lemma" => "PLANTEDLEMMA")
      eval = census(out_dir)
      assert_equal LEMMATIZED_TOKENS, eval["lemmatized_tokens_counted"]
      assert_equal({ "dan" => 1, "swe" => 1 }, eval["out_of_scope_documents_by_language"])
      assert_equal({ "nc" => 1 }, eval["license_excluded_documents"])
      assert_equal({ "other-norse" => 1 }, eval["excluded_old_norse_documents"])
    end
  end

  def test_the_manifest_describes_the_derivation_honestly
    with_build_env do |root, runner, _catalog|
      summary, out_dir = build!(root, runner)
      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      assert_equal "non-form-lemma", manifest["name"]
      assert_equal "CC-BY-SA-4.0", manifest.dig("licenses", 0, "name")
      assert_match(/\A\h{64}\z/, manifest.dig("nabu", "derivation", "inputs", "menota", "canonical_sha"))
      recipe = manifest.dig("nabu", "derivation", "recipe")
      ["menota", "facs", "dipl", "norm", "isl", "nor", "Level, Form, Lemma, Msa"].each do |claim|
        assert_includes recipe, claim
      end
      assert_equal summary.rows, manifest.dig("nabu", "counts", "rows")
      bib = File.read(File.join(out_dir, "sources.bib"))
      assert_includes bib, "@misc{menota,"
      assert_includes bib, "menota.org"
      languages = read_csv(out_dir, "languages.csv")
      assert_equal([["non", "Old Norse", "oldn1244", "non"]],
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
        Nabu::DataBuild::NonFormLemmaBuilder.new.build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_refuses_a_catalog_without_menota_rows
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::NonFormLemmaBuilder.new.build(catalog: store_test_db, out_dir: dir)
      end
      assert_match(/sync menota/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_refuses_a_menota_row_whose_license_class_is_not_publishable
    with_build_env do |_root, _runner, catalog|
      catalog[:sources].where(slug: "menota").update(license_class: "nc")
      Dir.mktmpdir do |dir|
        error = assert_raises(Nabu::DataBuild::Error) do
          Nabu::DataBuild::NonFormLemmaBuilder.new.build(catalog: catalog, out_dir: dir)
        end
        assert_match(/not publishable/, error.message)
        assert_empty Dir.children(dir)
      end
    end
  end
end
