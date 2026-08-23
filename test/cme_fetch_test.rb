# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::CmeFetch (P82-2): the polite autoindex crawl for the Corpus of
# Middle English — the FIFTH ElephantineFetch/OtdoFetch/CantigasFetch/
# DeromFetch crawl sibling (the extraction signal stands; still not smuggled
# into a new-source change). ONE Apache "Index of /texts" listing at
# medictionary.info enumerates every corpus XML (297 files, sizes and dates
# in the listing itself); records land under texts/. prepare! (the listing
# GET only, live tree untouched) → guard (mass-deletion breaker) →
# complete! (attic the vanished, download the missing skip-on-disk, pin the
# ledger).
#
# Defenses pinned here: a listing without the "Index of" shape or without a
# single .xml href (an outage page or site reshape) aborts BEFORE any
# write; a downloaded body that is not XML (an error page landing where a
# text should be) is fatal; 5xx retries then fails loudly; a listed 404 is
# fatal immediately (the autoindex lists what exists — a hole is real
# breakage, never censused away). The listing's sort links (?C=N;O=D) and
# the Parent Directory row are never harvested.
#
# The listing fixture is the REAL May-2026 autoindex trimmed to six rows —
# see test/fixtures/cme/README.md.
class CmeFetchTest < Minitest::Test
  BASE = "http://www.medictionary.example"
  FIXTURES = Nabu::TestSupport.fixtures("cme")
  LISTED = %w[3KCol.xml CME00011.xml CME00121.xml CME301.xml afz9170.xml tenwives.xml].freeze

  def setup
    @root = Dir.mktmpdir("cme-fetch-test")
    @dir = File.join(@root, "cme")
    @attic = File.join(@dir, ".attic")
    @listing = File.binread(File.join(FIXTURES, "fetch", "texts-index.html"))
    @xml_body = File.binread(File.join(FIXTURES, "texts", "CME301.xml"))
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def stub_listing(body: @listing, status: 200)
    stub_request(:get, Nabu::CmeFetch.listing_url(BASE))
      .to_return(status: status, body: body, headers: { "Content-Type" => "text/html" })
  end

  def stub_records(body: @xml_body)
    stub_request(:get, %r{#{Regexp.escape(BASE)}/texts/.+\.xml\z})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "text/xml" })
  end

  def sync!(guard: nil)
    Nabu::CmeFetch.sync!(base_url: BASE, dir: @dir, attic_dir: @attic, delay: 0, guard: guard)
  end

  def test_listing_url_is_the_texts_autoindex
    assert_equal "#{BASE}/texts/", Nabu::CmeFetch.listing_url(BASE)
    assert_equal "#{BASE}/texts/CME301.xml", Nabu::CmeFetch.record_url(BASE, "CME301.xml")
  end

  def test_sync_lands_records_under_texts_and_pins_the_ledger
    stub_listing
    stub_records
    result = sync!
    assert_equal LISTED, Dir.children(File.join(@dir, "texts")).grep(/\.xml\z/).sort
    assert_equal 6, result.fetched
    assert_equal 0, result.cached
    assert_equal 6, result.listed
    state = JSON.parse(File.read(File.join(@dir, Nabu::CmeFetch::STATE_FILE)))
    assert_equal result.sha, state["sha256"]
    assert_equal BASE, state["url"]
  end

  def test_sort_links_and_parent_directory_are_never_harvested
    stub_listing
    stub_records
    sync!
    children = Dir.children(File.join(@dir, "texts"))
    assert_empty children.grep(/\A\?/), "the ?C=N;O=D sort links are navigation, not records"
    assert_equal 6, children.grep(/\.xml\z/).size
  end

  def test_files_already_on_disk_are_not_refetched
    stub_listing
    stub_records
    sync!
    second = sync!
    assert_equal 0, second.fetched
    assert_equal 6, second.cached
  end

  def test_a_reshaped_listing_aborts_before_any_write
    stub_listing(body: "<html><body>We have moved!</body></html>")
    error = assert_raises(Nabu::CmeFetch::Error) { sync! }
    assert_match(/not a corpus autoindex/, error.message)
    refute Dir.exist?(File.join(@dir, "texts")), "abort happens before any tree write"
  end

  def test_a_non_xml_record_body_is_fatal
    stub_listing
    stub_records(body: "<html>404-ish error page</html>")
    error = assert_raises(Nabu::CmeFetch::Error) { sync! }
    assert_match(/not XML/, error.message)
  end

  def test_a_listed_404_is_fatal_immediately
    stub_listing
    stub_request(:get, %r{#{Regexp.escape(BASE)}/texts/.+\.xml\z})
      .to_return(status: 404, body: "gone")
    error = assert_raises(Nabu::CmeFetch::Error) { sync! }
    assert_match(/404/, error.message)
  end

  def test_a_5xx_retries_then_fails_loudly
    stub_listing
    stub_request(:get, %r{#{Regexp.escape(BASE)}/texts/.+\.xml\z})
      .to_return(status: 503, body: "maintenance")
    error = assert_raises(Nabu::CmeFetch::Error) { sync! }
    assert_match(/503/, error.message)
    assert_requested :get, Nabu::CmeFetch.record_url(BASE, LISTED.first),
                     times: Nabu::CmeFetch::MAX_ATTEMPTS
  end

  def test_vanished_records_are_atticked_behind_the_guard
    stub_listing
    stub_records
    sync!
    stale = File.join(@dir, "texts", "scrapped.xml")
    File.binwrite(stale, @xml_body)
    doomed = nil
    result = sync!(guard: ->(paths) { doomed = paths })
    assert_equal [stale], doomed, "the guard sees the doomed absolute paths before any mutation"
    refute File.exist?(stale)
    assert File.file?(File.join(@attic, "texts", "scrapped.xml")), "first copy wins in the attic"
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert manifest.key?("texts/scrapped.xml")
    assert_equal ["texts/scrapped.xml"], result.atticked
  end

  def test_a_raising_guard_aborts_with_the_tree_unchanged
    stub_listing
    stub_records
    sync!
    stale = File.join(@dir, "texts", "scrapped.xml")
    File.binwrite(stale, @xml_body)
    assert_raises(Nabu::SyncAborted) do
      sync!(guard: lambda { |_paths|
        raise Nabu::SyncAborted.new(existing_count: 7, would_withdraw_count: 1, threshold: 0.2)
      })
    end
    assert File.exist?(stale), "the breaker fires with the tree byte-unchanged"
    refute Dir.exist?(@attic)
  end
end
