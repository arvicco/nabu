# frozen_string_literal: true

require "test_helper"

# Wiktionary-Scots: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (frei · acre),
# selected by rule (README). Stored code sco.
class WiktionaryScoTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionarySco
  def kaikki_slug = "wiktionary-sco"
  def kaikki_filename = "kaikki.org-dictionary-Scots.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Scots/kaikki.org-dictionary-Scots.jsonl"
  def kaikki_language = "sco"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("frei")
    assert_equal "free", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "ang" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("acre")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "gd" && r.word == "acaire" })
  end
end
