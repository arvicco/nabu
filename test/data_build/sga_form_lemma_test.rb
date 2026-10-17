# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"

# sga/form-lemma — the Old Irish form→lemma table derived from TWO
# independent gold-annotated editions of the SAME St Gall Priscian glosses
# (the stgall-priscian edition and CorPH's text 0007), with the two-edition
# agreement census joined on the Thesaurus Palaeohibernicus reference.
#
# The builder reads the CATALOG (both adapters' token blobs, ingested here
# through the REAL adapters + loader). Expectations are HAND-COUNTED from
# the fixtures — test/fixtures/stgall-priscian (26 glosses, 62 word
# analyses on 14 glosses) and test/fixtures/data_build/sga-form-lemma/corph
# (CorPH text 0007, 16 units, 83 analyses):
#
#   stgall-priscian  62 lemma-bearing sga tokens → 61 distinct rows
#   corph (0007)     71 lemma-bearing sga tokens → 67 distinct rows
#                    (the 12 non-sga analyses — `.i.`, CorPH's Latin
#                    "(Latin letters and suffixes)", ut/accentus — mint none)
#
#   Thesaurus refs   16 St Gall / 16 CorPH → 15 matched; St Gall-only
#                    "105" (its malformed upstream ref), CorPH-only "1a6".
#   Tokens in the matched refs: 62 St Gall / 64 CorPH; 55 aligned by
#   folded form → 34 identical lemmas, 10 more equal once folded (marks,
#   case, hyphens, the CorPH middot), 11 genuine divergences; 7 St Gall
#   and 9 CorPH tokens find no partner.
class DataBuildSgaFormLemmaTest < Minitest::Test
  include StoreTestDB

  STGALL = Nabu::TestSupport.fixtures("stgall-priscian")
  CORPH = File.join(Nabu::TestSupport.fixtures("data_build"), "sga-form-lemma", "corph")

  FORM_COLUMNS = %w[ID Language_ID Edition Form Lemma Homonym Part_Of_Speech Analysis Count Source].freeze
  FORM_PRIMARY_KEY = %w[Edition Form Lemma Homonym Part_Of_Speech Analysis].freeze
  DIVERGENCE_COLUMNS = %w[ID Thesaurus_Ref Stgall_Form Stgall_Lemma Stgall_Homonym Stgall_Analysis
                          Corph_Form Corph_Lemma Corph_Homonym Corph_Analysis Stgall_URN Corph_URN].freeze

  STGALL_TOKENS = 62
  STGALL_ROWS = 61
  CORPH_TOKENS = 71
  CORPH_ROWS = 67
  DIVERGENCES = 11

  # -- rig -------------------------------------------------------------------

  def load_source(db, slug:, adapter:, workdir:)
    source = Nabu::Store::Source.create(slug: slug, name: adapter.manifest.name,
                                        adapter_class: adapter.name, license_class: "attribution")
    Nabu::Store::Loader.new(db: db, source: source, ledger: nil).load_from(adapter.new, workdir: workdir)
    source.update(last_ingest_identity: Nabu::DerivationFingerprint.canonical_identity(workdir))
  end

  def load_catalog(db)
    load_source(db, slug: "stgall-priscian", adapter: Nabu::Adapters::StgallPriscian, workdir: STGALL)
    load_source(db, slug: "corph", adapter: Nabu::Adapters::Corph, workdir: CORPH)
    db
  end

  SOURCES_YML = <<~YAML
    stgall-priscian:
      adapter: Nabu::Adapters::StgallPriscian
      wired: true
      sync_policy: manual
    corph:
      adapter: Nabu::Adapters::Corph
      wired: true
      sync_policy: manual
  YAML

  def with_build_env
    Dir.mktmpdir("nabu-sga-form-lemma") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      FileUtils.cp_r(STGALL, File.join(canonical, "stgall-priscian"))
      FileUtils.cp_r(CORPH, File.join(canonical, "corph"))
      sources = File.join(root, "sources.yml")
      File.write(sources, SOURCES_YML)
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      catalog = load_catalog(store_test_db)
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources),
                                           catalog: catalog)
      yield root, runner
    end
  end

  def feature
    Nabu::DataBuild.feature("sga/form-lemma")
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

  def manifest(out_dir)
    JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
  end

  # -- registration ----------------------------------------------------------

  def test_the_feature_is_registered_available_with_both_editions_as_inputs
    assert feature.available?
    assert_equal Nabu::DataBuild::SgaFormLemma, feature.builder
    assert_equal %w[stgall-priscian corph], feature.inputs,
                 "both editions are declared inputs — the stale-ingest guard must cover them"
    assert_equal feature.inputs, feature.canonical_cones
    assert_equal "CC-BY-4.0", feature.license, "both inputs are MIT"
    assert_equal "none", feature.anchoring, "the san/form-lemma mold: the table is unanchored"
    sga = feature.language
    assert_equal ["sga", "Old Irish", "oldi1245", "sga"], [sga.id, sga.name, sga.glottocode, sga.iso639p3]
    assert_match(/agreement census/, feature.rationale,
                 "the two-edition differentiator is stated where the owner reads it")
  end

  # -- the form-lemma table --------------------------------------------------

  def test_build_aggregates_both_editions_gold_tokens_exactly
    with_build_env do |root, runner|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")
      assert_equal FORM_COLUMNS, table.headers

      by_edition = table.group_by { |row| row["Edition"] }
      assert_equal %w[corph stgall-priscian], by_edition.keys.sort
      assert_equal STGALL_ROWS, by_edition["stgall-priscian"].size
      assert_equal CORPH_ROWS, by_edition["corph"].size
      tokens = by_edition.transform_values { |rows| rows.sum { |row| Integer(row["Count"]) } }
      assert_equal STGALL_TOKENS, tokens["stgall-priscian"]
      assert_equal CORPH_TOKENS, tokens["corph"],
                   "only CorPH's sga tokens count — its Latin/particle analyses mint no row"
      assert(table.all? { |row| row["Language_ID"] == "sga" })
      assert(table.all? { |row| row["Source"] == row["Edition"] }, "each row cites its edition's bib key")
      assert(table.map { |row| row["ID"] }.all? { |id| id.match?(Nabu::DataBuild::CsvWriter::ID_PATTERN) })

      # Known rows, end to end. St Gall: tuisel twice in gloss 4229, as
      # acc.sg. and nom.sg. — Analysis is part of the grain.
      row = find_row(table, "Edition" => "stgall-priscian", "Form" => "tuisel", "Analysis" => "acc.sg.")
      assert_equal %w[tuisel noun 1], row.values_at("Lemma", "Part_Of_Speech", "Count")
      # The homonym index rides its own column (upstream "ad 1").
      row = find_row(table, "Edition" => "stgall-priscian", "Form" => "Ad")
      assert_equal %w[ad 1 particle], row.values_at("Lemma", "Homonym", "Part_Of_Speech")
      # CorPH: the same two tuisel tokens of Sg 051b13, independently
      # analysed the same way; CorPH tokens carry no part of speech.
      rows = table.select { |r| r["Edition"] == "corph" && r["Form"] == "tuisel" }
      assert_equal [%w[acc.sg. 1], %w[nom.sg. 1]], rows.map { |r| r.values_at("Analysis", "Count") }.sort
      assert(rows.all? { |r| r["Part_Of_Speech"].nil? }, "no per-token POS upstream — honestly empty")
      assert_nil find_row(table, "Edition" => "corph", "Lemma" => "(Latin letters and suffixes)")
      assert_nil find_row(table, "Edition" => "corph", "Form" => ".i.")
    end
  end

  def test_the_declared_primary_key_matches_the_aggregation_grain
    with_build_env do |root, runner|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "form-lemma.csv")
      resource = manifest(out_dir)["resources"].find { |entry| entry["name"] == "form-lemma" }
      assert_equal FORM_PRIMARY_KEY, resource.dig("schema", "primaryKey")
      tuples = table.map { |row| row.values_at(*FORM_PRIMARY_KEY) }
      assert_equal tuples.size, tuples.uniq.size, "the data must satisfy the claimed primary key"

      # Every PK column is load-bearing in the fixtures: the same St Gall
      # (Form, Lemma) split by Analysis (tuisel acc.sg. / nom.sg.), and the
      # same (Form, Lemma) split by Edition (méit in both).
      assert_equal %w[acc.sg. nom.sg.],
                   table.select { |row| row["Edition"] == "stgall-priscian" && row["Form"] == "tuisel" }
                        .map { |row| row["Analysis"] }.sort
      assert_equal %w[corph stgall-priscian],
                   table.select { |row| row["Form"] == "méit" }.map { |row| row["Edition"] }.sort
    end
  end

  # -- the two-edition agreement census --------------------------------------

  def test_the_agreement_census_is_published_in_nabu_eval
    with_build_env do |root, runner|
      _summary, out_dir = build!(root, runner)
      census = manifest(out_dir).dig("nabu", "eval")
      refute_nil census, "the agreement census rides nabu.eval"

      assert_equal({ "stgall_priscian" => 16, "corph" => 16, "matched" => 15, "stgall_only" => 1,
                     "corph_only" => 1, "matched_pooled" => 0, "matched_with_tokens" => 14 },
                   census["refs"])
      assert_equal({ "stgall_priscian" => STGALL_TOKENS, "corph" => CORPH_TOKENS,
                     "stgall_priscian_in_matched_refs" => 62, "corph_in_matched_refs" => 64,
                     "aligned" => 55, "unaligned_stgall_priscian" => 7, "unaligned_corph" => 9 },
                   census["tokens"])
      assert_equal({ "identical" => 34, "equal_folded" => 10, "agree" => 44, "diverge" => DIVERGENCES,
                     "agreement_rate" => 0.8 },
                   census["lemmas"])
      assert_match(/Thesaurus Palaeohibernicus/, census["join"], "the census states its join key")
    end
  end

  def test_the_divergences_sidecar_lists_every_disagreeing_aligned_pair
    with_build_env do |root, runner|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "divergences.csv")
      assert_equal DIVERGENCE_COLUMNS, table.headers
      assert_equal DIVERGENCES, table.size

      # 1a1: the same form, two headword conventions.
      row = find_row(table, "Thesaurus_Ref" => "1a1")
      assert_equal %w[libardaib lebarda libardaib lebardae],
                   row.values_at("Stgall_Form", "Stgall_Lemma", "Corph_Form", "Corph_Lemma")
      assert_equal "urn:nabu:stgall-priscian:p1:9", row["Stgall_URN"]
      assert_equal "urn:nabu:corph:0007:S0007-1", row["Corph_URN"]
      # A grammatical-label lemma on the CorPH side, the homonym-indexed
      # headword on St Gall's.
      row = find_row(table, "Thesaurus_Ref" => "1a2", "Stgall_Form" => "a")
      assert_equal %w[a 4 3pl.poss.pron.], row.values_at("Stgall_Lemma", "Stgall_Homonym", "Corph_Lemma")

      # Folded agreement is NOT a divergence: días / diäs, so / -so.
      assert_nil find_row(table, "Stgall_Lemma" => "días")
      assert_nil find_row(table, "Stgall_Lemma" => "so")

      resource = manifest(out_dir)["resources"].find { |entry| entry["name"] == "divergences" }
      assert_equal ["ID"], resource.dig("schema", "primaryKey")
    end
  end

  # -- furniture ---------------------------------------------------------------

  def test_the_manifest_and_furniture_describe_the_derivation_honestly
    with_build_env do |root, runner|
      summary, out_dir = build!(root, runner)
      data = manifest(out_dir)
      assert_equal "sga-form-lemma", data["name"]
      assert_equal "none", data.dig("nabu", "anchoring", "kind")
      %w[stgall-priscian corph].each do |cone|
        assert_match(/\A\h{64}\z/, data.dig("nabu", "derivation", "inputs", cone, "canonical_sha"))
      end
      recipe = data.dig("nabu", "derivation", "recipe")
      ["Thesaurus Palaeohibernicus", "0007", "folded", "Edition, Form, Lemma, Homonym, Part_Of_Speech, Analysis"]
        .each { |claim| assert_includes recipe, claim, "the recipe states the sweep precisely" }
      assert_equal STGALL_ROWS + CORPH_ROWS + DIVERGENCES, data.dig("nabu", "counts", "rows")
      assert_equal summary.rows, data.dig("nabu", "counts", "rows")

      bib = File.read(File.join(out_dir, "sources.bib"))
      assert_includes bib, "@misc{stgall-priscian,"
      assert_includes bib, "@misc{corph,"
      assert_includes bib, "Moran"
      assert_includes bib, "Chronologicon Hibernicum"

      readme = File.read(File.join(out_dir, "README.md"))
      assert_includes readme, "pd.read_csv"
      assert_includes readme, "divergences.csv"
      assert_match(/[Cc]ite/, readme)
    end
  end

  def test_building_twice_is_byte_identical
    with_build_env do |root, runner|
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

  # -- refusals --------------------------------------------------------------

  def test_the_builder_refuses_without_a_catalog
    Dir.mktmpdir("nabu-sga-form-lemma") do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::SgaFormLemma.new.build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_the_builder_refuses_when_either_edition_is_absent
    Dir.mktmpdir("nabu-sga-form-lemma") do |dir|
      db = store_test_db
      load_source(db, slug: "stgall-priscian", adapter: Nabu::Adapters::StgallPriscian, workdir: STGALL)
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::SgaFormLemma.new.build(catalog: db, out_dir: dir)
      end
      assert_match(/corph/, error.message)
      assert_match(/sync corph/, error.message, "the refusal carries the sync hint")
      assert_empty Dir.children(dir), "a refusal must write nothing"
    end
  end

  def test_a_cone_that_moved_since_ingest_is_refused
    with_build_env do |root, runner|
      File.write(File.join(root, "canonical", "corph", "fresh-upstream.txt"), "new upstream bytes\n")
      error = assert_raises(Nabu::DataBuild::Error) do
        runner.run(feature: feature, into: File.join(root, "out"))
      end
      assert_match(/sync corph/, error.message)
      refute Dir.exist?(File.join(root, "out", "sga")), "a refusal must write nothing"
    end
  end
end
