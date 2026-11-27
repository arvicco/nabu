# frozen_string_literal: true

require "test_helper"

# Wiktionary-Ottoman Turkish: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (آیا · جهاد),
# selected by rule (README). Stored code ota.
class WiktionaryOtaTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryOta
  def kaikki_slug = "wiktionary-ota"
  def kaikki_filename = "kaikki.org-dictionary-OttomanTurkish.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Ottoman%20Turkish/kaikki.org-dictionary-OttomanTurkish.jsonl"
  def kaikki_language = "ota"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("آیا")
    assert_equal "the inner surface of the hand and foot, or the middle portion of that surface", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "trk-pro" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("جهاد")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "tr" && r.word == "cihat" })
  end
end
