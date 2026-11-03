# frozen_string_literal: true

require "test_helper"

# Wiktionary-Old French: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (livre · chien),
# selected by rule (README). Stored code fro.
class WiktionaryFroTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryFro
  def kaikki_slug = "wiktionary-fro"
  def kaikki_filename = "kaikki.org-dictionary-OldFrench.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Old%20French/kaikki.org-dictionary-OldFrench.jsonl"
  def kaikki_language = "fro"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("livre")
    assert_equal "livre (medieval French equivalent of a monetary pound)", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "la" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("chien")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "roa-ang" && r.word == "chin" })
  end
end
