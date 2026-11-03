# frozen_string_literal: true

require "test_helper"

# Wiktionary-Middle Dutch: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (raven · name),
# selected by rule (README). Stored code dum.
class WiktionaryDumTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryDum
  def kaikki_slug = "wiktionary-dum"
  def kaikki_filename = "kaikki.org-dictionary-MiddleDutch.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Middle%20Dutch/kaikki.org-dictionary-MiddleDutch.jsonl"
  def kaikki_language = "dum"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("raven")
    assert_equal "raven", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "odt" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("name")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "nl" && r.word == "naam" })
  end
end
