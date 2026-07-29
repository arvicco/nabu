# frozen_string_literal: true

require "test_helper"

# The in-band evaluation behind xct/segmentation (P51-W5): leave-one-text-out
# cross-validation of the unigram segmenter against gold segmentation, scored
# as boundary precision/recall/F1 (char positions where a token starts inside
# the line) plus token exact-span F1. The published dataset's headline number
# comes from this class, so its arithmetic is pinned on hand-computed inputs.
class DataBuildSegmentationEvalTest < Minitest::Test
  Eval = Nabu::DataBuild::SegmentationEval

  # Two tiny gold "texts" whose folds are fully hand-checkable.
  # ཆོས (3 chars) + ་ (1) = "ཆོས་" is 4 chars; "ལ" 1; "ལ་" 2.
  def agreeing_docs
    {
      "a" => [{ text: "ཆོས་ལ", forms: ["ཆོས་", "ལ"] }],
      "b" => [{ text: "ཆོས་ལ་ཆོས", forms: ["ཆོས་", "ལ་", "ཆོས"] }]
    }
  end

  def test_perfect_agreement_scores_one
    # Fold a: trained on b's counts {ཆོས: 2, ལ: 1} — both syllables known,
    # no merged span known → boundaries {4}, gold {4}. Fold b: trained on a's
    # counts {ཆོས: 1, ལ: 1} → boundaries {4, 6}, gold {4, 6}. tp=3 fp=0 fn=0.
    result = Eval.leave_one_text_out(agreeing_docs)
    assert_equal 1.0, result.fetch("boundary_f1")
    assert_equal 1.0, result.fetch("boundary_precision")
    assert_equal 1.0, result.fetch("boundary_recall")
    assert_equal 1.0, result.fetch("token_f1")
    assert_equal 2, result.fetch("texts")
    assert_equal 2, result.fetch("lines")
    assert_equal 5, result.fetch("tokens")
    assert_match(/leave-one-text-out/, result.fetch("protocol"))
    assert_match(/clean/, result.fetch("contamination"))
  end

  def test_total_disagreement_scores_zero_without_dividing_by_zero
    # Fold a: b's vocabulary is the merged word ཆོས་ལ → the fold predicts no
    # interior boundary where gold has one (fn). Fold b: a's vocabulary is
    # the two syllables → the fold predicts a boundary gold lacks (fp).
    docs = {
      "a" => [{ text: "ཆོས་ལ", forms: ["ཆོས་", "ལ"] }],
      "b" => [{ text: "ཆོས་ལ", forms: ["ཆོས་ལ"] }]
    }
    result = Eval.leave_one_text_out(docs)
    assert_equal 0.0, result.fetch("boundary_f1")
    assert_equal 0.0, result.fetch("boundary_precision")
    assert_equal 0.0, result.fetch("boundary_recall")
    assert_equal 0.0, result.fetch("token_f1")
  end

  def test_scores_are_rounded_to_four_places
    # Fold a (trained on b: ཆོས, ལ known separately): "ཆོས་ལ་ལ" → pred {4, 6},
    # gold {4} → one fp. Fold b: pred {4, 6} = gold. Micro: tp=3 fp=1 fn=0 →
    # P=0.75, R=1.0, F1=6/7=0.857142… → 0.8571.
    docs = {
      "a" => [{ text: "ཆོས་ལ་ལ", forms: ["ཆོས་", "ལ་ལ"] }],
      "b" => [{ text: "ཆོས་ལ་ཆོས", forms: ["ཆོས་", "ལ་", "ཆོས"] }]
    }
    result = Eval.leave_one_text_out(docs)
    assert_equal 0.75, result.fetch("boundary_precision")
    assert_equal 1.0, result.fetch("boundary_recall")
    assert_equal 0.8571, result.fetch("boundary_f1")
  end

  def test_a_single_gold_text_refuses_the_protocol
    error = assert_raises(Nabu::DataBuild::Error) do
      Eval.leave_one_text_out(agreeing_docs.slice("a"))
    end
    assert_match(/leave-one-text-out/, error.message)
    assert_match(/2/, error.message, "the refusal names the minimum")
  end
end
