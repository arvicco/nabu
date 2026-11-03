# frozen_string_literal: true

require "test_helper"

# Wiktionary-Korean: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (OK · 불가사리),
# selected by rule (README). Stored code ko.
class WiktionaryKoTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryKo
  def kaikki_slug = "wiktionary-ko"
  def kaikki_filename = "kaikki.org-dictionary-Korean.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Korean/kaikki.org-dictionary-Korean.jsonl"
  def kaikki_language = "ko"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("OK")
    assert_equal "good", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "en" && r.relation == "derived" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("불가사리")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "en" && r.word == "bulgasari" })
  end
end
