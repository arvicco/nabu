# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::PomaFetch (P117-5): the polite page crawl for the Royal Danish
# Library's Guaman Poma edition — the OtdoFetch mold with a DERIVED
# manifest: the title page's last-page arrow (">|" → /1189/es/text/) names
# N, the table of contents must not link past it, and the crawl walks
# titlepage + 1..N, writing every page at once (resumable). The title page
# is the real fixture (test/fixtures/guaman-poma/titlepage.html); every
# other page answers a stub body. No network: WebMock throughout.
class PomaFetchTest < Minitest::Test
  BASE = "https://poma.example/permalink/2006/poma"
  FIXTURES = Nabu::TestSupport.fixtures("guaman-poma")

  def setup
    @root = Dir.mktmpdir("poma-fetch-test")
    @dir = File.join(@root, "guaman-poma")
    @attic = File.join(@dir, ".attic")
    @titlepage = File.read(File.join(FIXTURES, "titlepage.html"))
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def stub_titlepage(body = @titlepage)
    stub_request(:get, "#{BASE}/titlepage/es/text/")
      .to_return(status: 200, body: body, headers: { "Content-Type" => "text/html;charset=UTF-8" })
  end

  def stub_pages(status: 200)
    stub_request(:get, %r{\A#{Regexp.escape(BASE)}/\d+/es/text/\z})
      .to_return(status: status, body: "<html><div id=\"contentPage\"><div><p>page</p></div></div></html>")
  end

  def sync!(guard: nil)
    Nabu::PomaFetch.sync!(base_url: BASE, dir: @dir, attic_dir: @attic, delay: 0, guard: guard)
  end

  def test_page_url_and_record_shape
    assert_equal "#{BASE}/317/es/text/", Nabu::PomaFetch.page_url(BASE, "317")
    assert Nabu::PomaFetch.record?("titlepage.html")
    assert Nabu::PomaFetch.record?("1189.html")
    refute Nabu::PomaFetch.record?(Nabu::PomaFetch::STATE_FILE)
    refute Nabu::PomaFetch.record?("1189.html.tmp")
  end

  def test_the_manifest_is_the_titlepage_plus_one_to_the_last_page_arrow
    stub_titlepage
    stub_pages
    result = sync!
    assert_equal 1190, result.manifest_count, "titlepage + 1..1189 (the real arrow)"
    assert_equal 1190, result.fetched
    assert_equal 1190, result.records
    assert_equal @titlepage, File.read(File.join(@dir, "titlepage.html")), "the manifest GET lands as the title page"
    assert File.file?(File.join(@dir, "1189.html"))
    state = JSON.parse(File.read(File.join(@dir, Nabu::PomaFetch::STATE_FILE)))
    assert_equal result.sha, state["sha256"]
    assert_equal 1190, state["manifest_count"]
  end

  def test_a_resync_fetches_nothing_and_pins_identically
    stub_titlepage
    stub_pages
    first = sync!
    second = sync!
    assert_equal 0, second.fetched
    assert_equal 1190, second.cached
    assert_equal first.sha, second.sha
  end

  def test_an_interrupted_crawl_resumes_at_the_page_grain
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "1.html"), "already here")
    stub_titlepage
    stub_pages
    result = sync!
    assert_equal 1, result.cached
    assert_equal 1189, result.fetched
    assert_equal "already here", File.read(File.join(@dir, "1.html")), "a page on disk is never re-fetched"
  end

  def test_a_reshaped_navigation_aborts_before_any_write
    stub_titlepage(@titlepage.gsub(">&gt;|<", ">end<"))
    error = assert_raises(Nabu::PomaFetch::Error) { sync! }
    assert_match(/navigation is reshaped/, error.message)
    refute Dir.exist?(@dir), "no write happened"
  end

  def test_an_arrow_short_of_the_table_of_contents_aborts
    stub_titlepage(@titlepage.sub(%r{/permalink/2006/poma/1189/es/text/">&gt;\|},
                                  '/permalink/2006/poma/12/es/text/">&gt;|'))
    error = assert_raises(Nabu::PomaFetch::Error) { sync! }
    assert_match(/last-page arrow 12, highest table-of-contents page 1188/, error.message)
  end

  def test_a_lone_404_is_censused_and_the_crawl_continues
    stub_titlepage
    stub_pages
    stub_request(:get, "#{BASE}/7/es/text/").to_return(status: 404)
    result = sync!
    assert_equal ["7"], result.missing
    refute File.exist?(File.join(@dir, "7.html"))
    assert File.file?(File.join(@dir, "8.html"))
  end

  def test_a_systemic_miss_aborts
    stub_titlepage
    stub_pages(status: 404)
    assert_raises(Nabu::PomaFetch::Error) { sync! }
  end

  def test_pages_outside_the_manifest_are_atticked_behind_the_guard
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "1190.html"), "renumbered away")
    stub_titlepage
    stub_pages
    seen = nil
    result = sync!(guard: ->(doomed) { seen = doomed })
    assert_equal [File.join(@dir, "1190.html")], seen
    assert_equal ["1190.html"], result.atticked
    refute File.exist?(File.join(@dir, "1190.html"))
    assert_equal "renumbered away", File.read(File.join(@attic, "1190.html"))
  end
end
