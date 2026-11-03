# frozen_string_literal: true

require "test_helper"

# Wiktionary-Arabic: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base, plus the shelf's one parse rule — glossless
# records (inflected-form stubs) are skipped by rule and censused in
# discovery_skips. Trimmed-real fixture: 5 records (README), 3 glossed
# (kept) and 2 glossless stubs of the two shapes (skipped). Stored code ara.
class WiktionaryArTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryAr
  def kaikki_slug = "wiktionary-ar"
  def kaikki_filename = "kaikki.org-dictionary-Arabic.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Arabic/kaikki.org-dictionary-Arabic.jsonl"
  def kaikki_language = "ara"
  def kaikki_entry_count = 3

  def test_only_glossed_records_become_entries
    assert_equal %w[أنا:pron:1 حساسية:adj:2 لبد:noun], kaikki_document.map(&:entry_id)
    kaikki_document.each { |entry| refute_nil entry.gloss }
  end

  def test_a_known_entry_reads_with_its_gloss_etymon_and_descendants
    entry = kaikki_entry("أنا")
    assert_equal "I (first person singular subject pronoun)", entry.gloss
    assert(entry.reflexes.any? { |r| r.relation == "inherited" && r.lang_code == "afa-pro" })
    assert(entry.reflexes.any? { |r| r.relation.nil? && r.lang_code == "mt" && r.word == "jien" })
  end

  def test_a_borrowing_etymon_mints_a_borrowed_edge
    entry = kaikki_entry("لبد")
    assert(entry.reflexes.any? { |r| r.relation == "borrowed" && r.lang_code == "arc" && r.borrowed })
  end

  # The rule reads the GLOSS, never the etymology text: a glossed form-of
  # entry carrying the "corresponding lemma form" pointer stays.
  def test_a_glossed_form_of_entry_with_the_lemma_pointer_is_kept
    entry = kaikki_entry("حساسية")
    assert_match(/\Afeminine singular of/, entry.gloss)
    assert_match(/corresponding lemma form/, entry.body)
  end

  def test_both_stub_shapes_are_skipped_by_rule_and_censused
    adapter = kaikki_adapter_class.new
    document = adapter.parse(adapter.discover(kaikki_fixtures).first)
    refute(document.any? { |entry| entry.headword == "أدبي" }, "the lemma-pointer stub is skipped")
    refute(document.any? { |entry| entry.entry_id == "أنا:verb:3" }, "the bare no-gloss stub is skipped")

    skips = adapter.discovery_skips(kaikki_fixtures)
    assert_equal 2, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_equal 1, skips.notes.size
    assert_match(/2 glossless record\(s\) skipped by rule/, skips.notes.first)
    assert_match(/1 inflected-form stub\(s\) pointing at the corresponding lemma form/, skips.notes.first)
    assert_match(/1 bare no-gloss stub\(s\)/, skips.notes.first)
    assert_match(/3 glossed entries kept/, skips.notes.first)
  end

  def test_discovery_skips_without_a_parse_says_so
    skips = kaikki_adapter_class.new.discovery_skips(kaikki_fixtures)
    assert_equal 0, skips.skipped_by_rule
    assert_match(/rides the parse/, skips.notes.first)
  end
end
