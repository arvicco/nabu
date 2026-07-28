# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::ElephantineFetch (P47-1): the polite id-manifest crawl for the Berlin
# Elephantine database — an upstream that is neither a git repo nor a zip nor
# an API, but ONE session-stateful POST listing (objects/index.php,
# showresults=15000) plus a static per-id TEI file tree
# (/xml/elephantine_erc_db_<ID6>.tei.xml, ID6 zero-padded — unpadded 404s).
# The TitusFetch mold: prepare! (manifest only, live tree untouched) → guard
# (mass-deletion breaker on ids the manifest no longer lists) → complete!
# (attic the vanished, crawl the missing records skip-on-disk, land the
# listing + the four authority files, pin the ledger).
#
# The session-truncation defense (census 2026-07-26): the listing POST is
# session-stateful, so a stale filter would silently truncate the id set. The
# page's own "N Results" header is the cross-check — extracted unique ids
# MUST equal it, or the sync aborts loudly before any write.
#
# Fixtures are REAL: objects-listing-marriage.html is the same POST filtered
# to searchtext=marriage (23 Results, 23 rows), and the truncated variant is
# a documented row-trim of it (8 rows under the untouched 23-header) — see
# test/fixtures/elephantine/README.md. No network: WebMock throughout.
class ElephantineFetchTest < Minitest::Test
  BASE = "https://elephantine.example"
  OBJECTS_URL = "#{BASE}/objects/index.php".freeze
  FIXTURES = Nabu::TestSupport.fixtures("elephantine")

  # The 23 object ids of the marriage listing, as the page prints them
  # (unpadded — 2881 is the 4-digit exemplar).
  MARRIAGE_IDS = %w[
    2881 100275 100349 100351 100449 100461 100473 307138 307361 307762
    307763 308116 308130 308137 308159 310339 310340 310493 312146 312155
    312156 312158 312159
  ].freeze

  def setup
    @root = Dir.mktmpdir("elephantine-fetch-test")
    @dir = File.join(@root, "elephantine")
    @attic = File.join(@dir, ".attic")
    @listing = File.read(File.join(FIXTURES, "objects-listing-marriage.html"))
  end

  def teardown
    FileUtils.remove_entry(@root)
    super # webmock/minitest resets the request registry via aliased teardown
  end

  def stub_listing(body = @listing)
    stub_request(:post, OBJECTS_URL)
      .with(body: "showresults=15000")
      .to_return(status: 200, body: body, headers: { "Content-Type" => "text/html" })
  end

  def stub_records
    stub_request(:get, %r{#{BASE}/xml/elephantine_erc_db_\d{6}\.tei\.xml})
      .to_return(status: 200, body: "<TEI/>",
                 headers: { "Content-Type" => "application/xml",
                            "Last-Modified" => "Thu, 24 Nov 2022 19:20:17 GMT" })
  end

  def stub_authorities
    Nabu::ElephantineFetch::AUTHORITY_FILES.each do |name|
      stub_request(:get, "#{BASE}/xml/#{name}")
        .to_return(status: 200, body: "<TEI/>", headers: { "Content-Type" => "application/xml" })
    end
  end

  def sync!(guard: nil)
    Nabu::ElephantineFetch.sync!(base_url: BASE, dir: @dir, attic_dir: @attic,
                                 delay: 0, guard: guard)
  end

  # --- URL construction ------------------------------------------------------

  def test_record_url_zero_pads_the_id_to_six_digits
    assert_equal "#{BASE}/xml/elephantine_erc_db_000331.tei.xml",
                 Nabu::ElephantineFetch.record_url(BASE, "331"),
                 "the unpadded URL 404s upstream — ID6 padding is load-bearing"
    assert_equal "#{BASE}/xml/elephantine_erc_db_800112.tei.xml",
                 Nabu::ElephantineFetch.record_url(BASE, "800112")
  end

  # --- the happy path --------------------------------------------------------

  def test_sync_lands_manifest_records_authorities_and_ledger
    stub_listing
    stub_records
    stub_authorities
    result = sync!
    assert_equal 23, result.manifest_count
    assert_equal 23, result.records
    assert_equal 23, result.fetched
    assert_equal 0, result.cached
    assert File.file?(File.join(@dir, "elephantine_erc_db_002881.tei.xml")),
           "the 4-digit id 2881 lands under its zero-padded filename"
    assert_requested :get, "#{BASE}/xml/elephantine_erc_db_002881.tei.xml"
    MARRIAGE_IDS.each do |id|
      assert File.file?(File.join(@dir, "elephantine_erc_db_#{id.rjust(6, '0')}.tei.xml"))
    end
    Nabu::ElephantineFetch::AUTHORITY_FILES.each do |name|
      assert File.file?(File.join(@dir, name)), "authority file #{name} fetched beside the records"
    end
    assert File.file?(File.join(@dir, Nabu::ElephantineFetch::OBJECTS_FILE)),
           "the listing HTML persists in canonical — it doubles as a metadata sidecar"
    state = JSON.parse(File.read(File.join(@dir, Nabu::ElephantineFetch::STATE_FILE)))
    assert_equal 23, state["manifest_count"]
    assert_equal result.sha, state["sha256"]
  end

  def test_sync_sha_is_stable_across_a_byte_identical_recrawl
    stub_listing
    stub_records
    stub_authorities
    first = sync!
    second = sync!
    assert_equal first.sha, second.sha
    assert_equal 23, second.cached, "a re-sync of a frozen upstream re-fetches no record"
    assert_equal 0, second.fetched
  end

  # --- the session-truncation defense ---------------------------------------

  def test_truncated_listing_aborts_loudly_before_any_write
    stub_listing(File.read(File.join(FIXTURES, "objects-listing-truncated.html")))
    error = assert_raises(Nabu::ElephantineFetch::Error) { sync! }
    assert_match(/23 Results/, error.message, "the defense names the header count")
    assert_match(/8/, error.message, "and the extracted id count")
    assert_match(/session/i, error.message, "and points at the session-stateful cause")
    refute Dir.exist?(@dir) && !Dir.empty?(@dir), "no write happened"
  end

  def test_listing_without_a_results_header_aborts_loudly
    stub_listing("<html><body>maintenance</body></html>")
    error = assert_raises(Nabu::ElephantineFetch::Error) { sync! }
    assert_match(/Results/, error.message)
  end

  # --- resume (skip-on-disk, the frozen-export posture) ----------------------

  def test_records_already_on_disk_are_not_refetched
    stub_listing
    stub_records
    stub_authorities
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "elephantine_erc_db_002881.tei.xml"), "<TEI/>")
    result = sync!
    assert_equal 1, result.cached
    assert_equal 22, result.fetched
    assert_not_requested :get, "#{BASE}/xml/elephantine_erc_db_002881.tei.xml"
  end

  # --- retention (attic + guard) ---------------------------------------------

  def test_record_no_longer_in_the_manifest_is_atticked_not_deleted
    stub_listing
    stub_records
    stub_authorities
    FileUtils.mkdir_p(@dir)
    vanished = File.join(@dir, "elephantine_erc_db_999999.tei.xml")
    File.write(vanished, "<TEI>gone upstream</TEI>")
    seen = nil
    result = sync!(guard: ->(doomed) { seen = doomed })
    assert_equal [vanished], seen, "the guard sees the doomed path BEFORE any mutation"
    refute File.exist?(vanished)
    attic_copy = File.join(@attic, "elephantine_erc_db_999999.tei.xml")
    assert File.file?(attic_copy)
    assert_equal "<TEI>gone upstream</TEI>", File.read(attic_copy)
    assert_equal ["elephantine_erc_db_999999.tei.xml"], result.atticked
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert manifest.key?("elephantine_erc_db_999999.tei.xml")
  end

  def test_a_raising_guard_aborts_with_the_tree_byte_unchanged
    stub_listing
    FileUtils.mkdir_p(@dir)
    vanished = File.join(@dir, "elephantine_erc_db_999999.tei.xml")
    File.write(vanished, "<TEI>gone upstream</TEI>")
    assert_raises(Nabu::SyncAborted) do
      sync!(guard: lambda { |_doomed|
        raise Nabu::SyncAborted.new(existing_count: 1, would_withdraw_count: 1, threshold: 0.2)
      })
    end
    assert File.file?(vanished), "the doomed file survives an aborted sync"
    assert_equal ["elephantine_erc_db_999999.tei.xml"], Dir.children(@dir),
                 "nothing else was written"
  end

  # --- anomalies -------------------------------------------------------------

  # P47-i1 (owner live incident 2026-07-27: the first real crawl died at
  # record 3,905/10,744 on id 311131 — 404 on BOTH the TEI and its object
  # page, an upstream DB row the live-generated listing still promises).
  # A LONE hole is upstream damage to CENSUS, never a reason to abort a
  # 3-hour polite crawl: record the id, skip, keep crawling, report in the
  # sync tail. Only a SYSTEMIC miss rate (the URL scheme broke, the export
  # moved) aborts.
  def test_a_404_on_a_manifest_id_is_censused_and_the_crawl_continues
    stub_listing
    stub_records
    stub_authorities
    stub_request(:get, "#{BASE}/xml/elephantine_erc_db_002881.tei.xml").to_return(status: 404)
    result = sync!
    assert_equal ["002881"], result.missing, "the hole is censused by padded id"
    assert_equal 22, result.fetched, "every other record still lands"
    refute File.exist?(File.join(@dir, "elephantine_erc_db_002881.tei.xml")),
           "no file is written for a missing record"
  end

  def test_a_systemic_miss_rate_still_aborts
    stub_listing
    stub_authorities
    # Every record 404s — the URL scheme or export is broken, not one hole.
    stub_request(:get, %r{#{BASE}/xml/elephantine_erc_db_\d{6}\.tei\.xml})
      .to_return(status: 404)
    error = assert_raises(Nabu::ElephantineFetch::Error) { sync! }
    assert_match(/systemic/i, error.message)
    assert_match(/23 of 23/, error.message, "the abort names the miss rate")
  end

  def test_a_404_on_an_authority_file_stays_hard
    stub_listing
    stub_records
    stub_authorities
    stub_request(:get, "#{BASE}/xml/elephantine_erc_db_places.tei.xml").to_return(status: 404)
    error = assert_raises(Nabu::ElephantineFetch::Error) { sync! }
    assert_match(/places/, error.message,
                 "the four authority files are known-present — absence is real breakage")
  end

  # P47-i2 (owner live incident 2026-07-27, second crawl attempt: an SSL
  # "unexpected eof" at record ~9,900/10,744 aborted the run — only 5xx
  # STATUSES retried; transport-level failures bypassed the backoff). A
  # dropped TLS handshake on request nine-thousand-odd of a 3-hour polite
  # crawl is transient by nature: same retry ceiling, same backoff.
  def test_a_transport_error_is_retried_with_backoff_then_succeeds
    stub_listing
    stub_records
    stub_authorities
    stub_request(:get, "#{BASE}/xml/elephantine_erc_db_002881.tei.xml")
      .to_raise(Faraday::ConnectionFailed.new("SSL_connect returned=1 errno=0 state=error: " \
                                              "unexpected eof while reading"))
      .then.to_return(status: 200, body: "<TEI/>")
    result = sync!
    assert_equal 23, result.fetched, "one dropped handshake never kills the crawl"
  end

  def test_a_persistent_transport_error_is_fatal_after_the_retry_ceiling
    stub_listing
    stub_records
    stub_authorities
    stub_request(:get, "#{BASE}/xml/elephantine_erc_db_002881.tei.xml")
      .to_raise(Faraday::ConnectionFailed.new("unexpected eof while reading"))
    error = assert_raises(Nabu::ElephantineFetch::Error) { sync! }
    assert_match(/attempts/, error.message, "the ceiling is named — persistent failure stays loud")
  end

  def test_a_5xx_is_retried_with_backoff_then_succeeds
    stub_listing
    stub_records
    stub_authorities
    stub_request(:get, "#{BASE}/xml/elephantine_erc_db_002881.tei.xml")
      .to_return({ status: 503 }, { status: 200, body: "<TEI/>" })
    result = sync!
    assert_equal 23, result.fetched
    assert_requested :get, "#{BASE}/xml/elephantine_erc_db_002881.tei.xml", times: 2
  end

  def test_a_persistent_5xx_exhausts_the_retries_and_aborts
    stub_listing
    stub_records
    stub_authorities
    stub_request(:get, "#{BASE}/xml/elephantine_erc_db_002881.tei.xml").to_return(status: 503)
    error = assert_raises(Nabu::ElephantineFetch::Error) { sync! }
    assert_match(/503/, error.message)
    assert_requested :get, "#{BASE}/xml/elephantine_erc_db_002881.tei.xml",
                     times: Nabu::ElephantineFetch::MAX_ATTEMPTS
  end
end
