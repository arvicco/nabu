# frozen_string_literal: true

require "test_helper"

# Wiktionary-Vietnamese: the kaikki.org per-language JSONL on the shared
# WiktionaryScriptShelf base — the family mold plus the chữ Nôm layer
# (readings and Hán-Nôm forms into body lines + typed crossrefs) and the
# empty-stub skip rule. Trimmed-real fixture: 9 records (README), 7 kept
# and 2 empty stubs (one character, one word) skipped. Stored code vi.
class WiktionaryViTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryVi
  def kaikki_slug = "wiktionary-vi"
  def kaikki_filename = "kaikki.org-dictionary-Vietnamese.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Vietnamese/kaikki.org-dictionary-Vietnamese.jsonl"
  def kaikki_language = "vi"
  def kaikki_entry_count = 7

  def test_the_kept_entries_in_upstream_order
    assert_equal %w[犬:character 馬:character 馬:noun:1 犭:character toe:verb sung:adj:2 chó:noun],
                 kaikki_document.map(&:entry_id)
  end

  def test_a_glossed_character_carries_its_nom_and_han_viet_readings
    entry = kaikki_entry("犬")
    assert_equal "chữ Nôm form of chó (“dog”)", entry.gloss
    assert_includes entry.body.lines.map(&:chomp), "Hán-Việt readings: khuyển"
    assert_includes entry.body.lines.map(&:chomp), "Nôm readings: khuyển, chó"
    assert_equal([%w[han-viet-reading khuyển], %w[nom-reading khuyển], %w[nom-reading chó]],
                 entry.crossrefs.map { |c| [c.kind, c.target] })
  end

  # The Nôm data the shelf exists for rides glossless character records:
  # kept, gloss nil, the readings in the body.
  def test_a_glossless_character_with_readings_is_kept
    entry = kaikki_document.find { |e| e.entry_id == "馬:character" }
    assert_nil entry.gloss
    assert_includes entry.body.lines.map(&:chomp), "Nôm readings: mựa, mã, mở, mứa, mả, mỡ, ngựa"
    assert_includes entry.body.lines.map(&:chomp), "Hán-Việt readings: mã"
    assert_equal 8, entry.crossrefs.size
  end

  def test_the_older_shape_reads_han_nom_tagged_forms_as_readings
    entry = kaikki_entry("犭")
    assert_includes entry.body.lines.map(&:chomp), "Hán-Nôm readings: khuyển"
    assert_equal([%w[han-nom-reading khuyển]], entry.crossrefs.map { |c| [c.kind, c.target] })
  end

  def test_a_word_carries_its_han_nom_spellings
    entry = kaikki_entry("chó")
    assert_equal "dog", entry.gloss
    assert_includes entry.body.lines.map(&:chomp), "Hán-Nôm forms: 㹥, 𤝹, 𤠚, 𦢞, 犬"
    assert_equal %w[㹥 𤝹 𤠚 𦢞 犬], entry.crossrefs.select { |c| c.kind == "han-nom-form" }.map(&:target)
    assert(entry.reflexes.any? { |r| r.relation == "inherited" && r.lang_code == "mkh-vie-pro" })
  end

  def test_the_family_body_is_kept_ahead_of_the_script_lines
    entry = kaikki_entry("chó")
    assert_match(/\AFrom Proto-Vietic/, entry.body)
    assert_equal "Hán-Nôm forms: 㹥, 𤝹, 𤠚, 𦢞, 犬", entry.body.lines.last
  end

  def test_glossless_words_with_a_spelling_or_an_etymology_are_kept
    assert_includes kaikki_entry("toe").body, "Hán-Nôm forms: 𡄪"
    sung = kaikki_document.find { |e| e.entry_id == "sung:adj:2" }
    assert_nil sung.gloss
    assert_match(/Sino-Vietnamese word from 充/, sung.body)
  end

  def test_empty_stubs_are_skipped_by_rule_and_censused
    adapter = kaikki_adapter_class.new
    document = adapter.parse(adapter.discover(kaikki_fixtures).first)
    refute(document.any? { |entry| entry.headword == "丂" }, "the empty character stub is skipped")
    refute(document.any? { |entry| entry.headword == "ken" }, "the empty word stub is skipped")

    skips = adapter.discovery_skips(kaikki_fixtures)
    assert_equal 2, skips.skipped_by_rule
    assert_equal 1, skips.notes.size
    assert_match(/2 empty stub\(s\) skipped by rule/, skips.notes.first)
    assert_match(%r{7 entries kept \(3 glossless kept for their readings/script forms, 1 for their etymology\)},
                 skips.notes.first)
  end

  def test_discovery_skips_without_a_parse_says_so
    skips = kaikki_adapter_class.new.discovery_skips(kaikki_fixtures)
    assert_equal 0, skips.skipped_by_rule
    assert_match(/rides the parse/, skips.notes.first)
  end
end
