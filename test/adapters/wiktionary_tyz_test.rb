# frozen_string_literal: true

require "test_helper"

# Wiktionary-Tày: the kaikki.org per-language JSONL on the shared
# WiktionaryScriptShelf base — Latin-orthography headwords with their Nôm
# Tày spellings as body lines + typed crossrefs, the Nôm Tày character
# records ("Nôm form of …"), and the empty-stub skip rule. Trimmed-real
# fixture: 5 records (README), 4 kept and 1 empty stub skipped. Stored
# code tyz.
class WiktionaryTyzTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryTyz
  def kaikki_slug = "wiktionary-tyz"
  def kaikki_filename = "kaikki.org-dictionary-Tay.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/T%C3%A0y/kaikki.org-dictionary-T%C3%A0y.jsonl"
  def kaikki_language = "tyz"
  def kaikki_entry_count = 4

  def test_the_kept_entries_in_upstream_order
    assert_equal ["nu:noun", "倍:character", "xá:classifier:4", "náo lo̱:particle"],
                 kaikki_document.map(&:entry_id)
  end

  def test_a_headword_carries_its_nom_tay_spelling_and_proto_tai_etymon
    entry = kaikki_entry("nu")
    assert_equal "mouse", entry.gloss
    assert_equal "Nôm Tày forms: 𮮬", entry.body.lines.last
    assert_equal([%w[nom-tay-form 𮮬]], entry.crossrefs.map { |c| [c.kind, c.target] })
    assert(entry.reflexes.any? { |r| r.relation == "inherited" && r.lang_code == "tai-pro" })
  end

  def test_a_nom_tay_character_record_reads_with_its_gloss
    assert_equal "Nôm form of viòi.", kaikki_entry("倍").gloss
  end

  def test_a_glossless_entry_with_spellings_is_kept
    entry = kaikki_document.find { |e| e.entry_id == "xá:classifier:4" }
    assert_nil entry.gloss
    assert_equal "Nôm Tày forms: 赦, 舍", entry.body.lines.last
  end

  def test_the_empty_stub_is_skipped_by_rule_and_censused
    adapter = kaikki_adapter_class.new
    document = adapter.parse(adapter.discover(kaikki_fixtures).first)
    refute(document.any? { |entry| entry.headword == "nà" })
    skips = adapter.discovery_skips(kaikki_fixtures)
    assert_equal 1, skips.skipped_by_rule
    assert_match(%r{4 entries kept \(1 glossless kept for their readings/script forms, 1 for their etymology\)},
                 skips.notes.first)
  end
end
