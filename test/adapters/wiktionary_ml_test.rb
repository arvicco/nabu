# frozen_string_literal: true

require "test_helper"

# Wiktionary-Malayalam: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base (the South Asian dictionary wave). Trimmed-real
# fixture: 3 entries (പുസ്തകം · കരയുക · കാളൻ) — a Sanskrit borrowing
# etymon, a cognate note that mints nothing, and a descendants tree
# lending into Tamil. The stored code is mal (no Malayalam node in the
# lect registry yet; the dictionary shelf carries the code verbatim).
class WiktionaryMlTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryMl
  def kaikki_slug = "wiktionary-ml"
  def kaikki_filename = "kaikki.org-dictionary-Malayalam.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Malayalam/kaikki.org-dictionary-Malayalam.jsonl"
  def kaikki_language = "mal"
  def kaikki_entry_count = 3

  def test_the_sanskrit_donor_is_a_borrowed_etymon
    book = kaikki_entry("പുസ്തകം")
    assert_equal "book", book.gloss
    reflex = book.reflexes.find { |r| r.lang_code == "sa" }
    refute_nil reflex
    assert_equal "पुस्तक", reflex.word
    assert_equal "borrowed", reflex.relation
  end

  def test_a_cognate_note_mints_no_reflex
    assert_empty kaikki_entry("കരയുക").reflexes,
                 "\"Cognate with Tamil கரை\" is a cognate, not the entry's own etymon"
  end

  def test_the_descendants_tree_lends_into_tamil
    assert(kaikki_entry("കാളൻ").reflexes.any? { |r| r.lang_code == "ta" && r.word == "காளன்" })
  end
end
