# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::AioFetch (P154): the polite REST-listing crawl for Attic
# Inscriptions Online. prepare! (the "next"-linked listing GETs only, live
# tree untouched) → guard (mass-deletion breaker) → complete! (attic the
# vanished, land the listing sidecars, crawl each listed record's API JSON
# + inscription page skip-on-disk into records/, pin the ledger).
#
# Stub bodies are the real fixture bytes under test/fixtures/aio/ (the
# two listing pages are the trimmed real rows — README).
class AioFetchTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/aio", __dir__)
  HOST = "https://www.atticinscriptions.com"

  def setup
    @root = Dir.mktmpdir("aio-fetch-test")
    @dir = File.join(@root, "aio")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def fixture(rel) = File.binread(File.join(FIXTURES, rel))

  def stub_listing(page1: fixture("list-page-1.json"), page2: fixture("list-page-2.json"))
    stub_request(:get, "#{HOST}/inscription/list_all_inscriptions.json?page=1")
      .to_return(status: 200, body: page1, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "#{HOST}/inscription/list_all_inscriptions.json?page=2")
      .to_return(status: 200, body: page2, headers: { "Content-Type" => "application/json" })
  end

  RECORDS = { 2103 => "AIUK11/9", 2586 => "SEG/46153", 3869 => "IGII2/5271" }.freeze

  def stub_records(missing: [])
    RECORDS.each do |number, path|
      { "json" => "#{HOST}/inscription/#{path}.json", "html" => "#{HOST}/inscription/#{path}" }.each do |ext, url|
        if missing.include?([number, ext])
          stub_request(:get, url).to_return(status: 404, body: "")
        else
          stub_request(:get, url).to_return(status: 200, body: fixture("records/aio-#{number}.#{ext}"))
        end
      end
    end
  end

  def sync!(guard: nil)
    Nabu::AioFetch.sync!(dir: @dir, attic_dir: @attic, delay: 0, guard: guard)
  end

  # --- URLs, filenames, predicates ------------------------------------------

  def test_urls_and_filenames
    assert_equal "#{HOST}/inscription/list_all_inscriptions.json?page=4",
                 Nabu::AioFetch.listing_url(HOST, 4)
    assert_equal File.join("records", "aio-3869.json"), Nabu::AioFetch.record_relpath(3869, "json")
    assert_equal "list-page-2.json", Nabu::AioFetch.listing_filename(2)
    assert Nabu::AioFetch.record?("aio-3869.html")
    refute Nabu::AioFetch.record?("list-page-1.json")
    refute Nabu::AioFetch.record?(Nabu::AioFetch::STATE_FILE)
  end

  def test_listing_urls_read_as_https
    assert_equal "#{HOST}/inscription/SEG/46153",
                 Nabu::AioFetch.absolute("www.atticinscriptions.com/inscription/SEG/46153"),
                 "the listing's host-relative urls read as https"
    assert_equal "#{HOST}/inscription/list_all_inscriptions.json?page=2",
                 Nabu::AioFetch.absolute("http://www.atticinscriptions.com/inscription/list_all_inscriptions.json?page=2"),
                 "the http:// next links (301 to https upstream) are upgraded up front"
  end

  def test_the_user_agent_names_the_license_and_contact
    assert_includes Nabu::AioFetch::USER_AGENT, "CC BY-SA 3.0"
    assert_includes Nabu::AioFetch::USER_AGENT, "arvicco@nabu.ac"
  end

  # --- the happy path -------------------------------------------------------

  def test_sync_follows_next_lands_pairs_sidecars_and_ledger
    stub_listing
    stub_records
    result = sync!
    assert_equal 2, result.pages, "page 1's next link leads to page 2; page 2 carries no next"
    assert_equal 3, result.records
    assert_equal 3, result.advertised, "upstream's own count"
    assert_equal 6, result.fetched, "a JSON record + an inscription page per inscription"
    RECORDS.each_key do |number|
      %w[json html].each do |ext|
        assert File.file?(File.join(@dir, "records", "aio-#{number}.#{ext}")), "aio-#{number}.#{ext}"
      end
    end
    assert File.file?(File.join(@dir, "list-page-1.json")), "listing pages persist as sidecars"
    assert File.file?(File.join(@dir, "list-page-2.json"))
    state = JSON.parse(File.read(File.join(@dir, Nabu::AioFetch::STATE_FILE)))
    assert_equal result.sha, state["sha256"]
    assert_equal 3, state["records"]
  end

  def test_a_resync_reuses_records_on_disk_and_keeps_the_pin
    stub_listing
    stub_records
    first = sync!
    second = sync!
    assert_equal 0, second.fetched
    assert_equal 6, second.cached, "resume at the file grain"
    assert_equal first.sha, second.sha
  end

  # --- drift guards ----------------------------------------------------------

  def test_a_count_disagreeing_with_the_listed_keys_aborts_before_any_write
    stub_listing(page2: JSON.generate(JSON.parse(fixture("list-page-2.json")).merge("count" => 3466)))
    page1 = JSON.parse(fixture("list-page-1.json")).merge("count" => 3466)
    stub_request(:get, "#{HOST}/inscription/list_all_inscriptions.json?page=1")
      .to_return(status: 200, body: JSON.generate(page1))
    error = assert_raises(Nabu::AioFetch::Error) { sync! }
    assert_match(/count=3466/, error.message)
    refute Dir.exist?(File.join(@dir, "records")), "nothing landed"
  end

  def test_a_non_json_listing_aborts
    stub_listing(page1: fixture("records/aio-3869.html"))
    error = assert_raises(Nabu::AioFetch::Error) { sync! }
    assert_match(/not JSON/, error.message)
  end

  def test_a_listing_page_without_rows_aborts
    stub_listing(page2: JSON.generate("count" => 3, "inscriptions" => []))
    error = assert_raises(Nabu::AioFetch::Error) { sync! }
    assert_match(/lists no inscriptions/, error.message)
  end

  def test_a_listed_404_is_censused_and_the_crawl_continues
    stub_listing
    stub_records(missing: [[2586, "html"]])
    result = sync!
    assert_equal ["AIO_2586.html"], result.missing
    assert_equal 5, result.fetched
    assert File.file?(File.join(@dir, "records", "aio-2586.json"))
  end

  def test_a_5xx_retries_then_fails_loudly
    stub_request(:get, "#{HOST}/inscription/list_all_inscriptions.json?page=1").to_return(status: 503)
    error = assert_raises(Nabu::AioFetch::Error) { sync! }
    assert_match(/503.*after 3 attempts/, error.message)
  end

  # --- retention ---------------------------------------------------------------

  def test_vanished_records_are_atticked_after_the_guard
    stub_listing
    stub_records
    sync!
    stale = File.join(@dir, "records", "aio-9999.json")
    File.write(stale, "{}")
    seen = nil
    sync!(guard: ->(doomed) { seen = doomed })
    assert_equal [stale], seen
    refute File.exist?(stale)
    assert File.file?(File.join(@attic, "records", "aio-9999.json"))
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert manifest.key?(File.join("records", "aio-9999.json"))
  end

  def test_a_raising_guard_leaves_the_tree_unchanged
    stub_listing
    stub_records
    sync!
    stale = File.join(@dir, "records", "aio-9999.json")
    File.write(stale, "{}")
    assert_raises(Nabu::FetchError) { sync!(guard: ->(_doomed) { raise Nabu::FetchError, "breaker" }) }
    assert File.file?(stale)
  end
end
