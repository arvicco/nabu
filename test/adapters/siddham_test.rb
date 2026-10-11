# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# Nabu::Adapters::Siddham (P118-4): the Siddham Epigraphic Archive texts
# (Dániel Balogh; Gupta-age Sanskrit epigraphy), the 2019-02-21 EpiDoc
# deposit of Zenodo record 2574901 — 427 editions, san-Latn, physical-line
# grain (the siddham-epidoc family). Fixtures: four whole zip members
# (test/fixtures/siddham/README.md). Fetch runs against a WebMock stub of
# the Zenodo artifact with the sha pin overridden to the stub zip's own
# sha (the rem drill).
class SiddhamTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("siddham")
  ZIP_URL = "https://zenodo.org/api/records/2574901/files/Siddham%20Texts%20Archive%2020190221.zip/content"

  URNS = %w[
    urn:nabu:siddham:IN00002
    urn:nabu:siddham:IN00021
    urn:nabu:siddham:IN00077
    urn:nabu:siddham:IN00121
  ].freeze

  def conformance_adapter = Nabu::Adapters::Siddham.new

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "siddham"

  def adapter = conformance_adapter

  def parse(urn)
    adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id == urn })
  end

  # -- manifest: the record-level grant -----------------------------------------

  def test_manifest_records_the_record_level_cc_by_sa_grant
    manifest = Nabu::Adapters::Siddham.manifest
    assert_equal "siddham", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "CC BY-SA 4.0"
    assert_includes manifest.license, "2574901"
    assert_match(/headers .*blank/i, manifest.license,
                 "the in-file absence of <availability> is stated, not hidden")
    assert_equal "siddham-epidoc", manifest.parser_family
    assert_match(/Balogh/, manifest.credit)
  end

  # -- discover -----------------------------------------------------------------

  def test_discover_mints_one_ref_per_edition_file_sorted
    assert_equal URNS, adapter.discover(FIXTURES).map(&:id),
                 "urn:nabu:siddham:<IN-number>, the archive's own id, case kept (the dharma stem rule)"
  end

  def test_discovery_skips_census_the_schema_and_stray_files
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(FIXTURES, "IN00121_TEI.xml"), dir)
      File.write(File.join(dir, "tei-epidoc.rng"), "<grammar/>")
      File.write(File.join(dir, "desktop.ini"), "[.ShellClassInfo]")
      File.write(File.join(dir, ".zip-fetch.json"), "{}")
      assert_equal 1, adapter.discover(dir).count
      skips = adapter.discovery_skips(dir)
      assert_equal 2, skips.skipped_by_rule, "the schema and the Windows stray are known non-editions"
      assert_equal 0, skips.unrecognized
      assert_match(/tei-epidoc\.rng/, skips.notes.join(" "))
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # -- parse --------------------------------------------------------------------

  def test_document_carries_title_language_and_the_record_grant
    document = parse("urn:nabu:siddham:IN00021")
    assert_equal "Gadhwa Donation 3 of the Time of Kumāragupta I, GE 98", document.title
    assert_equal "san-Latn", document.language
    assert_equal "IN00021", document.metadata["siddham_id"]
    assert_includes document.metadata["license"], "CC BY-SA 4.0",
                    "the record-level grant recorded per document (no in-file licence exists)"
  end

  def test_passages_are_physical_lines
    document = parse("urn:nabu:siddham:IN00021")
    assert_equal "urn:nabu:siddham:IN00021:1", document.passages.first.urn
    assert_equal "jitaṃ bhagavatā| parama-bhāgavata-mahārājādhi", document.passages.first.text
    assert_equal (0...document.passages.size).to_a, document.passages.map(&:sequence)
  end

  def test_annotations_ride_the_line_passages
    document = parse("urn:nabu:siddham:IN00077")
    seal = document.passages.find { |p| p.urn.end_with?(":seal.1") }
    assert_equal({ "textpart" => "seal" }, seal.annotations)
    assert_equal %w[seal body], document.metadata["textparts"]
  end

  # -- the date lane: era-typed title years only ---------------------------------

  def test_an_era_typed_title_year_converts_through_the_era_table
    date = parse("urn:nabu:siddham:IN00021").metadata["date"]
    assert_equal 417, date["not_before"], "GE 98 + 319"
    assert_equal 418, date["not_after"], "the Gupta–Valabhī envelope's width 1"
    assert_equal "GE 98", date["raw"]
    assert_equal "gupta_valabhi", date["era"]
    assert_equal 98, date["era_year"]
    assert_equal "title", date["basis"]
  end

  def test_an_untyped_title_year_is_recorded_never_converted
    metadata = parse("urn:nabu:siddham:IN00077").metadata
    assert_nil metadata["date"], "\"year 156\" names no era — converting it would invent the Gupta claim"
    assert_equal({ "raw" => "year 156", "year" => 156 }, metadata["title_year"])
  end

  def test_a_century_attribution_becomes_its_envelope
    date = parse("urn:nabu:siddham:IN00121").metadata["date"]
    assert_equal({ "not_before" => 401, "not_after" => 500, "raw" => "5th Century", "basis" => "title" }, date)
  end

  def test_a_title_without_date_matter_mints_no_date
    metadata = parse("urn:nabu:siddham:IN00002").metadata
    assert_nil metadata["date"]
    assert_nil metadata["title_year"]
  end

  def test_title_dating_helper_covers_the_censused_shapes
    dating = ->(title) { Nabu::Adapters::Siddham.title_dating(title) }
    assert_equal 482, dating.call("Damodarpur Charter 1 (GE 163) of Budhagupta")["date"]["not_before"]
    assert_equal({ "raw" => "Year 50 (100?)", "year" => 50 },
                 dating.call("Bagh Hoard (2) Charter of Bhuluṇḍa, Year 50 (100?)")["title_year"],
                 "the alternative reading rides raw; the primary number is the year")
    assert_equal 501, dating.call("Bodhgaya Image Inscription of the 6th Century")["date"]["not_before"]
    assert_empty dating.call("Amaravati Graffito 550 of 1907"),
                 "a report-year/accession number is no date claim"
  end

  # -- fetch: one sha-pinned Zenodo zip ------------------------------------------

  def test_fetch_downloads_verifies_the_pin_and_unpacks_flat
    body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(status: 200, body: body, headers: zip_headers)
    Dir.mktmpdir do |workdir|
      siddham = Nabu::Adapters::Siddham.new(pin: Digest::SHA256.hexdigest(body))
      report = siddham.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal URNS, siddham.discover(workdir).map(&:id), "the flat zip unpacks onto the workdir"
    end
  end

  def test_fetch_aborts_on_a_pin_mismatch_with_the_tree_untouched
    stub_request(:get, ZIP_URL).to_return(status: 200, body: stub_zip_body, headers: zip_headers)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Siddham.new.fetch(workdir) }
      assert_match(/sha256 pin/, error.message)
      assert_empty Dir.children(workdir), "a pin miss aborts BEFORE any tree mutation"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Siddham.new.fetch(workdir) }
    end
  end

  def test_the_pin_is_the_recorded_2019_deposit_sha
    assert_equal "f9ebbf9938f6357daac3e12c0467db7ff1fe13d2b85e3130024318474694ac73",
                 Nabu::Adapters::Siddham::ZIP_SHA256
  end

  def test_probe_heads_the_zenodo_artifact
    assert_equal :http_zip, Nabu::Adapters::Siddham.remote_probe_strategy
    assert_equal [ZIP_URL], Nabu::Adapters::Siddham.http_probe_targets.map(&:zip_url)
  end

  private

  def zip_headers
    { "Content-Type" => "application/zip", "Last-Modified" => "Thu, 21 Feb 2019 12:00:00 GMT" }
  end

  # The checked-in members zipped FLAT (the upstream layout: no top dir),
  # with the schema beside them.
  def stub_zip_body
    Dir.mktmpdir do |dir|
      Dir.glob(File.join(FIXTURES, "IN*_TEI.xml")).each { |path| FileUtils.cp(path, dir) }
      File.write(File.join(dir, "tei-epidoc.rng"), "<grammar/>")
      zip_path = File.join(dir, "siddham.zip")
      Nabu::Shell.run("zip", "-q", zip_path, *Dir.children(dir).sort, chdir: dir)
      return File.binread(zip_path)
    end
  end
end
