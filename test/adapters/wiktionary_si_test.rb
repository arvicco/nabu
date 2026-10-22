# frozen_string_literal: true

require "test_helper"

# Wiktionary-Sinhala: the kaikki.org per-language JSONL ("Sinhalese" in
# kaikki's naming) on the shared WiktionaryKaikki base (the South Asian
# dictionary wave). Trimmed-real fixture: 3 entries (අම්මා · ගෙය ·
# කන්ද) — a Tamil borrowing into the wiktionary-ta headword space, a
# Prakrit inheritance, and a descendants tree lending into Portuguese
# and English.
class WiktionarySiTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionarySi
  def kaikki_slug = "wiktionary-si"
  def kaikki_filename = "kaikki.org-dictionary-Sinhalese.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Sinhalese/kaikki.org-dictionary-Sinhalese.jsonl"
  def kaikki_language = "sin"
  def kaikki_entry_count = 3

  def test_the_tamil_donor_is_a_borrowed_etymon
    mother = kaikki_entry("අම්මා")
    assert_equal "mother", mother.gloss
    reflex = mother.reflexes.find { |r| r.lang_code == "ta" }
    assert_equal "அம்மா", reflex&.word
    assert_equal "borrowed", reflex&.relation
  end

  def test_the_prakrit_ancestor_is_an_inherited_etymon
    assert(kaikki_entry("ගෙය").reflexes.any? { |r| r.lang_code == "pra" && r.relation == "inherited" })
  end

  def test_the_descendants_tree_lends_into_european_languages
    codes = kaikki_entry("කන්ද").reflexes.map(&:lang_code)
    assert_equal %w[pt en], codes
  end
end
