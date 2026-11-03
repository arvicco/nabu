# frozen_string_literal: true

require "test_helper"

# Wiktionary-Old Spanish: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base. Trimmed-real fixture: 2 records (pie · pez),
# selected by rule (README). Stored code osp.
class WiktionaryOspTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryOsp
  def kaikki_slug = "wiktionary-osp"
  def kaikki_filename = "kaikki.org-dictionary-OldSpanish.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Old%20Spanish/kaikki.org-dictionary-OldSpanish.jsonl"
  def kaikki_language = "osp"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("pie")
    assert_equal "foot", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "la" && r.relation == "inherited" })
  end

  def test_a_descendant_tree_mints_its_reflex
    entry = kaikki_entry("pez")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "es" && r.word == "pez" })
  end
end
