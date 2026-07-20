# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Tls adapter tests (P33-4): the Thesaurus Linguae Sericae as the dictionary
# shelf's first onomasiological occupant — ONE source, TWO dictionaries
# (tls-concepts + tls-words, the hebrew-lexicon grain), membership INVERTED
# from the words side into concept bodies. Fixtures are byte-verbatim
# upstream files (one trimmed — test/fixtures/tls/README.md).
class TlsTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("tls")

  CONCEPTS_URN = "urn:nabu:dict:tls-concepts:"

  def adapter
    Nabu::Adapters::Tls.new
  end

  # --- manifest / capabilities ------------------------------------------------

  def test_manifest_records_the_by_sa_grant_and_the_readme_discrepancy
    manifest = Nabu::Adapters::Tls.manifest
    assert_equal "tls", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/LICENSE\.md/, manifest.license, "the LICENSE.md grant is the witness")
    assert_match(/CC BY 4\.0 badge/, manifest.license, "the README badge discrepancy is recorded, not hidden")
    assert_equal "tls-xml", manifest.parser_family
  end

  def test_content_kind_routes_to_the_dictionary_loader
    assert_equal :dictionary, Nabu::Adapters::Tls.content_kind
  end

  def test_no_reflexes_are_promised
    refute Nabu::Adapters::Tls.reflex_bearing?,
           "concept membership is onomasiological, not etymological — no dictionary_reflexes"
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_dictionary_sorted
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[tls-concepts:concepts tls-words:words], refs.map(&:id)
    assert_equal(%w[tls-concepts tls-words], refs.map { |ref| ref.metadata.fetch("dictionary") })
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_discovery_skips_census_the_two_upstream_strays
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert skips.notes.any? { |note| note.include?("percent-encoded") }, skips.notes.inspect
    assert skips.notes.any? { |note| note.include?("empty-orth") }, skips.notes.inspect
  end

  # --- concepts ---------------------------------------------------------------

  def concepts_doc
    refs = adapter.discover(FIXTURES).to_a
    adapter.parse(refs.find { |ref| ref.id.start_with?("tls-concepts") })
  end

  def words_doc
    refs = adapter.discover(FIXTURES).to_a
    adapter.parse(refs.find { |ref| ref.id.start_with?("tls-words") })
  end

  def test_concepts_document_shape
    document = concepts_doc
    assert_equal "tls-concepts", document.slug
    assert_equal "och", document.language
    assert_equal 3, document.size,
                 "the percent-encoded stray AND the content-empty N-A placeholder skip by rule"
    assert_equal document.size, document.entries.map(&:entry_id).uniq.size
  end

  # Owner's first real sync (2026-07-20): concepts/N-A.xml is a genuinely
  # empty placeholder (head "N/A", definition <p/>, no notes/pointers/
  # members) — an empty body fails validation and quarantined the WHOLE
  # one-document shelf. Content-empty concepts skip by rule, censused.
  def test_content_empty_concept_skips_by_rule_not_quarantine
    parser = Nabu::Adapters::TlsXmlParser.new
    entries = parser.concept_entries(File.join(FIXTURES, "concepts"))
    refute entries.any? { |e| e.headword == "N/A" },
           "the N-A placeholder must not mint an empty entry"
    assert_equal 1, parser.skipped_empty_concepts, "the skip is censused, not silent"
  end

  def test_concept_entry_id_is_the_uuid_pointer_targets_name
    two = concepts_doc.entries.find { |entry| entry.headword == "TWO" }
    assert_equal "uuid-c4a2e239-0e1f-4a1b-8b9e-02a7fc557e6e", two.entry_id
  end

  def test_concept_carries_definition_notes_and_pointer_urns
    two = concepts_doc.entries.find { |entry| entry.headword == "TWO" }
    assert_equal "The NUMBER which is the BIGGER successor of ONE.", two.gloss
    assert_match(/translations: zh 兩個; och 二/, two.body)
    assert_match(/old-chinese-criteria:/, two.body)
    assert_match(/èr 二/, two.body, "the synonym-group discussion rides the body")
    assert_match(/hypernymy: NUMBER → #{CONCEPTS_URN}uuid-dd1c8de7-8201-4782-b6e3-960df290eae7/, two.body)
    assert_match(/taxonymy: DIVIDE → #{CONCEPTS_URN}uuid-3762c04a-9ca0-4fd6-b04e-2e24b1f91682/, two.body)
  end

  def test_concept_membership_is_inverted_from_the_words_side
    two = concepts_doc.entries.find { |entry| entry.headword == "TWO" }
    assert_match(/^words:$/, two.body)
    assert_match(/陪貳 \(péi èr\) — pair, two together/, two.body)

    abandon = concepts_doc.entries.find { |entry| entry.headword == "ABANDON" }
    assert_match(/棄/, abandon.body, "棄's ABANDON entry joins back via tls:concept-id")
    assert_match(/舍/, abandon.body)
  end

  def test_concept_without_members_omits_the_words_section
    crony = concepts_doc.entries.find { |entry| entry.headword == "CRONY" }
    refute_nil crony
    refute_match(/^words:$/, crony.body)
  end

  def test_concept_source_references_ride_the_body
    abandon = concepts_doc.entries.find { |entry| entry.headword == "ABANDON" }
    assert_match(/source: ROBERTS 1998 — Encyclopedia of Comparative Iconography — page 3/, abandon.body)
  end

  # --- words ------------------------------------------------------------------

  def test_words_document_shape
    document = words_doc
    assert_equal "tls-words", document.slug
    assert_equal "och", document.language
    assert_equal 4, document.size, "the empty-orth aggregate is skipped by rule"
    assert_equal document.size, document.entries.map(&:entry_id).uniq.size
  end

  def test_word_entry_is_the_superentry_with_orth_headword
    pei_er = words_doc.entries.find { |entry| entry.headword == "陪貳" }
    assert_equal "uuid-0002ba3b-600a-407c-82ba-3b600a007c84", pei_er.entry_id
    assert_equal "pair, two together", pei_er.gloss
    assert_match(/concept: TWO → #{CONCEPTS_URN}uuid-c4a2e239-0e1f-4a1b-8b9e-02a7fc557e6e/, pei_er.body)
    assert_match(/pinyin: péi èr \| oc: bɯɯ njis \| mc: buo̝i ȵi/, pei_er.body)
  end

  def test_word_sense_lines_keep_upstream_uuids_and_grammar
    qi = words_doc.entries.find { |entry| entry.headword == "棄" }
    assert_match(/entry 1 — concept: DISCARD → #{CONCEPTS_URN}uuid-2aa87a64-bc2b-49a7-88d4-99361624b20c/, qi.body)
    assert_match(
      /sense uuid-fa11bf1f-e345-480c-8a59-7b294a4a3297: N n \[object\] \(warring-states-currency:3\)/,
      qi.body, "the sense uuid is the attestation-crosswalk join key — kept verbatim"
    )
    assert_match(/— what has been discarded$/, qi.body)
    assert_match(/note: The standard general words for discarding/, qi.body,
                 "the entry-level discussion rides as a note line")
  end

  def test_word_variant_orth_is_shown_on_its_entry_block
    she = words_doc.entries.find { |entry| entry.headword == "舍" }
    assert_match(/entry 11 \(捨\) — concept: REJECT/, she.body, "the 捨 variant block names its own orth")
  end

  def test_entry_less_superentry_still_mints_a_minimal_word
    chi = words_doc.entries.find { |entry| entry.headword == "勑" }
    refute_nil chi, "an entry-less superEntry is a real word, not a skip"
    assert_nil chi.gloss
    assert_equal "word: 勑", chi.body
  end

  # --- shared contracts -------------------------------------------------------

  def test_headwords_fold_for_lookup
    two = concepts_doc.entries.find { |entry| entry.headword == "TWO" }
    assert_equal Nabu::Normalize.search_form("TWO", language: "och"), two.headword_folded
    qi = words_doc.entries.find { |entry| entry.headword == "棄" }
    assert_equal Nabu::Normalize.search_form("棄", language: "och"), qi.headword_folded
  end

  def test_parse_is_stable_across_two_runs
    first = concepts_doc.entries.map { |entry| [entry.entry_id, entry.body] }
    second = concepts_doc.entries.map { |entry| [entry.entry_id, entry.body] }
    assert_equal first, second
  end

  def test_all_text_is_nfc
    (concepts_doc.entries + words_doc.entries).each do |entry|
      assert entry.headword.unicode_normalized?(:nfc), entry.entry_id
      assert entry.body.unicode_normalized?(:nfc), entry.entry_id
    end
  end

  # --- registry ---------------------------------------------------------------

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["tls"]
    refute_nil entry, "config/sources.yml must register tls"
    assert_equal Nabu::Adapters::Tls, entry.adapter_class
    refute entry.enabled, "enabled stays false until the owner-fired first sync"
    assert_equal "manual", entry.sync_policy
  end
end
