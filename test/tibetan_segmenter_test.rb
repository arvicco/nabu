# frozen_string_literal: true

require "test_helper"

# The pure-Ruby Tibetan tsheg-bar segmenter behind xct/segmentation (P51-W5,
# promoted from DataBuild to Nabu::TibetanSegmenter in P54-1): unigram-cost
# Viterbi over tsheg-bar units with a closed attached-clitic class. The spike
# behind the design (2026-07-29, full SOAS gold corpus, leave-one-text-out):
# boundary F1 0.9622 — greedy maximal-match measured worse (0.954) and
# external lexica measured unhelpful (wiktionary-bo/TVD +0.0001 F1) or
# harmful (Mahāvyutpatti phrases −0.02 recall), so the segmenter trains on
# SOAS gold token counts alone.
#
# Every expectation below is hand-computed on tiny inputs.
class TibetanSegmenterTest < Minitest::Test
  Segmenter = Nabu::TibetanSegmenter

  # སངས་རྒྱས (sangs rgyas, "buddha") — a two-syllable word; ཆོས (chos,
  # "dharma") — one syllable; ལ (la) — one syllable.
  def trained
    Segmenter.train({ "སངས་རྒྱས" => 10, "ཆོས" => 5, "ལ" => 5 })
  end

  def forms(text, segmenter: trained)
    segmenter.segment(text).map(&:form)
  end

  # -- word_key ---------------------------------------------------------------

  def test_word_key_strips_trailing_tsheg_and_refuses_non_letter_material
    assert_equal "སངས་རྒྱས", Segmenter.word_key("སངས་རྒྱས་"), "trailing tsheg stripped, interior kept"
    assert_equal "ཆོས", Segmenter.word_key("ཆོས")
    assert_nil Segmenter.word_key("།"), "punctuation is not a word"
    assert_nil Segmenter.word_key(""), "empty is not a word"
    assert_nil Segmenter.word_key("་"), "a bare tsheg is not a word"
  end

  # -- segmentation -----------------------------------------------------------

  def test_a_known_multi_syllable_word_is_kept_whole
    # སངས་རྒྱས་ལ = buddha + la: the two-syllable word must not split.
    assert_equal %w[སངས་རྒྱས་ ལ], forms("སངས་རྒྱས་ལ")
  end

  def test_unknown_syllables_fall_back_to_tsheg_bar_grain
    # No word in the table covers these; each tsheg-bar is its own token.
    assert_equal %w[བམ་ པོ་], forms("བམ་པོ་", segmenter: Segmenter.train({ "ཆོས" => 1 }))
  end

  def test_offsets_index_into_the_text_exactly
    text = "སངས་རྒྱས་ལ"
    tokens = trained.segment(text)
    tokens.each do |token|
      assert_equal token.form, text[token.offset, token.form.length],
                   "every token must be the exact substring at its offset"
    end
    assert_equal [0, 9], tokens.map(&:offset)
  end

  def test_punctuation_is_tokenized_and_whitespace_is_dropped
    # Derge running text carries "། " (shad + space): the shad is a token,
    # the space is not — but offsets must still index the original text.
    text = "ཆོས། ལ"
    tokens = trained.segment(text)
    assert_equal ["ཆོས", "།", "ལ"], tokens.map(&:form)
    assert_equal [0, 3, 5], tokens.map(&:offset)
  end

  def test_the_genitive_clitic_splits_inside_a_tsheg_bar
    # ཆོསའི does not occur; the real orthography attaches འི to the final
    # syllable: བླ་མ + འི → བླ་མའི. Stem known + clitic known → split edge.
    segmenter = Segmenter.train({ "བླ་མ" => 10, "འི" => 10 })
    tokens = segmenter.segment("བླ་མའི་")
    assert_equal %w[བླ་མ འི་], tokens.map(&:form)
    assert_equal [0, 4], tokens.map(&:offset)
  end

  def test_the_agentive_clitic_needs_a_known_stem
    # ས attaches to open syllables — but native words end in ས too, so the
    # split edge exists only when the stem is itself a known word.
    with_stem = Segmenter.train({ "བླ་མ" => 10, "ས" => 10 })
    assert_equal %w[བླ་མ ས], with_stem.segment("བླ་མས").map(&:form)

    without_stem = Segmenter.train({ "ས" => 10 })
    assert_equal %w[བླ་ མས], without_stem.segment("བླ་མས").map(&:form),
                 "no known stem — no split edge; the text stays at tsheg-bar grain"
  end

  def test_segmentation_is_deterministic
    text = "སངས་རྒྱས་ལ་ཆོས། །སངས་རྒྱས་"
    assert_equal trained.segment(text), trained.segment(text)
  end

  def test_empty_and_whitespace_text_yield_no_tokens
    assert_empty trained.segment("")
    assert_empty trained.segment("   ")
  end

  def test_train_ignores_punctuation_keys
    segmenter = Segmenter.train({ "།" => 100, "ཆོས" => 1 })
    assert_equal %w[ཆོས], segmenter.segment("ཆོས").map(&:form)
  end
end
