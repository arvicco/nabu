# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::DeromFetch (P56-4): the polite collection-index crawl for the DÉRom
# Ortolang workspace — the FOURTH ElephantineFetch/OtdoFetch/CantigasFetch
# HTML-crawl sibling (the extraction signal those classes flag; still not
# smuggled into a new-source change). Five OPEN collection listings under
# the content API's `latest` root enumerate the article XMLs; collections 4
# and 7 are auth-gated upstream (HTTP 303 → Keycloak) and deliberately
# absent. prepare! (listings only, live tree untouched) → guard
# (mass-deletion breaker) → complete! (attic the vanished, download the
# missing skip-on-disk, pin the ledger).
#
# Defenses pinned here: a listing without the "Index of" shape or without a
# single .xml href (what an auth-gate or SPA reshape serves) aborts BEFORE
# any write; a downloaded body that is not XML (a login page landing where
# an article should be) is fatal; 5xx retries then fails loudly; a listed
# 404 is fatal immediately (the Ortolang archive serves consistent
# listings — a hole is real breakage, never censused away).
#
# Fixtures are REAL trimmed listings (fetch/listing-*.html) and the real
# Keycloak page (fetch/auth-gate.html) — see test/fixtures/derom/README.md.
class DeromFetchTest < Minitest::Test
  BASE = "https://repository.ortolang.example/api/content/derom/latest"
  FIXTURES = Nabu::TestSupport.fixtures("derom")
  COLLECTION_1 = "1 Fichiers XML articles DERom 1"

  def setup
    @root = Dir.mktmpdir("derom-fetch-test")
    @dir = File.join(@root, "derom")
    @attic = File.join(@dir, ".attic")
    @xml_body = File.binread(
      File.join(FIXTURES, "6 Fichiers XML articles potiches en attente", "'al-a.xml")
    )
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def stub_listings(overrides = {})
    { "1 Fichiers XML articles DERom 1" => "listing-1.html",
      "2 Fichiers XML articles DERom 2" => "listing-2.html",
      "3 Fichiers XML articles DERom 3" => "listing-3.html",
      "5 Fichiers XML articles de renvoi a Mertens 2021" => "listing-5.html",
      "6 Fichiers XML articles potiches en attente" => "listing-6.html" }.each do |collection, fixture|
      body = overrides.fetch(collection) { File.binread(File.join(FIXTURES, "fetch", fixture)) }
      stub_request(:get, Nabu::DeromFetch.collection_url(BASE, collection))
        .to_return(status: 200, body: body, headers: { "Content-Type" => "text/html" })
    end
  end

  def stub_records
    stub_request(:get, %r{#{Regexp.escape(BASE)}/.+\.xml\z})
      .to_return(status: 200, body: @xml_body, headers: { "Content-Type" => "application/xml" })
  end

  def sync!(guard: nil)
    Nabu::DeromFetch.sync!(base_url: BASE, dir: @dir, attic_dir: @attic, delay: 0, guard: guard)
  end

  def test_collections_are_the_five_open_ones
    assert_equal 5, Nabu::DeromFetch::COLLECTIONS.size
    assert_includes Nabu::DeromFetch::COLLECTIONS, COLLECTION_1
    refute Nabu::DeromFetch::COLLECTIONS.any? { |c| c.include?("anglais") },
           "collections 4 and 7 are auth-gated upstream — never enumerated"
  end

  def test_collection_url_percent_encodes_the_segment
    url = Nabu::DeromFetch.collection_url(BASE, COLLECTION_1)
    assert_equal "#{BASE}/1%20Fichiers%20XML%20articles%20DERom%201", url
    record = Nabu::DeromFetch.record_url(BASE, COLLECTION_1, "'lakt-e.xml")
    assert_equal "#{BASE}/1%20Fichiers%20XML%20articles%20DERom%201/%27lakt-e.xml", record
  end

  def test_sync_lands_records_under_their_collection_dirs_and_pins_the_ledger
    stub_listings
    stub_records
    result = sync!
    assert_equal 6, result.fetched
    assert_equal 0, result.cached
    assert_equal 6, result.manifest_count
    assert_match(/\A\h{64}\z/, result.sha)
    assert File.file?(File.join(@dir, COLLECTION_1, "'lakt-e.xml"))
    assert File.file?(File.join(@dir, Nabu::DeromFetch::STATE_FILE))
  end

  def test_a_second_sync_is_resume_at_the_file_grain
    stub_listings
    stub_records
    sync!
    result = sync!
    assert_equal 0, result.fetched
    assert_equal 6, result.cached
  end

  def test_records_no_listing_names_are_atticked_then_deleted
    stub_listings
    stub_records
    FileUtils.mkdir_p(File.join(@dir, COLLECTION_1))
    doomed = File.join(@dir, COLLECTION_1, "vanished.xml")
    File.write(doomed, "<?xml version=\"1.0\"?><DERom/>")
    seen = nil
    result = sync!(guard: ->(paths) { seen = paths })
    assert_equal [doomed], seen, "the breaker sees the doomed set between prepare! and complete!"
    refute File.exist?(doomed)
    assert File.file?(File.join(@attic, COLLECTION_1, "vanished.xml"))
    assert_equal ["#{COLLECTION_1}/vanished.xml"], result.atticked
  end

  def test_an_auth_gated_listing_aborts_before_any_write
    stub_listings("2 Fichiers XML articles DERom 2" =>
      File.binread(File.join(FIXTURES, "fetch", "auth-gate.html")))
    error = assert_raises(Nabu::DeromFetch::Error) { sync! }
    assert_match(/auth-gated or reshaped/, error.message)
    refute Dir.exist?(@dir), "abort with the tree untouched"
  end

  def test_a_non_xml_record_body_is_fatal
    stub_listings
    stub_request(:get, %r{#{Regexp.escape(BASE)}/.+\.xml\z})
      .to_return(status: 200, body: File.binread(File.join(FIXTURES, "fetch", "auth-gate.html")),
                 headers: { "Content-Type" => "text/html" })
    error = assert_raises(Nabu::DeromFetch::Error) { sync! }
    assert_match(/not XML/, error.message)
  end

  def test_a_persistent_5xx_fails_loudly_after_retries
    stub_listings
    stub_request(:get, %r{#{Regexp.escape(BASE)}/.+\.xml\z}).to_return(status: 503)
    error = assert_raises(Nabu::DeromFetch::Error) { sync! }
    assert_match(/HTTP 503/, error.message)
    assert_match(/attempts/, error.message)
  end

  def test_a_listed_404_is_fatal_never_censused
    stub_listings
    stub_request(:get, %r{#{Regexp.escape(BASE)}/.+\.xml\z}).to_return(status: 404)
    error = assert_raises(Nabu::DeromFetch::Error) { sync! }
    assert_match(/404/, error.message)
  end
end
