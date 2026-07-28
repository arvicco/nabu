# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::OtdoFetch (P48-5): the polite page-manifest crawl for Old Tibetan
# Documents Online — one stateless catalog GET (/archives, a numbered table
# with one datatxt[] checkbox per document) plus per-slug page GETs
# (/archives?p=<slug>). The ElephantineFetch mold: prepare! (catalog only,
# live tree untouched) → guard (mass-deletion breaker) → complete! (attic
# the vanished, crawl the missing pages skip-on-disk, land the catalog
# sidecar, pin the ledger).
#
# The count-assertion defense (census 2026-07-28): the catalog table numbers
# its rows 1..N — extracted unique slugs MUST equal both the row count and
# the highest row number, or the sync aborts loudly before any write.
#
# Fixtures are REAL: fetch/archives-6rows.html is the live /archives page
# with rows 7..414 spliced out (numbers 1..6 intact), and the truncated
# variant splices rows 2-3 out of it (4 rows under a top number of 6) — see
# test/fixtures/otdo/README.md. No network: WebMock throughout.
class OtdoFetchTest < Minitest::Test
  BASE = "https://otdo.example"
  CATALOG_URL = "#{BASE}/archives".freeze
  FIXTURES = Nabu::TestSupport.fixtures("otdo")

  # The six slugs of the trimmed catalog, in page order (the real first six
  # rows of the 2026-07-28 census).
  ROW_SLUGS = %w[Pt_0016 Pt_0037 Pt_0126 Pt_0149 Pt_0239 Pt_0366].freeze

  def setup
    @root = Dir.mktmpdir("otdo-fetch-test")
    @dir = File.join(@root, "otdo")
    @attic = File.join(@dir, ".attic")
    @catalog = File.read(File.join(FIXTURES, "fetch", "archives-6rows.html"))
  end

  def teardown
    FileUtils.remove_entry(@root)
    super # webmock/minitest resets the request registry via aliased teardown
  end

  def stub_catalog(body = @catalog)
    stub_request(:get, CATALOG_URL)
      .to_return(status: 200, body: body, headers: { "Content-Type" => "text/html; charset=UTF-8" })
  end

  def stub_pages
    ROW_SLUGS.each do |slug|
      stub_request(:get, "#{BASE}/archives?p=#{slug}")
        .to_return(status: 200, body: "<html><h2>#{slug}</h2></html>",
                   headers: { "Content-Type" => "text/html; charset=UTF-8" })
    end
  end

  def sync!(guard: nil)
    Nabu::OtdoFetch.sync!(base_url: BASE, dir: @dir, attic_dir: @attic,
                          delay: 0, guard: guard)
  end

  # --- URL construction ------------------------------------------------------

  def test_record_url_percent_encodes_the_apostrophe_slugs
    assert_equal "#{BASE}/archives?p=insc_%27Bis2",
                 Nabu::OtdoFetch.record_url(BASE, "insc_'Bis2"),
                 "the catalog escapes apostrophe slugs as &#039;; the GET needs %27"
    assert_equal "#{BASE}/archives?p=Pt_1287", Nabu::OtdoFetch.record_url(BASE, "Pt_1287")
  end

  def test_record_predicate_excludes_the_catalog_sidecar
    assert Nabu::OtdoFetch.record?("Pt_1287.html")
    assert Nabu::OtdoFetch.record?("insc_'Bis2.html")
    refute Nabu::OtdoFetch.record?(Nabu::OtdoFetch::ARCHIVES_FILE),
           "the persisted catalog matches the filename shape but is never a record"
    refute Nabu::OtdoFetch.record?(Nabu::OtdoFetch::STATE_FILE)
  end

  # --- the happy path --------------------------------------------------------

  def test_sync_lands_catalog_pages_and_ledger
    stub_catalog
    stub_pages
    result = sync!
    assert_equal 6, result.manifest_count
    assert_equal 6, result.records
    assert_equal 6, result.fetched
    assert_equal 0, result.cached
    ROW_SLUGS.each do |slug|
      assert File.file?(File.join(@dir, "#{slug}.html")), "#{slug}.html lands under its slug filename"
    end
    assert File.file?(File.join(@dir, Nabu::OtdoFetch::ARCHIVES_FILE)),
           "the catalog HTML persists in canonical — it doubles as a metadata sidecar"
    state = JSON.parse(File.read(File.join(@dir, Nabu::OtdoFetch::STATE_FILE)))
    assert_equal 6, state["manifest_count"]
    assert_equal result.sha, state["sha256"]
  end

  def test_sync_sha_is_stable_across_a_recrawl_and_ignores_the_catalog_sidecar
    stub_catalog
    stub_pages
    first = sync!
    # The live app stamps a fresh CSRF token into every page body — the
    # sidecar is excluded from the pin, and cached records are not refetched,
    # so a re-sync of an unchanged corpus pins identically.
    stub_catalog(@catalog.sub(/name="_token" value="[^"]*"/, 'name="_token" value="fresh-session"'))
    second = sync!
    assert_equal first.sha, second.sha
    assert_equal 6, second.cached, "a re-sync re-fetches no page"
    assert_equal 0, second.fetched
  end

  # --- the count-assertion defense ------------------------------------------

  def test_truncated_catalog_aborts_loudly_before_any_write
    stub_catalog(File.read(File.join(FIXTURES, "fetch", "archives-truncated.html")))
    error = assert_raises(Nabu::OtdoFetch::Error) { sync! }
    assert_match(/4 document slugs/, error.message, "the defense names the extracted slug count")
    assert_match(/numbered up to 6/, error.message, "and the page's own top row number")
    refute Dir.exist?(@dir) && !Dir.empty?(@dir), "no write happened"
  end

  def test_catalog_without_content_rows_aborts_loudly
    stub_catalog("<html><body>maintenance</body></html>")
    error = assert_raises(Nabu::OtdoFetch::Error) { sync! }
    assert_match(/TRUNCATED or reshaped/, error.message)
  end

  # --- resume (skip-on-disk) -------------------------------------------------

  def test_pages_already_on_disk_are_not_refetched
    stub_catalog
    stub_pages
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "Pt_0016.html"), "<html>already here</html>")
    result = sync!
    assert_equal 1, result.cached
    assert_equal 5, result.fetched
    assert_not_requested :get, "#{BASE}/archives?p=Pt_0016"
  end

  # --- retention (attic + guard) ---------------------------------------------

  def test_page_no_longer_in_the_catalog_is_atticked_not_deleted
    stub_catalog
    stub_pages
    FileUtils.mkdir_p(@dir)
    vanished = File.join(@dir, "Pt_9999.html")
    File.write(vanished, "<html>gone upstream</html>")
    seen = nil
    result = sync!(guard: ->(doomed) { seen = doomed })
    assert_equal [vanished], seen, "the guard sees the doomed path BEFORE any mutation"
    refute File.exist?(vanished)
    attic_copy = File.join(@attic, "Pt_9999.html")
    assert File.file?(attic_copy)
    assert_equal "<html>gone upstream</html>", File.read(attic_copy)
    assert_equal ["Pt_9999.html"], result.atticked
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert manifest.key?("Pt_9999.html")
  end

  def test_a_raising_guard_aborts_with_the_tree_byte_unchanged
    stub_catalog
    FileUtils.mkdir_p(@dir)
    vanished = File.join(@dir, "Pt_9999.html")
    File.write(vanished, "<html>gone upstream</html>")
    assert_raises(Nabu::SyncAborted) do
      sync!(guard: lambda { |_doomed|
        raise Nabu::SyncAborted.new(existing_count: 1, would_withdraw_count: 1, threshold: 0.2)
      })
    end
    assert File.file?(vanished), "the doomed file survives an aborted sync"
    assert_equal ["Pt_9999.html"], Dir.children(@dir), "nothing else was written"
  end

  # --- anomalies -------------------------------------------------------------

  # The P47-i1 lesson, inherited by design: a catalog-promised page that
  # 404s is upstream damage to CENSUS — record the slug, skip, keep
  # crawling, report in the sync tail. Only a SYSTEMIC miss rate aborts.
  def test_a_404_on_a_catalog_slug_is_censused_and_the_crawl_continues
    stub_catalog
    stub_pages
    stub_request(:get, "#{BASE}/archives?p=Pt_0126").to_return(status: 404)
    result = sync!
    assert_equal ["Pt_0126"], result.missing, "the hole is censused by slug"
    assert_equal 5, result.fetched, "every other page still lands"
    refute File.exist?(File.join(@dir, "Pt_0126.html")), "no file is written for a missing page"
  end

  def test_a_systemic_miss_rate_still_aborts
    stub_catalog
    # Every page 404s — the URL scheme or catalog is broken, not one hole.
    stub_request(:get, %r{#{BASE}/archives\?p=.+}).to_return(status: 404)
    error = assert_raises(Nabu::OtdoFetch::Error) { sync! }
    assert_match(/systemic/i, error.message)
    assert_match(/6 of 6/, error.message, "the abort names the miss rate")
  end

  # P47-i2, inherited: transport-level failures (a dropped TLS handshake)
  # retry with the same backoff as 5xx statuses.
  def test_a_transport_error_is_retried_with_backoff_then_succeeds
    stub_catalog
    stub_pages
    stub_request(:get, "#{BASE}/archives?p=Pt_0016")
      .to_raise(Faraday::ConnectionFailed.new("SSL_connect returned=1 errno=0 state=error: " \
                                              "unexpected eof while reading"))
      .then.to_return(status: 200, body: "<html><h2>Pt_0016</h2></html>")
    result = sync!
    assert_equal 6, result.fetched, "one dropped handshake never kills the crawl"
  end

  def test_a_persistent_transport_error_is_fatal_after_the_retry_ceiling
    stub_catalog
    stub_pages
    stub_request(:get, "#{BASE}/archives?p=Pt_0016")
      .to_raise(Faraday::ConnectionFailed.new("unexpected eof while reading"))
    error = assert_raises(Nabu::OtdoFetch::Error) { sync! }
    assert_match(/attempts/, error.message, "the ceiling is named — persistent failure stays loud")
  end

  def test_a_5xx_is_retried_with_backoff_then_succeeds
    stub_catalog
    stub_pages
    stub_request(:get, "#{BASE}/archives?p=Pt_0016")
      .to_return({ status: 503 }, { status: 200, body: "<html><h2>Pt_0016</h2></html>" })
    result = sync!
    assert_equal 6, result.fetched
    assert_requested :get, "#{BASE}/archives?p=Pt_0016", times: 2
  end

  def test_a_persistent_5xx_exhausts_the_retries_and_aborts
    stub_catalog
    stub_pages
    stub_request(:get, "#{BASE}/archives?p=Pt_0016").to_return(status: 503)
    error = assert_raises(Nabu::OtdoFetch::Error) { sync! }
    assert_match(/503/, error.message)
    assert_requested :get, "#{BASE}/archives?p=Pt_0016",
                     times: Nabu::OtdoFetch::MAX_ATTEMPTS
  end
end
