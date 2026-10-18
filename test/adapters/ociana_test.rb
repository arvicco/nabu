# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# OCIANA adapter tests: the Online Corpus of the Inscriptions of Ancient
# North Arabia (Khalili Research Centre, Oxford) as ONE immutable ORA
# deposit (doi 10.5287/bodleian:OBVk0AY52). No open licence — ORA's own
# Terms of Use (private study or research, non-commercial) → class
# research_private on the corpus-gysseling non-grant posture, so NO
# deposit bytes enter git: the excerpt lives under the gitignored
# local/fixtures/ociana/ and every data-bearing case SKIPs when it is
# absent (StrictSkips turns that into a failure on the owner's box).
#
# Fixture ground truth (local/fixtures/ociana/README.md, cut 2026-10-18):
# the deposit's prologue + xs:schema preamble, then 10 real records —
# JaS 2 (Safaitic, &quot; apparatus), JaS 1 (Hismaic, coordinates, &#xD;
# CRs), JaS 12 + HCH 180 (EMPTY transliterations), HCH 1 (XML-illegal
# U+000B — the recover fallback), KhU 5 (degree-minute coordinates), C 2
# (full survey metadata), JSLih 237 (Dadanitic, multi-line), JSLih 203
# (the "OCIANA_0035040JSLih 200" url id with a space), Esk. 272
# (Taymanitic, multi-line).
class OcianaTest < Minitest::Test
  include AdapterConformance

  SLUG = "ociana"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  EXCERPT = "ociana-excerpt.xml"
  URN = "urn:nabu:ociana:"

  def teardown
    FileUtils.remove_entry(@staged_workdir) if @staged_workdir
    super
  end

  # --- conformance hooks (data-bearing → skip when local fixtures absent) ----

  def conformance_adapter
    Nabu::Adapters::Ociana.new
  end

  def conformance_workdir
    staged_workdir
  end

  def conformance_expected_source_id
    SLUG
  end

  # --- manifest: the ORA terms (runs in CI, no bytes) -------------------------

  def test_manifest_is_research_private_on_the_ora_terms
    manifest = Nabu::Adapters::Ociana.manifest
    assert_equal SLUG, manifest.id
    assert_equal "research_private", manifest.license_class,
                 "no open licence — local research only, never on a redistribution surface"
    assert_match(/private study or research for non-commercial purposes/, manifest.license,
                 "the ORA Terms of Use operative clause rides verbatim")
    assert_match(%r{https://ora\.ox\.ac\.uk/terms_of_use}, manifest.license)
    assert_match(%r{10\.5287/bodleian:OBVk0AY52}, manifest.license)
    assert_match(/Cite: /, manifest.license)
    assert_equal "ociana-xml", manifest.parser_family
  end

  def test_the_citation_names_ociana_the_khalili_centre_and_the_doi
    citation = Nabu::Adapters::Ociana::CITATION
    assert_match(/Online Corpus of the Inscriptions of Ancient North Arabia/, citation)
    assert_match(/Khalili Research Centre/, citation)
    assert_match(/University of Oxford/, citation)
    assert_match(%r{10\.5287/bodleian:OBVk0AY52}, citation)
    assert_equal citation, Nabu::Adapters::Ociana.manifest.credit
  end

  def test_the_probe_heads_the_one_deposit_file_against_the_file_fetch_state
    targets = Nabu::Adapters::Ociana.http_probe_targets
    assert_equal :http_zip, Nabu::Adapters::Ociana.remote_probe_strategy
    assert_equal 1, targets.size
    assert_equal Nabu::Adapters::Ociana::FILE_URL, targets[0].zip_url
    assert_equal Nabu::FileFetch::STATE_FILE, targets[0].state_file
  end

  # --- discover: fragments cut across the preamble ----------------------------

  def test_discover_cuts_every_record_past_the_schema_preamble_and_skips_empty_transliterations
    ids = conformance_adapter.discover(staged_workdir).map(&:id)
    assert_equal %W[
      #{URN}OCIANA_0002825 #{URN}OCIANA_0002826 #{URN}OCIANA_0002854 #{URN}OCIANA_0003194
      #{URN}OCIANA_0003207 #{URN}OCIANA_0035092 #{URN}OCIANA_0035954
      #{URN}OCIANA_0035040JSLih-200 #{URN}OCIANA_0040126
    ], ids, "file order; JaS 12 + HCH 180 (empty transliterations) skip by rule; the " \
            "xs:schema preamble is never a record"
  end

  def test_the_empty_transliteration_census
    skips = conformance_adapter.discovery_skips(staged_workdir)
    assert_equal 2, skips.skipped_by_rule, "JaS 12 and the HCH 180 rock drawing carry no text"
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("2 records without a transliteration") })
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty conformance_adapter.discover(dir).to_a
    end
  end

  def test_urns_are_stable_across_two_independent_parses
    first = Nabu::Adapters::Ociana.new.discover(staged_workdir).map(&:id)
    second = Nabu::Adapters::Ociana.new.discover(staged_workdir).map(&:id)
    assert_equal first, second
  end

  # --- parse: one document, one passage per inscription -----------------------

  def test_a_safaitic_record_parses_to_one_xna_passage_with_its_metadata
    doc = parse_urn("#{URN}OCIANA_0002825")
    assert_equal "xna", doc.language, "ISO Ancient North Arabian — the bare-code claim"
    assert_equal "JaS 2", doc.title
    assert_equal 1, doc.passages.size
    passage = doc.passages.first
    assert_equal "#{URN}OCIANA_0002825:1", passage.urn
    assert_equal "l klb bn ntn bn frẖ w ʾtm ʿl- ḫr ḏ- ʾl bs¹ʾ", passage.text
    meta = doc.metadata
    assert_equal "Safaitic", meta["script"], "the script rides for the facet and the stage flip"
    assert_equal "JaS 2", meta["siglum"]
    assert_equal "SAMAS 9.83", meta["alternative_sigla"]
    assert_equal "OCIANA_0002825", meta["ociana_id"]
    assert_equal "http://krc.orient.ox.ac.uk/ociana/corpus/pages/OCIANA_0002825.html",
                 meta["permanent_url"]
    assert_equal Nabu::Adapters::Ociana::CITATION, meta["citation"]
    assert_equal "By Klb son of Ntn son of Frḫ and ʾtm ʿl ḫr of the lineage of Bs¹ʾ",
                 meta["translation_en"]
    assert_equal "No satisfatory explanation for ʾtm ʿl ḫr has yet been suggested.",
                 meta["commentary"], "verbatim — upstream's own spelling kept"
    assert_equal 2, meta["references"].size
    assert meta["references"].first.start_with?("Clark, V.A. A Study of New Safaitic")
  end

  def test_xml_entities_decode_and_text_is_kept_verbatim
    apparatus = parse_urn("#{URN}OCIANA_0002825").metadata["apparatus"]
    assert_includes apparatus, "for ʾtm ʿl ḫr \"and he came together with ḫr of the clan of bhʾ\""
    refute_includes apparatus, "&quot;"
    jas1 = parse_urn("#{URN}OCIANA_0002826").metadata
    assert jas1["apparatus"].start_with?("TEXT\nJamme 1959: l ʿrs bn t{b}tl;"),
           "the &#xD; CR entities decode to line breaks (normalized to LF)"
    assert_includes jas1["references"].last, "Notes d'épigraphie", "&apos; decodes"
  end

  def test_the_place_hash_carries_site_and_the_geo_pair
    place = parse_urn("#{URN}OCIANA_0002826").metadata["place"]
    assert_equal({ "ancient" => "Negev V 9591-2", "geo" => "30.712172, 34.874716" }, place)
    rich = parse_urn("#{URN}OCIANA_0003207").metadata
    assert_equal "Syria", rich["place"]["country"]
    assert_equal "Rif Dimašq", rich["place"]["region"]
    refute rich["place"].key?("geo"), "no coordinates → no geo pair"
    jas2 = parse_urn("#{URN}OCIANA_0002825").metadata["place"]
    assert_equal "Badana area", jas2["notes"], "provenanceNotes ride verbatim"
  end

  def test_non_decimal_coordinates_stay_raw_and_never_mint_a_geo_pair
    place = parse_urn("#{URN}OCIANA_0003194").metadata["place"]
    refute place.key?("geo"), "degree-minute strings are not a WGS84 decimal pair"
    assert_equal "33° 04', 36° 58'", place["coordinates_raw"]
  end

  def test_the_survey_fields_and_the_find_date_ride_as_metadata
    meta = parse_urn("#{URN}OCIANA_0003207").metadata
    assert_equal "1858 and 1995", meta["find_date"], "the discovery date — never a dating claim"
    assert_equal "Safaitic Epigraphic Survey Programme (SESP)", meta["survey"]
    refute_nil meta["field_collector"]
  end

  def test_multi_line_transliterations_keep_their_line_breaks
    doc = parse_urn("#{URN}OCIANA_0035092")
    assert_equal "Dadanitic", doc.metadata["script"]
    assert_equal "dws¹ \nʾs¹lm", doc.passages.first.text
    taym = parse_urn("#{URN}OCIANA_0040126")
    assert_equal "Taymanitic", taym.metadata["script"]
    assert_equal 4, taym.passages.first.text.lines.size
  end

  # The corpus holds a few non-ANA inscriptions (22 Greek, 1 Latin, 8
  # Minaic, 4 Nabataean, 1 South Arabian on the full deposit): their own
  # language code, never a false xna claim.
  def test_a_greek_script_record_is_grc_not_xna
    doc = parse_urn("#{URN}OCIANA_0035954")
    assert_equal "grc", doc.language
    assert_equal "grc", doc.passages.first.language
    assert_equal "Greek", doc.metadata["script"]
    assert_equal "ΜΝΗϹΘΗ ΝΑϹΡΙΛΟϹ ΑΛΟΥΟΥ", doc.passages.first.text
  end

  def test_the_script_language_map_covers_the_non_ana_scripts_only
    map = Nabu::Adapters::Ociana::SCRIPT_LANGUAGES
    assert_equal({ "Greek" => "grc", "Latin" => "lat", "Minaic" => "inm",
                   "South Arabian" => "xsa", "Nabataean" => "arc" }, map)
  end

  def test_the_illegal_control_char_record_recovers_inside_its_own_fragment
    doc = parse_urn("#{URN}OCIANA_0002854")
    assert doc.passages.first.text.start_with?("l hnʾ bn ʿqrb bn hnʾ bn ḥyr w h- rgm"),
           "the U+000B damage stays inside HCH 1; its text survives"
    refute_match(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, doc.passages.first.text)
  end

  def test_a_suffixed_url_id_with_a_space_mints_a_hyphenated_urn
    doc = parse_urn("#{URN}OCIANA_0035040JSLih-200")
    assert_equal "OCIANA_0035040JSLih 200", doc.metadata["ociana_id"], "the upstream id verbatim"
    assert_equal "JSLih 203", doc.title
  end

  def test_a_record_without_a_readable_url_id_quarantines
    require_fixtures!
    Dir.mktmpdir do |dir|
      bytes = File.read(File.join(FIXTURES, EXCERPT), encoding: "UTF-8")
      broken = bytes.sub("pages/OCIANA_0002825.html", "pages/broken.html")
      File.write(File.join(dir, "ociana.xml"), broken)
      adapter = Nabu::Adapters::Ociana.new
      ref = adapter.discover(dir).first
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # --- fetch (WebMock'd FileFetch, frozen sha pin) ------------------------------

  def test_fetch_lands_the_deposit_as_ociana_xml
    body = fixture_bytes
    stub_request(:get, Nabu::Adapters::Ociana::FILE_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::Ociana.new(corpus_sha256: Digest::SHA256.hexdigest(body)).fetch(dir)
      assert_equal body, File.binread(File.join(dir, "ociana.xml"))
      assert_equal Digest::SHA256.hexdigest(body), report.sha
    end
  end

  def test_fetch_aborts_on_sha_drift_with_the_tree_untouched
    stub_request(:get, Nabu::Adapters::Ociana::FILE_URL).to_return(status: 200, body: fixture_bytes)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Ociana.new.fetch(dir) }
      assert_match(/re-pin/, error.message, "drift is an owner re-pin decision, named loudly")
      refute File.exist?(File.join(dir, "ociana.xml")), "the drifted body never reaches the tree"
    end
  end

  def test_the_frozen_pin_is_the_acquisition_sha
    assert_equal "5a90c113356fac5943f34036464680f4a8651a69cb34102fed6bc54af0a3077c",
                 Nabu::Adapters::Ociana::CORPUS_SHA256
  end

  # --- registry round-trip (runs in CI) ---------------------------------------

  def test_registry_resolves_ociana_unwired_frozen_on_the_epigraphy_axis
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "ociana must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Ociana, entry.adapter_class
    refute entry.wired, "wired: false until the first real sync is verified"
    assert_equal "frozen", entry.sync_policy
    assert_includes entry.axes, "epigraphy"
    assert_equal Nabu::Adapters::Ociana.manifest, entry.manifest
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (ORA terms: private study/research — bytes live in " \
         "local/fixtures/, never in git)"
  end

  def fixture_bytes
    require_fixtures!
    File.binread(File.join(FIXTURES, EXCERPT))
  end

  # The canonical-shaped workdir the fetch produces: the deposit as
  # ociana.xml at the workdir root.
  def staged_workdir
    require_fixtures!
    @staged_workdir ||= Dir.mktmpdir("ociana-test").tap do |dir|
      FileUtils.cp(File.join(FIXTURES, EXCERPT), File.join(dir, "ociana.xml"))
    end
  end

  def parse_urn(urn)
    adapter = Nabu::Adapters::Ociana.new
    ref = adapter.discover(staged_workdir).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end
end
