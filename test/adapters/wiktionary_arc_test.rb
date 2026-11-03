# frozen_string_literal: true

require "test_helper"

# Wiktionary-Aramaic: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (עבר · מרים),
# selected by rule (README). Stored code arc.
class WiktionaryArcTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryArc
  def kaikki_slug = "wiktionary-arc"
  def kaikki_filename = "kaikki.org-dictionary-Aramaic.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Aramaic/kaikki.org-dictionary-Aramaic.jsonl"
  def kaikki_language = "arc"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("עבר")
    assert_equal "to pass over, to cross over", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "sem-pro" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("מרים")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "syc" && r.word == "ܡܪܝܡ" })
  end
end
