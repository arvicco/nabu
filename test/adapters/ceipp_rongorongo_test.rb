# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# CEIPP rongorongo adapter tests: the Barthel numbering of the rongorongo
# corpus as edited by the C.E.I.P.P. (Cercle d'Études sur l'Île de Pâques
# et la Polynésie), in P. Spaelti's corpus XML on kohaumotu.org. Held under
# a codes-only, attributed, non-commercial license grant (class nc) — the
# site's own materials are "as far as I know under copyright", so NO bytes
# enter git: the cut lives under the gitignored
# local/fixtures/ceipp-rongorongo/ and every data-bearing case SKIPs when it
# is absent (StrictSkips turns that into a failure on the owner's box).
#
# Fixture ground truth (local/fixtures/ceipp-rongorongo/README.md, cut
# 2026-11-21): corpus.xml cut at the byte level to tablets D (Échancrée,
# 14 lines, the Da08 illegible-run estimate), J (Reimiro 1, two glyphs),
# W (Honolulu 4, illegible slots only) and Y (Snuff Box, five sides, the
# c side "Side c/d", breakage links); tablets.html whole (A–Z, 26 rows —
# Z Poike carries no transliteration upstream); rejected/J.xml, a
# per-tablet XML twin (the rejected grain).
class CeippRongorongoTest < Minitest::Test
  include AdapterConformance

  SLUG = "ceipp-rongorongo"
  ADAPTER = Nabu::Adapters::CeippRongorongo
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  URN = "urn:nabu:ceipp-rongorongo:"

  def teardown
    FileUtils.remove_entry(@staged_workdir) if @staged_workdir
    super
  end

  # --- conformance hooks (data-bearing → skip when local fixtures absent) ----

  def conformance_adapter
    ADAPTER.new
  end

  def conformance_workdir
    staged_workdir
  end

  def conformance_expected_source_id
    SLUG
  end

  # --- manifest: the grant's terms (runs in CI, no bytes) --------------------

  def test_manifest_is_nc_on_the_codes_only_attributed_terms
    manifest = ADAPTER.manifest
    assert_equal SLUG, manifest.id
    assert_equal "nc", manifest.license_class, "attributed, non-commercial — never redistributed"
    assert_match(/codes only/i, manifest.license)
    assert_match(/never the (?:glyph )?tracings/i, manifest.license, "the grant's scope: no images")
    assert_match(/non-commercial/i, manifest.license)
    assert_match(/observe the usual rules of attribution/, manifest.license,
                 "upstream's own copyright notice rides verbatim")
    refute_match(/\b20\d\d-\d\d-\d\d\b|by e-?mail|personal(?:ly)?[\s-](?:research[\s-])?grant/i,
                 manifest.license, "terms + credit only — never the grant's date, channel or arrangement")
    assert_equal "ceipp-xml", manifest.parser_family
    assert_equal "http://kohaumotu.org/Rongorongo/", manifest.upstream_url
  end

  def test_the_credit_names_the_ceipp_corpus_kohaumotu_and_the_xml_author
    credit = ADAPTER::CREDIT
    assert_match(/C\.E\.I\.P\.P\./, credit)
    assert_match(/Cercle d'Études sur l'Île de Pâques et la Polynésie/, credit)
    assert_match(/Barthel/, credit)
    assert_match(/Spaelti/, credit, "the header's own 'XML format by p.spaelti'")
    assert_match(/kohaumotu\.org/, credit)
    assert_equal credit, ADAPTER.manifest.credit, "the credit seam renders it on every passage"
  end

  def test_the_probe_heads_both_files_against_their_file_fetch_state
    targets = ADAPTER.http_probe_targets
    assert_equal :http_zip, ADAPTER.remote_probe_strategy
    assert_equal ["http://kohaumotu.org/Rongorongo/xml/corpus.xml", "http://kohaumotu.org/Rongorongo/tablets.html"],
                 targets.map(&:zip_url), "plain http — the host's TLS certificate expired 2018-06-27"
    assert_equal %w[corpus tablets], targets.map(&:state_subdir)
    assert(targets.all? { |target| target.state_file == Nabu::FileFetch::STATE_FILE })
  end

  # --- discover ----------------------------------------------------------------

  def test_discover_yields_one_document_per_tablet_by_barthel_siglum_in_corpus_order
    ids = ADAPTER.new.discover(staged_workdir).map(&:id)
    assert_equal %W[#{URN}D #{URN}J #{URN}W #{URN}Y], ids
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty ADAPTER.new.discover(dir).to_a
      assert_equal 0, ADAPTER.new.discovery_skips(dir).unrecognized
    end
  end

  def test_discovery_census_reports_the_image_only_slots_and_the_table_residue
    skips = ADAPTER.new.discovery_skips(staged_workdir)
    assert_equal 0, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("84 image-only glyph slots") },
           "the tracing-only slots are dropped by the grant's scope, counted: #{skips.notes.inspect}")
    assert(skips.notes.any? { |note| note.include?("Z (Poike)") },
           "the object table's rows with no transliteration are named: #{skips.notes.inspect}")
  end

  def test_a_per_tablet_xml_twin_in_the_workdir_is_skipped_by_rule
    dir = staged_workdir
    FileUtils.cp(File.join(FIXTURES, "rejected", "J.xml"), File.join(dir, "J.xml"))
    adapter = ADAPTER.new
    assert_equal %W[#{URN}D #{URN}J #{URN}W #{URN}Y], adapter.discover(dir).map(&:id),
                 "the twin never becomes a document — the corpus file is the versioned whole"
    skips = adapter.discovery_skips(dir)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("J.xml") && note.include?("twin") }, skips.notes.inspect)
  end

  def test_an_unknown_file_in_the_workdir_is_unrecognized
    dir = staged_workdir
    File.write(File.join(dir, "stray.txt"), "x")
    skips = ADAPTER.new.discovery_skips(dir)
    assert_equal 1, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("stray.txt") })
  end

  def test_a_tablet_without_a_siglum_is_unrecognized_never_minted_from_its_position
    dir = staged_workdir
    path = File.join(dir, "corpus", "corpus.xml")
    File.write(path, File.read(path).sub("<tablet-code>W</tablet-code>", "<tablet-code></tablet-code>"))
    adapter = ADAPTER.new
    assert_equal %W[#{URN}D #{URN}J #{URN}Y], adapter.discover(dir).map(&:id)
    skips = adapter.discovery_skips(dir)
    assert_equal 1, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("tablet 3") }, skips.notes.inspect)
  end

  # --- parse: tablet D (Échancrée) ---------------------------------------------

  def test_tablet_d_parses_to_its_fourteen_lines_on_two_sides
    document = parse_urn("#{URN}D")
    assert_equal "rap", document.language
    assert_equal "Échancrée (D)", document.title
    assert_equal 14, document.size
    assert_equal((1..8).map { |n| "Da0#{n}" } + (1..6).map { |n| "Db0#{n}" },
                 document.map { |passage| passage.annotations["citation"] })
    first = document.first
    assert_equal "#{URN}D:Da01", first.urn
    assert_equal "a", first.annotations["side"]
    assert_equal "Side a", first.annotations["side_name"]
    assert_equal 1, first.annotations["line"]
    last = document.to_a.last
    assert_equal "#{URN}D:Db06", last.urn
    assert_equal "244?-006-009-044-608V-006-007-600-007-680-200-093f-009:042-041*", last.text
  end

  def test_a_line_is_the_sites_own_codes_only_rendering
    document = parse_urn("#{URN}D")
    da01 = document.first
    assert_equal "______000!-006-381-700-208-007y-007-000!-207-063y.207-734-204:042-005f-522f-522_*", da01.text,
                 "every glyph's code then its link, image-only slots contributing their link alone " \
                 "(corpus_codes_html.xsl)"
    da08 = document.find { |passage| passage.annotations["citation"] == "Da08" }
    assert_equal "(10-20)!___*", da08.text, "the worn-run estimate kept verbatim"
  end

  def test_tokens_carry_each_coded_glyph_with_its_link_and_location
    document = parse_urn("#{URN}D")
    tokens = document.first.annotations["tokens"]
    assert_equal 23, tokens.size, "Da01: 26 slots, 23 coded — the 3 image-only slots carry no token"
    assert_equal({ "form" => "_", "link" => "", "loc" => "01.01" }, tokens.first)
    assert_includes tokens, { "form" => "204:042", "link" => "-", "loc" => "02.04" }
    assert_equal 3, document.first.annotations["image_only_slots"]
  end

  def test_document_metadata_joins_the_object_table_and_the_corpus_header
    meta = parse_urn("#{URN}D").metadata
    assert_equal "D", meta["siglum"]
    assert_equal "Échancrée", meta["name"]
    assert_equal [{ "code" => "a", "name" => "Side a", "lines" => 8 },
                  { "code" => "b", "name" => "Side b", "lines" => 6 }], meta["sides"]
    assert_equal 333, meta["glyph_slots"]
    assert_equal 283, meta["coded_glyphs"]
    assert_equal 50, meta["image_only_slots"]
    assert_equal "Podocarpus sp. cf Latifolia", meta["material"]
    assert_match(/Orliac \(2010\)/, meta["material_note"])
    assert_equal({ "length" => "241", "width" => "121", "thickness" => "26" }, meta["dimensions"])
    assert_equal "7+6", meta["lines_stated"], "upstream's own table figure, verbatim — never reconciled"
    assert_equal "270", meta["signs_stated"]
    assert_equal "Good", meta["condition"]
    assert_equal "http://kohaumotu.org/Rongorongo/D/index.html", meta["page_url"]
    assert_equal "1.0.1", meta["database_version"]
    assert_equal "2011-12-14", meta["database_created"]
    assert_equal ADAPTER::CREDIT, meta["citation"]
  end

  # --- parse: the small and damaged objects ---------------------------------------

  def test_reimiro_1_is_one_line_of_two_glyphs_and_na_dimensions_are_omitted
    document = parse_urn("#{URN}J")
    assert_equal 1, document.size
    assert_equal "522.088*", document.first.text
    assert_equal({ "length" => "700" }, document.metadata["dimensions"])
    assert_nil document.metadata["material_note"], "J's material carries no footnote"
    assert_equal "unidentified", document.metadata["material"]
  end

  def test_honolulu_4_keeps_its_illegible_slots_verbatim
    document = parse_urn("#{URN}W")
    assert_equal %w[_ _______ ___ _____], document.map(&:text), "never cleaned into silence"
    assert_equal "Honolulu 4 [#445]", document.metadata["catalogue_name"],
                 "the object table's name differs from the corpus's — kept beside it"
  end

  def test_the_snuff_box_keeps_its_five_sides_and_breakage_links
    document = parse_urn("#{URN}Y")
    assert_equal 13, document.size
    assert_equal(%w[a b c e f], document.metadata["sides"].map { |side| side["code"] })
    yc01 = document.find { |passage| passage.annotations["citation"] == "Yc01" }
    assert_equal "Side c/d", yc01.annotations["side_name"]
    assert_equal "…035?-386.009-014-025-007-380.001…", document.first.text
  end

  def test_no_image_reference_reaches_the_catalog
    %w[D J W Y].each do |siglum|
      document = parse_urn("#{URN}#{siglum}")
      blob = [document.metadata, document.map { |passage| [passage.text, passage.annotations] }].to_s
      refute_match(/\.png|\.svg|image_file|image_pos/i, blob, "#{siglum}: codes only — never the tracings")
    end
  end

  def test_a_missing_object_table_is_a_broken_fetch_never_a_silent_join
    dir = staged_workdir
    FileUtils.rm_rf(File.join(dir, "tablets"))
    adapter = ADAPTER.new
    ref = adapter.discover(dir).first
    error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    assert_match(/tablets\.html/, error.message)
  end

  # --- fetch (WebMock'd FileFetch pair, sha pins) --------------------------------

  def test_fetch_lands_the_corpus_and_the_object_table_in_their_subdirs
    corpus = fixture_bytes("corpus.xml")
    table = fixture_bytes("tablets.html")
    stub_request(:get, ADAPTER::CORPUS_URL).to_return(status: 200, body: corpus)
    stub_request(:get, ADAPTER::TABLETS_URL).to_return(status: 200, body: table)
    Dir.mktmpdir do |dir|
      adapter = ADAPTER.new(pins: { "corpus" => Digest::SHA256.hexdigest(corpus),
                                    "tablets" => Digest::SHA256.hexdigest(table) })
      report = adapter.fetch(dir)
      assert_equal corpus, File.binread(File.join(dir, "corpus", "corpus.xml"))
      assert_equal table, File.binread(File.join(dir, "tablets", "tablets.html"))
      assert_equal Digest::SHA256.hexdigest(corpus), report.sha
      assert_equal 4, adapter.discover(dir).count
    end
  end

  def test_fetch_aborts_on_sha_drift_with_the_tree_untouched
    stub_request(:get, ADAPTER::CORPUS_URL).to_return(status: 200, body: fixture_bytes("corpus.xml"))
    stub_request(:get, ADAPTER::TABLETS_URL).to_return(status: 200, body: fixture_bytes("tablets.html"))
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(dir) }
      assert_match(/re-pin/, error.message, "drift is an owner re-pin decision, named loudly")
      refute File.exist?(File.join(dir, "corpus", "corpus.xml")), "the drifted body never reaches the tree"
    end
  end

  def test_the_pins_are_the_acquisition_shas
    assert_equal "4aee2361a367fbed5ffba0b77c50e0ef3c055a35ee2499f66a757a903e61e627", ADAPTER::PINS.fetch("corpus")
    assert_equal "87a3273e1b2d9b488d808bf5e8a49db0dac97f518ccc21bb0dad2e83b4b3dabd", ADAPTER::PINS.fetch("tablets")
  end

  # --- registry round-trip (runs in CI) -------------------------------------------

  def test_registry_resolves_the_source_unwired_manual_and_grant_gated
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "#{SLUG} must be registered in config/sources.yml"
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "wired: false until the first real sync is verified"
    assert_equal "manual", entry.sync_policy
    assert_includes entry.axes, "epigraphy"
    assert_predicate entry, :grant_required?, "the fetch right is a grant, not a public license"
    assert_equal ADAPTER.manifest, entry.manifest
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (codes-only nc grant — bytes live in local/fixtures/, " \
         "never in git)"
  end

  def fixture_bytes(name)
    require_fixtures!
    File.binread(File.join(FIXTURES, name))
  end

  # The canonical-shaped workdir the fetch produces: corpus/corpus.xml and
  # tablets/tablets.html, one FileFetch subdirectory each.
  def staged_workdir
    require_fixtures!
    @staged_workdir ||= Dir.mktmpdir("ceipp-rongorongo-test").tap do |dir|
      { "corpus" => "corpus.xml", "tablets" => "tablets.html" }.each do |subdir, name|
        FileUtils.mkdir_p(File.join(dir, subdir))
        FileUtils.cp(File.join(FIXTURES, name), File.join(dir, subdir, name))
      end
    end
  end

  def parse_urn(urn)
    adapter = ADAPTER.new
    ref = adapter.discover(staged_workdir).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end
end
