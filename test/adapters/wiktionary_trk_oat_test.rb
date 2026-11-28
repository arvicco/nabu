# frozen_string_literal: true

require "test_helper"

# Wiktionary-Old Anatolian Turkish: the kaikki.org per-language JSONL on the
# shared WiktionaryKaikki base. Trimmed-real fixture: 2 records (میوه · من),
# selected by rule (README). Stored code trk-oat — Wiktionary's own code,
# verbatim (no ISO code exists; the wiktionary-recon proto-shelf stance).
class WiktionaryTrkOatTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryTrkOat
  def kaikki_slug = "wiktionary-trk-oat"
  def kaikki_filename = "kaikki.org-dictionary-OldAnatolianTurkish.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Old%20Anatolian%20Turkish/kaikki.org-dictionary-OldAnatolianTurkish.jsonl"
  def kaikki_language = "trk-oat"
  def kaikki_entry_count = 2

  def test_a_known_entry_reads_with_its_gloss_and_etymon
    entry = kaikki_entry("میوه")
    assert_equal "fruit", entry.gloss
    assert(entry.reflexes.any? { |r| r.lang_code == "fa" && r.relation == "borrowed" && r.borrowed })
  end

  # The Old Anatolian → Ottoman descent rides the descendant trees: the
  # crosswalk edge the wiktionary-ota shelf meets.
  def test_a_descendant_tree_mints_its_ottoman_reflex
    entry = kaikki_entry("من")
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "ota" && r.word == "من" })
  end
end
