# frozen_string_literal: true

require "test_helper"

# Wiktionary-Middle French: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (livre · chien),
# selected by rule (README). Stored code frm.
class WiktionaryFrmTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryFrm
  def kaikki_slug = "wiktionary-frm"
  def kaikki_filename = "kaikki.org-dictionary-MiddleFrench.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Middle%20French/kaikki.org-dictionary-MiddleFrench.jsonl"
  def kaikki_language = "frm"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("livre")
    assert_equal "book", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "fro" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("chien")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "fr" && r.word == "chien" })
  end
end
