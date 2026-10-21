# frozen_string_literal: true

require "test_helper"

# Wiktionary-Tamil: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base (the South Asian dictionary wave). Trimmed-real
# fixture: 3 entries (கோடி · அம்மா · ரசம்) — a Sanskrit borrowing etymon,
# a Proto-Dravidian inheritance stated in prose only, and a descendants
# tree carrying the English loan "rasam".
class WiktionaryTaTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryTa
  def kaikki_slug = "wiktionary-ta"
  def kaikki_filename = "kaikki.org-dictionary-Tamil.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Tamil/kaikki.org-dictionary-Tamil.jsonl"
  def kaikki_language = "tam"
  def kaikki_entry_count = 3

  def test_a_known_gloss_rides_the_tamil_headword
    assert_equal "very", kaikki_entry("கோடி").gloss
  end

  def test_the_sanskrit_donor_is_a_borrowed_etymon
    reflex = kaikki_entry("கோடி").reflexes.find { |r| r.lang_code == "sa" }
    refute_nil reflex, "From Sanskrit कोटि — the typed bor template mints the donor edge"
    assert_equal "कोटि", reflex.word
    assert_equal "borrowed", reflex.relation
  end

  def test_the_descendants_tree_mints_the_english_loan
    reflex = kaikki_entry("ரசம்").reflexes.find { |r| r.lang_code == "en" }
    refute_nil reflex
    assert_equal "rasam", reflex.word
    assert_nil reflex.relation, "a descendants-tree row states no typed relation"
  end
end
