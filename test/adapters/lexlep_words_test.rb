# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The lexlep-words adapter (P29-3): LexLep's Word pages as the Lepontic /
# Cisalpine Gaulish dictionary shelf. Dictionary-shaped, so it cannot
# include the passage-shaped AdapterConformance suite; like CclTest /
# LexicaTest it mirrors those checks for the dictionary shape (manifest
# validity, discover→parse round-trip, id uniqueness/stability, NFC,
# license class) and adds the DictionaryLoader idempotency contract and
# the registry pins. Fixtures = real api.php page envelopes, 2026-07-18.
class LexlepWordsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("lexlep-words")

  def adapter = Nabu::Adapters::LexlepWords.new(delay: 0)

  # --- manifest (the conformance mirror) ------------------------------------

  def test_shelf_cover_language_is_xlp_never_lepcha
    # Review pin (P29-3 merge): the shelf covers Lexicon Leponticum —
    # cover language xlp (Lepontic), NOT "lep" (Lepcha, the spec slip).
    assert_equal "xlp", Nabu::Adapters::LexlepWords::LANGUAGE
  end

  def test_manifest_is_valid_and_holds_the_shared_nc_posture
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "lexlep-words", manifest.id
    assert_includes Nabu::SourceManifest::LICENSE_CLASSES, manifest.license_class
    assert_equal "nc", manifest.license_class
    assert_equal Nabu::Adapters::Lexlep::MANIFEST.license, manifest.license,
                 "one wiki, one license posture — the quote is shared verbatim"
    assert_equal "wiki-template", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::LexlepWords.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------

  def test_discover_yields_one_ref_per_word_page_with_stable_ids
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[a? acisius aes aesia esopnos kasios tati tekialui].map { |t| "lexlep-words:#{t}" },
                 refs.map(&:id)
    refs.each { |ref| assert_equal "lexlep-words", ref.source_id }
    assert_equal refs.map(&:id), adapter.discover(FIXTURES).map(&:id),
                 "ids are stable across independent discoveries"
  end

  def test_parse_yields_one_nfc_entry_per_page
    adapter.discover(FIXTURES).each do |ref|
      document = adapter.parse(ref)
      assert_kind_of Nabu::DictionaryDocument, document
      assert_equal "lexlep-words", document.slug
      assert_equal 1, document.size
      document.each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
        refute_empty entry.body
      end
    end
  end

  def test_aes_entry_carries_grammar_gloss_and_the_etymology_commentary
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "lexlep-words:aes" }
    entry = adapter.parse(ref).first
    assert_equal "aes", entry.entry_id
    assert_equal "cel", entry.language, "the page's own language param (Celtic) is the entry grain"
    assert_equal "abbreviation of a name \"Aes...\"", entry.gloss
    assert_includes entry.body, "proper noun"
    assert_includes entry.body, "semantic field: personal name"
    assert_includes entry.body, "Lejeune 1971: 126", "the scrubbed Commentary rides in the body"
    assert_includes entry.body, "Phonemic analysis: aes"
  end

  def test_acisius_maps_cisalpine_gaulish_and_flattens_the_analyses
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "lexlep-words:acisius" }
    entry = adapter.parse(ref).first
    assert_equal "xcg", entry.language
    assert_includes entry.body, "Language: Cisalpine Gaulish (adapted from Latin)"
    assert_includes entry.body, "Morphemic analysis: akis-i̯us".unicode_normalize(:nfc)
  end

  def test_marker_bearing_titles_stay_verbatim_with_a_usable_fold
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "lexlep-words:a?" }
    entry = adapter.parse(ref).first
    assert_equal "a?", entry.headword, "Leiden markers are part of the attested form — verbatim"
    assert_equal "und", entry.language
    refute_empty entry.headword_folded
  end

  # --- DictionaryLoader contract --------------------------------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "lexlep-words", name: "LexLep words", adapter_class: "Nabu::Adapters::LexlepWords",
      license: "nc-conservative", license_class: "nc",
      upstream_url: "https://lexlep.univie.ac.at", enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 8, first.added
    assert_equal 0, first.errored
    citations = db[:dictionary_citations].count

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 8, second.skipped
    assert_equal 8, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
    assert_equal citations, db[:dictionary_citations].count, "the AcS citation rows are stable across loads"

    aes = db[:dictionary_entries].where(entry_id: "aes").first
    assert_equal "urn:nabu:dict:lexlep-words:aes", aes[:urn]
  end

  # --- Holder "AcS" citations (Q280a) -----------------------------------------

  def citation_labels(title)
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "lexlep-words:#{title}" }
    adapter.parse(ref).first.citations.map(&:label)
  end

  # Holder's Alt-celtischer Sprachschatz, cited in the Commentary prose as
  # "{{bib|AcS}} <vol>: <col>". One citation per cited locus — a locus
  # list ("I: 282, 832 f.") mints each column under the running volume, a
  # range anchors at its first column; the label is the scan-anchor key
  # ("AcS I: 282", roman volume upper-cased).
  def test_acs_locus_lists_mint_one_citation_per_column_under_the_running_volume
    assert_equal ["AcS I: 282", "AcS I: 832"], citation_labels("kasios")
    assert_equal ["AcS I: 1247", "AcS II: 1779", "AcS II: 1788"], citation_labels("tekialui"),
                 "a volume switch inside the list carries over to the bare columns after it"
  end

  # Upstream's spelling variance: the colon-less "I 53" with a bold-wrapped
  # second locus ('''III 516'''), and a lower-case volume ("ii: 1751").
  def test_acs_variant_spellings_normalize
    assert_equal ["AcS I: 53", "AcS III: 516"], citation_labels("aesia")
    assert_equal ["AcS II: 1723", "AcS II: 1751"], citation_labels("tati")
  end

  # "AcS: 1489 f." names no volume — the citation stands (its label says
  # so) but no volume is guessed, so no scan anchor claims it.
  def test_a_volumeless_acs_citation_mints_without_a_guessed_volume
    assert_equal ["AcS: 1489"], citation_labels("esopnos")
  end

  def test_the_acs_citation_keeps_the_cited_locus_verbatim
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "lexlep-words:tekialui" }
    citation = adapter.parse(ref).first.citations.first
    assert_equal "AcS I: 1247–1250", citation.urn_raw
    assert_nil citation.cts_work
    assert_equal "I: 1247", citation.citation
  end

  def test_pages_without_acs_carry_no_citations
    %w[aes acisius].each { |title| assert_empty citation_labels(title), title }
  end

  # The define bridge end to end: the mined label resolves through the
  # shipped config/scan_anchors.yml column row to the Bd. II scan leaf.
  def test_acs_citations_resolve_to_the_holder_scan_leaf
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    library = Nabu::Store::Source.create(slug: "local-library", name: "Library",
                                         adapter_class: "Nabu::Adapters::LocalLibrary",
                                         license_class: "research_private")
    item = "urn:nabu:local-library:dictionaries:bub-gb-62g9aaaayaaj"
    doc = Nabu::Store::Document.create(source_id: library.id, urn: item, title: "Holder II", language: "deu",
                                       content_sha256: "x", revision: 1, withdrawn: false)
    Nabu::Store::Passage.create(document_id: doc.id, urn: "#{item}:p1007", sequence: 1007, language: "deu",
                                text: "1779", text_normalized: "1779", content_sha256: "x", revision: 1)
    table = Nabu::Query::ScanAnchors.load(File.expand_path("../../config/scan_anchors.yml", __dir__))
    result = Nabu::Query::Define.new(catalog: db, lects: nil, scan_anchors: table)
                                .by_urn("urn:nabu:dict:lexlep-words:tekialui")
    scans = result.citations.to_h { |citation| [citation.label, citation.scan] }
    assert_equal [:anchored, "#{item}:p1007"], [scans["AcS II: 1779"].status, scans["AcS II: 1779"].urn]
    assert_equal :not_held, scans["AcS I: 1247"].status,
                 "Bd. I is configured (the BSB scan landed on the owner's shelf) but this catalog does not hold it"
  end

  def test_acs_volume_one_resolves_when_its_scan_is_held
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    library = Nabu::Store::Source.create(slug: "local-library", name: "Local library",
                                         adapter_class: "Nabu::Adapters::LocalLibrary",
                                         license_class: "research_private")
    item = "urn:nabu:local-library:dictionaries:bsb10931773"
    doc = Nabu::Store::Document.create(source_id: library.id, urn: item, title: "Holder I", language: "deu",
                                       content_sha256: "x", revision: 1, withdrawn: false)
    # col 1247 → leaf ceil(1247/2) + 20 (the from_column 381 break) = 644
    Nabu::Store::Passage.create(document_id: doc.id, urn: "#{item}:p644", sequence: 644, language: "deu",
                                text: "1247", text_normalized: "1247", content_sha256: "x", revision: 1)
    table = Nabu::Query::ScanAnchors.load(File.expand_path("../../config/scan_anchors.yml", __dir__))
    result = Nabu::Query::Define.new(catalog: db, lects: nil, scan_anchors: table)
                                .by_urn("urn:nabu:dict:lexlep-words:tekialui")
    scans = result.citations.to_h { |citation| [citation.label, citation.scan] }
    assert_equal [:anchored, "#{item}:p644"], [scans["AcS I: 1247"].status, scans["AcS I: 1247"].urn]
  end

  # --- fetch (WebMock; Word category only) ----------------------------------

  def test_fetch_crawls_only_the_word_category
    api = "https://lexlep.univie.ac.at/api.php"
    stub_request(:get, api)
      .with(query: hash_including("generator" => "categorymembers"))
      .to_return(status: 200, body: JSON.generate(
        { "query" => { "pages" => { "1" => { "pageid" => 1, "ns" => 0, "title" => "aes",
                                             "lastrevid" => 7 } } } }
      ))
    stub_request(:get, api)
      .with(query: hash_including("prop" => "revisions"))
      .to_return(status: 200, body: JSON.generate(
        { "query" => { "pages" => { "1" => {
          "pageid" => 1, "ns" => 0, "title" => "aes",
          "revisions" => [{ "revid" => 7, "timestamp" => "2026-07-18T12:00:00Z",
                            "slots" => { "main" => { "*" => "{{word\n|meaning=x\n}}" } } }]
        } } } }
      ))

    Dir.mktmpdir do |dir|
      adapter.fetch(dir)
      assert File.file?(File.join(dir, "pages", "Word", "aes.json"))
      assert_requested :get, api, query: hash_including("gcmtitle" => "Category:Word"), times: 1
      assert_not_requested :get, api, query: hash_including("gcmtitle" => "Category:Inscription")
    end
  end

  # --- registry --------------------------------------------------------------

  def test_registry_rows_exist_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    { "lexlep" => Nabu::Adapters::Lexlep, "lexlep-words" => Nabu::Adapters::LexlepWords,
      "tir" => Nabu::Adapters::Tir }.each do |slug, adapter_class|
      entry = registry[slug]
      refute_nil entry, "config/sources.yml must register #{slug}"
      assert_equal adapter_class, entry.adapter_class
      assert entry.wired, "#{slug}: live (owner order 2026-07-18: all pre-P30 sources flipped)"
      assert_equal "manual", entry.sync_policy
    end
  end
end
