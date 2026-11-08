# frozen_string_literal: true

require "test_helper"
require "digest"
require "tmpdir"
require "fileutils"

# Llct1 adapter tests (P164): the Late Latin Charter Treebank 1 (v1.2,
# Zenodo 3633607) — one PML file, one document per charter (edition siglum
# + number), one passage per sentence tree. Conformance suite over the
# checked-in fixture trim (4 of 519 charters, every tree of each, verbatim
# bytes). No network: fetch runs against WebMock stubs of the real Zenodo
# file URL with the sha256 pin swapped for the fixture body's (the helipad
# pattern).
class Llct1Test < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("llct1")
  FILE_URL = "https://zenodo.org/api/records/3633607/files/LLCT1,%20version%201.2.xml/content"
  ADAPTER = Nabu::Adapters::Llct1

  def conformance_adapter = ADAPTER.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "llct1"

  def refs = ADAPTER.new.discover(FIXTURES).to_a

  def parsed(urn)
    adapter = ADAPTER.new
    adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id == urn })
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_is_cc_by_attribution_on_the_aldt_pml_family
    manifest = ADAPTER.manifest
    assert_equal "llct1", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(/Korkiakangas/, manifest.license)
    assert_equal "https://zenodo.org/records/3633607", manifest.upstream_url
    assert_equal "aldt-pml", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_document_per_charter_in_file_order
    assert_equal %w[urn:nabu:llct1:CDL-115 urn:nabu:llct1:CDL-208 urn:nabu:llct1:CDT-63
                    urn:nabu:llct1:MED-259], refs.map(&:id)
    ref = refs.first
    assert_equal "llct1", ref.source_id
    assert_equal({ "edition" => "CDL", "number" => "115", "date" => "754",
                   "place" => "S. Cassiano (di Moriano o a Vico?, Lucca)", "scribe" => "Osprand",
                   "type" => "charta dotis", "redaction" => "copy" }, ref.metadata.fetch("root"))
    assert_equal 5, ref.metadata.fetch("ranges").size, "one byte range per sentence tree"
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty ADAPTER.new.discover(dir).to_a }
  end

  def test_no_grain_is_skipped_by_rule_in_the_fixture
    skips = ADAPTER.new.discovery_skips(FIXTURES)
    assert_equal 0, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_reads_the_charter_at_sentence_grain
    document = parsed("urn:nabu:llct1:CDL-208")
    assert_equal "lat", document.language
    assert_equal "CDL 208 — breve (767)", document.title
    assert_equal %w[urn:nabu:llct1:CDL-208:2936672 urn:nabu:llct1:CDL-208:2936673], document.map(&:urn)
    assert_equal "Et ecce breue scriptum, quam dictauit Barbenti presbiter, de casis et pertinentia " \
                 "et hominibus sancti Quirici, quam Osprandus diaconus scripsit per eius dictatum.",
                 document.first.text
  end

  def test_charter_metadata_mines_date_place_type_scribe_and_redaction
    meta = parsed("urn:nabu:llct1:CDL-208").metadata
    assert_equal "CDL", meta["edition"]
    assert_equal "208", meta["number"]
    assert_equal({ "not_before" => 767, "not_after" => 767, "raw" => "767" }, meta["date"],
                 "an original charter's year is the artifact's own — no class label")
    assert_equal "Monte San Quirico (Lucca?)", meta["place"]
    assert_equal "breve", meta["document_type"]
    assert_equal "Osprandus", meta["scribe"]
    assert_equal "original", meta["redaction"]
    refute meta.key?("ranges"), "byte ranges are discover plumbing, never catalog metadata"
  end

  def test_a_copy_dates_the_act_as_composition
    meta = parsed("urn:nabu:llct1:CDL-115").metadata
    assert_equal({ "not_before" => 754, "not_after" => 754, "raw" => "754", "class" => "composition" },
                 meta["date"])
  end

  def test_italian_type_labels_ride_verbatim
    meta = parsed("urn:nabu:llct1:CDT-63").metadata
    assert_equal "Locazione", meta["document_type"]
    assert_equal "Pisa", meta["place"]
    assert_equal 804, meta.dig("date", "not_before")
  end

  def test_token_lane_carries_gold_lemma_and_morphology
    tokens = parsed("urn:nabu:llct1:MED-259").flat_map { |p| p.annotations.fetch("tokens") }
    domini = tokens.find { |t| t["form"] == "Domini" }
    assert_equal %w[dominus 1], domini.values_at("lemma", "lemma_homograph")
    assert_equal "genitive", domini["case"]
    assert_equal "free", domini["seg"], "the notitia's narrative opening is free text"
    assert_equal({ "formulaic" => 27, "free" => 111, "subs" => 25 }, tokens.map { |t| t["seg"] }.tally,
                 "the formulaic frame, free text and subscriptions, per word")
    assert_equal 8, tokens.count { |t| t["status"] == "expan" }, "expanded abbreviations flagged"
    assert(tokens.all? { |t| t.key?("head") && t.key?("relation") })
  end

  def test_a_drifted_file_quarantines_rather_than_misreading
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(FIXTURES, "llct1-1.2.xml"), dir)
      adapter = ADAPTER.new
      ref = adapter.discover(dir).find { |r| r.id.end_with?("CDT-63") }
      other = adapter.discover(dir).find { |r| r.id.end_with?("MED-259") }
      forged = Nabu::DocumentRef.new(source_id: ref.source_id, id: ref.id, path: ref.path,
                                     metadata: ref.metadata.merge("ranges" => other.metadata["ranges"]))
      assert_raises(Nabu::ParseError) { adapter.parse(forged) }
    end
  end

  # --- fetch (WebMock only) ---------------------------------------------------

  def test_fetch_downloads_the_pinned_file
    body = File.binread(File.join(FIXTURES, "llct1-1.2.xml"))
    stub_request(:get, FILE_URL).to_return(status: 200, body: body,
                                           headers: { "Last-Modified" => "Sat, 01 Feb 2020 00:00:00 GMT" })
    Dir.mktmpdir do |workdir|
      adapter = ADAPTER.new(file_sha256: Digest::SHA256.hexdigest(body))
      report = adapter.fetch(workdir)
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal 4, adapter.discover(workdir).count
    end
  end

  def test_fetch_aborts_on_sha_drift_with_the_tree_untouched
    stub_request(:get, FILE_URL).to_return(status: 200, body: "<aldt_treebank/>")
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(workdir) }
      assert_match(/drifted/, error.message)
      refute File.exist?(File.join(workdir, "llct1-1.2.xml"))
    end
  end

  def test_fetch_wraps_http_failure
    stub_request(:get, FILE_URL).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(workdir) } }
  end

  def test_probe_targets_the_zenodo_file
    assert_equal :http_zip, ADAPTER.remote_probe_strategy
    target = ADAPTER.http_probe_targets.first
    assert_equal FILE_URL, target.zip_url
    assert_nil target.metadata_url
  end

  # --- registration -----------------------------------------------------------

  def test_registered_wired_manual_romance
    row = YAML.safe_load_file(File.expand_path("../../config/sources.yml", __dir__)).fetch("llct1")
    assert_equal "Nabu::Adapters::Llct1", row.fetch("adapter")
    assert_equal true, row.fetch("wired"), "flipped live after the verified first sync (P164)"
    assert_equal "manual", row.fetch("sync_policy")
    assert_equal ["romance"], row.fetch("axes")
  end
end
