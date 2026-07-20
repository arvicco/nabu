# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Ops
  # Nabu::Ops::HaniFoldBuilder (P37-2): the generator behind lib/nabu/hani.rb.
  # Dev-time ops code, tested the FixtureSentinel way — logic against tmp
  # inputs, no network. The variant lines below are BYTE-VERBATIM lines from
  # canonical/unihan/Unihan_Variants.txt (Unicode 17.0.0, file date
  # 2025-07-24), hand-SELECTED to cover each resolution branch, never
  # hand-invented — except the two clearly-labelled synthetic lines in the
  # cycle test, which exercise the deterministic cycle rule the real file
  # happens not to need.
  class HaniFoldBuilderTest < Minitest::Test
    HEADER = <<~TXT
      # Unihan_Variants.txt
      # Date: 2025-07-24 00:00:00 GMT [KL]
      # Unicode Version 17.0.0
      #
    TXT

    # The characterization set (real lines):
    #   亚→亞          direct single-target kTraditionalVariant
    #   说→{說,説}     multi-target forgiven — both targets one z-cluster
    #   說↔説          mutual kZVariant, cluster canonical = lowest cp (說)
    #   发→{發,髮}     multi-target across clusters — refused, censused
    #   体 self+體     self-listing — refused even though 體 simplifies to 体
    #   台 self+3      self-listing, three targets — refused
    #   吳/吴/呉       3-member z-cluster; 吴 self-lists but z-warrant folds it
    #   値↔值          anchorless z-pair — canonical = lowest codepoint (値)
    #   𱃗→颱          reverse-only (only kSimplifiedVariant names it)
    #   㐀→丘          kSemanticVariant — EXCLUDED (different words)
    REAL_LINES = <<~TXT
      U+3400	kSemanticVariant	U+4E18
      U+4E9A	kTraditionalVariant	U+4E9E
      U+4F53	kSimplifiedVariant	U+4F53
      U+4F53	kTraditionalVariant	U+4F53 U+9AD4
      U+5024	kZVariant	U+503C
      U+503C	kZVariant	U+5024
      U+53D1	kTraditionalVariant	U+767C U+9AEE
      U+53F0	kSimplifiedVariant	U+53F0
      U+53F0	kTraditionalVariant	U+53F0 U+6AAF U+81FA U+98B1
      U+5433	kSemanticVariant	U+5449<kMatthews
      U+5433	kSimplifiedVariant	U+5434
      U+5433	kZVariant	U+5434 U+5449
      U+5434	kSimplifiedVariant	U+5434
      U+5434	kTraditionalVariant	U+5433 U+5434
      U+5434	kZVariant	U+5433 U+5449
      U+5449	kSemanticVariant	U+5433<kMatthews
      U+5449	kZVariant	U+5433 U+5434
      U+6AAF	kSimplifiedVariant	U+53F0
      U+81FA	kSimplifiedVariant	U+53F0
      U+8AAA	kSimplifiedVariant	U+8BF4
      U+8AAA	kZVariant	U+8AAC
      U+8AAC	kSimplifiedVariant	U+8BF4
      U+8AAC	kZVariant	U+8AAA
      U+8BF4	kTraditionalVariant	U+8AAA U+8AAC
      U+98B1	kSimplifiedVariant	U+53F0 U+310D7
      U+9AD4	kSimplifiedVariant	U+4F53
    TXT

    def build(lines = REAL_LINES)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "Unihan_Variants.txt")
        File.write(path, HEADER + lines)
        return Nabu::Ops::HaniFoldBuilder.new(variants_path: path, generated_on: "2026-07-20")
      end
    end

    # -- resolution branches -------------------------------------------------

    def test_direct_single_target_simplified_folds_to_traditional
      assert_equal "亞", build.table["亚"]
    end

    def test_multi_target_within_one_z_cluster_resolves_to_cluster_canonical
      # 说's two traditional targets 說/説 are mutual z-variants; the cluster
      # canonical is the lowest codepoint (說 U+8AAA < 説 U+8AAC) — which is
      # also the form kanripo/cbeta store.
      assert_equal "說", build.table["说"]
    end

    def test_z_variant_member_folds_to_cluster_canonical
      assert_equal "說", build.table["説"]
    end

    def test_cross_cluster_multi_target_is_refused_and_censused
      builder = build
      assert_nil builder.table["发"]
      assert_includes builder.census.multi_trad, "发"
    end

    def test_self_listing_char_is_its_own_traditional_word_and_never_folds
      # 体 lists ITSELF among its traditional variants: it is a traditional
      # character in its own right, so folding 体→體 would merge two words.
      # The reverse edge (體 kSimplifiedVariant 体) must not re-add it.
      builder = build
      assert_nil builder.table["体"]
      assert_nil builder.table["台"]
      assert_includes builder.census.self_ambiguous, "体"
      assert_includes builder.census.self_ambiguous, "台"
    end

    def test_z_warrant_overrides_self_listing_within_the_cluster
      # 吴 self-lists (kTraditionalVariant 吳 吴) but Unihan's own mutual
      # kZVariant edges assert 吳/吴/呉 are ONE abstract character — the
      # z-warrant folds the cluster to its lowest codepoint, 吳 (U+5433).
      builder = build
      assert_equal "吳", builder.table["吴"]
      assert_equal "吳", builder.table["呉"]
      assert_nil builder.table["吳"]
    end

    def test_anchorless_z_pair_folds_to_lowest_codepoint
      # 値 (U+5024) / 值 (U+503C): no trad/simp edge anchors the pair, so the
      # deterministic canonical is the lowest codepoint — arbitrary but
      # stable, and invisible (the skeleton is an index form, not display).
      builder = build
      assert_equal "値", builder.table["值"]
      assert_nil builder.table["値"]
    end

    def test_reverse_only_simplification_target_folds_to_its_declarer
      # U+310D7 appears ONLY as a kSimplifiedVariant target of 颱 (U+98B1):
      # the traditional side declares it, unambiguously — fold it.
      builder = build
      assert_equal "颱", builder.table[[0x310D7].pack("U")]
      assert_includes builder.census.reverse_only, [0x310D7].pack("U")
    end

    def test_semantic_variants_are_refused_wholesale
      # 㐀 kSemanticVariant 丘: semantic variants are different WORDS that
      # mean the same thing — folding them would be a lie. The refusal is
      # structural (the field is never read into the graph), pinned here.
      builder = build
      assert_nil builder.table["㐀"]
      refute_includes builder.table.values, "丘"
      assert_operator builder.census.semantic_lines_excluded, :>, 0
    end

    # -- structural invariants ----------------------------------------------

    def test_every_value_is_a_fixed_point_and_every_pair_is_single_char
      table = build.table
      table.each do |from, to|
        assert_equal 1, from.length, "key #{from.inspect} must be one codepoint"
        assert_equal 1, to.length, "value #{to.inspect} must be one codepoint"
        refute table.key?(to), "value #{to.inspect} must not itself be a key (chains resolve to a fixed point)"
        refute_equal from, to
      end
    end

    def test_cycle_resolves_to_lowest_codepoint_member
      # SYNTHETIC lines (labelled, not upstream bytes): a two-member
      # kTraditionalVariant cycle the real 17.0.0 file does not contain,
      # pinning the documented deterministic rule — every cycle member maps
      # to the cycle's lowest codepoint, which becomes the fixed point.
      lines = "U+4E01\tkTraditionalVariant\tU+4E02\nU+4E02\tkTraditionalVariant\tU+4E01\n"
      builder = build(lines)
      assert_equal "丁", builder.table["丂"] # U+4E02 → U+4E01 (lowest)
      assert_nil builder.table["丁"]
      assert_equal 1, builder.census.cycles
    end

    # -- provenance + rendering ---------------------------------------------

    def test_provenance_is_parsed_from_the_file_header
      builder = build
      assert_equal "17.0.0", builder.census.unihan_version
      assert_equal "2025-07-24", builder.census.unihan_date
    end

    def test_render_is_valid_ruby_defining_a_working_hani_module
      source = build.render
      assert_includes source, "17.0.0"
      assert_includes source, "2026-07-20"
      mod = Module.new
      mod.module_eval(source.sub("module Nabu", "module NabuRenderCheck").sub(/\A# frozen_string_literal: true\n/, ""))
      hani = mod.const_get(:NabuRenderCheck).const_get(:Hani)
      assert_equal "亞說", hani.fold("亚说")
      assert_equal build.table, hani::TABLE
    end
  end
end
