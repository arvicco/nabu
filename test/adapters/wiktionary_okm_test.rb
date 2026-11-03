# frozen_string_literal: true

require "test_helper"

# Wiktionary-Middle Korean: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (오다 · 고기),
# selected by rule (README). Stored code okm.
class WiktionaryOkmTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryOkm
  def kaikki_slug = "wiktionary-okm"
  def kaikki_filename = "kaikki.org-dictionary-MiddleKorean.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Middle%20Korean/kaikki.org-dictionary-MiddleKorean.jsonl"
  def kaikki_language = "okm"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("오다")
    assert_equal "to come", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "oko-lat" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("고기")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "jje" && r.word == "궤기" })
  end
end
