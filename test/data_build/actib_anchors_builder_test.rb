# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"
require "digest"

# The xct/actib-anchors builder (P55-4) — nabu-data's FIRST RE-PUBLICATION:
# every derge-kangyur passage anchored to its ACTib v2.0 seg line by
# (volume, page, line), with the match census published in-band as the eval.
# The 800 MB seg+POS content is NOT republished — rows carry only the join
# key into the DOI-cited Zenodo artifact plus the URN+sha anchor into Nabu;
# near/partial rows republish both folded text forms in divergences.csv.
#
# Fixture facts (test/fixtures/data_build/actib/README.md): the ACTib side is
# a real trim of BDRC volume I1KG9167 (= Esukhia volume 41), pages 1-8 and
# 65-70; the derge side is the volume-41 folio skeleton (full text folios
# 1a-4b, bare brackets through 34b — x-folios 33xa/33xb included, shifting
# folio 34a to physical page 69) plus the volume-31 folio-restart witness.
# The catalog side is SYNTHETIC by convention, constructed against the real
# ACTib bytes to exercise all five statuses.
class DataBuildActibAnchorsBuilderTest < Minitest::Test
  include StoreTestDB

  FIXTURES = File.join(Nabu::TestSupport::FIXTURES_ROOT, "data_build", "actib")

  ANCHORS_COLUMNS = %w[ID URN Passage_SHA256 ACTib_Volume ACTib_Page ACTib_Line Status Distance].freeze
  DIVERGENCES_COLUMNS = %w[ID URN Passage_SHA256 ACTib_Volume ACTib_Page ACTib_Line Status Distance
                           Nabu_Text ACTib_Text].freeze

  DOC56 = "urn:nabu:derge-kangyur:toh56" # multi-volume: refs are volume-prefixed
  DOC57 = "urn:nabu:derge-kangyur:toh57" # single-volume: refs are bare page.line

  # The fixture-canonical builder (the MeterBuilder TestMeterBuilder
  # precedent — the constructor seam exists exactly for this).
  class TestBuilder < Nabu::DataBuild::ActibAnchorsBuilder
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
      derge-kangyur:
        adapter: Nabu::Adapters::DergeKangyur
        wired: true
        sync_policy: manual
      actib:
        adapter: Nabu::Adapters::Actib
        kind: module
        wired: false
        sync_policy: manual
    YAML
  end

  def with_build_env
    Dir.mktmpdir("nabu-actib-anchors") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      FileUtils.cp_r(File.join(FIXTURES, "derge-kangyur"), File.join(canonical, "derge-kangyur"))
      FileUtils.cp_r(File.join(FIXTURES, "actib"), File.join(canonical, "actib"))
      sources = File.join(root, "sources.yml")
      File.write(sources, sources_yml)
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      catalog = store_test_db
      seed_catalog!(canonical)
      TestBuilder.canonical_dir = canonical
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources),
                                           catalog: catalog)
      yield root, runner, catalog, canonical
    ensure
      TestBuilder.canonical_dir = nil
    end
  end

  # The real ACTib letters, re-derived from the fixture bytes by a direct
  # re-reading of the token grammar (p<N>/ln<N> markers, <utt> dropped,
  # letters concatenated, NFC) — the catalog side is constructed FROM these
  # so exact/near/partial are exercised against real upstream bytes.
  def actib_letters
    @actib_letters ||= begin
      map = Hash.new { |hash, key| hash[key] = +"" }
      page = nil
      line = nil
      path = File.join(FIXTURES, "actib", "seg", "UT4CZ5369-I1KG9167-0000.txt")
      File.foreach(path, encoding: Encoding::UTF_8) do |raw|
        raw.split.each do |token|
          next if token == "<utt>"

          if (m = /\Ap(\d+)\z/.match(token))
            page = m[1].to_i
            line = nil
          elsif (m = /\Aln(\d+)\z/.match(token))
            line = m[1].to_i
          else
            map[[page, line]] << token
          end
        end
      end
      map.transform_values { |value| value.unicode_normalize(:nfc) }
    end
  end

  # One deterministic single-letter substitution (a distance-1 NEAR, never a
  # containment).
  def mutated(text)
    copy = text.dup
    copy[10] = copy[10] == "ག" ? "ཀ" : "ག"
    copy
  end

  # The synthetic catalog: one multi-volume document (toh56 spans vols
  # 40-41 upstream, so refs are volume-prefixed) and one single-volume
  # document, exercising exact / near / partial / missing / badref plus the
  # x-folio page shift.
  def seed_catalog!(canonical)
    derge = Nabu::Store::Source.create(slug: "derge-kangyur", name: "derge-kangyur",
                                       adapter_class: "Nabu::Adapters::DergeKangyur", license_class: "open")
    actib = Nabu::Store::Source.create(slug: "actib", name: "actib",
                                       adapter_class: "Nabu::Adapters::Actib", license_class: "attribution")

    seed_document!(derge, DOC56, volumes: [40, 41], passages: {
                     "41.1a.1" => actib_letters[[1, nil]], # p1 carries no ln markers → missing
                     "41.1b.1" => actib_letters[[2, 1]],               # exact
                     "41.1b.2" => mutated(actib_letters[[2, 2]]),      # near, distance 1
                     "41.1b.3" => actib_letters[[2, 3]][5..],          # partial (containment)
                     "41.34a.1" => actib_letters[[69, 1]], # exact via the x-folio shift
                     "41.99a.1" => "བོད" # folio outside the volume → missing
                   })
    seed_document!(derge, DOC57, volumes: [41], passages: {
                     "2a.1" => actib_letters[[3, 1]], # exact, bare single-volume ref
                     "9x9" => "བོད" # fails the ref grammar → badref
                   })

    { derge => "derge-kangyur", actib => "actib" }.each do |source, slug|
      identity = Nabu::DerivationFingerprint.canonical_identity(File.join(canonical, slug))
      source.update(last_ingest_identity: identity)
    end
  end

  def seed_document!(source, doc_urn, volumes:, passages:)
    doc = Nabu::Store::Document.create(source_id: source.id, urn: doc_urn, title: doc_urn,
                                       language: "xct", metadata_json: JSON.generate("volumes" => volumes),
                                       content_sha256: Digest::SHA256.hexdigest(doc_urn),
                                       revision: 1, withdrawn: false)
    passages.each_with_index do |(ref, text), sequence|
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "#{doc_urn}:#{ref}", sequence: sequence, language: "xct",
        text: text, text_normalized: text,
        content_sha256: Digest::SHA256.hexdigest(text), revision: 1, withdrawn: false
      )
    end
  end

  # The registry feature with the builder swapped for the fixture rig.
  def test_feature
    real = Nabu::DataBuild.feature("xct/actib-anchors")
    Nabu::DataBuild::Feature.new(
      slug: real.slug, language: real.language, title: real.title, status: :available,
      tier: real.tier, anchoring: real.anchoring, inputs: real.inputs,
      canonical_cones: real.canonical_cones, rationale: real.rationale,
      maintenance: real.maintenance, builder: TestBuilder
    )
  end

  def build!(root, runner, into: File.join(root, "nabu-data"))
    summary = runner.run(feature: test_feature, into: into)
    [summary, summary.out_dir]
  end

  def read_csv(dir, name)
    CSV.read(File.join(dir, name), headers: true)
  end

  def read_manifest(dir)
    JSON.parse(File.read(File.join(dir, "datapackage.json")))
  end

  # -- the registry flip -----------------------------------------------------

  def test_the_feature_is_available_with_the_builder_wired
    feature = Nabu::DataBuild.feature("xct/actib-anchors")
    assert feature.available?, "P55-4 lands xct/actib-anchors :available"
    assert_equal Nabu::DataBuild::ActibAnchorsBuilder, feature.builder
    assert_equal "gold-derived", feature.tier
    assert_equal "urn+sha", feature.anchoring
    assert_equal %w[derge-kangyur actib], feature.inputs,
                 "both cones are declared inputs — the stale-ingest guard must cover them"
    assert_equal feature.inputs, feature.canonical_cones
  end

  # -- the volume permutation and file naming, pinned ------------------------

  def test_the_bdrc_volume_permutation_is_pinned
    assert_equal({ 100 => 101, 101 => 102, 102 => 100 },
                 Nabu::DataBuild::ActibAnchorsBuilder::VOL_PERMUTATION,
                 "Esukhia 100=gzungs-'dus E, 101=WaM, 102=dri-med-'od; BDRC orders them 101/102/100")
    builder = Nabu::DataBuild::ActibAnchorsBuilder
    assert_equal "I1KG9127", builder.bdrc_volume(1)
    assert_equal "I1KG9167", builder.bdrc_volume(41)
    assert_equal "I1KG9227", builder.bdrc_volume(100), "the permutation applies before the I1KG offset"
    assert_equal "I1KG9228", builder.bdrc_volume(101)
    assert_equal "I1KG9226", builder.bdrc_volume(102)
    assert_equal "UT4CZ5369-I1KG9167-0000.txt", builder.seg_filename(41)
  end

  # -- the folio→page walk ---------------------------------------------------

  def walk
    @walk ||= Nabu::DataBuild::ActibAnchorsBuilder::FolioPageWalk.new(
      Dir.glob(File.join(FIXTURES, "derge-kangyur", "text", "*.txt"))
    )
  end

  def test_the_walk_counts_x_folios_as_physical_pages
    assert_equal 65, walk.page_for(volume: 41, doc_slug: "toh56", folio: "33a")
    assert_equal 67, walk.page_for(volume: 41, doc_slug: "toh56", folio: "33xa")
    assert_equal 68, walk.page_for(volume: 41, doc_slug: "toh56", folio: "33xb")
    # The load-bearing shift: the naive 2F-1 rule would put 34a at page 67;
    # the two x-folio sides push it to 69.
    assert_equal 69, walk.page_for(volume: 41, doc_slug: "toh56", folio: "34a")
  end

  def test_the_walk_keeps_per_document_maps_for_folio_restarts
    # Vol 31 (the census's vol-31 correction): folio numbering RESTARTS where
    # Toh 11 begins ({D11} on the restart's [1b.1]), so "1b" is ambiguous
    # volume-wide. Per-document maps disambiguate: toh11's 1b is the restart
    # page; a document whose marker predates the walked files (toh10 — {D10}
    # lives in vol 29) falls back to the volume-wide first occurrence.
    restart = walk.page_for(volume: 31, doc_slug: "toh11", folio: "1b")
    first = walk.page_for(volume: 31, doc_slug: "toh10", folio: "1b")
    assert_equal 4, restart, "toh11's 1b is the restart page (1a,1b,2a then the restart in the trim)"
    assert_equal 2, first, "an unknown document resolves via the volume-wide first occurrence"
    refute_equal first, restart, "the per-document map must beat the volume-wide map for toh11"
  end

  def test_the_walk_answers_nil_for_unknown_volume_or_folio
    assert_nil walk.page_for(volume: 99, doc_slug: "toh1", folio: "1a")
    assert_nil walk.page_for(volume: 41, doc_slug: "toh56", folio: "99a")
  end

  # -- the anchor rows -------------------------------------------------------

  def test_anchors_cover_every_parseable_passage_with_honest_statuses
    with_build_env do |root, runner, catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "anchors.csv")

      assert_equal ANCHORS_COLUMNS, table.headers
      assert_equal 7, table.size, "8 passages minus the 1 badref (censused, never faked as a row)"
      assert(table.all? { |row| row["ACTib_Volume"] == "I1KG9167" })

      statuses = table.to_h { |row| [row["URN"], row["Status"]] }
      assert_equal "missing", statuses.fetch("#{DOC56}:41.1a.1"), "p1 carries no ln markers upstream"
      assert_equal "exact", statuses.fetch("#{DOC56}:41.1b.1")
      assert_equal "near", statuses.fetch("#{DOC56}:41.1b.2")
      assert_equal "partial", statuses.fetch("#{DOC56}:41.1b.3")
      assert_equal "exact", statuses.fetch("#{DOC56}:41.34a.1")
      assert_equal "missing", statuses.fetch("#{DOC56}:41.99a.1")
      assert_equal "exact", statuses.fetch("#{DOC57}:2a.1")
      assert_nil statuses["#{DOC57}:9x9"], "the badref passage mints no row"

      shas = catalog[:passages].select_hash(:urn, :content_sha256)
      table.each do |row|
        assert_equal shas.fetch(row["URN"]), row["Passage_SHA256"],
                     "#{row['URN']}: Passage_SHA256 must be the catalog passage's content sha"
      end
    end
  end

  def test_the_x_folio_passage_anchors_at_the_shifted_page
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      row = read_csv(out_dir, "anchors.csv").find { |r| r["URN"] == "#{DOC56}:41.34a.1" }
      assert_equal %w[69 1 exact], row.values_at("ACTib_Page", "ACTib_Line", "Status"),
                   "folio 34a sits at physical page 69 (33xa/33xb shift it; naive 2F-1 says 67) " \
                   "and matches the real ACTib bytes there"
    end
  end

  def test_distance_rides_near_rows_only_and_missing_keeps_what_it_knows
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      rows = read_csv(out_dir, "anchors.csv").to_h { |row| [row["URN"], row] }

      assert_equal "1", rows.fetch("#{DOC56}:41.1b.2")["Distance"], "near rows carry the edit distance"
      %W[#{DOC56}:41.1b.1 #{DOC56}:41.1b.3 #{DOC56}:41.1a.1].each do |urn|
        assert_equal "", rows.fetch(urn)["Distance"].to_s, "#{urn}: Distance is empty off the near status"
      end

      # A missing row keeps the page it could still compute (the title folio
      # maps to p1; ACTib just has no ln-marked line there) — and an
      # unmappable folio keeps nothing.
      assert_equal %w[1 1], rows.fetch("#{DOC56}:41.1a.1").values_at("ACTib_Page", "ACTib_Line")
      assert_equal "", rows.fetch("#{DOC56}:41.99a.1")["ACTib_Page"].to_s
    end
  end

  def test_ids_obey_the_cldf_discipline_and_the_primary_key_is_honest
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      %w[anchors.csv divergences.csv].each do |name|
        table = read_csv(out_dir, name)
        ids = table.map { |row| row["ID"] }
        assert_equal ids.size, ids.uniq.size, "#{name}: IDs are unique"
        assert(ids.all? { |id| id.match?(Nabu::DataBuild::CsvWriter::ID_PATTERN) },
               "#{name}: every ID matches the CLDF identifier regex (URNs are never IDs)")
      end

      manifest = read_manifest(out_dir)
      %w[anchors divergences].each do |name|
        resource = manifest["resources"].find { |entry| entry["name"] == name }
        refute_nil resource
        assert_equal ["ID"], resource.dig("schema", "primaryKey")
      end
    end
  end

  # -- the divergences file --------------------------------------------------

  def test_divergences_republish_both_folded_text_forms
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      table = read_csv(out_dir, "divergences.csv")

      assert_equal DIVERGENCES_COLUMNS, table.headers
      assert_equal 2, table.size, "exactly the near + partial rows; missing/badref are censused, not faked"

      near = table.find { |row| row["Status"] == "near" }
      assert_equal "#{DOC56}:41.1b.2", near["URN"]
      assert_equal "1", near["Distance"]
      assert_equal mutated(actib_letters[[2, 2]]), near["Nabu_Text"]
      assert_equal actib_letters[[2, 2]], near["ACTib_Text"],
                   "ACTib_Text is the real upstream letters at the anchored line"

      partial = table.find { |row| row["Status"] == "partial" }
      assert_equal "#{DOC56}:41.1b.3", partial["URN"]
      assert_equal actib_letters[[2, 3]][5..], partial["Nabu_Text"]
      assert_equal actib_letters[[2, 3]], partial["ACTib_Text"]
      assert_equal "", partial["Distance"].to_s
    end
  end

  # -- the in-band eval ------------------------------------------------------

  def test_the_manifest_publishes_the_census_as_the_eval
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      eval_block = read_manifest(out_dir).dig("nabu", "eval")

      refute_nil eval_block, "the measured anchoring quality IS the eval"
      assert_equal 8, eval_block.fetch("passages")
      assert_equal 5, eval_block.fetch("compared")
      assert_equal 3, eval_block.fetch("exact")
      assert_equal 1, eval_block.fetch("near")
      assert_equal 1, eval_block.fetch("partial")
      assert_equal 2, eval_block.fetch("missing")
      assert_equal 1, eval_block.fetch("badref")
      assert_equal({ "1" => 1 }, eval_block.fetch("distance_histogram"))
      assert_in_delta 0.6, eval_block.fetch("exact_rate"), 0.0001
      assert_includes eval_block.fetch("against"), "3951503"
    end
  end

  def test_the_readme_states_the_join_contract_and_the_license_basis
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      readme = File.read(File.join(out_dir, "README.md"))

      assert_includes readme, "SegPOS-eKangyur_July2020.zip",
                      "the README names the DOI-cited artifact consumers join against"
      assert_includes readme, "10.5281/zenodo.3951503"
      assert_includes readme, "(ACTib_Volume, ACTib_Page, ACTib_Line)",
                      "the join key is stated where the consumer reads it"
      assert_match(/no license file/i, readme,
                   "the license basis is the Zenodo record — the in-zip absence is stated honestly")
      assert_includes readme, "urn:nabu:derge-kangyur:toh57:9x9",
                      "badref refs are censused by name in the README, never faked as rows"
    end
  end

  def test_the_recipe_states_the_mapping_precisely
    with_build_env do |root, runner, _catalog|
      _summary, out_dir = build!(root, runner)
      recipe = read_manifest(out_dir).dig("nabu", "derivation", "recipe")
      ["I1KG(9126+N)", "100→101", "x-folio", "vol-31", "Levenshtein", "NOT republished"].each do |claim|
        assert_includes recipe, claim, "the recipe states the derivation precisely"
      end
    end
  end

  # -- determinism -----------------------------------------------------------

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
    Dir.mktmpdir("nabu-actib-anchors") do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::ActibAnchorsBuilder.new.build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
      assert_empty Dir.children(dir), "a refusal must write nothing"
    end
  end

  def test_the_builder_refuses_a_catalog_without_derge_passages
    with_build_env do |_root, _runner, _catalog, canonical|
      Dir.mktmpdir("nabu-actib-anchors-empty") do |dir|
        error = assert_raises(Nabu::DataBuild::Error) do
          builder = Nabu::DataBuild::ActibAnchorsBuilder.new(canonical_dir: canonical)
          builder.build(catalog: store_test_db, out_dir: dir)
        end
        assert_match(/derge-kangyur/, error.message)
        assert_match(/sync/, error.message)
        assert_empty Dir.children(dir), "a refusal must write nothing"
      end
    end
  end

  def test_the_builder_refuses_a_missing_actib_seg_cone
    with_build_env do |_root, _runner, catalog, canonical|
      FileUtils.rm_rf(File.join(canonical, "actib", "seg"))
      Dir.mktmpdir("nabu-actib-anchors-noseg") do |dir|
        error = assert_raises(Nabu::DataBuild::Error) do
          builder = Nabu::DataBuild::ActibAnchorsBuilder.new(canonical_dir: canonical)
          builder.build(catalog: catalog, out_dir: dir)
        end
        assert_match(/actib/, error.message)
        assert_match(/sync actib/, error.message)
        assert_empty Dir.children(dir), "a refusal must write nothing"
      end
    end
  end
end
