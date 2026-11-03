# frozen_string_literal: true

require "test_helper"

# Wiktionary-Old Occitan: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (ab · libre),
# selected by rule (README). Stored code pro.
class WiktionaryProTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryPro
  def kaikki_slug = "wiktionary-pro"
  def kaikki_filename = "kaikki.org-dictionary-OldOccitan.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Old%20Occitan/kaikki.org-dictionary-OldOccitan.jsonl"
  def kaikki_language = "pro"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("ab")
    assert_equal "with", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "la" && r.relation == "derived" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("libre")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "oc" && r.word == "libre" })
  end
end
