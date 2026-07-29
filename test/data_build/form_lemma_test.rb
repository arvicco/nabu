# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"

# The first REAL nabu-data feature (P50-W2): san/form-lemma — the Sanskrit
# form→lemma table swept from the DCS gold annotations. The builder reads the
# CATALOG (annotations_json token blobs, the Indexer's own read path), never
# canonical/, and aggregates gold attestation counts at the distinct
# (Form, Unsandhied, Lemma, Lemma_ID, UPOS) grain.
#
# Every expectation below is HAND-COUNTED from the real dcs fixtures
# (test/fixtures/dcs — 3 gold chapter files, trimmed upstream samples):
#   584 token lines, of which 99 are lemma-less sandhi-surface MWT range
#   lines (EXCLUDED — no lemma, no row) → 485 gold lemma-bearing tokens,
#   355 distinct (Form, Unsandhied, Lemma, LemmaId, UPOS) tuples,
#   271 distinct (LemmaId, Lemma) pairs.
# The grain is honest in miniature exactly as at scale: the fixtures carry
# tuples distinguished ONLY by UPOS (tvac NOUN vs ADV) and ONLY by
# Unsandhied (jaṅghā vs jaṅghāḥ), so the declared primary key is provably
# the coarsest key the data satisfies.
class DataBuildFormLemmaTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("dcs")

  FORM_COLUMNS = %w[ID Language_ID Form Unsandhied Lemma Lemma_ID Part_Of_Speech Count Source].freeze
  FORM_PRIMARY_KEY = %w[Form Unsandhied Lemma Lemma_ID Part_Of_Speech].freeze
  LEMMA_COLUMNS = %w[ID Language_ID Lemma_ID Lemma Count].freeze

  DISTINCT_TUPLES = 355
  DISTINCT_LEMMA_PAIRS = 271
  GOLD_TOKENS = 485

  # -- rig -------------------------------------------------------------------

  # A migrated catalog with the dcs fixtures ingested through the REAL
  # adapter + loader — the same bytes a production catalog holds. The
  # last-ingest identity is recorded exactly as both real ingest paths record
  # it (P50-r1): the canonical identity of the tree the load just derived
  # from (the fixture copy under canonical/ is byte-identical to FIXTURES,
  # so the content identity is the same).
  def load_dcs_catalog(db)
    source = Nabu::Store::Source.create(
      slug: "dcs", name: Nabu::Adapters::Dcs.manifest.name,
      adapter_class: "Nabu::Adapters::Dcs", license_class: "attribution"
    )
    loader = Nabu::Store::Loader.new(db: db, source: source, ledger: nil)
    loader.load_from(Nabu::Adapters::Dcs.new, workdir: FIXTURES)
    source.update(last_ingest_identity: Nabu::DerivationFingerprint.canonical_identity(FIXTURES))
    db
  end

  # Full Runner environment: a canonical/dcs cone (fixture copy, non-git →
  # content identity), a sources.yml registering dcs, and the ingested
  # catalog — everything `nabu data build san/form-lemma` needs.
  def with_build_env
    Dir.mktmpdir("nabu-form-lemma") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      FileUtils.cp_r(FIXTURES, File.join(canonical, "dcs"))
      sources = File.join(root, "sources.yml")
      File.write(sources, "dcs:\n  adapter: Nabu::Adapters::Dcs\n  wired: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      catalog = load_dcs_catalog(store_test_db)
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources),
                                           catalog: catalog)
      yield root, runner, catalog
    end
  end

  def feature
    Nabu::DataBuild.feature("san/form-lemma")
  end

  def build!(root, runner, into: File.join(root, "nabu-data"))
    summary = runner.run(feature: feature, into: into)
    [summary, summary.out_dir]
  end

  def read_csv(dir, name)
    CSV.read(File.join(dir, name), headers: true)
  end

  def find_row(table, match)
    table.find { |row| match.all? { |column, value| row[column] == value } }
  end

  # -- the flip --------------------------------------------------------------

  def test_the_feature_is_available_with_the_builder_wired
    assert feature.available?, "P50-W2 flips san/form-lemma to :available"
    assert_equal Nabu::DataBuild::FormLemma, feature.builder
  end

  # -- the dataset against hand-counted fixture expectations -----------------

  def test_build_aggregates_the_gold_tuples_exactly
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)

      table = read_csv(out_dir, "form-lemma.csv")
      assert_equal FORM_COLUMNS, table.headers
      assert_equal DISTINCT_TUPLES, table.size,
                   "one row per distinct (Form, Unsandhied, Lemma, LemmaId, UPOS) tuple"
      assert_equal GOLD_TOKENS, table.sum { |row| Integer(row["Count"]) },
                   "Count sums to the fixture's 485 gold lemma-bearing tokens"
      assert(table.all? { |row| row["Language_ID"] == "san" })
      assert(table.all? { |row| row["Source"] == "dcs" }, "every row cites the sources.bib key")
      assert(table.map { |row| row["ID"] }.all? { |id| id.match?(Nabu::DataBuild::CsvWriter::ID_PATTERN) })

      # A known row, end to end (AU 1,1: saḥ → tad, 4 gold attestations).
      row = find_row(table, "Form" => "saḥ", "Lemma" => "tad")
      refute_nil row
      assert_equal %w[saḥ 37875 PRON 4], row.values_at("Unsandhied", "Lemma_ID", "Part_Of_Speech", "Count"),
                   "Lemma_ID is the DCS numeric id verbatim; Count the gold attestation count"

      # Sandhi bridging is the dataset's point: Form keeps the attested
      # surface, Unsandhied the padapāṭha analysis form from MISC.
      row = find_row(table, "Form" => "svair")
      assert_equal %w[svaiḥ sva 114356 ADJ 1],
                   row.values_at("Unsandhied", "Lemma", "Lemma_ID", "Part_Of_Speech", "Count")
    end
  end

  def test_lemma_less_sandhi_surface_lines_are_excluded
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")

      # The fixture's 99 lemma-less lines are the MWT compound surfaces
      # (kaṇṭhagrīvaṃ = kaṇṭha + grīva): no lemma → no row, while the
      # analyzed member tokens are counted.
      assert_nil find_row(table, "Form" => "kaṇṭhagrīvaṃ"),
                 "a sandhi-surface line (CoNLL-U lemma `_`) must never mint a row"
      refute_nil find_row(table, "Lemma" => "kaṇṭha")
      refute_nil find_row(table, "Lemma" => "grīvā")
    end
  end

  def test_the_declared_primary_key_matches_the_aggregation_grain
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")

      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      form_lemma = manifest["resources"].find { |resource| resource["name"] == "form-lemma" }
      assert_equal FORM_PRIMARY_KEY, form_lemma.dig("schema", "primaryKey"),
                   "the manifest must claim exactly the grain the data is aggregated at"
      tuples = table.map { |row| row.values_at(*FORM_PRIMARY_KEY) }
      assert_equal tuples.size, tuples.uniq.size, "the data must satisfy the claimed primary key"

      # The fixtures prove every PK column is load-bearing: same
      # (Form, Unsandhied, Lemma, Lemma_ID) split by UPOS...
      assert_equal %w[ADV NOUN],
                   table.select { |row| row["Form"] == "tvac" && row["Unsandhied"] == "tvac" }
                        .map { |row| row["Part_Of_Speech"] }.sort
      # ...and same (Form, Lemma, Lemma_ID, UPOS) split by Unsandhied.
      assert_equal %w[jaṅghā jaṅghāḥ],
                   table.select { |row| row["Form"] == "jaṅghā" }.map { |row| row["Unsandhied"] }.sort

      lemmas = manifest["resources"].find { |resource| resource["name"] == "lemmas" }
      assert_equal %w[Lemma_ID Lemma], lemmas.dig("schema", "primaryKey")
    end
  end

  def test_the_lemmas_sidecar_aggregates_per_dcs_lemma_id
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "lemmas.csv")
      assert_equal LEMMA_COLUMNS, table.headers
      assert_equal DISTINCT_LEMMA_PAIRS, table.size
      assert_equal GOLD_TOKENS, table.sum { |row| Integer(row["Count"]) },
                   "the sidecar re-buckets the same 485 gold tokens, losing none"

      pairs = table.map { |row| row.values_at("Lemma_ID", "Lemma") }
      assert_equal pairs.size, pairs.uniq.size

      assert_equal "14", find_row(table, "Lemma_ID" => "37875")["Count"], "tad: 14 gold attestations"
      assert_equal %w[aṅgula 26], find_row(table, "Lemma_ID" => "6274").values_at("Lemma", "Count")
    end
  end

  def test_the_manifest_and_furniture_describe_the_derivation_honestly
    with_build_env do |root, runner, _catalog|
      summary, out_dir = build!(root, runner)

      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      assert_equal "san-form-lemma", manifest["name"]
      assert_equal "gold-derived", manifest.dig("nabu", "tier")
      assert_equal "none", manifest.dig("nabu", "anchoring", "kind")
      sha = manifest.dig("nabu", "derivation", "inputs", "dcs", "canonical_sha")
      assert_match(/\A\h{64}\z/, sha, "the non-git fixture cone gets its content identity")
      recipe = manifest.dig("nabu", "derivation", "recipe")
      ["gold", "Unsandhied", "sandhi", "Form, Unsandhied, Lemma, Lemma_ID, UPOS"].each do |claim|
        assert_includes recipe, claim, "the recipe states the sweep precisely"
      end
      assert_equal DISTINCT_TUPLES + DISTINCT_LEMMA_PAIRS + 1, manifest.dig("nabu", "counts", "rows"),
                   "form-lemma + lemmas + the one languages.csv row"
      assert_equal summary.rows, manifest.dig("nabu", "counts", "rows")

      source = manifest["sources"].first
      assert_includes source["title"], "Digital Corpus of Sanskrit"
      assert_equal sha, source["version"]

      bib = File.read(File.join(out_dir, "sources.bib"))
      assert_includes bib, "@misc{dcs,"
      assert_includes bib, "Hellwig"
      assert_includes bib, "https://github.com/OliverHellwig/sanskrit"
      assert_includes bib, "CC BY 4.0"

      readme = File.read(File.join(out_dir, "README.md"))
      assert_includes readme, "pd.read_csv", "scholar-facing README carries the pandas one-liner"
      assert_match(/[Cc]ite/, readme, "the README says how to cite")
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
                     "#{name} must be byte-identical across rebuilds — no timestamps, no nondeterminism"
      end
    end
  end

  # -- refusals --------------------------------------------------------------

  def test_the_builder_refuses_without_a_catalog
    Dir.mktmpdir("nabu-form-lemma") do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::FormLemma.new.build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
      assert_empty Dir.children(dir), "a refusal must write nothing"
    end
  end

  def test_the_builder_refuses_a_catalog_without_dcs_rows
    Dir.mktmpdir("nabu-form-lemma") do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::FormLemma.new.build(catalog: store_test_db, out_dir: dir)
      end
      assert_match(/dcs/, error.message)
      assert_match(/sync/, error.message, "the refusal carries the sync hint")
      assert_empty Dir.children(dir)
    end
  end

  # P50-r1 (owner ruling D50-a): the stale-ingest guard on the REAL feature —
  # canonical/dcs moved since the catalog last ingested it, so the manifest
  # would cite a cone sha the rows were not derived from. Hard refusal, no
  # override; the remedy is a re-ingest.
  def test_a_dcs_cone_that_moved_since_ingest_is_refused
    with_build_env do |root, runner, _catalog|
      File.write(File.join(root, "canonical", "dcs", "fresh-upstream.txt"), "new upstream bytes\n")
      error = assert_raises(Nabu::DataBuild::Error) do
        runner.run(feature: feature, into: File.join(root, "out"))
      end
      assert_match(/dcs/, error.message)
      assert_match(/sync dcs/, error.message, "the refusal carries the re-ingest remedy")
      refute Dir.exist?(File.join(root, "out", "san")), "a refusal must write nothing"
    end
  end

  # -- the CLI, end to end ---------------------------------------------------

  def test_nabu_data_build_drives_the_real_feature_end_to_end
    Dir.mktmpdir("nabu-form-lemma-cli") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      FileUtils.cp_r(FIXTURES, File.join(canonical, "dcs"))
      sources = File.join(root, "sources.yml")
      File.write(sources, "dcs:\n  adapter: Nabu::Adapters::Dcs\n  wired: true\n  sync_policy: manual\n")
      db_dir = File.join(root, "db")
      FileUtils.mkdir_p(db_dir)
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: db_dir,
                                sources_path: sources, config_path: "(test)")
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      load_dcs_catalog(catalog)
      catalog.disconnect

      into = File.join(root, "nabu-data")
      out, _err, status = with_config(config) do
        run_cli(["data", "build", "san/form-lemma", "--into", into])
      end

      assert_nil status, "the CLI build must succeed against the real registry entry"
      out_dir = File.join(into, "san", "form-lemma")
      %w[form-lemma.csv lemmas.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert File.file?(File.join(out_dir, name)), "expected #{name}"
        assert_includes out, name, "the summary lists every file written"
      end
      assert_match(/form-lemma\.csv\s+#{DISTINCT_TUPLES} rows/, out)
      assert_match(/lemmas\.csv\s+#{DISTINCT_LEMMA_PAIRS} rows/, out)
    end
  end

  private

  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end
end
