# frozen_string_literal: true

require "test_helper"

# Wiktionary-Estonian: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (aam · sent),
# selected by rule (README). Stored code et.
class WiktionaryEtTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryEt
  def kaikki_slug = "wiktionary-et"
  def kaikki_filename = "kaikki.org-dictionary-Estonian.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Estonian/kaikki.org-dictionary-Estonian.jsonl"
  def kaikki_language = "et"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("aam")
    assert_equal "a large barrel", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "gml" && r.relation == "derived" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("sent")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "en" && r.word == "sent" })
  end
end
