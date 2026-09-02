# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::CjkBigrams (P93-3, №R-39 b) — the character-pair mint
  # shared by the index side (Indexer's cjk lane) and the query side
  # (Query::Search), the fold-both-sides contract applied to unsegmented
  # CJK runs.
  class CjkBigramsTest < Minitest::Test
    M = Nabu::Store::CjkBigrams

    # -- index tokens --------------------------------------------------------

    def test_run_mints_overlapping_bigrams_plus_the_trailing_unigram
      assert_equal "六龍 龍飛 飛天 天", M.index_text("六龍飛天")
    end

    def test_single_char_run_mints_its_lone_char
      assert_equal "天", M.index_text("天")
    end

    def test_separate_runs_never_bridge
      # "AB … CD": no bigram spans the break; the trailing unigrams keep
      # the token stream un-phrasable across runs (the no-false-positive
      # property the search tests pin end to end).
      assert_equal "六龍 龍 飛天 天", M.index_text("六龍, 飛天")
    end

    def test_kana_and_iteration_marks_ride_inside_runs
      # Japanese mixes kanji and kana in one unbroken run — the same
      # unsegmented problem, the same mint (aozora is in scope).
      assert_equal "時々 々に に", M.index_text("時々に")
      assert_equal "ラー ー", M.index_text("ラー")
    end

    def test_non_cjk_text_mints_nothing
      assert_nil M.index_text("mηnin arma virumque")
      assert_nil M.index_text("")
      assert_nil M.index_text(nil)
    end

    def test_hangul_stays_out_of_the_run_class
      # Modern Korean is space-segmented — unicode61 already serves it;
      # the lane deliberately scopes to Han/kana runs (plan P93-3).
      assert_nil M.index_text("조선왕조실록")
    end

    # -- query expressions ---------------------------------------------------

    def test_multichar_run_compiles_to_a_phrase_of_bigrams
      assert_equal '"六龍 龍飛"', M.query_expression("六龍飛")
    end

    def test_two_char_run_is_a_single_bigram_phrase
      assert_equal '"六龍"', M.query_expression("六龍")
    end

    def test_single_char_compiles_to_a_prefix_query
      # Prefix reaches every position: any bigram starting with the char
      # AND the run-final trailing unigram.
      assert_equal '"龍" *', M.query_expression("龍")
    end

    def test_whitespace_tokens_compose_with_implicit_and
      assert_equal '"六龍" "飛天"', M.query_expression("六龍 飛天")
    end

    def test_mixed_or_non_cjk_queries_leave_the_lane
      assert_nil M.query_expression("六龍 king"), "a mixed query stays on the main lane"
      assert_nil M.query_expression("king")
      assert_nil M.query_expression("六龍king"), "a mixed token leaves the lane whole"
      assert_nil M.query_expression("")
    end

    def test_search_expression_ors_the_servable_fold_variants
      assert_equal '"六龍"', M.search_expression(["六龍"])
      assert_equal '("六龍") OR ("六竜")', M.search_expression(%w[六龍 六竜])
      assert_nil M.search_expression(["king"])
      assert_equal '"六龍"', M.search_expression(%w[六龍 king]),
                   "unservable variants drop; the servable one still engages the lane"
    end
  end
end
