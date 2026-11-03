# frozen_string_literal: true

require "test_helper"

# Wiktionary-Serbo-Croatian: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (august · žaba),
# selected by rule (README). Stored code srp.
class WiktionaryShTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionarySh
  def kaikki_slug = "wiktionary-sh"
  def kaikki_filename = "kaikki.org-dictionary-SerboCroatian.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Serbo-Croatian/kaikki.org-dictionary-SerboCroatian.jsonl"
  def kaikki_language = "srp"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("august")
    assert_equal "August", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "la" && r.relation == "derived" })
  end

  def test_every_entry_also_answers_the_croatian_tag
    kaikki_document.each { |entry| assert_equal "hrv", entry.annotations["language"] }
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("žaba")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "sq" && r.word == "zhabë" })
  end
end
