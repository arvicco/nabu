# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::StatutesRealmFetch (P160-7): the paced TOC walk + act-page crawl of
# British History Online's Statutes of the Realm. prepare! (the volume TOC
# GETs only, following each pager's rel=next; live tree untouched) → guard
# (mass-deletion breaker) → complete! (attic the vanished, land the TOC
# sidecars, crawl each ACCEPTED row's page skip-on-disk, pin the ledger).
#
# Stub bodies are the real fixture bytes under test/fixtures/statutes-realm/.
# vol5's page 0 pager links rel=next to ?page=1; the stub serves the real
# last page (vol5-page-3, whose pager has no next) in that slot, so the
# walk is two pages long here.
class StatutesRealmFetchTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/statutes-realm", __dir__)
  HOST = "https://www.british-history.ac.uk"

  def setup
    @root = Dir.mktmpdir("statutes-realm-fetch-test")
    @dir = File.join(@root, "statutes-realm")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def fixture(rel) = File.binread(File.join(FIXTURES, rel))

  def stub_toc(page0: fixture("toc/vol5-page-0.html"), page1: fixture("toc/vol5-page-3.html"))
    stub_request(:get, "#{HOST}/statutes-realm/vol5?page=0").to_return(status: 200, body: page0)
    stub_request(:get, "#{HOST}/statutes-realm/vol5?page=1").to_return(status: 200, body: page1)
  end

  def stub_pages(missing: [])
    %w[p1a pp255-259].each do |slug|
      stub = stub_request(:get, "#{HOST}/statutes-realm/vol5/#{slug}")
      if missing.include?(slug)
        stub.to_return(status: 404, body: "")
      else
        stub.to_return(status: 200, body: fixture("vol5/#{slug}.html"))
      end
    end
  end

  def sync!(guard: nil)
    Nabu::StatutesRealmFetch.sync!(dir: @dir, attic_dir: @attic, delay: 0, volumes: [5], guard: guard)
  end

  # --- URLs, filenames ------------------------------------------------------

  def test_urls_and_filenames
    assert_equal "#{HOST}/statutes-realm/vol6?page=2", Nabu::StatutesRealmFetch.toc_url(HOST, 6, 2)
    assert_equal "#{HOST}/statutes-realm/vol7/p641a", Nabu::StatutesRealmFetch.page_url(HOST, 7, "p641a")
    assert_equal File.join("toc", "vol6-page-2.html"), Nabu::StatutesRealmFetch.toc_relpath(6, 2)
    assert_equal File.join("vol7", "p641a.html"), Nabu::StatutesRealmFetch.page_relpath(7, "p641a")
    assert_equal [5, 6, 7], Nabu::StatutesRealmFetch::VOLUMES, "vols 1–4 are not on BHO (404)"
  end

  def test_the_user_agent_names_the_license_and_contact
    assert_includes Nabu::StatutesRealmFetch::USER_AGENT, "Public Domain"
    assert_includes Nabu::StatutesRealmFetch::USER_AGENT, "arvicco@nabu.ac"
  end

  def test_the_crawl_is_paced_at_one_request_a_second
    assert_in_delta 1.0, Nabu::StatutesRealmFetch::DELAY
  end

  # --- the happy path -------------------------------------------------------

  def test_sync_walks_the_pager_lands_accepted_pages_sidecars_and_ledger
    stub_toc
    stub_pages
    result = sync!
    assert_equal 2, result.toc_pages
    assert_equal 6, result.rows, "every TOC row counted (5 on page 0 + 1 index row)"
    assert_equal 2, result.accepted, "the two act rows"
    assert_equal 2, result.fetched
    assert File.file?(File.join(@dir, "vol5", "p1a.html"))
    assert File.file?(File.join(@dir, "vol5", "pp255-259.html"))
    refute File.exist?(File.join(@dir, "vol5", "p1.html")), "rejected grains are never fetched"
    assert File.file?(File.join(@dir, "toc", "vol5-page-0.html"))
    assert File.file?(File.join(@dir, "toc", "vol5-page-1.html"))
    state = JSON.parse(File.read(File.join(@dir, Nabu::StatutesRealmFetch::STATE_FILE)))
    assert_equal result.sha, state["sha256"]
    assert_equal 2, state["accepted"]
  end

  def test_a_resync_reuses_pages_on_disk_and_keeps_the_pin
    stub_toc
    stub_pages
    first = sync!
    second = sync!
    assert_equal 0, second.fetched
    assert_equal 2, second.cached
    assert_equal first.sha, second.sha
  end

  # --- drift guards ----------------------------------------------------------

  def test_a_toc_page_without_rows_aborts_before_any_write
    stub_toc(page1: "<html><body><main><table><tbody></tbody></table></main></body></html>")
    error = assert_raises(Nabu::StatutesRealmFetch::Error) { sync! }
    assert_match(/lists no rows/, error.message)
    refute Dir.exist?(File.join(@dir, "vol5")), "nothing landed"
  end

  def test_a_listed_404_is_censused_and_the_crawl_continues
    stub_toc
    stub_pages(missing: ["pp255-259"])
    result = sync!
    assert_equal ["vol5/pp255-259"], result.missing
    assert_equal 1, result.fetched
  end

  def test_a_missing_toc_aborts
    stub_request(:get, "#{HOST}/statutes-realm/vol5?page=0").to_return(status: 404)
    error = assert_raises(Nabu::StatutesRealmFetch::Error) { sync! }
    assert_match(/404/, error.message)
  end

  def test_a_5xx_retries_then_fails_loudly
    stub_request(:get, "#{HOST}/statutes-realm/vol5?page=0").to_return(status: 503)
    error = assert_raises(Nabu::StatutesRealmFetch::Error) { sync! }
    assert_match(/503.*after 3 attempts/, error.message)
  end

  # --- retention ---------------------------------------------------------------

  def test_vanished_pages_are_atticked_after_the_guard
    stub_toc
    stub_pages
    sync!
    stale = File.join(@dir, "vol5", "p999.html")
    File.write(stale, "<html></html>")
    seen = nil
    sync!(guard: ->(doomed) { seen = doomed })
    assert_equal [stale], seen
    refute File.exist?(stale)
    assert File.file?(File.join(@attic, "vol5", "p999.html"))
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert manifest.key?(File.join("vol5", "p999.html"))
  end

  def test_a_raising_guard_leaves_the_tree_unchanged
    stub_toc
    stub_pages
    sync!
    stale = File.join(@dir, "vol5", "p999.html")
    File.write(stale, "<html></html>")
    assert_raises(Nabu::FetchError) { sync!(guard: ->(_doomed) { raise Nabu::FetchError, "breaker" }) }
    assert File.file?(stale)
  end
end
