# frozen_string_literal: true

require "test_helper"

# Wiktionary-Old Norse: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (en · man),
# selected by rule (README). Stored code non.
class WiktionaryNonTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryNon
  def kaikki_slug = "wiktionary-non"
  def kaikki_filename = "kaikki.org-dictionary-OldNorse.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Old%20Norse/kaikki.org-dictionary-OldNorse.jsonl"
  def kaikki_language = "non"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("en")
    assert_equal "but", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "gem-pro" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("man")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "is" && r.word == "man" })
  end
end
