# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::KyotoKanripoCrosswalk (P33-3): the UD Kyoto treebank's own Kanripo
# ids as kind=reference edges treebank-file ↔ kanripo-text. The censused id
# map (upstream master, 2026-07-20): every one of the 936 `# newdoc id`
# lines across the three real splits is `<KR-id>_<juan>` — ten distinct
# texts, all named in Kanripo's KR id space. Fixtures are trimmed REAL
# slices: the P32-0 head-50 of the test split (one newdoc, KR1h0004_001 —
# 論語 book 1) plus six real newdoc blocks of the dev split covering five
# texts across wave-1 (KR1h0004 ×2, KR1h0001, KR4a0001), out-of-wave KR2
# (KR2e0003) and phase-excluded KR6 (KR6f0082).
class KyotoKanripoCrosswalkTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("ud")

  LUNYU = "urn:nabu:kanripo:KR1h0004"
  TEST_HEAD50 = "urn:nabu:ud:classical-chinese-kyoto:lzh_kyoto-ud-test-head50"
  DEV_SLICES = "urn:nabu:ud:classical-chinese-kyoto:lzh_kyoto-ud-dev-slices"

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
  end

  def teardown
    @journal.disconnect
  end

  def producer
    Nabu::KyotoKanripoCrosswalk.new(catalog: @catalog, journal: @journal)
  end

  # --- minting: one edge per (conllu file, kanripo text) pair ----------------

  def test_mints_one_edge_per_file_text_pair
    result = producer.run("ud", workdir: FIXTURES)

    assert_equal 6, result.edges_written,
                 "dev-slices names 5 texts + test-head50 names 1 (KR1h0004 again, its own file's edge)"
    assert_equal 0, result.edges_refreshed
    assert_equal 0, result.skipped_unmapped, "all real newdoc ids are KR-shaped (the census)"
    assert_equal 6, @journal[:links].count
    assert_equal ["reference"], @journal[:links].select_map(:kind).uniq
    assert_equal [nil], @journal[:links].select_map(:score).uniq,
                 "an upstream naming assertion is not a mined similarity — no fake number"
    assert(@journal[:links].select_map(:from_urn).all? do |urn|
      urn.start_with?("urn:nabu:ud:classical-chinese-kyoto:")
    end, "the treebank file asserts the ids — it is always the from side")
    assert(@journal[:links].select_map(:to_urn).all? { |urn| urn.start_with?("urn:nabu:kanripo:KR") })
  end

  def test_out_of_wave_and_excluded_class_ids_still_mint
    producer.run("ud", workdir: FIXTURES)

    to_urns = @journal[:links].where(from_urn: DEV_SLICES).select_map(:to_urn).sort
    assert_equal %w[
      urn:nabu:kanripo:KR1h0001
      urn:nabu:kanripo:KR1h0004
      urn:nabu:kanripo:KR2e0003
      urn:nabu:kanripo:KR4a0001
      urn:nabu:kanripo:KR6f0082
    ], to_urns, "KR2 (P33-1) and KR6 (excluded — CBETA is the Buddhist shelf) still mint: " \
                "dangling-but-stable, the P32-6 precedent — they resolve when their wave syncs"
  end

  # --- the 論語 edge, pinned end-to-end --------------------------------------

  def test_pins_the_lunyu_edge_end_to_end
    load_fixture_sources!
    producer.run("ud", workdir: FIXTURES)

    edge = @journal[:links].first(from_urn: TEST_HEAD50, to_urn: LUNYU)
    refute_nil edge, "the crosswalk anchor: 論語 named by its own newdoc id"
    assert_equal "reference", edge[:kind]
    assert_nil edge[:score]
    assert_equal "newdoc KR1h0004_001 · 1 juan", edge[:detail]

    dev_edge = @journal[:links].first(from_urn: DEV_SLICES, to_urn: LUNYU)
    assert_equal "newdoc KR1h0004_012…KR1h0004_013 · 2 juan", dev_edge[:detail],
                 "first…last span plus exact count — juan sets are not always contiguous upstream"

    result = Nabu::Query::Links.new(catalog: @catalog, journal: @journal).run(LUNYU)
    counterparts = result.groups.fetch("reference")
    assert_equal [DEV_SLICES, TEST_HEAD50], counterparts.map(&:urn).sort,
                 "`nabu links` on the kanripo text serves both treebank files"
    assert counterparts.all?(&:resolved?),
           "both ud counterparts resolve against the loaded catalog"
    assert_equal "論語", result.title,
                 "the queried kanripo document resolves to its own title"
  end

  # --- honesty counters ------------------------------------------------------

  def test_a_non_kr_newdoc_id_is_counted_not_minted
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "classical-chinese-kyoto"))
      conllu = <<~CONLLU
        # newdoc id = KR1h0004_001
        # sent_id = KR1h0004_001_title
        # text = 學
        1\t學\t學\tVERB\t_\t_\t0\troot\t_\t_

        # newdoc id = extra-text
        # sent_id = extra-text_1
        # text = 學
        1\t學\t學\tVERB\t_\t_\t0\troot\t_\t_
      CONLLU
      File.write(File.join(dir, "classical-chinese-kyoto", "lzh_kyoto-ud-test.conllu"), conllu)

      result = producer.run("ud", workdir: dir)
      assert_equal 1, result.edges_written
      assert_equal 1, result.skipped_unmapped,
                   "a newdoc id outside the KR grammar mints nothing and is counted"
    end
  end

  # --- run mechanics ---------------------------------------------------------

  def test_rerun_supersedes_the_prior_edges
    first = producer.run("ud", workdir: FIXTURES)
    second = producer.run("ud", workdir: FIXTURES)

    assert_equal first.edges_written, second.edges_written
    assert_equal 1, second.superseded_runs
    assert_equal first.edges_written, second.superseded_edges
    assert_equal first.edges_written, @journal[:links].count,
                 "the journal holds exactly the current treebank's assertions"
    run = @journal[:link_runs].first(id: second.run_id)
    assert_equal "ud-kanripo", run[:producer]
    assert_equal "ud", run[:scope]
  end

  def test_a_workdir_without_the_kyoto_treebank_is_a_no_op_that_supersedes_nothing
    producer.run("ud", workdir: FIXTURES)
    Dir.mktmpdir do |empty|
      result = producer.run("ud", workdir: empty)
      assert_equal 0, result.edges_written
      assert_equal 0, result.superseded_runs,
                   "a workdir before the kyoto treebank's first sync must never wipe standing edges"
      assert_nil result.run_id
    end
    assert_equal 6, @journal[:links].count
  end

  private

  # Both catalog sides of the pinned edge: the ud fixtures (the asserting
  # treebank files) and the kanripo fixtures (KR1h0004 among them), loaded
  # through the real adapters.
  def load_fixture_sources!
    ud = Nabu::Store::Source.create(
      slug: "ud", name: "Universal Dependencies",
      adapter_class: "Nabu::Adapters::UniversalDependencies", license_class: "nc"
    )
    Nabu::Store::Loader.new(db: @catalog, source: ud)
                       .load_from(Nabu::Adapters::UniversalDependencies.new,
                                  workdir: FIXTURES, full: true)

    kanripo = Nabu::Store::Source.create(
      slug: "kanripo", name: "Kanripo",
      adapter_class: "Nabu::Adapters::Kanripo", license_class: "attribution"
    )
    Nabu::Store::Loader.new(db: @catalog, source: kanripo)
                       .load_from(Nabu::Adapters::Kanripo.new,
                                  workdir: Nabu::TestSupport.fixtures("kanripo"), full: true)
  end
end
