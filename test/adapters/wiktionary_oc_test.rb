# frozen_string_literal: true

require "test_helper"

# Wiktionary-Occitan: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (gratuit · nogat),
# selected by rule (README). Stored code oci.
class WiktionaryOcTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryOc
  def kaikki_slug = "wiktionary-oc"
  def kaikki_filename = "kaikki.org-dictionary-Occitan.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Occitan/kaikki.org-dictionary-Occitan.jsonl"
  def kaikki_language = "oci"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("gratuit")
    assert_equal "free, free of charge", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "la" && r.relation == "derived" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("nogat")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "fr" && r.word == "nougat" })
  end
end
