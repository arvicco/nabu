# frozen_string_literal: true

require "test_helper"

# Wiktionary-Persian: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 3 entries (کتاب · دل · شاه)
# — an Arabic borrowing whose descendants run into Tajik and the Indic
# languages, an inherited word with its Middle Persian → Proto-Iranian →
# PIE etymon chain, and a word whose chain passes through Old Persian.
# The stored code is fas (→ fa through the held codemap alias).
class WiktionaryFaTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryFa
  def kaikki_slug = "wiktionary-fa"
  def kaikki_filename = "kaikki.org-dictionary-Persian.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Persian/kaikki.org-dictionary-Persian.jsonl"
  def kaikki_language = "fas"
  def kaikki_entry_count = 3

  def test_the_inherited_word_carries_its_middle_persian_etymon_chain
    heart = kaikki_entry("دل")
    assert_equal "heart", heart.gloss
    etymons = heart.reflexes.select(&:relation).map { |r| [r.lang_code, r.relation] }
    assert_equal [%w[pal inherited], %w[ira-pro inherited], %w[iir-pro inherited], %w[ine-pro inherited]], etymons
    assert_equal "𐭣𐭩𐭫", heart.reflexes.find { |r| r.lang_code == "pal" }.word
  end

  def test_the_old_persian_link_rides_the_chain
    king = kaikki_entry("شاه")
    assert_equal "king; shah", king.gloss
    assert(king.reflexes.any? { |r| r.lang_code == "peo" && r.relation == "inherited" })
  end

  def test_the_arabic_borrowing_lends_into_tajik
    book = kaikki_entry("کتاب")
    assert_equal "book", book.gloss
    assert_equal "کتاب:noun:1", book.entry_id, "upstream's etymology number keeps the homograph id"
    assert(book.reflexes.any? { |r| r.lang_code == "tg" && r.word == "китоб" })
  end
end
