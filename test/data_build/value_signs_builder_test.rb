# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"

# The sux/value-signs dataset builder (P53-3, Edubba ask #3): the Oracc Sign
# List flattened to ONE ROW PER (value, sign) PAIR — ambiguity visible as
# multiple rows sharing a Value — plus the signs.csv sidecar (one row per
# @sign/@form record) and the concordances.csv print-list table. Expectations
# below are HAND-COUNTED from test/fixtures/osl/osl.asl (13 top-level signs,
# 5 variant forms, retrieved 2026-07-29):
#
#   60 value rows (23 on ŠEŠ alone; nannaₓ rides the |ŠEŠ.NA| FORM record);
#   idₓ is ambiguous — |A.BARA₂| and |UD.ŠEŠ.KI| → two rows, both flagged;
#   ṣillu is the one %akk-qualified value (|AN.SAG@g|);
#   aŋ is the one deprecated value (@v- on AK) — included, flagged;
#   18 sign rows: |A×AN| honestly unencoded (empty Codepoints), the
#   deprecated sign |A×GAN₂@t| flagged, |NU×U@c| encoded only in PUA;
#   52 concordance rows (AK carries 11, ŠEŠ 13).
class ValueSignsBuilderTest < Minitest::Test
  include StoreTestDB

  FIXTURE_ASL = File.join(Nabu::TestSupport.fixtures("osl"), "osl.asl")
  VALUES_COLUMNS = %w[ID Value Language_Qualifier Sign_Name OID Codepoints Glyph
                      Deprecated Ambiguous Source].freeze
  SIGNS_COLUMNS = %w[ID Sign_Name OID Parent_OID Aka Deprecated Codepoints PUA Glyph
                     Unicode_Name Source].freeze
  CONCORDANCES_COLUMNS = %w[ID OID Sign_Name List Number Source].freeze
  FILES = %w[value-signs.csv signs.csv concordances.csv languages.csv sources.bib
             datapackage.json README.md].freeze

  # A tmp environment shaped like the box: canonical/osl/00lib/osl.asl holds
  # the fixture (non-git → content identity), sources.yml carries the real
  # module row (its adapter manifest feeds the datapackage sources[]).
  def with_env
    Dir.mktmpdir("nabu-value-signs") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(File.join(canonical, "osl", "00lib"))
      FileUtils.cp(FIXTURE_ASL, File.join(canonical, "osl", "00lib", "osl.asl"))
      sources = File.join(root, "sources.yml")
      File.write(sources, "osl:\n  adapter: Nabu::Adapters::Osl\n  kind: module\n  " \
                          "wired: false\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      yield root, canonical, config
    end
  end

  # The registry's real feature, its builder pinned to the tmp canonical tree
  # (the Runner instantiates builders with no arguments; the default
  # canonical_dir is the box's own — tests must never read it).
  def feature_for(canonical)
    builder = Class.new(Nabu::DataBuild::ValueSignsBuilder) do
      define_method(:initialize) { super(canonical_dir: canonical) }
    end
    Nabu::DataBuild.feature("sux/value-signs").with(builder: builder)
  end

  def run_build(root, canonical, config, into: File.join(root, "nabu-data"), catalog: nil)
    registry = Nabu::SourceRegistry.load(config.sources_path)
    runner = Nabu::DataBuild::Runner.new(config: config, registry: registry, catalog: catalog)
    runner.run(feature: feature_for(canonical), into: into)
  end

  def read_table(out_dir, name)
    CSV.read(File.join(out_dir, name), headers: true)
  end

  def test_end_to_end_build_writes_the_full_dataset_directory
    with_env do |root, canonical, config|
      summary = run_build(root, canonical, config)

      out_dir = File.join(root, "nabu-data", "sux", "value-signs")
      assert_equal out_dir, summary.out_dir
      FILES.each { |name| assert File.file?(File.join(out_dir, name)), "expected #{name} in the dataset directory" }

      values = read_table(out_dir, "value-signs.csv")
      assert_equal VALUES_COLUMNS, values.headers
      assert_equal 60, values.size, "60 (value, sign) pairs hand-counted from the 13-sign fixture"

      signs = read_table(out_dir, "signs.csv")
      assert_equal SIGNS_COLUMNS, signs.headers
      assert_equal 18, signs.size, "13 top-level signs + 5 variant forms"

      concordances = read_table(out_dir, "concordances.csv")
      assert_equal CONCORDANCES_COLUMNS, concordances.headers
      assert_equal 52, concordances.size, "52 print-list tokens hand-counted (11 on AK, 13 on ŠEŠ)"

      assert_equal 60 + 18 + 52 + 1, summary.rows, "value + sign + concordance rows + 1 languages row"
      languages = CSV.read(File.join(out_dir, "languages.csv"))
      assert_equal %w[ID Name Glottocode ISO639P3code], languages[0]
      assert_equal %w[sux Sumerian sume1241 sux], languages[1]
    end
  end

  def test_the_packet_rows_value_grain_qualifiers_deprecation_ambiguity
    with_env do |root, canonical, config|
      values = read_table(run_build(root, canonical, config).out_dir, "value-signs.csv")

      # uri₅ → |ŠEŠ.AB|: the compound's @useq sequence, space-separated U+ hex.
      uri = values.select { |row| row["Value"] == "uri₅" }
      assert_equal 1, uri.size
      assert_equal "|ŠEŠ.AB|", uri[0]["Sign_Name"]
      assert_equal "o0002736", uri[0]["OID"]
      assert_equal "U+122C0 U+1200A", uri[0]["Codepoints"]
      assert_equal "𒋀𒀊", uri[0]["Glyph"]
      assert_equal "false", uri[0]["Ambiguous"]
      assert_match(/\Av-\h{12}\z/, uri[0]["ID"], "value IDs are digest-minted (subscripts cannot survive CLDF)")

      # idₓ maps to TWO signs: ambiguity is visible as multiple rows sharing
      # the Value, every one flagged — never one candidate silently.
      idx = values.select { |row| row["Value"] == "idₓ" }
      assert_equal(%w[|A.BARA₂| |UD.ŠEŠ.KI|], idx.map { |row| row["Sign_Name"] })
      assert_equal(%w[true true], idx.map { |row| row["Ambiguous"] })
      assert_equal "U+12000 U+12048", idx[0]["Codepoints"]
      assert_equal "U+12313 U+122C0 U+121A0", idx[1]["Codepoints"]

      # ṣillu is %akk-qualified: the Akkadian minority rides the column, the
      # unqualified sibling value on the same sign stays empty (= sux scope).
      assert_equal(["akk"], values.select { |row| row["Value"] == "ṣillu" }.map { |row| row["Language_Qualifier"] })
      assert_nil values.find { |row| row["Value"] == "ṣil₃" }["Language_Qualifier"]
      assert_equal 1, values.count { |row| row["Language_Qualifier"] }, "one qualified value in the fixture"

      # aŋ (@v- on AK) is INCLUDED and flagged: real corpora are
      # transliterated with deprecated values — exclusion would undercount.
      an = values.select { |row| row["Value"] == "aŋ" }
      assert_equal(["AK"], an.map { |row| row["Sign_Name"] })
      assert_equal(["true"], an.map { |row| row["Deprecated"] })
      assert_equal 1, values.count { |row| row["Deprecated"] == "true" }, "the one deprecated value in the fixture"

      values.each do |row|
        assert_equal "osl", row["Source"], "every row cites the sources.bib key"
        assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, row["ID"]
      end
      assert_equal values.size, values.map { |row| row["ID"] }.uniq.size, "IDs are unique — the PK"
    end
  end

  def test_the_signs_sidecar_keeps_encoding_honest_and_ties_forms_to_parents
    with_env do |root, canonical, config|
      signs = read_table(run_build(root, canonical, config).out_dir, "signs.csv")
      by_name = signs.group_by { |row| row["Sign_Name"] }

      # |A×AN| is honestly unencoded: empty Codepoints, no PUA, no glyph.
      a_an = by_name.fetch("|A×AN|")[0]
      assert_equal "o0027203", a_an["OID"]
      %w[Codepoints PUA Glyph Unicode_Name].each { |column| assert_nil a_an[column] }
      assert_equal "s-o0027203", a_an["ID"], "sign IDs ride the stable @oid verbatim"

      # The deprecated SIGN (@sign-) is flagged at sign level; value-level
      # deprecation lives in value-signs.csv.
      deprecated = by_name.fetch("|A×GAN₂@t|")[0]
      assert_equal "true", deprecated["Deprecated"]
      assert_equal "U+12003", deprecated["Codepoints"]

      # |NU×U@c| is encoded only in the Private Use Area: PUA carries it,
      # Codepoints stays empty (PUA is not interchange-stable).
      pua = by_name.fetch("|NU×U@c|")[0]
      assert_nil pua["Codepoints"]
      assert_equal "U+F009B", pua["PUA"]

      # A variant @form is its own row, tied to its parent by Parent_OID.
      form = by_name.fetch("|ŠEŠ.NA|")[0]
      assert_equal "o0018524", form["OID"]
      assert_equal "o0002740", form["Parent_OID"], "|ŠEŠ.NA| is a form of |ŠEŠ.KI|"
      top = by_name.fetch("ŠEŠ")[0]
      assert_nil top["Parent_OID"]
      assert_equal "U+122C0", top["Codepoints"]
      assert_equal "CUNEIFORM SIGN SHESH", top["Unicode_Name"]

      # @aka aliases survive, ";"-separated (the Source-cell separator).
      assert_equal "|A.BARAG|", by_name.fetch("|A.BARA₂|")[0]["Aka"]
    end
  end

  def test_the_concordances_sidecar_splits_list_and_number
    with_env do |root, canonical, config|
      concordances = read_table(run_build(root, canonical, config).out_dir, "concordances.csv")

      mzl = concordances.select { |row| row["List"] == "MZL" }
      assert_equal(%w[MZL127 MZL731 MZL825 MZL535], mzl.map { |row| row["List"] + row["Number"] })
      ak_mzl = mzl.find { |row| row["OID"] == "o0000093" }
      assert_equal %w[AK 127], [ak_mzl["Sign_Name"], ak_mzl["Number"]]
      assert_equal "c-o0000093-MZL127", ak_mzl["ID"]

      # Suffixed tokens keep the full number payload verbatim.
      rsp = concordances.find { |row| row["OID"] == "o0000456" && row["List"] == "RSP" }
      assert_equal "039^b", rsp["Number"]

      # A form's concordances cite the FORM record (own oid, own name).
      lak433 = concordances.find { |row| row["Number"] == "433" }
      assert_equal %w[LAK433 o0018571], [lak433["Sign_Name"], lak433["OID"]]

      assert_equal concordances.size, concordances.map { |row| row["ID"] }.uniq.size
    end
  end

  def test_the_manifest_describes_the_dataset_honestly
    with_env do |root, canonical, config|
      summary = run_build(root, canonical, config)
      manifest = JSON.parse(File.read(File.join(summary.out_dir, "datapackage.json")))

      assert_equal "sux-value-signs", manifest["name"]
      assert_equal "gold", manifest.dig("nabu", "tier"), "the sign list is the field's hand-curated registry"
      assert_equal "none", manifest.dig("nabu", "anchoring", "kind")
      assert_equal 131, manifest.dig("nabu", "counts", "rows")
      assert_equal(%w[value-signs signs concordances languages sources],
                   manifest["resources"].map { |resource| resource["name"] })
      manifest["resources"].first(3).each do |resource|
        assert_equal ["ID"], resource["schema"]["primaryKey"],
                     "#{resource['name']}: the grain is finer than any column tuple — the minted ID is the PK"
      end
      assert_equal(VALUES_COLUMNS, manifest["resources"][0]["schema"]["fields"].map { |field| field["name"] })

      cone_sha = manifest.dig("nabu", "derivation", "inputs", "osl", "canonical_sha")
      assert_equal Nabu::DerivationFingerprint.canonical_identity(File.join(canonical, "osl")), cone_sha

      recipe = manifest.dig("nabu", "derivation", "recipe")
      assert_match(/one row per/, recipe)
      assert_match(/deprecated values INCLUDED/, recipe, "the inclusion policy is part of the fingerprint")
      assert_match(/Language_Qualifier/, recipe, "the language-scope mechanism is part of the fingerprint")

      source = manifest["sources"].first
      assert_match(/Oracc Sign List/, source["title"])
      assert_equal "https://github.com/oracc/osl", source["path"]
      assert_equal cone_sha, source["version"]
      assert_match(/CC0/, source["licenses"].first["name"], "the upstream public-domain dedication is recorded")
    end
  end

  def test_the_readme_and_bib_state_scope_policy_and_provenance
    with_env do |root, canonical, config|
      summary = run_build(root, canonical, config)

      readme = File.read(File.join(summary.out_dir, "README.md"))
      assert_match(/CC-BY-4\.0/, readme, "the dataset license (upstream is CC0 — noted separately)")
      assert_match(/Sumerian/, readme)
      assert_match(/%akk/, readme, "the language-scope call is stated where the consumer reads it")
      assert_match(/[Dd]eprecated/, readme, "the deprecation inclusion policy is stated")
      assert_match(/[Aa]mbigu/, readme, "the one-row-per-pair grain is stated")
      assert_match(/unencoded/, readme, "empty Codepoints = honestly unencoded is stated")
      assert_match(/pd\.read_csv/, readme, "the scholar-facing pandas one-liner")

      bib = File.read(File.join(summary.out_dir, "sources.bib"))
      assert_match(/@misc\{osl,/, bib)
      assert_match(/Oracc Sign List/, bib)
      assert_match(/CC0/, bib, "the upstream dedication rides the citation")
    end
  end

  def test_building_twice_is_byte_identical
    with_env do |root, canonical, config|
      first = run_build(root, canonical, config, into: File.join(root, "first"))
      second = run_build(root, canonical, config, into: File.join(root, "second"))
      assert_equal first.fingerprint, second.fingerprint
      FILES.each do |name|
        assert_equal File.read(File.join(first.out_dir, name)), File.read(File.join(second.out_dir, name)),
                     "#{name} must be byte-identical across builds — the dataset is deterministic"
      end
    end
  end

  # The P53-1 full-file smoke found a same-named sign+form pair: the minter
  # must key on the record's own identity (@oid), never the bare name — and
  # survive even verbatim value restatements via the positional suffix.
  # (Inline synthetic ASL for minter mechanics only — the verb-lemma dup-rig
  # precedent; upstream-shape assertions stay on the real fixture.)
  def test_the_minter_survives_same_named_records_and_restated_values
    Dir.mktmpdir("nabu-value-signs-dup") do |root|
      cone = File.join(root, "canonical", "osl", "00lib")
      FileUtils.mkdir_p(cone)
      File.write(File.join(cone, "osl.asl"),
                 "@sign ZA\n@oid\to0000001\n@v\tzu\n@v\tzu\n" \
                 "@form ZA\n@oid\to0000002\n@v\tzu\n@@\n@end sign\n")
      out_dir = File.join(root, "out")
      FileUtils.mkdir_p(out_dir)

      builder = Nabu::DataBuild::ValueSignsBuilder.new(canonical_dir: File.join(root, "canonical"))
      result = builder.build(catalog: nil, out_dir: out_dir)
      assert_equal 3, result.resources.first.rows

      values = read_table(out_dir, "value-signs.csv")
      ids = values.map { |row| row["ID"] }
      assert_equal 3, ids.uniq.size, "same-named records and restated values must never collide"
      assert_equal "#{ids[0]}-2", ids[1], "a verbatim restatement on the same record is suffixed, never dropped"
      refute_equal ids[0], ids[2].sub(/-\d+\z/, ""), "the form's own @oid keys its digest"
      assert_equal %w[true true true], values.map { |row| row["Ambiguous"] },
                   "zu resolves to two distinct records — every row is flagged"

      signs = read_table(out_dir, "signs.csv")
      assert_equal(%w[s-o0000001 s-o0000002], signs.map { |row| row["ID"] })
      assert_equal([nil, "o0000001"], signs.map { |row| row["Parent_OID"] })
    end
  end

  def test_a_missing_canonical_input_refuses_with_a_sync_hint
    Dir.mktmpdir("nabu-value-signs-missing") do |root|
      builder = Nabu::DataBuild::ValueSignsBuilder.new(canonical_dir: File.join(root, "canonical"))
      error = assert_raises(Nabu::DataBuild::Error) do
        builder.build(catalog: nil, out_dir: root)
      end
      assert_match(/osl/, error.message)
      assert_match(/sync/, error.message)
    end
  end

  # The stale-ingest guard covers the osl cone (owner ruling D50-a): with a
  # catalog open, a canonical/osl that advanced past the recorded ingest
  # refuses — the dataset must never cite bytes its rows were not read from.
  def test_the_stale_ingest_guard_covers_the_osl_cone
    with_env do |root, canonical, config|
      catalog = store_test_db
      cone = File.join(canonical, "osl")
      Nabu::Store::Source.create(slug: "osl", name: "osl", adapter_class: "Nabu::Adapters::Osl",
                                 license_class: "open",
                                 last_ingest_identity: Nabu::DerivationFingerprint.canonical_identity(cone))

      summary = run_build(root, canonical, config, catalog: catalog)
      assert File.file?(File.join(summary.out_dir, "datapackage.json")), "a fresh ingest builds"

      File.write(File.join(cone, "00lib", "drifted.asl"), "@sign X\n@end sign\n")
      error = assert_raises(Nabu::DataBuild::Error) do
        run_build(root, canonical, config, into: File.join(root, "again"), catalog: catalog)
      end
      assert_match(/osl/, error.message)
      assert_match(/changed since/, error.message)
    end
  end
end
