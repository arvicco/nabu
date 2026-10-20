# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Eras (P118-5): the shared Indian-calendar era table —
# config/eras.yml rows (Śaka, Vikrama, Kollam, Gupta–Valabhī) mapping an
# era year to a CE envelope, with the two-value eras carrying an explicit
# uncertainty width (the titus-bactrian ERA_OFFSETS envelope, generalized).
class ErasTest < Minitest::Test
  def teardown = Nabu::Eras.reset!

  def eras = Nabu::Eras.default

  def test_the_shipped_table_loads_all_four_indian_eras
    refute_nil eras, "config/eras.yml is ruled repo config"
    assert_equal %w[gupta_valabhi kollam saka vikrama], eras.keys.reject { |key| eras.family(key) == "nengo" }.sort
  end

  def test_saka_is_a_single_offset_plus_seventy_eight
    conversion = eras.to_ce("saka", 1208)
    assert_equal 1286, conversion.not_before
    assert_equal 1286, conversion.not_after
    assert_equal 0, conversion.width, "Śaka is ruled single-valued (+78)"
  end

  def test_vikrama_is_a_single_offset_minus_fifty_seven
    conversion = eras.to_ce("vikrama", 1100)
    assert_equal [1043, 1043], [conversion.not_before, conversion.not_after]
  end

  def test_gupta_valabhi_is_a_two_value_envelope
    conversion = eras.to_ce("gupta_valabhi", 98)
    assert_equal [417, 418], [conversion.not_before, conversion.not_after],
                 "GE 98 straddles 417/418 CE — the envelope, never a picked epoch"
    assert_equal 1, conversion.width
  end

  def test_kollam_is_a_two_value_envelope
    conversion = eras.to_ce("kollam", 100)
    assert_equal [924, 925], [conversion.not_before, conversion.not_after]
    assert_equal 1, conversion.width
  end

  def test_a_bce_result_skips_year_zero_in_the_signed_convention
    # VS 1 = astronomical -56 = 57 BCE; the catalog's signed years have no
    # year 0 (2094 BC → -2094), so a non-positive astronomical year shifts.
    assert_equal [-57, -57], bounds("vikrama", 1)
    assert_equal [-1, -1], bounds("vikrama", 57)
    assert_equal [1, 1], bounds("vikrama", 58)
  end

  def test_the_conversion_carries_its_era_and_year
    conversion = eras.to_ce("gupta_valabhi", 163)
    assert_equal "gupta_valabhi", conversion.era
    assert_equal 163, conversion.year
    assert_equal({ "not_before" => 482, "not_after" => 483 }, conversion.to_date_bounds)
  end

  def test_resolve_finds_an_era_by_its_aliases_case_and_dot_insensitively
    assert_equal "gupta_valabhi", eras.resolve("GE")
    assert_equal "gupta_valabhi", eras.resolve("G.E.")
    assert_equal "saka", eras.resolve("Śaka")
    assert_equal "saka", eras.resolve("saka")
    assert_equal "vikrama", eras.resolve("VS")
    assert_equal "kollam", eras.resolve("Kollam")
    assert_nil eras.resolve("Seleucid"), "an unruled era answers nil, never a guess"
  end

  def test_an_unknown_era_key_raises
    assert_raises(KeyError) { eras.to_ce("hijri", 100) }
  end

  def test_every_row_declares_its_source
    eras.keys.each do |key| # rubocop:disable Style/HashEachMethods -- Eras#keys is an Array, not a Hash
      cite = eras.family(key) == "nengo" ? /元号一覧/ : /Sewell/
      assert_match(cite, eras.source(key), "#{key}: each row cites its published list")
    end
  end

  # -- The Japanese era (nengō) rows (owner-ruled 2026-10-20) ---------------
  # The standard era list, 大化 (645) to 令和 (2019): 248 eras; era year n
  # = start + (n - 1), 元年 = year 1. Nothing older than 大化 — pre-Taika
  # dates have no row and ride unparsed.

  def nengo_keys = eras.keys.select { |key| eras.family(key) == "nengo" }

  def test_the_nengo_list_is_the_full_standard_sequence
    assert_equal 248, nengo_keys.size, "大化 → 令和, both courts of the Nanboku-chō"
    assert_equal [645, 645], ce("大化", 1), "the first era — nothing older is ruled"
    assert_equal [2019, 2019], ce("令和", 1)
  end

  def test_era_year_arithmetic_is_start_plus_n_minus_one
    assert_equal [1792, 1792], ce("寛政", 4)
    assert_equal [1830, 1830], ce("天保", 1)
    assert_equal [1844, 1844], ce("天保", 15), "天保 15 = 1844, the last 天保 year"
    assert_equal [1868, 1868], ce("明治", 1)
    assert_equal [1926, 1926], ce("昭和", 1)
  end

  def test_prose_years_scan_ascii_kanji_and_gannen_forms
    assert_equal [[1792, "寛政4"]], scan("寛政4刊")
    assert_equal [[1789, "寛政元"]], scan("寛政元序"), "元 is year 1"
    assert_equal [[1840, "天保十一年"]], scan("天保十一年四月十六日岩窪御廟御普請仕様帳扣")
    assert_equal [[1891, "明治廿四年"]], scan("明治廿四年十月廿八日大地震後図")
    assert_equal [[1730, "享保拾五年"]], scan("「享保拾五年八月」")
    assert_equal [[1847, "弘化4"], [1853, "嘉永6"]], scan("弘化4-嘉永6 [1847-1853]")
    assert_equal [[1710, "寶永7"]], scan("寶永7 [1710]"), "old-form kanji fold (寶 → 宝)"
    assert_equal [[1653, "承應2"]], scan("承應2"), "應 → 応"
  end

  def test_a_same_era_continuation_reads_through_the_last_named_era
    assert_equal [[1704, "宝永元年"], [1705, "同二年"]], scan("家譜 二十三 吉品公 従宝永元年到同二年")
    assert_equal [[1738, "元文3"], [1740, "5"]], scan("元文3-5"), "a bare range end stays in the era"
    assert_equal [[1867, "慶応3"], [1869, "明治2"]], scan("慶応3-明治2")
  end

  # Declared, never guessed: Chinese print-era homonyms (Ming 正徳 imprints
  # sit in the same collections), the one-year eras, out-of-range years
  # and a 4-character Chinese era ending in a Japanese name ride unparsed.
  def test_ambiguous_one_year_and_out_of_range_eras_ride_unparsed
    assert_empty scan("正徳3"), "Ming 正徳 (1506–1521) shares the name"
    assert_empty scan("嘉慶元序刊(痩竹山房藏板)"), "Qing 嘉慶"
    assert_empty scan("弘治2"), "Ming 弘治"
    assert_empty scan("朱鳥元年"), "a one-year era"
    assert_empty scan("天平感宝元年"), "a one-year era"
    assert_empty scan("天保20"), "天保 had 15 years"
    assert_empty scan("太平興国5"), "the Song era 太平興国, not 興国"
    assert_empty scan("[慶長元和年間]"), "an era span without a year number"
    assert_empty scan("明治元勲"), "元 not standing for a year"
  end

  def test_nengo_date_is_the_structured_envelope_or_nil
    assert_equal({ "not_before" => 1758, "not_after" => 1780, "raw" => "宝暦8序,安永9刊",
                   "eras" => %w[宝暦8 安永9], "basis" => "census" },
                 eras.nengo_date("宝暦8序,安永9刊", basis: "census"))
    assert_nil eras.nengo_date("康熙11", basis: "census"), "an era the table does not hold"
  end

  def ce(era, year)
    conversion = eras.to_ce(era, year)
    [conversion.not_before, conversion.not_after]
  end

  def scan(text)
    eras.nengo_years(text).map { |hit| [hit.conversion.not_before, hit.text] }
  end

  def bounds(era, year)
    conversion = eras.to_ce(era, year)
    [conversion.not_before, conversion.not_after]
  end

  def test_load_returns_nil_for_a_missing_file
    assert_nil Nabu::Eras.load("/nonexistent/eras.yml")
  end

  def test_load_rejects_a_negative_width
    Dir.mktmpdir do |dir|
      path = File.join(dir, "eras.yml")
      File.write(path, { "eras" => { "x" => { "offset" => 1, "width" => -1, "source" => "s" } } }.to_yaml)
      assert_raises(ArgumentError) { Nabu::Eras.load(path) }
    end
  end
end
