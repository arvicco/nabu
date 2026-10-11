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

  def test_the_shipped_table_loads_all_four_eras
    refute_nil eras, "config/eras.yml is ruled repo config"
    assert_equal %w[gupta_valabhi kollam saka vikrama], eras.keys.sort
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
      assert_match(/Sewell/, eras.source(key), "#{key}: each row cites Sewell & Dikshit 1896")
    end
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
