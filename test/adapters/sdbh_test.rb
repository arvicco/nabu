# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The SDBH adapter (P30-2): the UBS Semantic Dictionary of Biblical Hebrew,
# the SECOND Hebrew dictionary shelf (deliberately unmerged with any sibling
# Hebrew lexicon — the MW-beside-kaikki precedent). Dictionary-shaped, so it
# cannot include the passage-shaped AdapterConformance suite; like
# MwTest/LexicaTest/BosworthTollerTest it mirrors those checks for the
# dictionary shape (manifest validity, discover→parse round-trip, id
# uniqueness/stability, byte-honesty in place of NFC — hbo/arc is the named
# NFC-exempt pair) and adds the FileFetch path (WebMock stubs of the raw
# GitHub URL), the DictionaryLoader contract (idempotency, urns, citation
# rows) and the fixture-level oshb resolution-shape measurement.
class SdbhTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("sdbh")

  RAW_URL = "https://raw.githubusercontent.com/ubsicap/ubs-open-license/main/" \
            "dictionaries/hebrew/XML/UBSHebrewDic-v0.9.2-en.XML"

  def adapter = Nabu::Adapters::Sdbh.new

  # --- manifest + content kind ----------------------------------------------

  def test_manifest_identifies_the_sdbh_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "sdbh", manifest.id
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/United Bible Societies/, manifest.license, "the UBS copyright line travels verbatim")
    assert_equal "attribution", manifest.license_class, "CC BY-SA → attribution (share-alike noted in docs)"
    assert_equal RAW_URL, manifest.upstream_url
    assert_equal "sdbh-xml", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Sdbh.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------

  def test_discover_yields_one_version_stable_ref
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["sdbh:UBSHebrewDic-en.XML"], refs.map(&:id),
                 "the ref id is version-free — a v1.0 upgrade must keep entry urns stable"
    assert_equal "sdbh", refs.first.source_id
    assert_equal "UBSHebrewDic-v0.9.2-en.XML", File.basename(refs.first.path)
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_hbo_dictionary_document_with_all_fixture_entries
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "sdbh", document.slug
    assert_equal "hbo", document.language
    assert_equal 11, document.size
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = -> { adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  # --- the hbo/arc byte-honesty seam (NFC exemption, architecture §3) --------

  # בֹּהוּ in UPSTREAM byte order: bet, dagesh (ccc 21), holam (ccc 19), he,
  # vav, dagesh — escaped so no editor can silently NFC-reorder the pin.
  BOHU_UPSTREAM = "בֹּהוּ"

  def test_headwords_are_byte_verbatim_never_nfc_normalized
    entries = adapter.parse(adapter.discover(FIXTURES).first).to_a
    bohu = entries.find { |e| e.entry_id == "000856000000000" }
    assert_equal BOHU_UPSTREAM, bohu.headword, "the upstream bytes exactly"
    refute bohu.headword.unicode_normalized?(:nfc),
           "בֹּהוּ ships dagesh-before-holam (Masoretic order) — NFC would reorder it; " \
           "if this ever normalizes, the exemption seam broke"
    assert bohu.headword.valid_encoding?
    assert bohu.headword_folded.unicode_normalized?(:nfc), "the SEARCH form always folds through NFC"
    assert_equal "בהו", bohu.headword_folded, "mark strip leaves the consonantal skeleton"
  end

  def test_entry_language_is_arc_only_when_every_strong_code_is_aramaic
    entries = adapter.parse(adapter.discover(FIXTURES).first).to_a
    by_id = entries.to_h { |e| [e.entry_id, e] }
    assert_equal "hbo", by_id.fetch("000001000000000").language, "אֵב carries H0003+A0004 — Hebrew primary"
    assert_equal "arc", by_id.fetch("000002000000000").language, "אַב carries only A0002"
    assert_equal "hbo", by_id.fetch("006756000000000").language,
                 "the Strong-quirk entry (an author name in StrongCodes) stays hbo"
    assert_equal "hbo", by_id.fetch("003803000000000").language, "no Strong codes at all → hbo default"
  end

  # --- gloss + body composition ---------------------------------------------

  def test_gloss_is_the_first_gloss_of_the_first_sense
    entries = adapter.parse(adapter.discover(FIXTURES).first).to_a
    assert_equal "blossom", entries.find { |e| e.entry_id == "000001000000000" }.gloss
    assert_equal "oppressor", entries.find { |e| e.entry_id == "002346000000000" }.gloss,
                 "an empty DefinitionShort still yields its gloss"
    assert_nil entries.find { |e| e.entry_id == "003803000000000" }.gloss,
               "a Notes-only entry (empty LEXMeanings) has no gloss — honest nil"
  end

  def test_body_carries_strongs_domains_definitions_and_glosses
    entries = adapter.parse(adapter.discover(FIXTURES).first).to_a
    body = entries.find { |e| e.entry_id == "000001000000000" }.body
    assert_includes body, "strong: H0003 A0004"
    assert_includes body, "noun m"
    assert_includes body, "1. (Vegetation 001002004) = part of a plant or tree that is typically " \
                          "surrounded by brightly colored petals and will eventually develop into a fruit"
    assert_includes body, "2. (Stage 002001001056)"
    assert_includes body, "collocations: בְּאֵב",
                    "בְּאֵב in upstream byte order (dagesh before sheva)"
    assert_includes body, "glosses: blossom; flower"
    assert_includes body, "refs: 3", "reference COUNTS ride the body; the list is citation rows"
  end

  def test_body_marks_aramaic_entries_and_renders_synonym_lanes
    entries = adapter.parse(adapter.discover(FIXTURES).first).to_a
    arc_body = entries.find { |e| e.entry_id == "000002000000000" }.body
    assert_includes arc_body, "language: arc"

    weak = entries.find { |e| e.entry_id == "002328000000000" }.body
    assert_includes weak, "synonyms: חשׁל"
    assert_includes weak, "antonyms: גִּבֹּור",
                    "גִּבֹּור in upstream byte order"
    assert_includes weak, "related: חלשׁ"
  end

  def test_body_renders_notes_with_reference_labels_and_content_verbatim
    entries = adapter.parse(adapter.discover(FIXTURES).first).to_a
    note_only = entries.find { |e| e.entry_id == "003803000000000" }
    assert_includes note_only.body, "note 1 (Jer 48:21 w15): {A:MT-K} | {A:MT-Q} מֵיפַעַת"
    assert_includes note_only.body, "name", "the pos line keeps a meaning-less entry non-empty"
  end

  def test_body_keeps_upstream_strong_quirks_verbatim
    entries = adapter.parse(adapter.discover(FIXTURES).first).to_a
    assert_includes entries.find { |e| e.entry_id == "006756000000000" }.body,
                    "strong: Reinier de Blois",
                    "an author name inside <StrongCodes> is an upstream defect — canonical means canonical"
    assert_includes entries.find { |e| e.entry_id == "006318000000000" }.body, "strong: 6859"
  end

  # --- scripture references → citation rows ---------------------------------

  def test_lexreferences_mint_verse_keyed_citations_against_oshb_urns
    entries = adapter.parse(adapter.discover(FIXTURES).first).to_a
    citations = entries.find { |e| e.entry_id == "000001000000000" }.citations
    assert_equal %w[02200601100016 01800801200006 02700400900008 02700401100032 02700401800010],
                 citations.map(&:urn_raw), "the 14-digit codes verbatim"
    assert_equal ["Song 6:11 w8", "Job 8:12 w3", "Dan 4:9 w4", "Dan 4:11 w16", "Dan 4:18 w5"],
                 citations.map(&:label), "MT versification — Dan 4:9, not the English 4:12"
    assert_equal %w[urn:nabu:oshb:song urn:nabu:oshb:job urn:nabu:oshb:dan],
                 citations.map(&:cts_work).uniq, "the resolution key IS the oshb document urn"
    assert_equal %w[6.11 8.12 4.9 4.11 4.18], citations.map(&:citation)
  end

  def test_footnote_marked_references_keep_the_marker_and_still_parse
    entries = adapter.parse(adapter.discover(FIXTURES).first).to_a
    citation = entries.find { |e| e.entry_id == "002346000000000" }.citations.first
    assert_equal "02300101700012{N:001}", citation.urn_raw, "the marker is upstream bytes — kept"
    assert_equal "urn:nabu:oshb:isa", citation.cts_work
    assert_equal "1.17", citation.citation
    assert_equal "Isa 1:17 w6 {N:001}", citation.label
  end

  def test_note_references_do_not_mint_citation_rows
    entries = adapter.parse(adapter.discover(FIXTURES).first).to_a
    assert_empty entries.find { |e| e.entry_id == "003803000000000" }.citations,
                 "Note <Reference>s are footnote anchors — rendered in the body, never citation rows"
  end

  # --- fetch (WebMock only, no network) --------------------------------------

  def fixture_bytes = File.binread(File.join(FIXTURES, "UBSHebrewDic-v0.9.2-en.XML"))

  def test_fetch_downloads_the_xml_and_returns_report
    stub_request(:get, RAW_URL).to_return(
      status: 200, body: fixture_bytes,
      headers: { "Last-Modified" => "Thu, 09 Jul 2026 18:17:22 GMT" }
    )
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      refs = adapter.discover(workdir).to_a
      assert_equal ["sdbh:UBSHebrewDic-en.XML"], refs.map(&:id), "the fetched file is discoverable in place"
      assert_equal 11, adapter.parse(refs.first).size

      stub_request(:get, RAW_URL)
        .with(headers: { "If-Modified-Since" => "Thu, 09 Jul 2026 18:17:22 GMT" })
        .to_return(status: 304)
      assert_equal report.sha, adapter.fetch(workdir).sha, "a 304 keeps the pinned sha"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, RAW_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ---------------------------------------------

  def test_probe_targets_head_the_raw_file_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Sdbh.remote_probe_strategy
    targets = Nabu::Adapters::Sdbh.http_probe_targets
    assert_equal 1, targets.size
    assert_equal RAW_URL, targets.first.zip_url
    assert_nil targets.first.metadata_url,
               "the grant lives in the repo's hebrew README.md (markdown, not a JSON license " \
               "endpoint) — honestly unchecked between refetches, the MW/ASPR stance"
    assert_equal Nabu::FileFetch::STATE_FILE, targets.first.state_file
  end

  # --- DictionaryLoader contract (idempotency / revision / urn) ---------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "sdbh", name: "UBS Dictionary of Biblical Hebrew",
      adapter_class: "Nabu::Adapters::Sdbh",
      license: "CC BY-SA 4.0", license_class: "attribution",
      upstream_url: RAW_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 11, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 11, second.skipped
    assert_equal 11, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    row = db[:dictionary_entries].where(entry_id: "000001000000000").first
    assert_equal "urn:nabu:dict:sdbh:000001000000000", row[:urn], "the upstream Id IS the entry id"
    assert_equal "אֵב", row[:headword]
    assert_equal "אב", row[:headword_folded]
  end

  def test_citation_rows_land_and_reload_idempotently
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 24, db[:dictionary_citations].count,
                 "5+9+1+3+1+1+1+1+0+1+1 LEXReferences across the eleven fixture entries"

    loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 24, db[:dictionary_citations].count, "idempotent reload keeps counts"
  end

  # --- the oshb resolution shape, measured at fixture level -------------------

  def seed_oshb!(db)
    source = Nabu::Store::Source.create(
      slug: "oshb", name: "Open Scriptures Hebrew Bible",
      adapter_class: "Nabu::Adapters::Oshb", license_class: "open"
    )
    Nabu::Store::Loader.new(db: db, source: source)
                       .load_from(Nabu::Adapters::Oshb.new,
                                  workdir: Nabu::TestSupport.fixtures("oshb"), full: true)
  end

  def test_citations_resolve_against_oshb_verse_urns_with_honest_misses
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    seed_oshb!(db)

    define = Nabu::Query::Define.new(catalog: db)
    bohu = define.run("בהו", lang: "hbo").find { |r| r.urn == "urn:nabu:dict:sdbh:000856000000000" }
    refute_nil bohu, "the consonantal skeleton finds the pointed headword — the both-sides fold"
    resolved = bohu.citations.to_h { |c| [c.label, c.resolved_urn] }
    assert_equal "urn:nabu:oshb:gen:1.2", resolved.fetch("Gen 1:2 w7"),
                 "Gen 1 is in the oshb fixture — a live verse-grain hit"
    assert_nil resolved.fetch("Isa 34:11 w19"), "Isaiah is not in the catalog — honest book miss"
    assert_nil resolved.fetch("Jer 4:23 w9"),
               "Jeremiah IS held but the fixture carries only chapter 10 — honest verse-grain miss"

    kinah = define.run("כנעה").find { |r| r.urn == "urn:nabu:dict:sdbh:003359000000000" }
    assert_equal ["urn:nabu:oshb:jer:10.17"], kinah.citations.map(&:resolved_urn),
                 "Jer 10:17 resolves — the second held book"
  end

  # --- registry ---------------------------------------------------------------

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["sdbh"]
    refute_nil entry, "config/sources.yml must register sdbh"
    assert_equal Nabu::Adapters::Sdbh, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first real sync (37 MB fetch)"
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::Sdbh.manifest, entry.manifest
  end
end
