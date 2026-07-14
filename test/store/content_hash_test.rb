# frozen_string_literal: true

require "test_helper"

# ContentHash is a PERSISTENT FORMAT (its own header note): P14-1 adds
# reflexes to dictionary entries, and the encoding appends them ONLY when
# non-empty so every reflex-less entry on every existing shelf keeps its
# stored sha — no revision storm on the next full load. The hex pins below
# were computed BEFORE the reflex field existed; they must never change.
class ContentHashTest < Minitest::Test
  def citation
    Nabu::DictionaryCitation.new(urn_raw: "urn:cts:x:y", cts_work: "urn:cts:x",
                                 citation: "1.1", label: "X 1.1")
  end

  def entry(**overrides)
    Nabu::DictionaryEntry.new(
      entry_id: "богъ:noun", key_raw: "богъ", language: "chu",
      headword: "богъ", headword_folded: "богъ",
      gloss: "god", body: "Inherited from Proto-Slavic *bogъ.\ngod",
      citations: [citation], **overrides
    )
  end

  def reflex(**overrides)
    Nabu::DictionaryReflex.new(
      lang_code: "cu", language: "chu", word: "богъ",
      roman: nil, word_folded: "богъ", roman_folded: nil, **overrides
    )
  end

  # The pre-P14-1 pins: reflex-less entries hash EXACTLY as they always did.
  def test_reflexless_entry_sha_is_pinned_pre_reflex_encoding
    assert_equal "5f8a81bdf8d59d25a731716491920e651e9ed5f93b8f7fe772e38efc9b7c9844",
                 Nabu::Store::ContentHash.dictionary_entry(entry)
  end

  def test_minimal_reflexless_entry_sha_is_pinned_pre_reflex_encoding
    minimal = Nabu::DictionaryEntry.new(
      entry_id: "a", key_raw: "a", language: "chu",
      headword: "a", headword_folded: "a", body: "b"
    )
    assert_equal "c3fd41c44df7f12c696f6ef60d5c591719aa0704d96f2af994657eaac5a8671b",
                 Nabu::Store::ContentHash.dictionary_entry(minimal)
  end

  def test_reflexes_are_content
    with_reflex = entry(reflexes: [reflex])
    assert_equal Nabu::Store::ContentHash.dictionary_entry(with_reflex),
                 Nabu::Store::ContentHash.dictionary_entry(entry(reflexes: [reflex]))
    refute_equal Nabu::Store::ContentHash.dictionary_entry(entry),
                 Nabu::Store::ContentHash.dictionary_entry(with_reflex)
    refute_equal Nabu::Store::ContentHash.dictionary_entry(entry(reflexes: [reflex])),
                 Nabu::Store::ContentHash.dictionary_entry(entry(reflexes: [reflex(word: "боже", word_folded: "боже")]))
  end

  # P17-3: the borrowed flag is DELIBERATELY part of the reflex encoding —
  # the flag-aware reparse changes the sha of every reflex-carrying entry,
  # which is exactly what re-mints their revisions (and thus backfills
  # migration 010's column) at the next owner-fired parse-only resync.
  # Reflex-less entries stay pinned above, byte for byte.
  def test_borrowed_is_content_on_reflex_carrying_entries_only
    refute_equal Nabu::Store::ContentHash.dictionary_entry(entry(reflexes: [reflex(borrowed: false)])),
                 Nabu::Store::ContentHash.dictionary_entry(entry(reflexes: [reflex(borrowed: true)]))
  end

  # P18-4: lang_name is DELIBERATELY NOT content — it feeds the derived
  # language_names census, not entry identity. The name-aware parse must not
  # revise a single stored entry (no revision storm; the census recovers at
  # any rebuild/resync regardless).
  def test_lang_name_is_display_metadata_never_content
    assert_equal Nabu::Store::ContentHash.dictionary_entry(entry(reflexes: [reflex])),
                 Nabu::Store::ContentHash.dictionary_entry(
                   entry(reflexes: [reflex(lang_name: "Old Church Slavonic")])
                 )
  end
end
