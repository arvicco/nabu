# frozen_string_literal: true

require "test_helper"

# Wiktionary-Old Swedish: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (fa · sky),
# selected by rule (README). Stored code sv.
class WiktionaryGmqOswTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryGmqOsw
  def kaikki_slug = "wiktionary-gmq-osw"
  def kaikki_filename = "kaikki.org-dictionary-OldSwedish.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Old%20Swedish/kaikki.org-dictionary-OldSwedish.jsonl"
  def kaikki_language = "sv"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("fa")
    assert_equal "to seize, take", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "non" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("sky")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "sv" && r.word == "sky" })
  end
end
