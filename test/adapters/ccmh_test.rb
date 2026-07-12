# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Ccmh adapter tests (P13-2 + P14-5): the Corpus Cyrillo-Methodianum
# Helsingiense (Kielipankki, CC BY 4.0) — the four gospel manuscripts as the
# corpus's own CES XML (one document per manuscript+gospel book) plus the
# three txt-only texts (Suprasliensis + the Vitae, the ccmh-txt family). The
# fixtures pin both CES sub-shapes (<ver>-wrapped vs direct seg text), the
# duplicate-id quirk (":b2" collision suffix, GRETIL precedent), marianus's
# non-canonical chapter 0, and the txt files' hyphen-split/collision/side-3
# quirks. No network: fetch runs against WebMock stubs of the seven real
# Kielipankki file URLs.
class CcmhTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("ccmh")

  BASE_URL = "https://www.kielipankki.fi/download/ccmh-src/www"

  # Manuscripts alphabetical (the MANUSCRIPTS map order), books in file
  # order — which is canonical gospel order; then the txt texts (TXT_TEXTS
  # order), appended so the P13-2 gospel documents keep their positions.
  DOC_URNS = %w[
    urn:nabu:ccmh:assemanianus:mat urn:nabu:ccmh:assemanianus:joh
    urn:nabu:ccmh:marianus:mat urn:nabu:ccmh:marianus:joh
    urn:nabu:ccmh:savvina:mat urn:nabu:ccmh:savvina:luk
    urn:nabu:ccmh:zographensis:mat
    urn:nabu:ccmh:suprasliensis
    urn:nabu:ccmh:vita-constantini
    urn:nabu:ccmh:vita-methodii
  ].freeze

  ALL_FILES = %w[
    assemanianus.xml marianus.xml savvina.xml zographensis.xml
    suprasliensis.txt vita_constantini.txt vita_methodii.txt
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Ccmh.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "ccmh"
  end

  # P14-5: ccmh-txt passages mint text_normalized from the documented
  # diplomatic line-break rejoining derivation (conventions §9, "hyphen_join"
  # annotation), recomputable from the stored passage alone; gospel (ces)
  # passages carry no hyphen_join and fall through to the identity.
  def conformance_search_source(passage)
    Nabu::Adapters::CcmhTxtParser.search_source(passage.text, passage.annotations)
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_ccmh_source
    manifest = Nabu::Adapters::Ccmh.manifest
    assert_equal "ccmh", manifest.id
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal BASE_URL, manifest.upstream_url
    assert_equal "ccmh-ces", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_manuscript_book
    refs = Nabu::Adapters::Ccmh.new.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id)
    assert(refs.all? { |r| r.source_id == "ccmh" && r.metadata["language"] == "chu" })
  end

  def test_discover_titles_join_manuscript_and_gospel
    refs = Nabu::Adapters::Ccmh.new.discover(FIXTURES).to_a
    titles = refs.to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Codex Assemanianus — Matthew", titles["urn:nabu:ccmh:assemanianus:mat"]
    assert_equal "Savvina kniga — Luke", titles["urn:nabu:ccmh:savvina:luk"]
    assert_equal "Codex Zographensis — Matthew", titles["urn:nabu:ccmh:zographensis:mat"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Ccmh.new.discover(dir).to_a
    end
  end

  # --- parse: shape A (<ver>-wrapped) -----------------------------------------

  def test_parse_round_trips_assemanianus_matthew_at_verse_grain
    document = parse_urn("urn:nabu:ccmh:assemanianus:mat")
    assert_equal "chu", document.language
    assert_equal "Codex Assemanianus — Matthew", document.title
    # The demo verse: Matthew 1:1 in the corpus's 7-bit transliteration.
    assert_equal "*k$nIg&I !rodstva !!iUxva . !sna !ddva . !sna *avra/am/l@ .",
                 document.find { |p| p.urn == "urn:nabu:ccmh:assemanianus:mat:1.1" }.text
  end

  def test_parse_concatenates_parallel_ver_elements_within_one_seg
    # The first JOH 21.25 seg holds THREE <ver> children (parallel lectionary
    # renditions, final ver-id digit 1/2/3) — one verse passage, text joined.
    document = parse_urn("urn:nabu:ccmh:assemanianus:joh")
    passage = document.find { |p| p.urn == "urn:nabu:ccmh:assemanianus:joh:21.25" }
    assert_includes passage.text, "*sOt& Ze /i ina mnoga"        # ver .1 opens
    assert_includes passage.text, "*piSem&ix six k/nig /am!n +"  # ver .3 closes
  end

  def test_parse_suffixes_duplicate_verse_ids_in_document_order
    # Upstream reality: b.JOH.21.25 appears twice with distinct text. Second
    # occurrence gets ":b2" (GRETIL collision-tolerance precedent) — never
    # merged, never quarantined.
    document = parse_urn("urn:nabu:ccmh:assemanianus:joh")
    second = document.find { |p| p.urn == "urn:nabu:ccmh:assemanianus:joh:21.25:b2" }
    assert_equal "piSem&ix k$nig$ /ami!n .:% -", second.text,
                 "the %-marked short parallel keeps its own passage (editor-flagged text kept verbatim)"
  end

  def test_parse_savvina_lectionary_chapter_starting_mid_chapter
    document = parse_urn("urn:nabu:ccmh:savvina:luk")
    first = document.first
    assert_equal "urn:nabu:ccmh:savvina:luk:1.32", first.urn,
                 "Savvina's LUK 1 opens at verse 32 — lectionary reality, no synthetic fill"
    assert_equal '(i dast& (emu !g$ !b& pr"estol& !dda !oca (ego .', first.text
  end

  # --- parse: shape B (text directly in <seg>, no <ver>) ----------------------

  def test_parse_marianus_direct_seg_text_with_whitespace_collapse
    document = parse_urn("urn:nabu:ccmh:marianus:mat")
    assert_equal "-to na tE",
                 document.find { |p| p.urn == "urn:nabu:ccmh:marianus:mat:5.23" }.text,
                 "the ms opens mid-verse — the fragment is the text, kept verbatim"
    assert_equal "ostavi tu dar& tvoi pr@d& ol&tarem& . J Sed& pr@Zde s&miri sE . " \
                 "s& bratrom& svoim& . i togda priSed& prinesi dar& tvoi ::",
                 document.find { |p| p.urn == "urn:nabu:ccmh:marianus:mat:5.24" }.text
  end

  def test_parse_marianus_chapter_zero_and_its_duplicate_heading
    # JOH "chapter 0" is the ms's chapter-heading list; b.JOH.0.14 repeats
    # with distinct headings — the :b2 suffix keeps both.
    document = parse_urn("urn:nabu:ccmh:marianus:joh")
    assert_equal "!vJ *o nix&Ze reCe ijuda ::",
                 document.find { |p| p.urn == "urn:nabu:ccmh:marianus:joh:0.14" }.text
    assert_equal "!gJ *o os$lEti ::",
                 document.find { |p| p.urn == "urn:nabu:ccmh:marianus:joh:0.14:b2" }.text
  end

  def test_parse_zographensis_book_starts_where_the_lacunose_ms_does
    document = parse_urn("urn:nabu:ccmh:zographensis:mat")
    assert_equal 7, document.size, "MAT 3.11-3.17 — the fixture chapter, one passage per verse"
    assert_equal(%w[3.11 3.12 3.13 3.14 3.15 3.16 3.17],
                 document.map { |p| p.urn.split(":").last })
    assert_equal "(J se glas& s& !nbse !glE . s$ est& !sn& moi . v&zl^jubl^en&J . " \
                 "o nem$Ze blagov[o]lix& .",
                 document.find { |p| p.urn == "urn:nabu:ccmh:zographensis:mat:3.17" }.text
  end

  # --- parse: the txt texts through the adapter (dispatch by extension) --------

  def test_parse_dispatches_suprasliensis_to_the_txt_parser_at_line_grain
    document = parse_urn("urn:nabu:ccmh:suprasliensis")
    assert_equal "Codex Suprasliensis", document.title
    assert_equal "chu", document.language
    passage = document.find { |p| p.urn == "urn:nabu:ccmh:suprasliensis:1.1.1.3" }
    assert_equal ")i do s&mr)$ti . ne dobr@ mOdrova-", passage.text,
                 "diplomatic line verbatim, hyphen included"
    assert_equal ")i do s&mr)$ti . ne dobr@ modrovati", passage.text_normalized,
                 "the split word is whole in the search form"
  end

  def test_parse_dispatches_the_vitae_at_verse_grain
    document = parse_urn("urn:nabu:ccmh:vita-constantini")
    assert_equal "Vita Constantini", document.title
    assert_equal "urn:nabu:ccmh:vita-constantini:0.0", document.first.urn,
                 "chapter 00 is the incipit"
    assert_equal 5, parse_urn("urn:nabu:ccmh:vita-methodii").size
  end

  def test_discover_txt_refs_carry_scheme_and_title_metadata
    refs = Nabu::Adapters::Ccmh.new.discover(FIXTURES).to_a
    by_id = refs.to_h { |r| [r.id, r.metadata] }
    assert_equal "folio-line", by_id["urn:nabu:ccmh:suprasliensis"]["scheme"]
    assert_equal "chapter-verse", by_id["urn:nabu:ccmh:vita-methodii"]["scheme"]
    assert_equal "Vita Methodii", by_id["urn:nabu:ccmh:vita-methodii"]["title"]
  end

  # --- search: the split-word mechanics end to end (owner req. 2026-07-12) -----

  def test_search_finds_a_word_split_across_two_lines_and_skips_the_orphan
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(
      slug: "ccmh", name: "CCMH", adapter_class: "Nabu::Adapters::Ccmh",
      license_class: "attribution"
    )
    adapter = Nabu::Adapters::Ccmh.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:ccmh:suprasliensis" }
    Nabu::Store::Loader.new(db: catalog, source: source).load([adapter.parse(ref)], full: false)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
    search = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext)

    assert_includes search.run("mOdrovati").map(&:urn), "urn:nabu:ccmh:suprasliensis:1.1.1.3",
                    "the word split as mOdrova-/ti is findable whole on the line where it starts"
    ti_hits = search.run("ti", limit: 100).map(&:urn)
    assert_includes ti_hits, "urn:nabu:ccmh:suprasliensis:1.1.1.24",
                    "the real word ti (dative pronoun) stays findable"
    refute_includes ti_hits, "urn:nabu:ccmh:suprasliensis:1.1.1.4",
                    "the orphan continuation fragment must not produce a junk hit"
  ensure
    fulltext&.disconnect
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_downloads_all_seven_files_into_per_text_subdirs
    stub_all_files
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Ccmh.new
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 7, report.repos.size, "one per-file sha pin per upstream url"
      report.repos.each_key { |url| assert_match %r{\A#{BASE_URL}/\w+\.(?:xml|txt)\z}, url }
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id),
                   "the fetched tree is discoverable in place"
      assert File.exist?(File.join(workdir, "marianus", Nabu::FileFetch::STATE_FILE)),
             "each text keeps its own FileFetch state (shared dirs would cross-doom siblings)"
      assert File.exist?(File.join(workdir, "suprasliensis", Nabu::FileFetch::STATE_FILE))
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_all_files
    stub_request(:get, "#{BASE_URL}/savvina.xml").to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Ccmh.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ------------------------------------------------

  def test_probe_targets_head_each_file_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Ccmh.remote_probe_strategy
    targets = Nabu::Adapters::Ccmh.http_probe_targets
    assert_equal 7, targets.size
    targets.each do |target|
      assert_match %r{\A#{BASE_URL}/\w+\.(?:xml|txt)\z}, target.zip_url
      assert_nil target.metadata_url, "the license lives in the bundle README, not a metadata endpoint"
      assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
    end
    assert_equal %w[assemanianus marianus savvina zographensis
                    suprasliensis vita_constantini vita_methodii], targets.map(&:state_subdir)
  end

  # --- registry round-trip -------------------------------------------------------

  def test_registry_resolves_ccmh_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ccmh"]
    refute_nil entry, "ccmh must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Ccmh, entry.adapter_class
    assert entry.enabled, "live (owner sign-off 2026-07-11 after first sync + eyeball)"
    assert_equal Nabu::Adapters::Ccmh.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Ccmh.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def stub_all_files
    ALL_FILES.each do |filename|
      stub_request(:get, "#{BASE_URL}/#{filename}").to_return(
        status: 200, body: File.read(File.join(FIXTURES, filename)),
        headers: { "Last-Modified" => "Thu, 11 Feb 2021 12:56:02 GMT" }
      )
    end
  end
end
