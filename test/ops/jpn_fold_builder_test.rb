# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Ops
  # Nabu::Ops::JpnFoldBuilder (P38-4 / P38-r1): the generator behind
  # lib/nabu/jpn.rb. Dev-time ops code, tested against tmp Unihan inputs (byte-
  # verbatim kJinmeiyoKanji/kJoyoKanji lines from Unihan 17.0.0) plus the
  # trimmed real KANJIDIC2 fixture (test/fixtures/kanjidic2/kanjidic2-sample.xml).
  # No network. Every fixture kanji is real upstream data; the fixture README
  # documents what each branch pins.
  class JpnFoldBuilderTest < Minitest::Test
    KANJIDIC = File.expand_path("../fixtures/kanjidic2/kanjidic2-sample.xml", __dir__)

    # Unihan header + the two fields the builder reads: kJinmeiyoKanji (lane 1
    # pointers) and kJoyoKanji (the jōyō SET, half of the lane-2 filter).
    #   U+570B(國) → U+56FD(国)   a jinmeiyō 1:1 reform pair
    #   U+6E1A(渚) → U+FA46(渚)   compat ideograph — NFC-identity, dropped
    # kJoyoKanji lines mark the fixture's jōyō chars: 国 医 弁 崎 埼 缶 学.
    UNIHAN = <<~TXT
      # Unihan_OtherMappings.txt
      # Date: 2025-07-24 00:00:00 GMT [KL]
      # Unicode Version 17.0.0
      #
      U+570B\tkJinmeiyoKanji\t2010:U+56FD
      U+6E1A\tkJinmeiyoKanji\t2010:U+FA46
      U+56FD\tkJoyoKanji\t2010
      U+533B\tkJoyoKanji\t2010
      U+5F01\tkJoyoKanji\t2010
      U+5D0E\tkJoyoKanji\t2010
      U+57FC\tkJoyoKanji\t2010
      U+7F36\tkJoyoKanji\t2010
      U+5B66\tkJoyoKanji\t2010
    TXT

    def build
      Dir.mktmpdir do |dir|
        path = File.join(dir, "Unihan_OtherMappings.txt")
        File.write(path, UNIHAN)
        yield Nabu::Ops::JpnFoldBuilder.new(mappings_path: path, kanjidic_path: KANJIDIC,
                                            generated_on: "2026-07-21")
      end
    end

    def test_reads_provenance_from_both_sources
      build do |b|
        assert_equal "17.0.0", b.census.unihan_version
        assert_equal "2025-07-24", b.census.unihan_date
        assert_equal "2026-202", b.census.kanjidic_version
        assert_equal "2026-07-21", b.census.kanjidic_date
      end
    end

    def test_lane1_jinmeiyo_pair_folds_new_to_the_traditional_skeleton
      build do |b|
        assert_equal "國", b.fold_table["国"]
        assert_equal "國", b.reform_pairs["国"]
        assert_equal 1, b.census.jinmeiyo_pairs
        refute b.fold_table.key?("國"), "the kyūjitai is the skeleton — not a key"
      end
    end

    def test_lane1_nfc_identity_compat_ideograph_is_dropped
      build do |b|
        assert_equal 1, b.census.nfc_identity_dropped
        refute b.reform_pairs.key?("渚")
      end
    end

    def test_lane2_clean_single_folds_but_stays_out_of_the_semantic_table
      # 醫 (no grade) ↔ 医 (grade 3, kJoyoKanji): a clean kanjidic single — it
      # FOLDS (findability) but is NOT a semantic reform pair (kanjidic variant
      # links are not reliable "old forms"; NEW/OLD stays jinmeiyō-authoritative).
      build do |b|
        assert_equal "醫", b.fold_table["医"]
        refute b.reform_pairs.key?("医"), "kanjidic singles are fold-only, not semantic pairs"
        assert_operator b.census.kanjidic_singles, :>=, 1
        refute b.fold_table.key?("醫"), "the kyūjitai is the skeleton"
      end
    end

    def test_lane2_merge_collapses_distinct_words_onto_the_shinjitai
      # 弁 ← 辨/瓣/辯: three distinct classical words, admitted as a merge onto
      # 弁's own skeleton (Hani keeps 辨/瓣/辯 apart — the lzh lane is untouched).
      build do |b|
        %w[辨 瓣 辯].each { |old| assert_equal "弁", b.fold_table[old], "#{old} must fold to 弁" }
        assert_equal Nabu::Hani.fold("弁"), b.fold_table["辨"]
        assert_includes b.census.merges.keys, "弁"
        # 辧/辮 decode from 弁's variants but are absent from the trimmed fixture
        # (not literals) so they are not claimants here — only 辨/瓣/辯 are.
        assert_equal %w[瓣 辨 辯].sort, b.census.merges["弁"].sort
        refute b.reform_pairs.key?("弁"), "a merge has no single kyūjitai — not a 1:1 pair"
        # The Chinese lane stays distinct — the merge lives only in the jpn fold.
        refute_equal Nabu::Hani.fold("辨"), Nabu::Hani.fold("瓣")
      end
    end

    def test_lane2_one_to_many_ambiguity_is_refused_and_censused
      # 碕 is variant-linked to TWO jōyō forms (崎 AND 埼) → never pick; refuse.
      build do |b|
        refute b.fold_table.key?("碕"), "an ambiguous old must not fold"
        refused = b.census.ambiguous_refused.to_h
        assert_equal %w[埼 崎], refused["碕"].sort
        # and neither jōyō target folds (its only claimant was the refused 碕)
        refute b.fold_table.key?("崎")
        refute b.fold_table.key?("埼")
      end
    end

    def test_jis212_variants_are_refused_a_different_standard
      # 學/斈/斅 carry a <variant var_type="jis212">1-33-55</variant>; decoding
      # that JIS X 0212 kuten through the 0213 plane-1 table would misread it as
      # 宋 (U+5B8B). The builder must never introduce that spurious edge.
      build do |b|
        refute b.fold_table.key?("宋"), "jis212 misread 宋 must not be a fold key"
        refute_includes b.fold_table.values, "宋", "jis212 misread 宋 must not be a fold target"
      end
    end

    def test_itaiji_cluster_folds_every_variant_onto_the_shinjitai_skeleton
      # 学 ← 學/斈/斅 (itaiji of one word): all fold onto Hani.fold(学)=學, a
      # clean fixed point (學 is never itself a key).
      build do |b|
        assert_equal "學", b.fold_table["学"]
        assert_equal "學", b.fold_table["斈"]
        assert_equal "學", b.fold_table["斅"]
        refute b.fold_table.key?("學"), "學 is the skeleton — a fixed point"
      end
    end

    def test_every_value_is_a_fixed_point_and_single_codepoint
      build do |b|
        b.fold_table.each do |from, to|
          assert_equal 1, from.length
          assert_equal 1, to.length
          refute b.fold_table.key?(to), "#{to.inspect} is a fold target but also a key"
        end
      end
    end

    def test_render_emits_a_loadable_module_with_a_working_merge_fold
      build do |b|
        source = b.render
        assert_includes source, "module Nabu"
        assert_includes source, "module Jpn"
        mod = Module.new
        mod.module_eval(source)
        jpn = mod.const_get(:Nabu).const_get(:Jpn)
        assert_equal "國", jpn.fold("国")
        assert_equal "醫", jpn.fold("医"), "the kanjidic single folds"
        assert_equal "弁", jpn.fold("辨")
        assert_equal jpn.fold("辨"), jpn.fold("弁"), "the merge is reachable through fold equality"
        assert_equal "國", jpn.old_form("国"), "the jinmeiyō semantic pair survives"
        assert_nil jpn.old_form("医"), "kanjidic singles are fold-only, not semantic"
      end
    end
  end
end
