# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::QieyunCrosswalk (P107, the Q78 sidecar harvest): the
# qieyun-restored repo's to_tshet_uinh_data/small_rimes.csv — 3,385
# small rimes with the 對應廣韻小韻號 join key — becomes kind=reference
# edges between the qieyun shelf's representative entries (頁.行,
# resolved through 藤田條目號 = the representative row's 序数) and the
# held guangyun shelf's small-rime heads (小韻號.1). The join is NOT the
# identity past 東 (冬 opens at qieyun 33 → guangyun 35 — the Guangyun
# added rimes), which is why the upstream table, not arithmetic, is the
# authority.
class QieyunCrosswalkTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("qieyun-restored")

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
  end

  def teardown
    @journal.disconnect
  end

  def crosswalk
    Nabu::QieyunCrosswalk.new(catalog: @catalog, journal: @journal)
  end

  def test_mints_small_rime_edges_qieyun_to_guangyun
    result = crosswalk.run("qieyun-restored", workdir: FIXTURES)

    assert_equal 35, result.edges_written, "every fixture small rime resolves and joins"
    assert_equal 0, result.skipped_unmapped

    edges = @journal[:links].where(kind: "reference").all
    dong = edges.find { |e| e[:from_urn] == "urn:nabu:dict:qieyun:1.1" }
    refute_nil dong, "東 heads the crosswalk"
    assert_equal "urn:nabu:dict:guangyun:1.1", dong[:to_urn]
    assert_includes dong[:detail], "東"
    assert_includes dong[:detail], "端一東平"
  end

  def test_the_join_is_the_upstream_table_not_arithmetic
    crosswalk.run("qieyun-restored", workdir: FIXTURES)
    dong_rime = @journal[:links].where(from_urn: "urn:nabu:dict:qieyun:5.12").first
    refute_nil dong_rime, "冬 (qieyun 小韻 33, representative row 5.12) joins"
    assert_equal "urn:nabu:dict:guangyun:35.1", dong_rime[:to_urn],
                 "qieyun 33 → guangyun 35: the Guangyun's added rimes shift the numbering"
  end

  def test_rerun_supersedes_the_prior_run_and_rederives_stably
    crosswalk.run("qieyun-restored", workdir: FIXTURES)
    second = crosswalk.run("qieyun-restored", workdir: FIXTURES)
    assert_equal 1, second.superseded_runs
    assert_equal 35, second.superseded_edges
    assert_equal 35, second.edges_written
  end

  # The shared 序数 numbering counts Li Yongfu's variant rows too, so a
  # rime's 藤田條目號 can name an ordinal Fujita's own table skips —
  # while the rime itself exists there, one row over (猪: pointer 1679,
  # Fujita's head 1680). The second lane resolves through upstream's own
  # (音韻地位, 代表字) pair against Fujita's small-rime HEAD rows only —
  # exact string equality, never arithmetic.
  def test_ordinal_misses_resolve_through_the_phonological_position_head_lane
    crosswalk.run("qieyun-restored", workdir: FIXTURES)
    zhu = @journal[:links].where(from_urn: "urn:nabu:dict:qieyun:29.56").first
    refute_nil zhu, "猪 (rime 224) resolves despite its ordinal missing from Fujita's table"
    assert_equal "urn:nabu:dict:guangyun:240.1", zhu[:to_urn]
  end

  def test_a_workdir_without_the_tables_is_the_honest_no_op
    Dir.mktmpdir do |empty|
      result = crosswalk.run("qieyun-restored", workdir: empty)
      assert_nil result.run_id
      assert_equal 0, result.edges_written
    end
  end

  def test_a_representative_row_missing_from_the_main_table_counts_unmapped
    Dir.mktmpdir do |dir|
      # Real bytes, trimmed shorter in place: the main table's first 100
      # lines lose 冬's rows, so its two small rimes cannot resolve.
      File.write(File.join(dir, Nabu::QieyunCrosswalk::MAIN_CSV),
                 File.readlines(File.join(FIXTURES, Nabu::QieyunCrosswalk::MAIN_CSV)).first(100).join)
      FileUtils.mkdir_p(File.join(dir, "to_tshet_uinh_data"))
      FileUtils.cp(File.join(FIXTURES, "to_tshet_uinh_data", "small_rimes.csv"),
                   File.join(dir, "to_tshet_uinh_data", "small_rimes.csv"))
      result = crosswalk.run("qieyun-restored", workdir: dir)
      assert_operator result.skipped_unmapped, :>=, 1, "unresolved rows are counted, never guessed"
      assert_equal 35, result.edges_written + result.skipped_unmapped
    end
  end

  def test_the_producer_rides_the_reference_seam
    assert Nabu::Adapters::QieyunRestored.reference_edges?
    producer = Nabu::Adapters::QieyunRestored.reference_producer(catalog: @catalog, journal: @journal)
    assert_instance_of Nabu::QieyunCrosswalk, producer
  end
end
