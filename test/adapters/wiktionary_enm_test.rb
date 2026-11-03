# frozen_string_literal: true

require "test_helper"

# Wiktionary-Middle English: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (cat · word),
# selected by rule (README). Stored code enm.
class WiktionaryEnmTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryEnm
  def kaikki_slug = "wiktionary-enm"
  def kaikki_filename = "kaikki.org-dictionary-MiddleEnglish.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Middle%20English/kaikki.org-dictionary-MiddleEnglish.jsonl"
  def kaikki_language = "enm"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("cat")
    assert_equal "cat (feline)", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "ang" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("word")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "en" && r.word == "word" })
  end
end
