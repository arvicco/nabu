# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"

# The xct/verb-lemma dataset builder (P50-W4, table half only): the Tibetan
# Verb Database's stem tuples expanded to ONE ROW PER GRAMMARIAN-ANALYSIS —
# each upstream (present/past/future/imperative) row yields one output row per
# attesting source column (TDC/PH/GT/KN), disagreements uncollapsed, empty
# stems left empty, never invented. Expectations below are HAND-COUNTED from
# test/fixtures/tibetan-verbs/db.csv (28 verbatim upstream rows):
#
#   61 attestation rows total; 20 distinct present stems (lemmas);
#   ཀེར heads 3 upstream rows (GT / TDC / PH — three DIFFERENT paradigms);
#   ཀློག is one row attested by all four sources → 4 identical-tuple rows;
#   ཀླུབ is attested by GT under TWO different paradigms, so even
#   (Lemma, Analysis_Source) is not unique — the PK is the minted ID.
class VerbLemmaBuilderTest < Minitest::Test
  FIXTURE_CSV = File.join(Nabu::TestSupport.fixtures("tibetan-verbs"), "db.csv")
  COLUMNS = %w[ID Language_ID Lemma Present Past Future Imperative Analysis_Source Comment Source].freeze

  # A tmp environment shaped like the box: a canonical/tibetan-verbs cone
  # holding the fixture CSV (non-git → content identity), a sources.yml
  # carrying the real adapter (its manifest feeds the datapackage sources[]).
  def with_env
    Dir.mktmpdir("nabu-verb-lemma") do |root|
      canonical = File.join(root, "canonical")
      cone = File.join(canonical, "tibetan-verbs")
      FileUtils.mkdir_p(cone)
      FileUtils.cp(FIXTURE_CSV, File.join(cone, "db.csv"))
      sources = File.join(root, "sources.yml")
      File.write(sources, "tibetan-verbs:\n  adapter: Nabu::Adapters::TibetanVerbs\n  " \
                          "wired: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      yield root, canonical, config
    end
  end

  # The registry's real feature, its builder pinned to the tmp canonical tree
  # (the Runner instantiates builders with no arguments; the default
  # canonical_dir is the box's own — tests must never read it).
  def feature_for(canonical)
    builder = Class.new(Nabu::DataBuild::VerbLemmaBuilder) do
      define_method(:initialize) { super(canonical_dir: canonical) }
    end
    Nabu::DataBuild.feature("xct/verb-lemma").with(builder: builder)
  end

  def run_build(root, canonical, config, into: File.join(root, "nabu-data"))
    registry = Nabu::SourceRegistry.load(config.sources_path)
    runner = Nabu::DataBuild::Runner.new(config: config, registry: registry)
    runner.run(feature: feature_for(canonical), into: into)
  end

  def read_rows(out_dir)
    CSV.read(File.join(out_dir, "verb-lemma.csv"), headers: true)
  end

  def test_end_to_end_build_writes_the_full_dataset_directory
    with_env do |root, canonical, config|
      summary = run_build(root, canonical, config)

      out_dir = File.join(root, "nabu-data", "xct", "verb-lemma")
      assert_equal out_dir, summary.out_dir
      %w[verb-lemma.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert File.file?(File.join(out_dir, name)), "expected #{name} in the dataset directory"
      end

      table = read_rows(out_dir)
      assert_equal COLUMNS, table.headers
      assert_equal 61, table.size, "28 fixture rows expand to 61 attestation rows (hand-counted)"
      assert_equal 20, table.map { |row| row["Lemma"] }.uniq.size
      assert_equal 62, summary.rows, "61 data rows + 1 languages row"

      languages = CSV.read(File.join(out_dir, "languages.csv"))
      assert_equal %w[ID Name Glottocode ISO639P3code], languages[0]
      assert_equal ["xct", "Classical Tibetan", "clas1254", "xct"], languages[1]
    end
  end

  def test_the_manifest_describes_the_dataset_honestly
    with_env do |root, canonical, config|
      summary = run_build(root, canonical, config)
      manifest = JSON.parse(File.read(File.join(summary.out_dir, "datapackage.json")))

      assert_equal "xct-verb-lemma", manifest["name"]
      assert_equal "gold-derived", manifest.dig("nabu", "tier")
      assert_equal "none", manifest.dig("nabu", "anchoring", "kind"),
                   "the anchored layer is deferred behind segmentation — anchoring stays none"
      assert_equal 62, manifest.dig("nabu", "counts", "rows")
      assert_equal(%w[verb-lemma languages sources], manifest["resources"].map { |resource| resource["name"] })

      table = manifest["resources"].first
      assert_equal "verb-lemma.csv", table["path"]
      assert_equal(COLUMNS, table["schema"]["fields"].map { |field| field["name"] })
      assert_equal ["ID"], table["schema"]["primaryKey"],
                   "the real grain is finer than (Lemma, Analysis_Source) — the minted ID is the PK"

      cone_sha = manifest.dig("nabu", "derivation", "inputs", "tibetan-verbs", "canonical_sha")
      assert_equal Nabu::DerivationFingerprint.canonical_identity(File.join(canonical, "tibetan-verbs")), cone_sha

      recipe = manifest.dig("nabu", "derivation", "recipe")
      assert_match(/one row per/, recipe)
      assert_match(/anchored layer/, recipe, "the manifest states the table-half-only scope")
      assert_match(%r{xct/segmentation}, recipe)

      source = manifest["sources"].first
      assert_equal "Tibetan Verbs Database (tibetan-nlp TVD)", source["title"]
      assert_equal "https://github.com/tibetan-nlp/tibetan-verbs-database", source["path"]
      assert_equal cone_sha, source["version"]
      assert_match(/CC0-1\.0/, source["licenses"].first["name"])
    end
  end

  def test_the_readme_and_bib_carry_scope_citation_and_a_pandas_one_liner
    with_env do |root, canonical, config|
      summary = run_build(root, canonical, config)

      readme = File.read(File.join(summary.out_dir, "README.md"))
      assert_match(/anchored layer/, readme)
      assert_match(%r{xct/segmentation}, readme, "the deferral names what it waits for")
      assert_match(/pd\.read_csv/, readme, "the scholar-facing pandas one-liner")
      assert_match(/one row per/, readme)
      assert_match(/Wylie/, readme, "the README states why no Wylie column exists")

      bib = File.read(File.join(summary.out_dir, "sources.bib"))
      assert_match(/@misc\{tvd,/, bib)
      assert_match(/Tibetan Verbs Database/, bib)
      assert_match(/CC0-1\.0/, bib)
    end
  end

  def test_disagreements_stay_uncollapsed_one_row_per_grammarian_analysis
    with_env do |root, canonical, config|
      table = read_rows(run_build(root, canonical, config).out_dir)

      # ཀེར: three upstream rows — GT, TDC, PH give three DIFFERENT paradigms.
      # (PH's tag sits in the TDC column upstream — the ONE loose-position
      # cell whole-file; attribution follows the cell value, as the adapter's.)
      ker = table.select { |row| row["Lemma"] == "ཀེར" }
      assert_equal 3, ker.size
      assert_equal(%w[GT TDC PH], ker.map { |row| row["Analysis_Source"] })
      assert_equal "ཀེར༼ད༽", ker[0]["Past"], "GT's past stem, upstream ༼ད༽ notation verbatim"
      assert_equal "ཀེར", ker[1]["Past"]
      assert_nil ker[1]["Imperative"], "TDC gives no imperative — empty cell, never invented"
      assert_equal "ཀེར", ker[2]["Imperative"]

      # ཀློག: ONE upstream row attested by all four sources → four rows with
      # an identical stem tuple, one per authority.
      klog = table.select { |row| row["Lemma"] == "ཀློག" }
      assert_equal(%w[TDC PH GT KN], klog.map { |row| row["Analysis_Source"] })
      assert_equal 1, klog.map { |row| row.values_at("Present", "Past", "Future", "Imperative") }.uniq.size

      # ཀླུབ: GT attests TWO different paradigms — (Lemma, Analysis_Source)
      # is NOT a key; the disagreement survives uncollapsed.
      klub_gt = table.select { |row| row["Lemma"] == "ཀླུབ" && row["Analysis_Source"] == "GT" }
      assert_equal 2, klub_gt.size
      assert_equal %w[ཀླུབས བཀླུབས], klub_gt.map { |row| row["Past"] }.sort
    end
  end

  def test_empty_stems_stay_empty_and_the_one_tag_language_call_holds
    with_env do |root, canonical, config|
      table = read_rows(run_build(root, canonical, config).out_dir)

      # ཁ (upstream line 125): present-only — past/future/imperative empty.
      kha = table.select { |row| row["Lemma"] == "ཁ" }
      assert_equal 1, kha.size
      assert_equal "TDC", kha[0]["Analysis_Source"]
      assert_equal "ཁ", kha[0]["Present"]
      %w[Past Future Imperative].each { |column| assert_nil kha[0][column] }

      # དཀའ: TDC and PH agree, neither gives an imperative.
      dka = table.select { |row| row["Lemma"] == "དཀའ" }
      assert_equal(%w[TDC PH], dka.map { |row| row["Analysis_Source"] })
      dka.each { |row| assert_nil row["Imperative"] }

      table.each do |row|
        assert_equal "xct", row["Language_ID"], "one tag for the whole dataset (upstream carries none)"
        assert_equal "tvd", row["Source"], "every row cites the sources.bib key"
        assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, row["ID"]
      end
      assert_equal table.size, table.map { |row| row["ID"] }.uniq.size, "IDs are unique — the PK"
    end
  end

  def test_building_twice_is_byte_identical
    with_env do |root, canonical, config|
      first = run_build(root, canonical, config, into: File.join(root, "first"))
      second = run_build(root, canonical, config, into: File.join(root, "second"))
      assert_equal first.fingerprint, second.fingerprint
      %w[verb-lemma.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert_equal File.read(File.join(first.out_dir, name)), File.read(File.join(second.out_dir, name)),
                     "#{name} must be byte-identical across builds — the dataset is deterministic"
      end
    end
  end

  # Upstream restates one (stems, source) row VERBATIM whole-file: PH's
  # འབྲལ,བྲལ,འབྲལ,བྲལ appears at upstream data rows 1702 and 1706 (the two
  # lines below are byte-verbatim upstream, census 2026-07-28). The second
  # occurrence gets the positional suffix — same discipline as the adapter.
  def test_an_upstream_restated_analysis_gets_a_positional_id_suffix
    Dir.mktmpdir("nabu-verb-lemma-dup") do |root|
      cone = File.join(root, "canonical", "tibetan-verbs")
      FileUtils.mkdir_p(cone)
      File.write(File.join(cone, "db.csv"),
                 "ད་ལྟ,འདས་པ,མ་འོངས,སྐུལ་ཚིག,TDC,PH,GT,KN\n" \
                 "འབྲལ,བྲལ,འབྲལ,བྲལ,,PH,,\n" \
                 "འབྲལ,བྲལ,འབྲལ,བྲལ,,PH,,\n")
      out_dir = File.join(root, "out")
      FileUtils.mkdir_p(out_dir)

      builder = Nabu::DataBuild::VerbLemmaBuilder.new(canonical_dir: File.join(root, "canonical"))
      result = builder.build(catalog: nil, out_dir: out_dir)
      assert_equal 2, result.resources.first.rows

      table = read_rows(out_dir)
      assert_equal(%w[PH PH], table.map { |row| row["Analysis_Source"] })
      first, second = table.map { |row| row["ID"] }
      assert_equal "#{first}-2", second, "the restatement is suffixed, never dropped and never colliding"
      assert_nil table[0]["Comment"]
      assert_match(/occurrence 2/, table[1]["Comment"])
    end
  end

  def test_a_missing_canonical_input_refuses_with_a_sync_hint
    Dir.mktmpdir("nabu-verb-lemma-missing") do |root|
      builder = Nabu::DataBuild::VerbLemmaBuilder.new(canonical_dir: File.join(root, "canonical"))
      error = assert_raises(Nabu::DataBuild::Error) do
        builder.build(catalog: nil, out_dir: root)
      end
      assert_match(/tibetan-verbs/, error.message)
      assert_match(/sync/, error.message)
    end
  end
end
