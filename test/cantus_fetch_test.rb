# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::CantusFetch: the polite source-list crawl for the Cantus Database.
# prepare! (the /json-sources/ manifest + the segment-4063 Browse Sources
# pages, live tree untouched) → guard (mass-deletion breaker) → complete!
# (attic the vanished and the superseded, land the sidecars, fetch each
# listed source's CSV export into sources/, pin the ledger).
#
# Stub bodies are the real fixture bytes under test/fixtures/cantus/
# (trimmed real pages and exports — README).
class CantusFetchTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/cantus", __dir__)
  HOST = "https://cantusdatabase.org"
  IDS = [693_666, 123_717, 123_738, 1_000_458].freeze

  def setup
    @root = Dir.mktmpdir("cantus-fetch-test")
    @dir = File.join(@root, "cantus")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def fixture(rel) = File.binread(File.join(FIXTURES, rel))

  def stub_manifest(body: fixture("json-sources.json"))
    stub_request(:get, "#{HOST}/json-sources/").to_return(status: 200, body: body,
                                                          headers: { "Content-Type" => "application/json" })
  end

  def stub_pages(overrides = {})
    (1..3).each do |n|
      stub_request(:get, "#{HOST}/sources/?segment=4063&page=#{n}")
        .to_return(status: 200, body: overrides.fetch(n) { fixture("sources-page-#{n}.html") })
    end
  end

  def stub_csvs(missing: [], bodies: {})
    IDS.each do |id|
      stub = stub_request(:get, "#{HOST}/source/#{id}/csv/")
      if missing.include?(id)
        stub.to_return(status: 404, body: "")
      else
        stub.to_return(status: 200, body: bodies.fetch(id) { fixture("sources/#{id}.csv") },
                       headers: { "Content-Type" => "text/csv" })
      end
    end
  end

  def stub_all
    stub_manifest
    stub_pages
    stub_csvs
  end

  def sync!(guard: nil)
    Nabu::CantusFetch.sync!(dir: @dir, attic_dir: @attic, delay: 0, guard: guard)
  end

  # --- URLs, filenames ------------------------------------------------------------

  def test_urls_and_filenames
    assert_equal "#{HOST}/sources/?segment=4063&page=2", Nabu::CantusFetch.page_url(HOST, 2)
    assert_equal "#{HOST}/source/123717/csv/", Nabu::CantusFetch.absolute("http://cantusdatabase.org/source/123717/csv/"),
                 "the manifest's http:// links (301 to https upstream) are upgraded up front"
    assert_equal File.join("sources", "123717.csv"), Nabu::CantusFetch.csv_relpath(123_717)
    assert_equal "sources-page-3.html", Nabu::CantusFetch.page_filename(3)
    assert_equal 123_717, Nabu::CantusFetch.csv_id("123717.csv")
    assert_equal 123_717, Nabu::CantusFetch.csv_id("123717.0a1b2c3d.csv"), "a superseded attic copy"
    assert_nil Nabu::CantusFetch.csv_id("json-sources.json")
  end

  def test_the_user_agent_names_the_license_and_contact
    assert_includes Nabu::CantusFetch::USER_AGENT, "CC BY-NC-SA 4.0"
    assert_includes Nabu::CantusFetch::USER_AGENT, "arvicco@nabu.ac"
  end

  # --- the happy path -----------------------------------------------------------

  def test_sync_lands_the_manifest_pages_and_every_listed_export
    stub_all
    result = sync!
    assert_equal 4, result.sources
    assert_equal 3, result.pages
    assert_equal 4, result.advertised_sources, "the listing's own \"of 4 sources\""
    assert_equal 42, result.advertised_chants, "the Chants column summed (2 + 25 + 14 + 1)"
    assert_equal 4, result.fetched
    assert_empty result.drift
    IDS.each { |id| assert File.file?(File.join(@dir, "sources", "#{id}.csv")), "#{id}.csv" }
    assert File.file?(File.join(@dir, "json-sources.json"))
    (1..3).each { |n| assert File.file?(File.join(@dir, "sources-page-#{n}.html")) }
    state = JSON.parse(File.read(File.join(@dir, Nabu::CantusFetch::STATE_FILE)))
    assert_equal result.sha, state["sha256"]
    assert_equal 42, state["advertised_chants"]
  end

  def test_a_resync_reuses_exports_whose_row_count_matches_the_listing
    stub_all
    first = sync!
    second = sync!
    assert_equal 0, second.fetched
    assert_equal 4, second.cached
    assert_equal first.sha, second.sha
  end

  def test_an_export_whose_row_count_drifted_is_refetched_and_the_old_copy_atticked
    stub_all
    sync!
    stale = File.join(@dir, "sources", "693666.csv")
    old = File.binread(stale).lines.first(2).join # header + one row: 1 ≠ the listing's 2
    File.binwrite(stale, old)
    result = sync!
    assert_equal 1, result.fetched, "only the drifted export"
    assert_equal fixture("sources/693666.csv"), File.binread(stale)
    copies = Dir.glob(File.join(@attic, "sources", "693666.*.csv"))
    assert_equal 1, copies.size, "the superseded body keeps its rows reachable"
    assert_equal old, File.binread(copies.first)
  end

  def test_a_fetched_export_disagreeing_with_the_listing_is_noted_not_fatal
    stub_manifest
    stub_pages
    stub_csvs(bodies: { 693_666 => fixture("sources/693666.csv").lines.first(2).join })
    result = sync!
    assert_equal ["693666: 1 rows, listing says 2"], result.drift
  end

  # --- drift guards ---------------------------------------------------------------

  def test_a_listing_total_disagreeing_with_its_rows_aborts_before_any_write
    stub_manifest
    stub_pages(1 => fixture("sources-page-1.html").sub("of <b>4</b> sources", "of <b>305</b> sources"))
    error = assert_raises(Nabu::CantusFetch::Error) { sync! }
    assert_match(/advertises 305 sources/, error.message)
    refute Dir.exist?(File.join(@dir, "sources")), "nothing landed"
  end

  def test_a_manifest_disagreeing_with_the_listing_aborts
    manifest = JSON.parse(fixture("json-sources.json"))
    manifest["999999"] = { "csv" => "http://cantusdatabase.org/source/999999/csv/" }
    stub_manifest(body: JSON.generate(manifest))
    stub_pages
    error = assert_raises(Nabu::CantusFetch::Error) { sync! }
    assert_match(/999999/, error.message)
  end

  def test_a_non_json_manifest_aborts
    stub_manifest(body: fixture("sources-page-1.html"))
    error = assert_raises(Nabu::CantusFetch::Error) { sync! }
    assert_match(/not JSON/, error.message)
  end

  def test_a_listed_404_is_censused_and_the_crawl_continues
    stub_manifest
    stub_pages
    stub_csvs(missing: [123_738])
    result = sync!
    assert_equal [123_738], result.missing
    assert_equal 3, result.fetched
  end

  def test_a_5xx_retries_then_fails_loudly
    stub_request(:get, "#{HOST}/json-sources/").to_return(status: 503)
    error = assert_raises(Nabu::CantusFetch::Error) { sync! }
    assert_match(/503.*after 3 attempts/, error.message)
  end

  def test_a_non_csv_export_body_aborts
    stub_manifest
    stub_pages
    stub_csvs(bodies: { 123_717 => fixture("sources-page-1.html") })
    error = assert_raises(Nabu::CantusFetch::Error) { sync! }
    assert_match(/123717.*not the CSV export/, error.message)
  end

  # --- retention ----------------------------------------------------------------------

  def test_vanished_sources_are_atticked_after_the_guard
    stub_all
    sync!
    gone = File.join(@dir, "sources", "424242.csv")
    FileUtils.cp(File.join(@dir, "sources", "693666.csv"), gone)
    seen = nil
    sync!(guard: ->(doomed) { seen = doomed })
    assert_equal [gone], seen
    refute File.exist?(gone)
    assert File.file?(File.join(@attic, "sources", "424242.csv"))
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert manifest.key?(File.join("sources", "424242.csv"))
  end

  def test_a_raising_guard_leaves_the_tree_unchanged
    stub_all
    sync!
    gone = File.join(@dir, "sources", "424242.csv")
    File.write(gone, "x")
    assert_raises(Nabu::FetchError) { sync!(guard: ->(_doomed) { raise Nabu::FetchError, "breaker" }) }
    assert File.file?(gone)
  end
end
