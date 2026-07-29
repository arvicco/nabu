# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"

# The xct/segmentation builder (P51-W5) — the curated-slice dataset: every
# live soas-tibetan document (gold segmentation + gold POS, verbatim from the
# deposit) plus ONE small Kangyur text, silver-segmented by the unigram
# Viterbi segmenter trained on the SOAS gold token counts, with the
# leave-one-text-out eval published in the manifest's nabu.eval block.
#
# Fixture facts (hand-censused 2026-07-29 from the real trimmed fixtures):
#   soas-tibetan: marpa 2 gold lines (13 + 105 tokens), mdzangsblun 3 gold
#   lines (377 + 415 + 419 tokens) → 5 passages, 1,329 gold tokens.
#   mdzangsblun line 1 opens "།|punc མཛངས་བླུན་|n.count …" — the spot-check row.
#   derge-kangyur: toh846a has 6 passages (the test slice; the production
#   default Toh 21 is not in the fixture trim, and its absence must refuse).
class DataBuildSegmentationBuilderTest < Minitest::Test
  include StoreTestDB

  SOAS_FIXTURES = Nabu::TestSupport.fixtures("soas-tibetan")
  DERGE_FIXTURES = Nabu::TestSupport.fixtures("derge-kangyur")

  COLUMNS = %w[ID URN Passage_SHA256 Position Form Offset Tier Source].freeze
  GOLD_TOKENS = 1329
  GOLD_PASSAGES = 5
  TEST_SLICE = ["urn:nabu:derge-kangyur:toh846a"].freeze

  # The test slice builder: the production default (Toh 21) is not in the
  # fixture trim, so tests pin the slice to the fixture's small toh846a —
  # the kangyur_slice seam exists exactly for this (the adapter pin: pattern).
  class TestSliceBuilder < Nabu::DataBuild::SegmentationBuilder
    def initialize
      super(kangyur_slice: TEST_SLICE)
    end
  end

  # -- rig -------------------------------------------------------------------

  def load_source(db, slug:, adapter:, workdir:)
    source = Nabu::Store::Source.create(
      slug: slug, name: adapter.class.manifest.name,
      adapter_class: adapter.class.name, license_class: adapter.class.manifest.license_class
    )
    Nabu::Store::Loader.new(db: db, source: source, ledger: nil).load_from(adapter, workdir: workdir)
    source.update(last_ingest_identity: Nabu::DerivationFingerprint.canonical_identity(workdir))
  end

  def sources_yml
    <<~YAML
      derge-kangyur:
        adapter: Nabu::Adapters::DergeKangyur
        wired: true
        sync_policy: manual
      soas-tibetan:
        adapter: Nabu::Adapters::SoasTibetan
        wired: true
        sync_policy: manual
    YAML
  end

  def with_build_env
    Dir.mktmpdir("nabu-segmentation") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      FileUtils.cp_r(SOAS_FIXTURES, File.join(canonical, "soas-tibetan"))
      FileUtils.cp_r(DERGE_FIXTURES, File.join(canonical, "derge-kangyur"))
      sources = File.join(root, "sources.yml")
      File.write(sources, sources_yml)
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      catalog = store_test_db
      load_source(catalog, slug: "soas-tibetan", adapter: Nabu::Adapters::SoasTibetan.new,
                           workdir: File.join(canonical, "soas-tibetan"))
      load_source(catalog, slug: "derge-kangyur", adapter: Nabu::Adapters::DergeKangyur.new,
                           workdir: File.join(canonical, "derge-kangyur"))
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources),
                                           catalog: catalog)
      yield root, runner, catalog
    end
  end

  # The registry feature with the builder swapped for the fixture-slice rig.
  def test_feature
    real = Nabu::DataBuild.feature("xct/segmentation")
    Nabu::DataBuild::Feature.new(
      slug: real.slug, language: real.language, title: real.title, status: :available,
      tier: real.tier, anchoring: real.anchoring, inputs: real.inputs,
      canonical_cones: real.canonical_cones, rationale: real.rationale,
      maintenance: real.maintenance, builder: TestSliceBuilder
    )
  end

  def build!(root, runner, into: File.join(root, "nabu-data"))
    summary = runner.run(feature: test_feature, into: into)
    [summary, summary.out_dir]
  end

  def read_csv(dir)
    CSV.read(File.join(dir, "segmentation.csv"), headers: true)
  end

  def read_manifest(dir)
    JSON.parse(File.read(File.join(dir, "datapackage.json")))
  end

  # -- the flip --------------------------------------------------------------

  def test_the_feature_is_available_with_the_builder_wired
    feature = Nabu::DataBuild.feature("xct/segmentation")
    assert feature.available?, "P51-W5 flips xct/segmentation to :available"
    assert_equal Nabu::DataBuild::SegmentationBuilder, feature.builder
    assert_equal "silver", feature.tier
    assert_equal "passage-urn", feature.anchoring
  end

  def test_the_production_slice_is_the_heart_sutra
    assert_equal ["urn:nabu:derge-kangyur:toh21"],
                 Nabu::DataBuild::SegmentationBuilder::KANGYUR_SLICE,
                 "the curated Kangyur slice is Toh 21 (Shes rab snying po), pinned in the recipe"
  end

  # -- gold rows -------------------------------------------------------------

  def test_gold_rows_carry_the_soas_tokens_verbatim
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir)
      assert_equal COLUMNS, table.headers

      gold = table.select { |row| row["Tier"] == "gold" }
      assert_equal GOLD_TOKENS, gold.size, "one gold row per SOAS form|tag token (hand-censused 1,329)"
      assert_equal GOLD_PASSAGES, gold.map { |row| row["URN"] }.uniq.size
      assert(gold.all? { |row| row["Source"] == "soas574878" })

      # mdzangsblun line 1 opens "།|punc མཛངས་བླུན་|n.count": the shad is
      # token 1 at offset 0, the title word token 2 at offset 1.
      first_two = table.select { |row| row["URN"] == "urn:nabu:soas-tibetan:mdzangsblun:1" }
                       .sort_by { |row| Integer(row["Position"]) }.first(2)
      assert_equal ["།", "0", "1"], first_two[0].values_at("Form", "Offset", "Position")
      assert_equal ["མཛངས་བླུན་", "1", "2"], first_two[1].values_at("Form", "Offset", "Position")
    end
  end

  # -- silver rows over the Kangyur slice ------------------------------------

  def test_silver_rows_cover_exactly_the_slice_passages
    with_build_env do |root, runner, catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir)

      silver = table.select { |row| row["Tier"] == "silver" }
      refute_empty silver
      assert(silver.all? { |row| row["Source"] == "derge" })

      slice_urns = catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                                     .where(Sequel[:documents][:urn] => TEST_SLICE.first)
                                     .select_map(Sequel[:passages][:urn])
      assert_equal 6, slice_urns.size, "fixture toh846a has 6 passages (hand-censused)"
      assert_equal slice_urns.sort, silver.map { |row| row["URN"] }.uniq.sort,
                   "every slice passage is segmented; nothing outside the slice leaks in"
    end
  end

  # -- the anchoring contract ------------------------------------------------

  def test_every_row_anchors_honestly_into_the_catalog_passage
    with_build_env do |root, runner, catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir)

      texts = catalog[:passages].select_hash(:urn, :text)
      shas = catalog[:passages].select_hash(:urn, :content_sha256)
      table.each do |row|
        urn = row["URN"]
        assert_equal shas.fetch(urn), row["Passage_SHA256"],
                     "#{urn}: Passage_SHA256 must be the catalog passage's content sha"
        form = row["Form"]
        offset = Integer(row["Offset"])
        assert_equal form, texts.fetch(urn)[offset, form.length],
                     "#{urn} position #{row['Position']}: Form must be the exact substring at Offset"
      end

      # Positions are 1-based and contiguous per passage.
      table.group_by { |row| row["URN"] }.each_value do |rows|
        positions = rows.map { |row| Integer(row["Position"]) }.sort
        assert_equal (1..rows.size).to_a, positions
      end
    end
  end

  def test_ids_are_unique_and_the_primary_key_is_honest
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir)
      ids = table.map { |row| row["ID"] }
      assert_equal ids.size, ids.uniq.size
      assert(ids.all? { |id| id.match?(Nabu::DataBuild::CsvWriter::ID_PATTERN) })

      manifest = read_manifest(out_dir)
      segmentation = manifest["resources"].find { |resource| resource["name"] == "segmentation" }
      assert_equal ["ID"], segmentation.dig("schema", "primaryKey")
    end
  end

  # -- the CoNLL-U projection ------------------------------------------------

  def test_the_conllu_projection_carries_gold_pos_and_invents_nothing
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      conllu = File.read(File.join(out_dir, "segmentation.conllu"))

      assert_includes conllu, "# sent_id = urn:nabu:soas-tibetan:mdzangsblun:1\n"
      assert_includes conllu, "# sent_id = urn:nabu:derge-kangyur:toh846a:3b.1\n"
      # Gold rows carry the real SOAS tag in XPOS; UPOS/LEMMA are never
      # invented; tokens join with nothing → SpaceAfter=No.
      assert_includes conllu, "2\tམཛངས་བླུན་\t_\t_\tn.count\t_\t_\t_\t_\tSpaceAfter=No\n"
      # Silver rows carry no POS at all.
      silver_block = conllu[/# sent_id = urn:nabu:derge-kangyur:toh846a:3b\.1\n.*?\n\n/m]
      refute_nil silver_block
      silver_block.lines.grep(/\A\d/).each do |line|
        fields = line.chomp.split("\t")
        assert_equal 10, fields.size
        assert_equal %w[_ _ _], fields.values_at(2, 3, 4), "no invented lemma/UPOS/XPOS on silver rows"
      end

      manifest = read_manifest(out_dir)
      resource = manifest["resources"].find { |entry| entry["name"] == "segmentation-conllu" }
      refute_nil resource
      assert_nil resource["schema"], "the CoNLL-U projection is a non-tabular resource"
      assert_equal "conllu", resource["format"]
    end
  end

  # -- the in-band eval ------------------------------------------------------

  def test_the_manifest_publishes_the_eval_in_the_nabu_block
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      manifest = read_manifest(out_dir)

      eval_block = manifest.dig("nabu", "eval")
      refute_nil eval_block, "the eval is the dataset's headline — it must ride the manifest"
      assert_includes eval_block.fetch("against"), "soas-tibetan"
      assert_match(/leave-one-text-out/, eval_block.fetch("protocol"))
      assert_match(/clean/, eval_block.fetch("contamination"))
      f1 = eval_block.fetch("boundary_f1")
      assert f1.positive? && f1 <= 1.0, "boundary F1 must be a real score, got #{f1.inspect}"
      assert_equal 2, eval_block.fetch("texts")
      assert_equal GOLD_PASSAGES, eval_block.fetch("lines")
      assert_equal GOLD_TOKENS, eval_block.fetch("tokens")

      readme = File.read(File.join(out_dir, "README.md"))
      assert_includes readme, format("%.4f", f1), "the README quotes the same eval number"
      assert_match(/Toh 21|toh21/, readme, "the README states the production slice definition")
    end
  end

  def test_the_recipe_states_the_slice_and_the_eval_protocol
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      recipe = read_manifest(out_dir).dig("nabu", "derivation", "recipe")
      %w[toh846a leave-one-text-out unigram Viterbi].each do |claim|
        assert_includes recipe, claim, "the recipe states the derivation precisely"
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

  # -- refusals --------------------------------------------------------------

  def test_the_builder_refuses_without_a_catalog
    Dir.mktmpdir("nabu-segmentation") do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::SegmentationBuilder.new.build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
      assert_empty Dir.children(dir), "a refusal must write nothing"
    end
  end

  def test_the_builder_refuses_a_catalog_without_soas_gold
    Dir.mktmpdir("nabu-segmentation") do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::SegmentationBuilder.new.build(catalog: store_test_db, out_dir: dir)
      end
      assert_match(/soas-tibetan/, error.message)
      assert_match(/sync/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_a_missing_slice_document_refuses_by_name
    with_build_env do |_root, _runner, catalog|
      Dir.mktmpdir("nabu-segmentation-slice") do |dir|
        error = assert_raises(Nabu::DataBuild::Error) do
          # The production default: Toh 21 is not in the fixture trim.
          Nabu::DataBuild::SegmentationBuilder.new.build(catalog: catalog, out_dir: dir)
        end
        assert_match(/toh21/, error.message)
        assert_match(/sync derge-kangyur/, error.message)
        assert_empty Dir.children(dir), "a refusal must write nothing"
      end
    end
  end
end
