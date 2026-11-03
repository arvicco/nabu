# frozen_string_literal: true

require "test_helper"

# Wiktionary-Gothic: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (𐌼𐌰𐌸𐌰 · 𐌺𐌰𐍄𐌹𐌻𐍃),
# selected by rule (README). Stored code got.
class WiktionaryGotTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryGot
  def kaikki_slug = "wiktionary-got"
  def kaikki_filename = "kaikki.org-dictionary-Gothic.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Gothic/kaikki.org-dictionary-Gothic.jsonl"
  def kaikki_language = "got"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("𐌼𐌰𐌸𐌰")
    assert_equal "maggot (larva that eats decomposing organic matter)", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "gem-pro" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("𐌺𐌰𐍄𐌹𐌻𐍃")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "sla-pro" && r.word == "*kotь̀lъ" })
  end
end
