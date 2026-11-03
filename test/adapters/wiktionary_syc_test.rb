# frozen_string_literal: true

require "test_helper"

# Wiktionary-Classical Syriac: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (ܟܠܒܐ · ܐܒܐ),
# selected by rule (README). Stored code syc.
class WiktionarySycTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionarySyc
  def kaikki_slug = "wiktionary-syc"
  def kaikki_filename = "kaikki.org-dictionary-ClassicalSyriac.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Classical%20Syriac/kaikki.org-dictionary-ClassicalSyriac.jsonl"
  def kaikki_language = "syc"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("ܟܠܒܐ")
    assert_equal "wild, mad", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "sem-pro" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("ܐܒܐ")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "grc" && r.word == "ἀββα" })
  end
end
