# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Ops
  # Nabu::Ops::JpnFoldBuilder (P38-4): the generator behind lib/nabu/jpn.rb.
  # Dev-time ops code, tested the FixtureSentinel way — logic against tmp
  # inputs, no network. The kJinmeiyoKanji lines below are BYTE-VERBATIM from
  # canonical/unihan/Unihan_OtherMappings.txt (Unicode 17.0.0, file date
  # 2025-07-24), hand-SELECTED to cover each branch, never hand-invented —
  # except the two clearly-labelled synthetic merge lines, which exercise the
  # deterministic merge-refusal the real file happens not to need.
  class JpnFoldBuilderTest < Minitest::Test
    HEADER = <<~TXT
      # Unihan_OtherMappings.txt
      # Date: 2025-07-24 00:00:00 GMT [KL]
      # Unicode Version 17.0.0
      #
    TXT

    # Real pointer lines:
    #   國(U+570B) → 国(U+56FD)   normal reform pair (kyūjitai is traditional)
    #   搖(U+6416) → 揺(U+63FA)   hani-composed: Hani.fold(搖)=揺, so the OLD
    #                            form folds onto the new (the 奨↔奬 family)
    #   渚(U+6E1A) → 渚(U+FA46)   compat ideograph — NFC-identity, dropped
    #   乙(U+4E59) 2010           no pointer — a plain jinmeiyō, ignored
    REAL_LINES = <<~TXT
      U+4E59	kJinmeiyoKanji	2010
      U+570B	kJinmeiyoKanji	2010:U+56FD
      U+6416	kJinmeiyoKanji	2010:U+63FA
      U+6E1A	kJinmeiyoKanji	2010:U+FA46
    TXT

    # SYNTHETIC (not in the real file): two old forms 辨(U+8FA8) 瓣(U+74E3)
    # pointing at ONE new form 弁(U+5F01) — the reform-merge the builder must
    # REFUSE rather than pick a winner.
    SYNTHETIC_MERGE = <<~TXT
      U+8FA8	kJinmeiyoKanji	2010:U+5F01
      U+74E3	kJinmeiyoKanji	2010:U+5F01
    TXT

    def build(body)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "Unihan_OtherMappings.txt")
        File.write(path, HEADER + body)
        yield Nabu::Ops::JpnFoldBuilder.new(mappings_path: path, generated_on: "2026-07-21")
      end
    end

    def test_reads_provenance_from_the_header
      build(REAL_LINES) do |b|
        assert_equal "17.0.0", b.census.unihan_version
        assert_equal "2025-07-24", b.census.unihan_date
      end
    end

    def test_normal_pair_folds_new_to_old_and_records_the_reform
      build(REAL_LINES) do |b|
        assert_equal "國", b.fold_table["国"]
        assert_equal "國", b.reform_pairs["国"]
        refute b.fold_table.key?("國"), "the kyūjitai is the skeleton — not a key"
      end
    end

    def test_nfc_identity_compat_ideographs_are_dropped
      build(REAL_LINES) do |b|
        assert_equal 1, b.census.nfc_identity_dropped
        refute b.reform_pairs.key?("渚")
      end
    end

    def test_lines_without_a_pointer_are_ignored
      build(REAL_LINES) do |b|
        # U+4E59 (乙) is a plain jinmeiyō with no old form — never a pair.
        refute_includes b.reform_pairs.values, "乙"
        refute b.fold_table.key?("乙")
      end
    end

    def test_hani_composition_folds_the_old_form_when_hani_moves_the_kyujitai
      build(REAL_LINES) do |b|
        # Hani.fold(搖)=揺, so the canonical is the shinjitai and the OLD form
        # (搖) folds onto it; the reform pair still reads new=揺 / old=搖.
        assert_equal "揺", b.fold_table["搖"]
        assert_equal "搖", b.reform_pairs["揺"]
        assert_equal 1, b.census.hani_composed
      end
    end

    def test_reform_merges_are_refused_and_censused
      build(REAL_LINES + SYNTHETIC_MERGE) do |b|
        refute b.reform_pairs.key?("弁"), "a many-to-one merge must not resolve"
        refute_includes b.fold_table.keys, "辨"
        refute_includes b.fold_table.keys, "瓣"
        assert_equal 2, b.census.merges_refused.size
      end
    end

    def test_census_counts_match_the_selected_fixture
      build(REAL_LINES) do |b|
        assert_equal 3, b.census.raw_pointers      # 國, 搖, 渚 (乙 has no pointer)
        assert_equal 1, b.census.nfc_identity_dropped
        assert_equal 2, b.census.reform_pairs      # 国/國, 揺/搖
        assert_equal 2, b.census.fold_entries
      end
    end

    def test_render_emits_a_loadable_module_with_a_working_fold
      build(REAL_LINES) do |b|
        source = b.render
        assert_includes source, "module Nabu"
        assert_includes source, "module Jpn"
        mod = Module.new
        mod.module_eval(source)
        jpn = mod.const_get(:Nabu).const_get(:Jpn)
        assert_equal "國", jpn.fold("国")
        assert_equal "國", jpn.old_form("国")
        assert_equal "国", jpn.new_form("國")
      end
    end
  end
end
