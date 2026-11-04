# frozen_string_literal: true

require "test_helper"

# Wiktionary-Zhuang: the kaikki.org per-language JSONL on the shared
# WiktionaryScriptShelf base — Sawcuengh (Latin) headwords with their
# Sawndip spellings as body lines + typed crossrefs, and the empty-stub
# skip rule. Trimmed-real fixture: 6 records (README), 4 kept and 2 empty
# stubs skipped. Stored code za.
class WiktionaryZaTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryZa
  def kaikki_slug = "wiktionary-za"
  def kaikki_filename = "kaikki.org-dictionary-Zhuang.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Zhuang/kaikki.org-dictionary-Zhuang.jsonl"
  def kaikki_language = "za"
  def kaikki_entry_count = 4

  def test_the_kept_entries_in_upstream_order
    assert_equal %w[de:pron o:adj:2 ч:character dienh:verb], kaikki_document.map(&:entry_id)
  end

  def test_a_headword_carries_its_sawndip_forms
    entry = kaikki_entry("de")
    assert_equal "he, she, it", entry.gloss
    assert_equal "Sawndip forms: 他, 𬿇, 𭶼, 爹, 佚, 𰂡", entry.body.lines.last
    assert_equal %w[他 𬿇 𭶼 爹 佚 𰂡], entry.crossrefs.map(&:target)
    assert_equal ["sawndip-form"], entry.crossrefs.map(&:kind).uniq
  end

  # Unencoded Sawndip characters ride as Ideographic Description Sequences
  # upstream (⿰目荷) — kept verbatim, never decomposed or dropped.
  def test_an_ids_spelled_sawndip_form_stays_verbatim
    entry = kaikki_document.find { |e| e.entry_id == "o:adj:2" }
    assert_equal "Sawndip forms: 嗬, 荷, ⿰目荷", entry.body.lines.last
  end

  def test_a_glossless_entry_with_an_etymology_is_kept
    entry = kaikki_document.find { |e| e.entry_id == "dienh:verb" }
    assert_nil entry.gloss
    assert_match(/From Chinese 電/, entry.body)
    assert_empty entry.crossrefs
  end

  def test_empty_stubs_are_skipped_by_rule_and_censused
    adapter = kaikki_adapter_class.new
    adapter.parse(adapter.discover(kaikki_fixtures).first)
    skips = adapter.discovery_skips(kaikki_fixtures)
    assert_equal 2, skips.skipped_by_rule
    assert_match(/2 empty stub\(s\) skipped by rule/, skips.notes.first)
    assert_match(%r{4 entries kept \(0 glossless kept for their readings/script forms, 1 for their etymology\)},
                 skips.notes.first)
  end
end
