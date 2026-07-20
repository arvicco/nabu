# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Tls adapter tests (P33-4): the Thesaurus Linguae Sericae as the dictionary
# shelf's first onomasiological occupant — ONE source, TWO dictionaries
# (tls-concepts + tls-words, the hebrew-lexicon grain), membership INVERTED
# from the words side into concept bodies. Fixtures are byte-verbatim
# upstream files (one trimmed — test/fixtures/tls/README.md).
class TlsTest < Minitest::Test
  include StoreTestDB

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

  # --- attestation citations (P34-4) ------------------------------------------
  # notes/doc + notes/swl carry the sense-level attestation lane: each
  # tls:ann links (seg id, sense uuid), and word entries mint one
  # DictionaryCitation per distinct pair whose sense they own. KR-shaped
  # text ids carry cts_work urn:nabu:kanripo:<id>; segs matching the
  # mandoku anchor grammar carry citation "<juan>:<page>" (the kanripo
  # passage key). Fixtures are trimmed REAL ann files (README).

  def test_word_entries_mint_citations_from_the_notes_attestations
    qi = words_doc.entries.find { |entry| entry.headword == "棄" }
    assert_equal 7, qi.citations.size, "7 fixture attestations name 棄's senses"

    first = qi.citations.first # sense doc order, then (text, juan, page, line)
    assert_nil first.cts_work, "CH1a0907 is a TLS-side text id — no kanripo claim"
    assert_nil first.citation
    assert_equal "#CH1a0907_CHANT_010-21a.6 #uuid-8f745d61-7ec6-4d08-a960-cc98b59fcc10", first.urn_raw
    assert_match(/說苑 010-21a\.6 「管仲半棄酒，」/, first.label)
    assert_match(/sense uuid-8f745d61/, first.label, "the sense binding rides the label")

    meng = qi.citations[2]
    assert_equal "urn:nabu:kanripo:KR1h0001", meng.cts_work
    assert_equal "001:6a", meng.citation, "the kanripo passage key (juan:page)"
    assert_match(/孟子 001-6a\.7 「棄甲曳兵而走。」/, meng.label)

    assert_equal %w[005:22a 018:31a 013:30a 017:27a], qi.citations[3..].map(&:citation),
                 "論語 attestations in sense doc order, page-sorted within a sense"
  end

  def test_citations_cover_both_upstream_ann_shapes
    she = words_doc.entries.find { |entry| entry.headword == "舍" }
    assert_equal 2, she.citations.size, "tls:ann-prefixed (孟子) + default-ns (論語) both parse"
    assert_equal %w[urn:nabu:kanripo:KR1h0001 urn:nabu:kanripo:KR1h0004], she.citations.map(&:cts_work)
    assert_equal %w[008:21a 009:19a], she.citations.map(&:citation)
    assert_match(/不舍晝夜/, she.citations.first.label)
  end

  def test_unattested_words_and_concepts_carry_no_citations
    pei_er = words_doc.entries.find { |entry| entry.headword == "陪貳" }
    assert_empty pei_er.citations
    concepts_doc.entries.each { |entry| assert_empty entry.citations }
  end

  def test_notes_absence_is_an_honest_citation_free_parse
    Dir.mktmpdir do |root|
      FileUtils.cp_r(File.join(FIXTURES, "concepts"), root)
      FileUtils.cp_r(File.join(FIXTURES, "words"), root)
      refs = adapter.discover(root).to_a
      words = adapter.parse(refs.find { |ref| ref.id.start_with?("tls-words") })
      words.entries.each { |entry| assert_empty entry.citations }
    end
  end

  def test_citations_are_stable_across_two_parses
    first = words_doc.entries.map(&:citations)
    second = words_doc.entries.map(&:citations)
    assert_equal first, second
  end

  # The seg-id grammar census (P34-4, upstream 2026-07-20): 99.7% match
  # <text>_<edition>_<juan>-<page>[.line]; the strays (REAL censused ids
  # below) keep text-grain honesty — KR-shaped ids still claim the kanripo
  # document, page probes are never invented.
  def test_seg_reference_maps_the_censused_grammar_and_its_strays
    parser = Nabu::Adapters::TlsXmlParser.new
    ref = parser.seg_reference("KR1h0004_tls_005-22a.4")
    assert_equal ["urn:nabu:kanripo:KR1h0004", "005:22a", "005-22a.4"],
                 [ref.cts_work, ref.citation, ref.ref]
    stray = parser.seg_reference("KR3f0032_tls_001-p0007a-s2-seg1a")
    assert_equal "urn:nabu:kanripo:KR3f0032", stray.cts_work, "KR text id still claims the document"
    assert_nil stray.citation, "a non-anchor seg never invents a page"
    cbeta = parser.seg_reference("T52n2102_CBETA_001-0001c0101.s16")
    assert_nil cbeta.cts_work, "Taishō ids are not kanripo texts — no claim this packet"
    assert_nil cbeta.citation
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

  # --- loader round-trip (P34-4): citations land and stay idempotent ----------

  def test_citation_rows_land_and_reload_is_idempotent
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "tls", name: "TLS", adapter_class: "Nabu::Adapters::Tls",
      license_class: "attribution", enabled: false
    )
    loader = Nabu::Store::DictionaryLoader.new(db: db, source: source)

    loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 9, db[:dictionary_citations].count, "棄 7 + 舍 2 — the fixture attestation census"
    qi = db[:dictionary_entries].where(entry_id: "uuid-fbba1aa8-49bc-49be-ba1a-a849bc59bed5").first
    assert_equal 7, db[:dictionary_citations].where(dictionary_entry_id: qi[:id]).count

    loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 9, db[:dictionary_citations].count, "idempotent reload keeps counts"
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq, "no revision flap"
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
