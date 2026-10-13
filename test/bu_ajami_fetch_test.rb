# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

# Nabu::BuAjamiFetch — the polite walk over the NEH Ajami WordPress site:
# REST listing → item pages → each item's ONE transcription PDF. WebMock
# only; the bodies are the real fixtures (test/fixtures/bu-ajami).
class BuAjamiFetchTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("bu-ajami")
  KLASS = Nabu::BuAjamiFetch
  ITEM_BASE = "https://sites.bu.edu/nehajami/the-four-languages"

  PAGES = {
    "hausa/falke-2729-wakar-sarkin-kano" => "files/2022/02/Falke-2729_Transcription.pdf",
    "wolof/bakk-wi" => "files/2021/07/Bàkk-wi_Transcription.pdf",
    "mandinka/mandinkakan-leetaroolu-3" => "files/2022/08/Mandinkakan-Leetaroolu-3_Transcription.pdf",
    "fula/coora" => nil # no fixture PDF: a stand-in body is served
  }.freeze

  def page_url(key)
    lang, slug = key.split("/")
    "#{ITEM_BASE}/#{lang}/#{lang}-manuscripts/#{slug}/"
  end

  def fixture(path) = File.binread(File.join(FIXTURES, path))

  def stub_listing(total: 2)
    (1..total).each do |n|
      stub_request(:get, KLASS.list_url(n))
        .to_return(status: 200, body: fixture("rest/pages-#{n}.json"),
                   headers: { "Content-Type" => "application/json", "X-WP-TotalPages" => total.to_s })
    end
  end

  def pdf_url(key)
    href = Nabu::Adapters::BuAjamiItemParser.parse_file(File.join(FIXTURES, "items", "#{key}.html")).transcription_href
    KLASS.request_url(href)
  end

  def stub_items(keys = PAGES.keys)
    keys.each do |key|
      stub_request(:get, page_url(key)).to_return(status: 200, body: fixture("items/#{key}.html"))
      body = fixture(PAGES[key] || PAGES.values.first)
      stub_request(:get, pdf_url(key)).to_return(status: 200, body: body)
    end
  end

  def sync(dir) = KLASS.sync!(dir: dir, delay: 0)

  def test_lands_every_listed_item_page_and_its_transcription_pdf
    stub_listing
    stub_items
    Dir.mktmpdir do |dir|
      result = sync(dir)
      assert_equal 4, result.listed, "the two non-item pages of the listing are not items"
      assert_equal [4, 4, 4], [result.pages_fetched, result.pdfs_fetched, result.held]
      assert_empty result.failed
      assert_match(/\A\h{64}\z/, result.sha)
      assert_equal fixture("items/wolof/bakk-wi.html"), File.binread(File.join(dir, "items/wolof/bakk-wi.html"))
      assert File.file?(File.join(dir, "files/2022/02/Falke-2729_Transcription.pdf"))
      state = JSON.parse(File.read(File.join(dir, KLASS::STATE_FILE)))["items"]
      assert_equal "2025-03-28T11:38:34", state.dig("wolof/bakk-wi", "modified")
    end
  end

  def test_an_nfd_href_is_requested_by_its_own_bytes_and_held_under_the_nfc_name
    assert_equal "https://sites.bu.edu/nehajami/files/2021/07/Ba%CC%80kk-wi_Transcription.pdf",
                 KLASS.request_url("/nehajami/files/2021/07/Bàkk-wi_Transcription.pdf")
    stub_listing
    stub_items
    Dir.mktmpdir do |dir|
      sync(dir)
      held = Dir.children(File.join(dir, "files/2021/07"))
      assert_equal(["Bàkk-wi_Transcription.pdf"], held.map { |name| name.unicode_normalize(:nfc) })
      assert File.file?(File.join(dir, "files/2021/07/Bàkk-wi_Transcription.pdf"))
    end
  end

  def test_an_unchanged_item_is_never_requested_again
    stub_listing
    stub_items
    Dir.mktmpdir do |dir|
      sync(dir)
      WebMock.reset!
      stub_listing
      result = sync(dir)
      assert_equal [0, 0, 4], [result.pages_fetched, result.pdfs_fetched, result.held]
      assert_not_requested :get, %r{/the-four-languages/}
      assert_not_requested :get, %r{/nehajami/files/}
    end
  end

  def test_a_changed_modified_stamp_refetches_the_page_but_not_a_held_pdf
    stub_listing
    stub_items
    Dir.mktmpdir do |dir|
      sync(dir)
      state_path = File.join(dir, KLASS::STATE_FILE)
      state = JSON.parse(File.read(state_path))
      state["items"]["wolof/bakk-wi"]["modified"] = "2022-01-01T00:00:00"
      File.write(state_path, JSON.generate(state))
      WebMock.reset!
      stub_listing
      stub_request(:get, page_url("wolof/bakk-wi")).to_return(status: 200, body: fixture("items/wolof/bakk-wi.html"))
      result = sync(dir)
      assert_equal [1, 0], [result.pages_fetched, result.pdfs_fetched]
    end
  end

  def test_a_busy_server_is_retried
    stub_listing
    stub_items(PAGES.keys - ["hausa/falke-2729-wakar-sarkin-kano"])
    key = "hausa/falke-2729-wakar-sarkin-kano"
    stub_request(:get, page_url(key)).to_return({ status: 503 }, { status: 503 },
                                                { status: 200, body: fixture("items/#{key}.html") })
    stub_request(:get, pdf_url(key)).to_return(status: 200, body: fixture(PAGES[key]))
    Dir.mktmpdir do |dir|
      assert_equal 4, sync(dir).held
    end
  end

  def test_an_unreachable_item_is_reported_and_the_rest_lands
    stub_listing
    stub_items(PAGES.keys - ["mandinka/mandinkakan-leetaroolu-3"])
    stub_request(:get, page_url("mandinka/mandinkakan-leetaroolu-3")).to_return(status: 503)
    Dir.mktmpdir do |dir|
      result = sync(dir)
      assert_equal ["mandinka/mandinkakan-leetaroolu-3"], result.failed
      assert_equal 3, result.held
      refute File.exist?(File.join(dir, "items/mandinka/mandinkakan-leetaroolu-3.html"))
    end
  end

  def test_a_failing_listing_aborts_before_any_write
    stub_request(:get, KLASS.list_url(1)).to_return(status: 500)
    Dir.mktmpdir do |dir|
      target = File.join(dir, "bu-ajami")
      assert_raises(KLASS::Error) { sync(target) }
      refute Dir.exist?(target)
    end
  end

  def test_a_listing_without_item_pages_is_an_error
    stub_request(:get, KLASS.list_url(1))
      .to_return(status: 200, body: '[{"id":1,"slug":"about","link":"https://sites.bu.edu/nehajami/about/"}]',
                 headers: { "X-WP-TotalPages" => "1" })
    Dir.mktmpdir do |dir|
      error = assert_raises(KLASS::Error) { sync(dir) }
      assert_match(/names no manuscript item page/, error.message)
    end
  end

  def test_a_transcription_href_outside_the_files_tree_is_refused
    assert_raises(KLASS::Error) { KLASS.local_pdf_path("/tmp/x", "/elsewhere/a.pdf") }
    assert_raises(KLASS::Error) { KLASS.local_pdf_path("/tmp/x", "/nehajami/files/../a.pdf") }
  end
end
