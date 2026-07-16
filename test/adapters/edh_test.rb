# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

# The EDH adapter (P17-2): conformance suite + the survey-verified specifics —
# language from the CSV nl_text column (the langUsage trap), metadata-only
# stubs skipped by rule at discover, the pers-CSV prosopography join, and the
# eleven-artifact fetch (nine flat zips + two CSV sidecars) exercised against
# WebMock-stubbed responses assembled from the checked-in fixtures. No
# network, ever.
class EdhTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("edh") # NABU_FIXTURE_DIR-aware (fixtures:check)

  def conformance_adapter
    Nabu::Adapters::Edh.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "edh"
  end

  # -- discovery --------------------------------------------------------------

  def test_discover_yields_the_five_fixture_records_in_urn_order
    refs = conformance_adapter.discover(FIXTURES).to_a
    assert_equal %w[urn:nabu:edh:hd000001 urn:nabu:edh:hd000082 urn:nabu:edh:hd029093
                    urn:nabu:edh:hd080825 urn:nabu:edh:hd081183],
                 refs.map(&:id)
  end

  def test_language_comes_from_the_csv_nl_text_never_the_epidoc_header
    refs = conformance_adapter.discover(FIXTURES).to_a
    by_id = refs.to_h { |ref| [ref.id, ref.metadata["language"]] }
    # HD000082 is nl_text=GL (bilingual, Latin document language) although its
    # langUsage header claims only en/de/lat — the survey's verified trap.
    assert_equal "lat", by_id["urn:nabu:edh:hd000082"]
    assert_equal "lat", by_id["urn:nabu:edh:hd000001"]
  end

  def test_language_map_covers_the_censused_codes
    { "L" => "lat", "G" => "grc", "GL" => "lat", "LG" => "lat", "PL" => "lat",
      "PyGL" => "lat", "PyG" => "grc", "N" => "und", "" => "und" }.each do |code, expected|
      assert_equal expected, Nabu::Adapters::Edh.language_for(code), "nl_text #{code.inspect}"
    end
  end

  def test_persons_ride_into_document_metadata_from_the_pers_csv
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:edh:hd000001" }
    persons = adapter.parse(ref).metadata["persons"]
    assert_equal 3, persons.size, "the survey's three structured persons"
    assert_equal({ "name" => "Noniae P.f. Optatae", "nomen" => "Nonia", "cognomen" => "Optata",
                   "filiation" => "P.f.", "sex" => "W", "kinship" => "BF" }, persons[0])
    assert_equal(%w[Artemo Optatus], persons[1..].map { |person| person["cognomen"] })
  end

  def test_trismegistos_and_genre_facets_land_in_metadata
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:edh:hd000001" }
    metadata = adapter.parse(ref).metadata
    assert_equal "251193", metadata["tm_nr"]
    assert_equal({ "value" => "epitaph", "raw" => "titsep" }, metadata.dig("facets", "genre"))
    assert_equal "LaC", metadata.dig("facets", "province", "raw")
    assert_equal "Latium et Campania (Regio I)", metadata.dig("facets", "province", "value")
  end

  def test_workdir_without_the_csvs_yields_nothing
    Dir.mktmpdir do |dir| # the attic-overlay shape: XML trees, no CSV sidecars
      FileUtils.mkdir_p(File.join(dir, "epidoc", "HD000001-HD010000"))
      FileUtils.cp(File.join(FIXTURES, "epidoc", "HD000001-HD010000", "HD000001.xml"),
                   File.join(dir, "epidoc", "HD000001-HD010000"))
      assert_empty conformance_adapter.discover(dir).to_a
      assert conformance_adapter.discovery_skips(dir).clean?
    end
  end

  # -- metadata-only stubs: skip-by-rule (survey §1, ~475 records) -------------

  def test_text_less_stub_is_skipped_by_rule_and_counted
    with_stubbed_workdir do |dir|
      adapter = conformance_adapter
      refs = adapter.discover(dir).to_a
      refute_includes refs.map(&:id), "urn:nabu:edh:hd000001",
                      "a CSV row with empty atext is a metadata-only stub, never a document"
      assert_equal %w[urn:nabu:edh:hd000082 urn:nabu:edh:hd029093
                      urn:nabu:edh:hd080825 urn:nabu:edh:hd081183], refs.map(&:id)

      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.skipped_by_rule
      assert_predicate skips, :clean?
    end
  end

  def test_xml_without_a_csv_row_is_unrecognized_and_loud
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      orphan = File.join(dir, "epidoc", "HD000001-HD010000", "HD999999.xml")
      FileUtils.cp(File.join(dir, "epidoc", "HD000001-HD010000", "HD000001.xml"), orphan)

      adapter = conformance_adapter
      refute_includes adapter.discover(dir).map(&:id), "urn:nabu:edh:hd999999"
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_match(/HD999999.*no edh_data_text.csv row/, skips.notes.first)
    end
  end

  # -- fetch (nine zips + two CSVs, WebMock-stubbed) ----------------------------

  LAST_MODIFIED = "Thu, 16 Dec 2021 11:04:11 GMT"

  def test_fetch_downloads_all_eleven_artifacts
    Dir.mktmpdir do |root|
      stub_edh_artifacts(root)
      workdir = File.join(root, "work")

      report = conformance_adapter.fetch(workdir)

      assert File.file?(File.join(workdir, "epidoc", "HD000001-HD010000", "HD000001.xml"))
      assert File.file?(File.join(workdir, "epidoc", "HD080001-HD082828", "HD080825.xml"))
      assert File.file?(File.join(workdir, "text", "edh_data_text.csv"))
      assert File.file?(File.join(workdir, "pers", "edh_data_pers.csv"))
      assert_match(/\A\h{64}\z/, report.sha)
      assert_match(/HD000001-HD010000=\h{12} \(2 records\)/, report.notes)
      assert_match(/text=\h{12} \(5 rows\)/, report.notes)
      assert_match(/pers=\h{12} \(5 rows\)/, report.notes)
      # repos pins every artifact by its URL: 9 zips + 2 CSVs.
      assert_equal 11, report.repos.size
      assert report.repos.key?("#{Nabu::Adapters::Edh::DUMP_BASE_URL}/edh_data_text.csv")
    end
  end

  def test_fetch_then_discover_round_trips
    Dir.mktmpdir do |root|
      stub_edh_artifacts(root)
      workdir = File.join(root, "work")
      adapter = conformance_adapter
      adapter.fetch(workdir)
      refs = adapter.discover(workdir).to_a
      assert_equal 5, refs.size
      assert_equal "urn:nabu:edh:hd000001", adapter.parse(refs.first).urn
    end
  end

  def test_fetch_is_a_no_op_on_304_not_modified
    Dir.mktmpdir do |root|
      stub_edh_artifacts(root)
      workdir = File.join(root, "work")
      adapter = conformance_adapter
      first = adapter.fetch(workdir)

      stub_edh_artifacts(root, status: 304)
      second = adapter.fetch(workdir)
      assert_equal first.sha, second.sha, "an unchanged upstream keeps the pinned sha"
      assert File.file?(File.join(workdir, "epidoc", "HD000001-HD010000", "HD000001.xml"))
    end
  end

  def test_fetch_trips_the_mass_deletion_breaker_before_any_tree_change
    Dir.mktmpdir do |root|
      stub_edh_artifacts(root)
      workdir = File.join(root, "work")
      adapter = conformance_adapter
      adapter.fetch(workdir)

      # A fresh build missing 2 of the 5 ingestible records (40% > 20%).
      stub_edh_artifacts(root, drop: %w[HD000001.xml HD000082.xml])
      assert_raises(Nabu::SyncAborted) { adapter.fetch(workdir) }
      assert File.file?(File.join(workdir, "epidoc", "HD000001-HD010000", "HD000001.xml")),
             "a tripped breaker must leave the tree byte-unchanged"

      # --force proceeds; the dropped records are atticked and rediscovered.
      report = adapter.fetch(workdir, force: true)
      assert_match(/atticked/, report.notes)
      assert File.file?(File.join(workdir, ".attic", "epidoc", "HD000001-HD010000", "HD000001.xml"))
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    Dir.mktmpdir do |root|
      stub_request(:get, Nabu::Adapters::Edh.zip_url("HD000001-HD010000")).to_return(status: 500)
      assert_raises(Nabu::FetchError) { conformance_adapter.fetch(File.join(root, "work")) }
    end
  end

  private

  # A workdir whose text CSV marks HD000001 as a metadata-only stub (atext
  # blanked in the CSV — the CSV cell is the rule's own input; the XML files
  # stay the real, untouched upstream records).
  def with_stubbed_workdir
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      csv_path = File.join(dir, "text", "edh_data_text.csv")
      rows = CSV.read(csv_path, headers: true)
      rows.each { |row| row["atext"] = nil if row["hd_nr"] == "HD000001" }
      CSV.open(csv_path, "w", write_headers: true, headers: rows.headers) do |csv|
        rows.each { |row| csv << row }
      end
      yield dir
    end
  end

  # Zip the fixture record trees (real upstream payloads, FLAT files — the
  # EDH zip shape) and stub all eleven artifact URLs. +drop+ omits records
  # from the fresh build; +status: 304+ answers every URL not-modified.
  def stub_edh_artifacts(root, drop: [], status: 200)
    if status == 304
      all_urls.each { |url| stub_request(:get, url).to_return(status: 304) }
      return
    end

    zips = File.join(root, "zips-#{drop.empty? ? 'full' : 'dropped'}")
    Nabu::Adapters::Edh::ZIP_RANGES.each do |range|
      staging = File.join(zips, range)
      FileUtils.mkdir_p(staging)
      fixture_dir = File.join(FIXTURES, "epidoc", range)
      if Dir.exist?(fixture_dir)
        FileUtils.cp_r(File.join(fixture_dir, "."), staging)
        drop.each { |name| FileUtils.rm_f(File.join(staging, name)) }
      end
      if Dir.empty?(staging)
        # Ranges without (remaining) records get a placeholder entry so the
        # zip is non-empty; discover never ingests non-HD files.
        File.write(File.join(staging, "empty.txt"), "no fixture records in this range\n")
      end
      zip_path = File.join(zips, "#{range}.zip")
      # Zip the CONTENTS flat (cd into the staging dir), matching upstream.
      Nabu::Shell.run("zip", "-q", "-r", zip_path, ".", chdir: staging)
      stub_request(:get, Nabu::Adapters::Edh.zip_url(range)).to_return(
        status: 200, body: File.binread(zip_path),
        headers: { "Content-Type" => "application/zip", "Last-Modified" => LAST_MODIFIED }
      )
    end
    Nabu::Adapters::Edh::CSVS.each do |subdir, filename|
      stub_request(:get, "#{Nabu::Adapters::Edh::DUMP_BASE_URL}/#{filename}").to_return(
        status: 200, body: File.binread(File.join(FIXTURES, subdir, filename)),
        headers: { "Content-Type" => "text/csv", "Last-Modified" => LAST_MODIFIED }
      )
    end
  end

  def all_urls
    Nabu::Adapters::Edh::ZIP_RANGES.map { |range| Nabu::Adapters::Edh.zip_url(range) } +
      Nabu::Adapters::Edh::CSVS.values.map { |name| "#{Nabu::Adapters::Edh::DUMP_BASE_URL}/#{name}" }
  end
end
