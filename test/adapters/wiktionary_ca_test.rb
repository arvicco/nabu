# frozen_string_literal: true

require "test_helper"

# Wiktionary-Catalan: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (gratis · guerra),
# selected by rule (README). Stored code cat.
class WiktionaryCaTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryCa
  def kaikki_slug = "wiktionary-ca"
  def kaikki_filename = "kaikki.org-dictionary-Catalan.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Catalan/kaikki.org-dictionary-Catalan.jsonl"
  def kaikki_language = "cat"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("gratis")
    assert_equal "free, for free", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "la" && r.relation == "learned-borrowing" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("guerra")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "sc" && r.word == "gherra" })
  end
end
