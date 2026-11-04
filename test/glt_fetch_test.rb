# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::GltFetch: the paced conditional crawl of glt.goarch.org — the two
# index pages are the catalog, every listed texts/ page is GET-ted (once,
# then conditionally on its pinned Last-Modified), 404s are censused, and
# the LotsawaFetch attic/guard contract holds. No network: WebMock stubs.
# The real index pages ride test/adapters/glt_test.rb (the 725-page crawl
# list); these tests drive the fetch logic over minimal index bodies.
class GltFetchTest < Minitest::Test
  BASE = "https://glt.goarch.org/"
  class Breaker < Nabu::Error; end

  INDEX = <<~HTML
    <BODY><P><FONT COLOR="#008000"><U>Σεπτέμβριος</U></FONT><br/>
    <A HREF="texts/Sep/Sep01.html"><U>01</U></A>
    <A HREF="texts/Oro/Esperinos%20Sunday.html"><U>ΕΣΠΕΡΙΝΟΣ</U></A>
    <a href="daily/Mon.html"><U>Δευτέρα</U></a> <a href="daily/Mon.epub"><U>Δευτέρα.epub</U></a>
    <A HREF="texts/Euch/Funeral.rtf"><U>Κηδεία</U></A> <A HREF="misc/Psaltirion.html">ΨΑΛΤΗΡΙΟΝ</A></P></BODY>
  HTML
  EXTRA = <<~HTML
    <body><p><a href="./texts/Sep/01b.html">01β</a> <a href="./texts/Sep/Sep01.html">01</a></p></body>
  HTML

  def setup
    @root = Dir.mktmpdir("glt-fetch-test")
    @dir = File.join(@root, "glt")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def sync!(guard: nil)
    Nabu::GltFetch.sync!(dir: @dir, attic_dir: @attic, delay: 0, guard: guard)
  end

  def stub_catalog(index: INDEX, extra: EXTRA)
    stub_request(:get, "#{BASE}index.html").to_return(status: 200, body: index)
    stub_request(:get, "#{BASE}extra.htm").to_return(status: 200, body: extra)
  end

  def stub_pages(status: 200, last_modified: "Mon, 29 May 2023 23:20:56 GMT")
    %w[texts/Sep/Sep01.html texts/Oro/Esperinos%20Sunday.html texts/Sep/01b.html].each do |href|
      stub_request(:get, "#{BASE}#{href}")
        .to_return(status: status, body: "page #{href}", headers: { "Last-Modified" => last_modified })
    end
  end

  def test_fetches_the_catalog_and_every_listed_page_and_nothing_else
    stub_catalog
    stub_pages
    result = sync!

    assert_equal 3, result.listed
    assert_equal 3, result.fetched
    assert_equal "page texts/Oro/Esperinos%20Sunday.html",
                 File.read(File.join(@dir, "texts", "Oro", "Esperinos Sunday.html")), "percent-decoded on disk"
    assert File.file?(File.join(@dir, "index.html")), "the catalog pages land as provenance"
    assert File.file?(File.join(@dir, "extra.htm"))
    refute File.exist?(File.join(@dir, "daily")), "the compiled daily services are never fetched"
    refute File.exist?(File.join(@dir, "texts", "Euch", "Funeral.rtf"))
    assert_requested :get, "#{BASE}texts/Sep/Sep01.html", times: 1
    assert_not_requested :get, "#{BASE}misc/Psaltirion.html"
    assert_match(/\A[0-9a-f]{64}\z/, result.sha)
    state = JSON.parse(File.read(File.join(@dir, Nabu::GltFetch::STATE_FILE)))
    assert_equal "Mon, 29 May 2023 23:20:56 GMT", state.dig("pages", "texts/Sep/Sep01.html", "last_modified")
  end

  def test_a_resync_asks_conditionally_and_counts_304s_unchanged
    stub_catalog
    stub_pages
    first = sync!

    WebMock.reset!
    stub_catalog
    %w[texts/Sep/Sep01.html texts/Oro/Esperinos%20Sunday.html texts/Sep/01b.html].each do |href|
      stub_request(:get, "#{BASE}#{href}")
        .with(headers: { "If-Modified-Since" => "Mon, 29 May 2023 23:20:56 GMT" }).to_return(status: 304)
    end
    second = sync!
    assert_equal 0, second.fetched
    assert_equal 3, second.unchanged
    assert_equal first.sha, second.sha
    assert_equal "page texts/Sep/Sep01.html", File.read(File.join(@dir, "texts", "Sep", "Sep01.html"))
  end

  def test_a_listed_page_that_404s_is_censused_not_fatal
    stub_catalog
    stub_pages
    stub_request(:get, "#{BASE}texts/Sep/01b.html").to_return(status: 404, body: "File is waiting to be re-formatted")
    result = sync!
    assert_equal ["texts/Sep/01b.html"], result.missing
    assert_equal 2, result.fetched
    refute File.exist?(File.join(@dir, "texts", "Sep", "01b.html"))
  end

  def test_systemic_404s_abort
    index = "<body>#{(1..12).map { |n| format('<a href="texts/Sep/Sep%02d.html">x</a>', n) }.join}</body>"
    stub_catalog(index: index, extra: "<body></body>")
    stub_request(:get, %r{\A#{BASE}texts/}).to_return(status: 404)
    error = assert_raises(Nabu::GltFetch::Error) { sync! }
    assert_match(/12 of 12 listed pages 404 — a systemic miss/, error.message)
  end

  def test_an_index_without_text_links_aborts_before_any_write
    stub_catalog(index: "<body>maintenance</body>", extra: "<body></body>")
    error = assert_raises(Nabu::GltFetch::Error) { sync! }
    assert_match(%r{list no texts/ pages}, error.message)
    refute File.exist?(@dir)
  end

  def test_a_5xx_retries_then_fails
    stub_catalog
    stub_request(:get, "#{BASE}texts/Sep/Sep01.html").to_return(status: 503)
    error = assert_raises(Nabu::GltFetch::Error) { sync! }
    assert_match(/HTTP 503 .* \(after 3 attempts\)/, error.message)
    assert_requested :get, "#{BASE}texts/Sep/Sep01.html", times: 3
  end

  def test_a_delisted_page_is_atticked_after_the_guard
    stub_catalog
    stub_pages
    sync!

    WebMock.reset!
    stub_catalog(extra: "<body></body>")
    stub_pages
    seen = nil
    result = sync!(guard: ->(doomed) { seen = doomed })
    assert_equal [File.join(@dir, "texts", "Sep", "01b.html")], seen
    assert_equal ["texts/Sep/01b.html"], result.atticked
    refute File.exist?(File.join(@dir, "texts", "Sep", "01b.html"))
    assert File.file?(File.join(@attic, "texts", "Sep", "01b.html"))
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert manifest.key?("texts/Sep/01b.html")
  end

  def test_a_tripped_guard_leaves_the_tree_untouched
    stub_catalog
    stub_pages
    sync!

    WebMock.reset!
    stub_catalog(extra: "<body></body>")
    assert_raises(Breaker) { sync!(guard: ->(_doomed) { raise Breaker, "mass deletion" }) }
    assert File.file?(File.join(@dir, "texts", "Sep", "01b.html"))
  end
end
