# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# ReN adapter tests (P46-5): the Reference Corpus of Middle Low German /
# Low Rhenish (1200–1650), v1.1 TEI from fdr.uni-hamburg.de record 9195,
# CC BY 4.0 — the second cora-tei registrant (the ReM mold with the ReN
# dialect parser). Fixtures are two whole deposit members + three
# structural trims (test/fixtures/ren/README.md); fetch runs against a
# WebMock stub of the deposit artifact URL with the sha pin overridden to
# the stub zip's own sha (the rem/iecor drill).
class RenTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("ren")

  ZIP_URL = "https://www.fdr.uni-hamburg.de/record/9195/files/tei_1.1.zip?download=1"

  DOC_URNS = %w[
    urn:nabu:ren:brs-alt-degb-altst-i
    urn:nabu:ren:dub-uk-1301-1350
    urn:nabu:ren:hamb-uk-1301-1350
    urn:nabu:ren:lub-uk-1351-1400
    urn:nabu:ren:reval-schragen-1351-1500
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Ren.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "ren"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_ren_source
    manifest = Nabu::Adapters::Ren.manifest
    assert_equal "ren", manifest.id
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(%r{10\.25592/uhhfdm\.9195}, manifest.license,
                 "no in-file licence exists — the deposit record + DOI are the license basis")
    assert_equal "attribution", manifest.license_class
    assert_equal "https://www.fdr.uni-hamburg.de/record/9195", manifest.upstream_url
    assert_equal "cora-tei", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_text_file_with_ascii_slugs
    refs = Nabu::Adapters::Ren.new.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id),
                 "the filename sigle slugifies rundata-style (Ält→alt, Lüb→lub), sorted"
    assert(refs.all? { |r| r.source_id == "ren" && r.metadata["language"] == "gml" })
  end

  def test_discover_reads_the_layer_from_the_deposit_subdirectory
    layers = Nabu::Adapters::Ren.new.discover(FIXTURES).to_h { |r| [r.id, r.metadata["layer"]] }
    assert_equal "annotated", layers["urn:nabu:ren:hamb-uk-1301-1350"]
    assert_equal "transcribed", layers["urn:nabu:ren:dub-uk-1301-1350"]
  end

  def test_discover_titles_read_the_sigle_underscores_as_spaces
    titles = Nabu::Adapters::Ren.new.discover(FIXTURES).to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Hamb. Uk. 1301-1350", titles["urn:nabu:ren:hamb-uk-1301-1350"],
                 "exactly the CorA-XML header's own name field (censused)"
    assert_equal "Brs. Ält. DegB Altst. I", titles["urn:nabu:ren:brs-alt-degb-altst-i"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Ren.new.discover(dir).to_a
    end
  end

  # --- parse ------------------------------------------------------------------

  def test_passages_are_manuscript_lines_cited_page_dot_line
    document = parse_urn("urn:nabu:ren:hamb-uk-1301-1350")
    assert_equal "gml", document.language
    assert_equal %w[1.01 1.02 1.03], document.first(3).map { |p| p.urn.split(":").last },
                 "pb @n + upstream's zero-padded lb @n, verbatim"
    assert_equal 15, document.size
  end

  def test_passage_text_is_the_diplomatic_layer_nfc_byte_pinned
    document = parse_urn("urn:nabu:ren:hamb-uk-1301-1350")
    line = document.find { |p| p.urn.end_with?(":1.01") }
    # NFC byte pin: ghoͤnen is o + U+0364 COMBINING LATIN SMALL LETTER E
    # (no precomposition exists, so NFC keeps the mark) — canonical means
    # canonical, the diplomatic transcription is the witness.
    assert_includes line.text, "ghoͤnen"
    assert line.text.unicode_normalized?(:nfc)
  end

  def test_gold_pos_msd_lemma_ride_in_token_annotations
    line = parse_urn("urn:nabu:ren:hamb-uk-1301-1350").find { |p| p.urn.end_with?(":1.01") }
    den = line.annotations["tokens"].find { |t| t["id"] == "t5_m1" }
    assert_equal({ "id" => "t5_m1", "form" => "den", "pos" => "DDARTA<DD",
                   "msd" => "_.Dat.Pl", "lemma" => "dê¹,dê¹,dat²A" }, den)
  end

  def test_transcribed_texts_parse_with_honestly_bare_tokens
    document = parse_urn("urn:nabu:ren:dub-uk-1301-1350")
    tokens = document.first.annotations["tokens"]
    assert_equal({ "id" => "t1_m1", "form" => "Allen" }, tokens.first)
    refute(document.flat_map { |p| p.annotations["tokens"] }.any? { |t| t.key?("lemma") },
           "the 74 trans/ texts carry no annotation layer — no invented lemmas")
  end

  def test_column_broken_pages_cite_page_column_line
    refs = parse_urn("urn:nabu:ren:brs-alt-degb-altst-i").map { |p| p.urn.split(":").last }
    assert_includes refs, "1ra.01"
    assert_includes refs, "1rb.01",
                    "two-column pages cite page+column (the ReM 5ra/5rb rule verbatim)"
    refute_includes refs, "1r.01", "the bare page ref would collide between the columns"
    assert_equal refs.size, refs.uniq.size
  end

  def test_charter_collection_restarts_take_the_positional_disambiguator
    document = parse_urn("urn:nabu:ren:lub-uk-1351-1400")
    refs = document.map { |p| p.urn.split("urn:nabu:ren:lub-uk-1351-1400:").last }
    assert_includes refs, "1r.01"
    assert_includes refs, "1r.01:b2",
                    "both charters restart at pb 1r / lb 01 with no container element — " \
                    "the house :b2 disambiguator (the ReM M345 shape), never quarantine, never merge"
    assert_equal refs.size, refs.uniq.size
  end

  def test_entry_notes_identify_the_charter_a_line_opens
    document = parse_urn("urn:nabu:ren:lub-uk-1351-1400")
    first = document.find { |p| p.urn.end_with?(":1r.01") && !p.urn.include?(":b") }
    second = document.find { |p| p.urn.end_with?(":1r.01:b2") }
    assert_equal ["ASnA Ortspunkt-Corpus Lübeck Lub 1352a"], first.annotations["entry_notes"]
    assert_equal ["ASnA Ortspunkt-Corpus Lübeck Lub 1353a"], second.annotations["entry_notes"]
    refute(document.all? { |p| p.annotations.key?("entry_notes") },
           "lines with no preceding editorial note carry no key — never an empty list")
  end

  def test_document_metadata_carries_sigle_and_layer
    metadata = parse_urn("urn:nabu:ren:hamb-uk-1301-1350").metadata
    assert_equal "Hamb._Uk._1301-1350", metadata["sigle"]
    assert_equal "annotated", metadata["layer"]
    refute metadata.key?("unrecognized_elements"), "the fixture parses clean"
  end

  def test_the_censused_low_rhenish_texts_carry_the_upstream_language_marker
    dub = parse_urn("urn:nabu:ren:dub-uk-1301-1350")
    assert_equal "niederrheinisch", dub.metadata["upstream_language"],
                 "the CorA-XML sibling's own classification (censused 2026-07-26), riding gml"
    refute parse_urn("urn:nabu:ren:hamb-uk-1301-1350").metadata.key?("upstream_language")
  end

  def test_unrecognized_elements_ride_the_document_census
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "anno"))
      doctored = File.read(File.join(FIXTURES, "anno/Hamb._Uk._1301-1350.tei"))
                     .sub("<w xml:id=\"t3_m1\"", "<seg>x</seg><w xml:id=\"t3_m1\"")
      File.write(File.join(dir, "anno", "Hamb._Uk._1301-1350.tei"), doctored)
      adapter = Nabu::Adapters::Ren.new
      document = adapter.parse(adapter.discover(dir).first)
      assert_equal({ "#text" => 1, "seg" => 1 }, document.metadata["unrecognized_elements"],
                   "loud census, not quarantine — the aozora precedent")
    end
  end

  # --- the gold lemma flow -----------------------------------------------------

  def test_gold_lemmas_reach_the_passage_lemmas_index_folded_for_gml
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(slug: "ren", name: "ReN",
                                        adapter_class: "Nabu::Adapters::Ren",
                                        license_class: "attribution")
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(Nabu::Adapters::Ren.new, workdir: FIXTURES, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE].where(lemma_folded: "wesen").all
    refute_empty rows, "wēsen² folds to wesen (macron to the Mn strip, homograph ² to the gml rule)"
    assert_includes rows.map { |r| r[:surface_forms] }.join(", "), "se",
                    "attested by the pristine diplomatic surface"
    assert(rows.all? { |r| r[:language] == "gml" && r[:tier] == "gold" },
           "manual annotation — gold tier, the ReM precedent (no lemma_tier override)")
  ensure
    fulltext&.disconnect
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_downloads_verifies_the_pin_and_unpacks
    body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(
      status: 200, body: body,
      headers: { "Content-Type" => "application/zip", "Last-Modified" => "Wed, 06 Jan 2021 12:00:00 GMT" }
    )
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Ren.new(pin: Digest::SHA256.hexdigest(body))
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id),
                   "the unpacked anno/ + trans/ tree is discoverable in place " \
                   "(the tei_1.1/ top dir strips)"
    end
  end

  def test_fetch_aborts_on_a_sha_pin_mismatch_with_the_tree_untouched
    body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Ren.new.fetch(workdir) }
      assert_match(/sha256 pin/, error.message)
      assert_empty Dir.children(workdir), "a pin miss aborts BEFORE any tree mutation"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Ren.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ------------------------------------------------

  def test_probe_heads_the_deposit_artifact_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Ren.remote_probe_strategy
    targets = Nabu::Adapters::Ren.http_probe_targets
    assert_equal 1, targets.size
    assert_equal ZIP_URL, targets[0].zip_url
    assert_nil targets[0].metadata_url,
               "the license lives on the record page — license_watch in the registry row"
    assert_equal Nabu::ZipFetch::STATE_FILE, targets[0].state_file
  end

  # --- registry round-trip ------------------------------------------------------

  def test_registry_resolves_ren_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ren"]
    refute_nil entry, "ren must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Ren, entry.adapter_class
    assert entry.wired, "flipped 2026-07-26 (owner ruling \"flip all wired\"; first sync verified)"
    assert_equal Nabu::Adapters::Ren.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Ren.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # Zip the checked-in fixtures under the upstream layout
  # (tei_1.1/anno/*.tei + tei_1.1/trans/*.tei) and return the zip bytes.
  def stub_zip_body
    Dir.mktmpdir do |dir|
      staging = File.join(dir, "tei_1.1")
      %w[anno trans].each do |layer|
        FileUtils.mkdir_p(File.join(staging, layer))
        Dir.glob(File.join(FIXTURES, layer, "*.tei")).each do |path|
          FileUtils.cp(path, File.join(staging, layer, File.basename(path)))
        end
      end
      zip_path = File.join(dir, "ren.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "tei_1.1", chdir: dir)
      return File.binread(zip_path)
    end
  end
end
