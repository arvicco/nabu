# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Ops
  # Nabu::Ops::AozoraIdsBuilder (P39-5): the generator behind the aozora IDS
  # lane (config/gaiji/aozora-ids.tsv, rung 2 of the P38-2 display ladder). A
  # pure function of the checked-in composition-description census — no network,
  # no canonical, no catalog. Every example below is a REAL description from the
  # live corpus census (the header names its provenance), so the grammar and its
  # refusals are pinned against what the parser actually emits.
  class AozoraIdsBuilderTest < Minitest::Test
    # A tiny census in the real file's shape (count<TAB>desc), one row per case
    # the grammar must decide. Every desc is real (see config/gaiji/
    # aozora-descriptions.tsv); comments/blanks exercise the reader too.
    MINI_CENSUS = <<~TSV
      # a header comment, ignored
      37\t口＋斗
      13\t一／力
      24\t魚＋昜
      8\t木／喬
      3\tにんべん＋巨
      2\t（禾＋尤）／上／日
      1\t旗－其＋冉
      2\t筮／八／口
      1\tＹ＋Ｙ
    TSV

    def build(census = MINI_CENSUS)
      Dir.mktmpdir("nabu-aozora-ids") do |dir|
        path = File.join(dir, "aozora-descriptions.tsv")
        File.write(path, census)
        yield Nabu::Ops::AozoraIdsBuilder.new(census_path: path, generated_on: "2026-07-22")
      end
    end

    # -- the two derivable shapes ------------------------------------------

    def test_single_plus_between_two_han_derives_left_right
      build do |b|
        assert_equal "⿰口斗", b.lane["口＋斗"], "single ＋ between two ideographs ⇒ ⿰ (left-right)"
        assert_equal "⿰魚昜", b.lane["魚＋昜"]
      end
    end

    def test_single_slash_between_two_han_derives_top_bottom
      build do |b|
        assert_equal "⿱一力", b.lane["一／力"], "single ／ between two ideographs ⇒ ⿱ (top-bottom)"
        assert_equal "⿱木喬", b.lane["木／喬"]
      end
    end

    # -- the refusal classes (each with a real example) --------------------

    def test_kana_radical_name_is_refused
      # にんべん is a radical NAME, not a component glyph — resolving it would be
      # a guess (the honest bar: a structural claim needs literal component chars).
      build { |b| refute b.lane.key?("にんべん＋巨"), "a kana radical-name formula is not mechanical" }
    end

    def test_subtractive_formula_is_refused
      # 旗－其＋冉 (U+FF0D removes 其, then adds 冉) is arithmetic on parts, not IDS.
      build { |b| refute b.lane.key?("旗－其＋冉") }
    end

    def test_parenthesised_formula_is_refused
      # （禾＋尤）／上／日 nests groups — needs a recursive parse we refuse.
      build { |b| refute b.lane.key?("（禾＋尤）／上／日") }
    end

    def test_multi_operator_formula_is_refused
      # 筮／八／口 has two ／ operators — ambiguous nesting, refused.
      build { |b| refute b.lane.key?("筮／八／口") }
    end

    def test_non_han_operand_is_refused
      # Ｙ＋Ｙ: fullwidth Latin, not \p{Han} — the single-ideograph rule refuses.
      build { |b| refute b.lane.key?("Ｙ＋Ｙ") }
    end

    def test_census_counts_each_refusal_under_its_salient_trait
      build do |b|
        c = b.census
        assert_equal 9, c.descriptions
        assert_equal 4, c.derived, "口＋斗 一／力 魚＋昜 木／喬"
        assert_equal 1, c.refused[:kana_component]
        assert_equal 1, c.refused[:subtractive]
        assert_equal 1, c.refused[:parenthesised]
        assert_equal 1, c.refused[:multi_operator]
        assert_equal 1, c.refused[:other], "Ｙ＋Ｙ"
      end
    end

    def test_derived_occurrences_track_the_census_counts
      build do |b|
        # 37 (口＋斗) + 13 (一／力) + 24 (魚＋昜) + 8 (木／喬) = 82
        assert_equal 82, b.census.derived_occurrences
        assert_equal 37 + 13 + 24 + 8 + 3 + 2 + 1 + 2 + 1, b.census.composition_occurrences
      end
    end

    def test_render_is_a_valid_tsv_with_a_documented_header
      build do |b|
        out = b.render
        assert_match(/\A# Aozora gaiji ladder/, out)
        assert_match(/GENERATED — do not edit by hand/, out)
        assert_match(/census: 4, 2026-07-22/, out, "the header pins the derived count + date")
        data = out.lines.reject { |l| l.start_with?("#") || l.strip.empty? }
        assert_equal 4, data.size
        data.each { |l| assert_equal 2, l.chomp.split("\t").size, "every data row is desc<TAB>ids" }
        assert_equal data, data.sort, "rows are desc-sorted for a stable diff"
      end
    end

    # -- the SHIPPED lane + census pins (§6b) ------------------------------

    ROOT = Nabu::Config::PROJECT_ROOT
    CENSUS_PATH = File.join(ROOT, "config", "gaiji", "aozora-descriptions.tsv")
    LANE_PATH = File.join(ROOT, "config", "gaiji", "aozora-ids.tsv")

    def test_shipped_lane_is_exactly_what_the_builder_produces_from_the_shipped_census
      # The lane is generated; drift between census and lane means someone
      # hand-edited one. Regenerate the header-free body and compare.
      builder = Nabu::Ops::AozoraIdsBuilder.new(census_path: CENSUS_PATH)
      shipped = File.read(LANE_PATH).lines.reject { |l| l.start_with?("#") }.join
      regenerated = builder.render.lines.reject { |l| l.start_with?("#") }.join
      assert_equal regenerated, shipped, "config/gaiji/aozora-ids.tsv is stale — run rake gaiji:aozora_ids"
    end

    # census: 244, 2026-07-22, derived IDS entries from the shipped aozora
    # composition-description census (582 descriptions, 1129 occurrences).
    def test_shipped_census_pins
      builder = Nabu::Ops::AozoraIdsBuilder.new(census_path: CENSUS_PATH)
      c = builder.census
      assert_equal 582, c.descriptions, "shipped composition-description census size"
      assert_equal 244, c.derived, "mechanically derivable IDS entries"
      assert_equal 338, c.refused.values.sum
      assert_equal 283, c.refused[:kana_component], "the dominant refusal — kana radical names"
    end

    def test_shipped_lane_loads_as_a_gaiji_map_keyed_by_formula
      lane = Nabu::Display.load_gaiji_map(LANE_PATH)
      assert_equal 244, lane.size
      assert_equal "⿰口斗", lane["口＋斗"], "the formula IS the lane key"
      refute lane.key?("にんべん＋巨"), "a refused formula is absent — it stays the loud sentinel"
    end
  end
end
