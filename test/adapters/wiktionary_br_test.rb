# frozen_string_literal: true

require "test_helper"

# Wiktionary-Breton: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (verb · aber),
# selected by rule (README). Stored code bre.
class WiktionaryBrTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryBr
  def kaikki_slug = "wiktionary-br"
  def kaikki_filename = "kaikki.org-dictionary-Breton.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Breton/kaikki.org-dictionary-Breton.jsonl"
  def kaikki_language = "bre"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("verb")
    assert_equal "verb", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "la" && r.relation == "derived" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("aber")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "fr" && r.word == "aber" })
  end
end
