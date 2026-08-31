# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# SEAL adapter tests (P89-3): Sources of Early Akkadian Literature
# (seal.huji.ac.il) under the research_private posture — Prof. Nathan
# Wasserman's personal-research grant (by email, 2026-08-30): local
# machine only, NO redistribution/mirroring/derivative publication. The
# fixture bytes therefore live under the gitignored local/fixtures/seal/
# (the corpus-oudnederlands/freising mold) and every data-bearing case SKIPs
# when they are absent — CI and other users pass without the bytes, the
# owner's local suite tests against reality.
#
# Fixture ground truth (retrieved 2026-08-30, see local/fixtures/seal/
# README.md): node-1526 (Gilg. OB Harmal 1 — the _ts_tb TABLE shape, 17
# lines obv. 1–9 / rev. 10–17), node-1830 (Gilg. OB II — table shape at
# scale, 218 lines over col. i–vi with "123–127 Lost." gap rows), node-31252
# (Gilg. OB RA 113 — the PARAGRAPH shape: <p> lines with ʹ-primed labels
# restarting per column, "1ʹ–4ʹ traces" range notes). One brief-vs-bytes
# correction recorded honestly: the packet brief placed "ši-ta-am" on line
# 3; the fixture carries it on obv. 2 (line 3 opens "⌈ib⌉-ri šu-tam…") —
# tests follow the bytes.
class SealTest < Minitest::Test
  include AdapterConformance

  SLUG = "seal"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  NODES = %w[node-1526 node-1830 node-31252].freeze

  def teardown
    FileUtils.remove_entry(@staged_workdir) if @staged_workdir
    super
  end

  # --- conformance hooks (data-bearing → skip when local fixtures absent) ----

  def conformance_adapter
    Nabu::Adapters::Seal.new(delay: 0)
  end

  def conformance_workdir
    staged_workdir
  end

  def conformance_expected_source_id
    SLUG
  end

  # --- manifest: the personal-research grant (runs in CI, no bytes) ----------

  def test_manifest_quotes_the_wasserman_grant_and_is_research_private
    manifest = Nabu::Adapters::Seal.manifest
    assert_equal SLUG, manifest.id
    assert_equal "research_private", manifest.license_class,
                 "local personal research only — never on a redistribution surface"
    assert_match(/Wasserman/, manifest.license, "the grantor is named")
    assert_match(/2026-08-30/, manifest.license, "the grant date is recorded")
    assert_match(/no redistribution/i, manifest.license)
    assert_match(/CC BY-NC-ND/, manifest.license)
    assert_match(/text only/i, manifest.license, "third-party visual material is excluded")
    assert_equal "seal-html", manifest.parser_family
    assert_equal "https://seal.huji.ac.il", manifest.upstream_url
  end

  def test_the_project_citation_is_the_grant_attribution_condition
    citation = Nabu::Adapters::Seal::CITATION
    assert_match(/Michael P\. Streck and Nathan Wasserman/, citation)
    assert_match(/Sources of Early Akkadian Literature/, citation)
    assert_match(%r{http://seal\.huji\.ac\.il}, citation)
    assert_equal citation, Nabu::Adapters::Seal.manifest.credit,
                 "the citation rides the credit seam so serving surfaces render it"
  end

  # --- discover: urn = the SEAL number, never the node id --------------------

  def test_discover_mints_urns_from_the_pages_own_seal_number
    ids = Nabu::Adapters::Seal.new.discover(staged_workdir).map(&:id)
    assert_equal %w[urn:nabu:seal:1526 urn:nabu:seal:1830 urn:nabu:seal:31252], ids,
                 "the SEAL no. field is the citation-stable key the grant names, sorted numerically"
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Seal.new.discover(dir).to_a
    end
  end

  def test_a_page_without_a_seal_number_is_censused_unrecognized_never_silently_minted
    require_fixtures!
    Dir.mktmpdir do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      FileUtils.cp(File.join(FIXTURES, "node-1526.html"), texts)
      # A real SEAL page with no "SEAL no." h4 (the search listing) standing
      # in a record slot — discover must not invent an identity for it.
      FileUtils.cp(File.join(FIXTURES, "search-page0.html"), File.join(texts, "node-42.html"))
      adapter = Nabu::Adapters::Seal.new
      assert_equal ["urn:nabu:seal:1526"], adapter.discover(dir).map(&:id)
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized, "a numberless page is a defect, censused prominently"
      assert(skips.notes.any? { |note| note.include?("node-42.html") }, "the census names the file")
    end
  end

  def test_discovery_skips_censuses_the_index_sidecars_by_rule
    require_fixtures!
    Dir.mktmpdir do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      FileUtils.cp(File.join(FIXTURES, "node-1526.html"), texts)
      FileUtils.cp(File.join(FIXTURES, "search-page0.html"),
                   File.join(dir, "advanced-search-page-0.html"))
      skips = Nabu::Adapters::Seal.new.discovery_skips(dir)
      assert_equal 1, skips.skipped_by_rule, "persisted search indexes are sidecars, not documents"
      assert_equal 0, skips.unrecognized
    end
  end

  # --- parse: the table shape (node 1526, Gilg. OB Harmal 1) -----------------

  def test_harmal_1_parses_to_17_lines_with_obverse_reverse_citations
    document = parse_urn("urn:nabu:seal:1526")
    assert_equal "akk", document.language
    assert_equal "Gilg. OB Harmal 1", document.title
    assert_equal 17, document.size, "the page's own line count, obv. 1–9 + rev. 10–17"
    first = document.first
    assert_equal "urn:nabu:seal:1526:1", first.urn
    assert_equal "obv. 1", first.annotations["citation"]
    assert_equal "obv.", first.annotations["section"]
    assert_includes first.text, "e-li", "the opening — ⌈e-li⌉-i-ma a-na ṣú-ri-im"
    second = document.find { |p| p.annotations["citation"] == "obv. 2" }
    assert_includes second.text, "ši-ta-am", "obv. 2: ši-ta-am ša i-li a-na-ku ek-mé-ku"
    tenth = document.find { |p| p.urn.end_with?(":10") }
    assert_equal "rev. 10", tenth.annotations["citation"],
                 "the numbering runs on across the obverse/reverse turn"
    assert_equal "rev. 17", document.to_a.last.annotations["citation"]
  end

  def test_harmal_1_metadata_carries_the_permanent_url_and_the_grant_fields
    metadata = parse_urn("urn:nabu:seal:1526").metadata
    assert_equal "https://seal.huji.ac.il/node/1526", metadata["permanent_url"],
                 "the project's own permanence promise — the scholarly-reference key"
    assert_equal "1526", metadata["seal_number"]
    assert_equal "Old Babylonian", metadata["period"]
    assert_equal "Epics, Gilgameš", metadata["genre"]
    assert_equal "Šaduppûm (mod. Tell Ḥarmal)", metadata["provenance"]
    assert_equal "Iraq Museum, Baghdad", metadata["collection"]
    assert_equal "IM 52615 (HL3 286)", metadata["tablet_siglum"]
    assert_equal "George 2003, 248–251", metadata["edition"]
    assert_equal Nabu::Adapters::Seal::CITATION, metadata["citation"],
                 "attribution on display — the grant condition rides every document"
  end

  def test_the_english_translation_rides_as_document_metadata
    metadata = parse_urn("urn:nabu:seal:1526").metadata
    assert_includes metadata["translation_en"], "Go up on to the mountain crag",
                    "the upstream Translation field, plain text — v1 keeps it document-level"
  end

  # --- parse: the table shape at scale (node 1830, Gilg. OB II) --------------

  def test_gilg_ob_ii_parses_218_lines_across_columns_with_gap_notes
    document = parse_urn("urn:nabu:seal:1830")
    assert_equal 218, document.size, "218 line rows; the 123–127/128–134 gaps are notes, not lines"
    assert_equal "col. i 1", document.first.annotations["citation"]
    assert_includes document.metadata["gap_notes"], "123–127 Lost.",
                    "the edition's lost-line ranges are censused, never silently dropped"
    assert_equal "243", document.to_a.last.annotations["line"],
                 "the edition's own continuous numbering survives the gaps"
  end

  # --- parse: the paragraph shape (node 31252, Gilg. OB RA 113) --------------

  def test_ra_113_paragraph_shape_parses_with_primed_column_citations
    document = parse_urn("urn:nabu:seal:31252")
    assert_equal 34, document.size, "14 col. i lines + 20 col. ii lines; the trace ranges are notes"
    first = document.first
    assert_equal "col. i 5ʹ", first.annotations["citation"],
                 "labels restart per column and keep the upstream prime verbatim"
    assert_includes first.text, "iš-tim"
    assert_equal ["1ʹ–4ʹ traces", "15ʹ–19ʹ traces"], document.metadata["gap_notes"]
    assert(document.each_slice(15).first.none? { |p| p.text.empty? })
  end

  # --- identity defenses -----------------------------------------------------

  # --- P89-3b: the first-sync census fixes (2026-08-30) ----------------------
  # The live crawl surfaced four page classes the Gilgamesh-corner fixtures
  # never sampled: sister series (DLL/LBPL), catalog-only entries with no
  # online transliteration, Word-export score tables, and free-form prose
  # pages. 1,011 fetched → 376 loaded, 546 quarantined; these pin the fixes.

  def test_sister_series_pages_are_censused_skips_never_unrecognized
    require_fixtures!
    Dir.mktmpdir do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      %w[node-1526 node-31727 node-36918].each do |node|
        FileUtils.cp(File.join(FIXTURES, "#{node}.html"), texts)
      end
      adapter = Nabu::Adapters::Seal.new
      assert_equal ["urn:nabu:seal:1526"], adapter.discover(dir).map(&:id),
                   "DLL/LBPL pages must not yield (the grant names SEAL)"
      skips = adapter.discovery_skips(dir)
      assert_equal 2, skips.skipped_by_rule, "the two sister-series pages skip BY RULE"
      assert_equal 0, skips.unrecognized
      assert(skips.notes.any? { |note| note.match?(/sister[- ]series/i) },
             "the census names the held-out class")
    end
  end

  def test_catalog_only_pages_are_censused_skips_never_quarantined
    require_fixtures!
    Dir.mktmpdir do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      %w[node-1526 node-1516].each { |node| FileUtils.cp(File.join(FIXTURES, "#{node}.html"), texts) }
      adapter = Nabu::Adapters::Seal.new
      assert_equal ["urn:nabu:seal:1526"], adapter.discover(dir).map(&:id),
                   "a SEAL page with no online transliteration must not reach the parser"
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.skipped_by_rule
      assert(skips.notes.any? { |note| note.match?(/no online transliteration/i) })
    end
  end

  def test_word_export_score_tables_parse_as_labeled_lines
    # node-1801 (Emar wisdom): a 3-column Word-export score — line number |
    # witness siglum | text; unnumbered witness rows continue their line.
    document = parse_fixture("node-1801")
    assert_equal 28, document.size, "28 numbered score lines"
    first = document.first
    assert_equal "l. 1", first.annotations["citation"]
    assert_match(/it-ti/, first.text)
    assert_match(/Ua/, first.text, "witness continuation rows ride the line")
  end

  def test_witness_prefixed_line_labels_parse_as_real_lines
    # node-7181 (TIM 9, 65+66): labels like "A1" — a witness letter before
    # the number, not a heading.
    document = parse_fixture("node-7181")
    assert_operator document.size, :>=, 20
    assert(document.any? { |passage| passage.annotations["citation"].match?(/\bA1\b/) },
           "the A1-labeled line is a line, not a heading")
    assert(document.any? { |passage| passage.text.include?("aṣ-ba-at") })
  end

  def test_free_form_prose_pages_fall_back_to_flagged_ordinal_lines
    # node-26977 (the diviner's ritual): 323 prose paragraphs, zero line
    # labels anywhere — the GRETIL precedent: ordinal refs, flagged.
    document = parse_fixture("node-26977")
    assert_operator document.size, :>=, 100
    assert_equal "l. p1", document.first.annotations["citation"]
    assert_match(/ordinal/, document.metadata.fetch("line_numbering"),
                 "ordinal numbering is flagged, never passed off as upstream labels")
  end

  def test_a_page_landed_under_the_wrong_node_id_quarantines
    require_fixtures!
    Dir.mktmpdir do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      path = File.join(texts, "node-9999.html")
      FileUtils.cp(File.join(FIXTURES, "node-1526.html"), path)
      ref = Nabu::DocumentRef.new(source_id: SLUG, id: "urn:nabu:seal:1526", path: path)
      error = assert_raises(Nabu::ParseError) { Nabu::Adapters::Seal.new.parse(ref) }
      assert_match(/node/, error.message, "the canonical self-link disagrees with the filename")
    end
  end

  def test_a_urn_disagreeing_with_the_pages_seal_number_quarantines
    require_fixtures!
    ref = Nabu::DocumentRef.new(source_id: SLUG, id: "urn:nabu:seal:999",
                                path: File.join(staged_workdir, "texts", "node-1526.html"))
    error = assert_raises(Nabu::ParseError) { Nabu::Adapters::Seal.new.parse(ref) }
    assert_match(/SEAL no/, error.message)
  end

  # --- fetch (WebMock only — wraps SealFetch failure; runs in CI) ------------

  def test_fetch_wraps_index_failure_in_fetch_error
    stub_request(:get, "https://seal.huji.ac.il/advanced-search?page=0").to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Seal.new(delay: 0).fetch(workdir) }
    end
  end

  # --- remote-health probe shape ---------------------------------------------

  def test_probe_heads_the_first_search_page_against_the_fetch_ledger
    assert_equal :http_zip, Nabu::Adapters::Seal.remote_probe_strategy
    targets = Nabu::Adapters::Seal.http_probe_targets
    assert_equal 1, targets.size
    assert_equal "https://seal.huji.ac.il/advanced-search?page=0", targets[0].zip_url
    assert_nil targets[0].metadata_url, "the grant lives in email, not at an endpoint"
    assert_equal Nabu::SealFetch::STATE_FILE, targets[0].state_file
  end

  # --- registry round-trip (runs in CI) --------------------------------------

  def test_registry_resolves_seal_unwired_manual_on_the_cuneiform_axis
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "seal must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Seal, entry.adapter_class
    refute entry.wired, "flips only after the owner-fired first sync + eyeball"
    assert_equal "manual", entry.sync_policy
    assert_includes entry.axes, "cuneiform"
    assert_equal Nabu::Adapters::Seal.manifest, entry.manifest
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (personal-research grant forbids redistribution — " \
         "bytes live in local/fixtures/, never in git)"
  end

  # The canonical-shaped workdir the crawl would produce: the captured node
  # pages under texts/. Staged per test from the flat fixture capture.
  def staged_workdir
    require_fixtures!
    @staged_workdir ||= Dir.mktmpdir("seal-test").tap do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      NODES.each { |node| FileUtils.cp(File.join(FIXTURES, "#{node}.html"), texts) }
    end
  end

  def parse_urn(urn)
    adapter = Nabu::Adapters::Seal.new
    ref = adapter.discover(staged_workdir).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # Stage ONE fixture page and parse it through discover (the urn comes
  # from the page's own SEAL no. — never hardcoded here).
  def parse_fixture(node)
    require_fixtures!
    Dir.mktmpdir do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      FileUtils.cp(File.join(FIXTURES, "#{node}.html"), texts)
      adapter = Nabu::Adapters::Seal.new
      refs = adapter.discover(dir).to_a
      assert_equal 1, refs.size, "expected exactly one ref from #{node}"
      return adapter.parse(refs.first)
    end
  end
end
