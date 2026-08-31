# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::SealFetch (P89-3): the polite advanced-search crawl for SEAL —
# Sources of Early Akkadian Literature (seal.huji.ac.il). The CantigasFetch
# mold: prepare! (the search-page GETs only, live tree untouched) → guard
# (mass-deletion breaker) → complete! (attic the vanished, land the index
# sidecars, crawl the missing node pages skip-on-disk into texts/, pin the
# ledger). The page count comes from page 0's own pager (rel="last"), never
# a hardcoded constant.
#
# Stub bodies are the REAL captured bytes from the gitignored
# local/fixtures/seal/ (the grant forbids redistribution, so no upstream
# HTML lives in the public tree; the house rule forbids hand-written fakes)
# — every data-bearing case SKIPs when the local fixtures are absent.
# search-page0.html lists 20 texts and a last-page pager of 53;
# node-1526.html doubles as the "index page with zero rows" drift body.
class SealFetchTest < Minitest::Test
  BASE = "https://seal.example"
  SLUG = "seal"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)

  def setup
    @root = Dir.mktmpdir("seal-fetch-test")
    @dir = File.join(@root, "seal")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
    super # webmock/minitest resets the request registry via aliased teardown
  end

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (personal-research grant forbids redistribution)"
  end

  def index_bytes
    @index_bytes ||= File.binread(File.join(FIXTURES, "search-page0.html"))
  end

  def node_bytes
    @node_bytes ||= File.binread(File.join(FIXTURES, "node-1526.html"))
  end

  # Page 0's pager promises pages 0..53; every search page serves the real
  # page-0 listing (same 20 node ids — the dedupe across pages is proven by
  # the resulting census of 20).
  def stub_indexes(body: index_bytes)
    (0..53).each do |page|
      stub_request(:get, "#{BASE}/advanced-search?page=#{page}")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "text/html" })
    end
  end

  def stub_pages
    stub_request(:get, %r{#{BASE}/node/\d+})
      .to_return(status: 200, body: node_bytes, headers: { "Content-Type" => "text/html" })
  end

  def sync!(guard: nil)
    Nabu::SealFetch.sync!(base_url: BASE, dir: @dir, attic_dir: @attic, delay: 0, guard: guard)
  end

  # --- URLs, filenames, predicates (no bytes needed — runs in CI) ------------

  def test_urls_and_filenames
    assert_equal "#{BASE}/advanced-search?page=7", Nabu::SealFetch.search_url(BASE, 7)
    assert_equal "#{BASE}/node/1526", Nabu::SealFetch.record_url(BASE, 1526),
                 "the permanent per-text URL the project promises"
    assert_equal File.join("texts", "node-1526.html"), Nabu::SealFetch.record_relpath(1526)
    assert_equal "advanced-search-page-3.html", Nabu::SealFetch.index_filename(3)
    assert Nabu::SealFetch.record?("node-1526.html")
    refute Nabu::SealFetch.record?("advanced-search-page-0.html")
    refute Nabu::SealFetch.record?(Nabu::SealFetch::STATE_FILE)
  end

  def test_the_user_agent_names_the_grant
    assert_includes Nabu::SealFetch::USER_AGENT, "Wasserman",
                    "the crawl identifies itself under the grant it fetches by"
    assert_includes Nabu::SealFetch::USER_AGENT, "arvicco@nabu.ac"
  end

  # --- the happy path --------------------------------------------------------

  def test_sync_lands_indexes_pages_and_ledger
    require_fixtures!
    stub_indexes
    stub_pages
    result = sync!
    assert_equal 54, result.pages, "page 0's pager (rel=last → page=53) sets the page count"
    assert_equal 20, result.manifest_count, "20 unique node ids per listing page, deduped across 54"
    assert_equal 20, result.fetched
    assert_equal 0, result.cached
    assert File.file?(File.join(@dir, "texts", "node-1692.html")), "min node id of the census"
    assert File.file?(File.join(@dir, "texts", "node-36163.html")), "max node id of the census"
    (0..53).each do |page|
      assert File.file?(File.join(@dir, "advanced-search-page-#{page}.html")),
             "search page #{page} persists in canonical as a discovery-census sidecar"
    end
    state = JSON.parse(File.read(File.join(@dir, Nabu::SealFetch::STATE_FILE)))
    assert_equal 20, state["manifest_count"]
    assert_equal 54, state["pages"]
    assert_equal result.sha, state["sha256"]
  end

  def test_sync_sha_ignores_the_index_sidecars
    require_fixtures!
    stub_indexes
    stub_pages
    first = sync!
    # Drupal re-renders per request; cached records are not refetched, so
    # the content pin holds across a re-sync with mutated index bytes.
    stub_request(:get, "#{BASE}/advanced-search?page=0")
      .to_return(status: 200, body: index_bytes + "<!-- fresh render -->".b)
    second = sync!
    assert_equal first.sha, second.sha, "index bytes stay out of the content pin"
    assert_equal 20, second.cached, "a re-sync re-fetches no node page"
    assert_equal 0, second.fetched
  end

  # --- shape defenses --------------------------------------------------------

  def test_a_search_page_listing_no_texts_aborts_before_any_write
    require_fixtures!
    stub_indexes(body: node_bytes) # a real SEAL page that lists nothing
    error = assert_raises(Nabu::SealFetch::Error) { sync! }
    assert_match(/page=0/, error.message, "the abort names the page")
    assert_match(/no texts/i, error.message)
    refute Dir.exist?(@dir), "no write happened"
  end

  # --- resume (skip-on-disk) -------------------------------------------------

  def test_pages_already_on_disk_are_not_refetched
    require_fixtures!
    stub_indexes
    stub_pages
    FileUtils.mkdir_p(File.join(@dir, "texts"))
    File.write(File.join(@dir, "texts", "node-7486.html"), "<html>already here</html>")
    result = sync!
    assert_equal 1, result.cached
    assert_equal 19, result.fetched
    assert_not_requested :get, "#{BASE}/node/7486"
  end

  # --- retention (attic + guard) ---------------------------------------------

  def test_page_no_longer_listed_is_atticked_not_deleted
    require_fixtures!
    stub_indexes
    stub_pages
    FileUtils.mkdir_p(File.join(@dir, "texts"))
    vanished = File.join(@dir, "texts", "node-99999.html")
    File.write(vanished, "<html>gone upstream</html>")
    seen = nil
    result = sync!(guard: ->(doomed) { seen = doomed })
    assert_equal [vanished], seen, "the guard sees the doomed path BEFORE any mutation"
    refute File.exist?(vanished)
    attic_copy = File.join(@attic, "texts", "node-99999.html")
    assert File.file?(attic_copy)
    assert_equal "<html>gone upstream</html>", File.read(attic_copy)
    assert_equal [File.join("texts", "node-99999.html")], result.atticked
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert manifest.key?(File.join("texts", "node-99999.html"))
  end

  def test_a_raising_guard_aborts_with_the_tree_byte_unchanged
    require_fixtures!
    stub_indexes
    FileUtils.mkdir_p(File.join(@dir, "texts"))
    vanished = File.join(@dir, "texts", "node-99999.html")
    File.write(vanished, "<html>gone upstream</html>")
    assert_raises(Nabu::SyncAborted) do
      sync!(guard: lambda { |_doomed|
        raise Nabu::SyncAborted.new(existing_count: 1, would_withdraw_count: 1, threshold: 0.2)
      })
    end
    assert File.file?(vanished), "the doomed file survives an aborted sync"
    assert_equal ["texts"], Dir.children(@dir), "nothing else was written"
    assert_equal ["node-99999.html"], Dir.children(File.join(@dir, "texts"))
  end

  # --- misses and failures ---------------------------------------------------

  def test_a_404_on_a_listed_node_is_censused_and_the_crawl_continues
    require_fixtures!
    stub_indexes
    stub_pages
    stub_request(:get, "#{BASE}/node/1692").to_return(status: 404)
    result = sync!
    assert_equal ["1692"], result.missing
    assert_equal 19, result.fetched
    refute File.exist?(File.join(@dir, "texts", "node-1692.html"))
  end

  def test_a_systemic_miss_rate_still_aborts
    require_fixtures!
    stub_indexes
    stub_request(:get, %r{#{BASE}/node/\d+}).to_return(status: 404)
    error = assert_raises(Nabu::SealFetch::Error) { sync! }
    assert_match(/systemic/i, error.message)
    assert_match(/20 of 20/, error.message, "the abort names the miss rate")
  end

  def test_a_500_on_a_listed_node_is_retried_then_fatal_never_censused
    require_fixtures!
    stub_indexes
    stub_pages
    stub_request(:get, "#{BASE}/node/1692").to_return(status: 500)
    error = assert_raises(Nabu::SealFetch::Error) { sync! }
    assert_match(/HTTP 500/, error.message)
    assert_match(/attempts/, error.message)
    assert_requested :get, "#{BASE}/node/1692", times: Nabu::SealFetch::MAX_ATTEMPTS
    refute File.exist?(File.join(@dir, "texts", "node-1692.html")),
           "the error body never lands as a page"
  end

  def test_a_transient_500_recovers_on_retry
    require_fixtures!
    stub_indexes
    stub_pages
    stub_request(:get, "#{BASE}/node/1692")
      .to_return({ status: 500 }, { status: 200, body: node_bytes })
    result = sync!
    assert_equal 20, result.fetched
    assert_requested :get, "#{BASE}/node/1692", times: 2
  end

  def test_a_transport_error_is_retried_with_backoff_then_succeeds
    require_fixtures!
    stub_indexes
    stub_pages
    stub_request(:get, "#{BASE}/node/1692")
      .to_raise(Faraday::ConnectionFailed.new("unexpected eof while reading"))
      .then.to_return(status: 200, body: node_bytes)
    result = sync!
    assert_equal 20, result.fetched, "one dropped handshake never kills the crawl"
  end
end
