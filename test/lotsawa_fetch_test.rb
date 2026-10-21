# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::LotsawaFetch: the paced per-language catalog crawl for Lotsawa House.
# Runs against WebMock stubs serving REAL pages (test/fixtures/lotsawa-house/
# — the listing pages are documented text-card splices, the text pages
# whole); never the network.
class LotsawaFetchTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("lotsawa-house")
  BASE = Nabu::LotsawaFetch::BASE_URL

  LISTINGS = {
    "/free-translations-tibetan-buddhist-texts" => "en-index.html",
    "/words-of-the-buddha/" => "en-wotb.html",
    "/tibetan-masters/mipham/" => "en-mipham.html",
    "/bo/free-translations-tibetan-buddhist-texts" => "bo-index.html",
    "/bo/words-of-the-buddha/" => "bo-wotb.html",
    "/bo/tibetan-masters/mipham/" => "bo-mipham.html"
  }.freeze

  TEXTS = %w[
    tibetan-masters/mipham/acala-sadhana
    tibetan-masters/mipham/instruction-on-point-of-mind
    words-of-the-buddha/amitayus-dharani
  ].freeze

  def stub_site(skip_text: nil)
    LISTINGS.each do |path, file|
      stub_request(:get, "#{BASE}#{path}")
        .to_return(status: 200, body: File.binread(File.join(FIXTURES, "fetch", file)))
    end
    %w[en bo].each do |lang|
      TEXTS.each do |path|
        url = "#{BASE}#{Nabu::LotsawaFetch.prefix(lang)}/#{path}"
        if skip_text == [lang, path]
          stub_request(:get, url).to_return(status: 404, body: "")
        else
          stub_request(:get, url).to_return(status: 200,
                                            body: File.binread(File.join(FIXTURES, "pages", lang, "#{path}.html")))
        end
      end
    end
  end

  def sync(dir, **)
    Nabu::LotsawaFetch.sync!(dir: dir, attic_dir: File.join(dir, ".attic"), languages: %w[bo en], delay: 0,
                             **)
  end

  def test_walks_explore_scripture_and_author_listings_then_lands_every_text_page
    stub_site
    Dir.mktmpdir do |dir|
      result = sync(dir)
      assert_equal 6, result.records, "3 texts listed in each of bo and en"
      assert_equal 6, result.fetched
      assert_equal 6, result.listings
      assert_empty result.missing
      TEXTS.each do |path|
        assert File.file?(File.join(dir, "pages", "bo", "#{path}.html"))
        assert File.file?(File.join(dir, "pages", "en", "#{path}.html"))
      end
      assert File.file?(File.join(dir, "catalog", "en", "tibetan-masters", "mipham.html")),
             "listing pages persist under catalog/ (provenance — the catalog grain)"
      state = JSON.parse(File.read(File.join(dir, Nabu::LotsawaFetch::STATE_FILE)))
      assert_equal({ "bo" => 3, "en" => 3 }, state["per_language"])
      assert_match(/\A\h{64}\z/, result.sha)
    end
  end

  def test_resumes_at_the_file_grain
    stub_site
    Dir.mktmpdir do |dir|
      sync(dir)
      second = sync(dir)
      assert_equal 0, second.fetched
      assert_equal 6, second.cached
      assert_requested :get, "#{BASE}/tibetan-masters/mipham/acala-sadhana", times: 1
      assert_requested :get, "#{BASE}/tibetan-masters/mipham/", times: 2 # listings re-walk every sync
    end
  end

  def test_a_missing_text_page_is_censused_not_fatal
    stub_site(skip_text: ["bo", "words-of-the-buddha/amitayus-dharani"])
    Dir.mktmpdir do |dir|
      result = sync(dir)
      assert_equal ["bo:words-of-the-buddha/amitayus-dharani"], result.missing
      assert_equal 5, result.fetched
    end
  end

  def test_an_empty_explore_page_aborts_before_any_write
    stub_site
    stub_request(:get, "#{BASE}/bo/free-translations-tibetan-buddhist-texts")
      .to_return(status: 200, body: "<html><body>maintenance</body></html>")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::LotsawaFetch::Error) { sync(dir) }
      assert_match(/lists no authors and no texts/, error.message)
      assert_empty Dir.children(dir), "nothing written"
    end
  end

  def test_a_page_no_longer_listed_goes_to_the_attic
    stub_site
    Dir.mktmpdir do |dir|
      stale = File.join(dir, "pages", "en", "tibetan-masters", "mipham", "withdrawn-text.html")
      FileUtils.mkdir_p(File.dirname(stale))
      File.write(stale, "<html>old</html>")
      out_of_scope = File.join(dir, "pages", "de", "tibetan-masters", "mipham", "kept.html")
      FileUtils.mkdir_p(File.dirname(out_of_scope))
      File.write(out_of_scope, "<html>de</html>")
      result = sync(dir)
      assert_equal ["pages/en/tibetan-masters/mipham/withdrawn-text.html"], result.atticked
      refute File.exist?(stale)
      assert File.file?(File.join(dir, ".attic", "pages", "en", "tibetan-masters", "mipham", "withdrawn-text.html"))
      assert File.file?(out_of_scope), "a language outside the crawl's scope is never doomed"
    end
  end

  def test_the_guard_sees_the_doomed_set_before_the_tree_mutates
    stub_site
    Dir.mktmpdir do |dir|
      stale = File.join(dir, "pages", "bo", "tibetan-masters", "mipham", "gone.html")
      FileUtils.mkdir_p(File.dirname(stale))
      File.write(stale, "<html>old</html>")
      seen = nil
      assert_raises(Nabu::SyncAborted) do
        sync(dir, guard: lambda { |doomed|
          seen = doomed
          raise Nabu::SyncAborted.new(existing_count: 1, would_withdraw_count: 1, threshold: 0.1)
        })
      end
      assert_equal [stale], seen
      assert File.file?(stale), "aborted before any mutation"
      refute File.exist?(File.join(dir, "catalog"))
    end
  end

  def test_unknown_languages_are_refused
    assert_raises(Nabu::LotsawaFetch::Error) do
      Nabu::LotsawaFetch.new(dir: "/tmp/x", attic_dir: "/tmp/x/.attic", languages: %w[xx])
    end
  end
end
