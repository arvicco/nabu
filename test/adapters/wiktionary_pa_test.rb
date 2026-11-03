# frozen_string_literal: true

require "test_helper"

# Wiktionary-Punjabi: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (زبان · ਵਾਹਿਗੁਰੂ),
# selected by rule (README). Stored code pan.
class WiktionaryPaTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryPa
  def kaikki_slug = "wiktionary-pa"
  def kaikki_filename = "kaikki.org-dictionary-Punjabi.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Punjabi/kaikki.org-dictionary-Punjabi.jsonl"
  def kaikki_language = "pan"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("زبان")
    assert_equal "tongue", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "fa-cls" && r.relation == "borrowed" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("ਵਾਹਿਗੁਰੂ")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "en" && r.word == "Waheguru" })
  end
end
