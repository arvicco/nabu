# frozen_string_literal: true

require "test_helper"

# Wiktionary-Old Frisian: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (fa · on),
# selected by rule (README). Stored code ofs.
class WiktionaryOfsTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryOfs
  def kaikki_slug = "wiktionary-ofs"
  def kaikki_filename = "kaikki.org-dictionary-OldFrisian.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Old%20Frisian/kaikki.org-dictionary-OldFrisian.jsonl"
  def kaikki_language = "ofs"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("fa")
    assert_equal "to catch", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "gmw-pro" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("on")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "frr" && r.word == "a" })
  end
end
