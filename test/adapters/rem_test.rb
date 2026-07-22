# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# ReM adapter tests (P40-5): the Reference Corpus of Middle High German
# (1050-1350), v2.1 TEI from Zenodo record 13982324, CC BY-SA 4.0 — the
# first cora-tei registrant (ReA/ReN ride the family when their licenses
# confirm). Fixtures are two whole zip members (test/fixtures/rem/README.md);
# fetch runs against a WebMock stub of the Zenodo artifact URL with the sha
# pin overridden to the stub zip's own sha (the iecor drill).
class RemTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("rem")

  ZIP_URL = "https://zenodo.org/api/records/13982324/files/ReM-v2.1_tei.zip/content"

  DOC_URNS = %w[
    urn:nabu:rem:m058
    urn:nabu:rem:m218b
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Rem.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "rem"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_rem_source
    manifest = Nabu::Adapters::Rem.manifest
    assert_equal "rem", manifest.id
    assert_match(/Creative Commons Attribution-ShareAlike 4\.0 International/, manifest.license,
                 "the in-file <licence> grant, verbatim")
    assert_equal "attribution", manifest.license_class
    assert_equal "https://zenodo.org/records/13982324", manifest.upstream_url
    assert_equal "cora-tei", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_text_file
    refs = Nabu::Adapters::Rem.new.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id),
                 "urn:nabu:rem:<textid downcased>, sorted; README and non-M files never match"
    assert(refs.all? { |r| r.source_id == "rem" && r.metadata["language"] == "gmh" })
  end

  def test_discover_titles_come_from_the_header
    titles = Nabu::Adapters::Rem.new.discover(FIXTURES).to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Sangspruchstrophe MF 'Namenlos IV'", titles["urn:nabu:rem:m058"]
    assert_equal "St. Galler Schularbeit, Exzerpt", titles["urn:nabu:rem:m218b"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Rem.new.discover(dir).to_a
    end
  end

  # --- parse -------------------------------------------------------------------

  def test_passages_are_manuscript_lines_cited_page_dot_line
    document = parse_urn("urn:nabu:rem:m058")
    assert_equal "gmh", document.language
    assert_equal %w[100v.5 100v.6], document.map { |p| p.urn.split(":").last },
                 "the primary (ed=1) lb milestones are the corpus's own layout grain"
  end

  def test_passage_text_is_the_diplomatic_layer_nfc_byte_pinned
    document = parse_urn("urn:nabu:rem:m058")
    line = document.find { |p| p.urn.end_with?(":100v.6") }
    # NFC byte pin: ſ is U+017F, uͦ is u + U+0366 (no precomposition exists,
    # so NFC keeps the combining mark) — canonical means canonical, the
    # diplomatic transcription is the witness. The normalized layer rides
    # the token lane, never the passage text.
    assert_equal "ginge wol uerwerden. ſin ere muͦz erſterben.", line.text
    assert line.text.unicode_normalized?(:nfc)
  end

  def test_the_gmh_fold_makes_diplomatic_text_findable_by_modern_spelling
    line = parse_urn("urn:nabu:rem:m058").find { |p| p.urn.end_with?(":100v.6") }
    assert_includes line.text_normalized, "sin ere muz ersterben",
                    "ſ folds to s (the sl precedent) and uͦ falls to the mark strip"
    refute_includes line.text_normalized, "ſ"
  end

  def test_gold_norm_and_lemma_ride_in_token_annotations
    line = parse_urn("urn:nabu:rem:m058").find { |p| p.urn.end_with?(":100v.5") }
    grimme = line.annotations["tokens"].find { |t| t["lemma"] == "grimme" }
    assert_equal({ "id" => "t5_m1", "form" => "grínme", "norm" => "grinme", "lemma" => "grimme" },
                 grimme)
  end

  def test_edition_lineation_rides_passage_annotations
    document = parse_urn("urn:nabu:rem:m218b")
    third = document.find { |p| p.urn.end_with?(":96v.3") }
    assert_equal ["08"], third.annotations["edition_lines"]
    m058 = parse_urn("urn:nabu:rem:m058")
    refute(m058.any? { |p| p.annotations.key?("edition_lines") },
           "M058 carries no secondary lineation — the key is absent, never an empty list")
  end

  def test_document_metadata_carries_the_classification_lanes
    document = parse_urn("urn:nabu:rem:m058")
    assert_equal %w[mhd oberdeutsch ostoberdeutsch bairisch], document.metadata["dialects"],
                 "the langUsage localization chain — the future timeline/place lane"
    assert_equal "V", document.metadata["genre"]
    assert_equal "Poesie", document.metadata["topic"]
    assert_equal "Spruchdichtung", document.metadata["text_type"]
    assert_equal "Wien, Österr. Nationalbibl.", document.metadata["repository"]
    assert_equal "Cod. 160", document.metadata["ms_idno"]
    assert_equal 23, document.metadata["token_count"]
    refute document.metadata.key?("orig_date"),
           "both fixtures carry the '--' placeholder — no invented dating (isicily discipline)"
  end

  def test_a_translation_text_records_its_derivation
    assert_equal "latein", parse_urn("urn:nabu:rem:m218b").metadata["derived_from"]
  end

  def test_unrecognized_elements_ride_the_document_census
    Dir.mktmpdir do |dir|
      doctored = File.read(File.join(FIXTURES, "M058.xml"))
                     .sub("<w xml:id=\"t3_m1\"", "<seg>x</seg><w xml:id=\"t3_m1\"")
      File.write(File.join(dir, "M058.xml"), doctored)
      adapter = Nabu::Adapters::Rem.new
      document = adapter.parse(adapter.discover(dir).first)
      assert_equal({ "#text" => 1, "seg" => 1 }, document.metadata["unrecognized_elements"],
                   "loud census, not quarantine — the aozora precedent")
    end
  end

  def test_license_drift_quarantines_the_document
    Dir.mktmpdir do |dir|
      doctored = File.read(File.join(FIXTURES, "M058.xml"))
                     .sub("Creative Commons Attribution-ShareAlike 4.0 International (CC-BY-SA)",
                          "All rights reserved")
      File.write(File.join(dir, "M058.xml"), doctored)
      adapter = Nabu::Adapters::Rem.new
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/licence/i, error.message)
    end
  end

  def test_a_non_gmh_language_ident_quarantines_the_document
    Dir.mktmpdir do |dir|
      doctored = File.read(File.join(FIXTURES, "M058.xml"))
                     .sub("<language ident=\"gmh\">mhd</language>",
                          "<language ident=\"goh\">ahd</language>")
      File.write(File.join(dir, "M058.xml"), doctored)
      adapter = Nabu::Adapters::Rem.new
      assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
    end
  end

  # --- the gold lemma flow ------------------------------------------------------

  def test_gold_lemmas_reach_the_passage_lemmas_index
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(slug: "rem", name: "ReM",
                                        adapter_class: "Nabu::Adapters::Rem",
                                        license_class: "attribution")
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(Nabu::Adapters::Rem.new, workdir: FIXTURES, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE].where(lemma_folded: "grimme").all
    assert_equal 1, rows.size, "the gold lemma grimme is indexed for gmh"
    assert_equal "grínme", rows[0][:surface_forms], "attested by the pristine diplomatic surface"
    assert rows[0][:urn].end_with?(":100v.5")
  ensure
    fulltext&.disconnect
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_downloads_verifies_the_pin_and_unpacks
    body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(
      status: 200, body: body,
      headers: { "Content-Type" => "application/zip", "Last-Modified" => "Mon, 28 Oct 2024 12:00:00 GMT" }
    )
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Rem.new(pin: Digest::SHA256.hexdigest(body))
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id),
                   "the unpacked tei/ tree is discoverable in place"
    end
  end

  def test_fetch_aborts_on_a_sha_pin_mismatch_with_the_tree_untouched
    body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Rem.new.fetch(workdir) }
      assert_match(/sha256 pin/, error.message)
      assert_empty Dir.children(workdir), "a pin miss aborts BEFORE any tree mutation"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Rem.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ------------------------------------------------

  def test_probe_heads_the_zenodo_artifact_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Rem.remote_probe_strategy
    targets = Nabu::Adapters::Rem.http_probe_targets
    assert_equal 1, targets.size
    assert_equal ZIP_URL, targets[0].zip_url
    assert_nil targets[0].metadata_url, "the license lives in-file and on the record page"
    assert_equal Nabu::ZipFetch::STATE_FILE, targets[0].state_file
  end

  # --- registry round-trip ------------------------------------------------------

  def test_registry_resolves_rem_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["rem"]
    refute_nil entry, "rem must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Rem, entry.adapter_class
    assert entry.enabled, "first sync verified + owner-flipped 2026-07-22"
    assert_equal Nabu::Adapters::Rem.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Rem.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # Zip the checked-in fixtures under the upstream layout
  # (ReM-v2.1_tei/tei/M*.xml + README) and return the zip bytes.
  def stub_zip_body
    Dir.mktmpdir do |dir|
      staging = File.join(dir, "ReM-v2.1_tei")
      FileUtils.mkdir_p(File.join(staging, "tei"))
      Dir.glob(File.join(FIXTURES, "M*.xml")).each do |path|
        FileUtils.cp(path, File.join(staging, "tei", File.basename(path)))
      end
      File.write(File.join(staging, "README"), "Reference Corpus of Middle High German\n")
      zip_path = File.join(dir, "rem.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "ReM-v2.1_tei", chdir: dir)
      return File.binread(zip_path)
    end
  end
end
