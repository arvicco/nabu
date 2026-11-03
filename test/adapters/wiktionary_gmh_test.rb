# frozen_string_literal: true

require "test_helper"

# Wiktionary-Middle High German: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (name · winter),
# selected by rule (README). Stored code gmh.
class WiktionaryGmhTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryGmh
  def kaikki_slug = "wiktionary-gmh"
  def kaikki_filename = "kaikki.org-dictionary-MiddleHighGerman.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Middle%20High%20German/kaikki.org-dictionary-MiddleHighGerman.jsonl"
  def kaikki_language = "gmh"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("name")
    assert_equal "name", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "goh" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("winter")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "gsw" && r.word == "Winter" })
  end
end
