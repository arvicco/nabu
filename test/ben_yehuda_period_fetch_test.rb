# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::BenYehudaPeriodFetch: upstream's own period taxonomy for the
# ben-yehuda dump, read off the site's author browse (filtered by period,
# cursor-paginated). The dump's catalogue carries no period field, and the
# site API needs a key — the browse pages need none. WebMock answers with
# the real trimmed browse pages under test/fixtures/ben-yehuda/site/.
class BenYehudaPeriodFetchTest < Minitest::Test
  SITE = File.join(Nabu::TestSupport.fixtures("ben-yehuda"), "site")
  FETCH = Nabu::BenYehudaPeriodFetch

  ANCIENT_1 = "https://benyehuda.org/authors?ckb_periods%5B%5D=ancient"
  MEDIEVAL_1 = "https://benyehuda.org/authors?ckb_periods%5B%5D=medieval"

  def setup
    @dir = Dir.mktmpdir("ben-yehuda-periods")
  end

  def teardown
    FileUtils.remove_entry(@dir)
    super
  end

  def page(name) = File.read(File.join(SITE, "#{name}.html"))

  # The cursor URL the page-N "next" button names (its data-search-after-*
  # attributes, exactly as the site's own paging script submits them).
  def cursor_url(band, id, page, value)
    query = URI.encode_www_form([["ckb_periods[]", band], ["search_after_id", id], ["page", page],
                                 ["reverse", "false"], ["search_after_value", value]])
    "https://benyehuda.org/authors?#{query}"
  end

  def stub_site(second_medieval_page: page("authors-medieval-2"))
    stub_request(:get, ANCIENT_1).to_return(status: 200, body: page("authors-ancient"))
    stub_request(:get, MEDIEVAL_1).to_return(status: 200, body: page("authors-medieval-1"))
    stub_request(:get, cursor_url("medieval", "2852", "2", "הנובר, נתן נטע "))
      .to_return(status: 200, body: second_medieval_page)
    stub_request(:get, cursor_url("medieval", "1423", "3", "שנירי, יצחק "))
      .to_return(status: 200, body: page("authors-medieval-3"))
  end

  def sync!(retrieved: Date.new(2026, 11, 18))
    FETCH.sync!(dir: @dir, retrieved: retrieved)
  end

  def sidecar = JSON.parse(File.read(File.join(@dir, FETCH::SIDECAR)))

  def test_both_bands_land_in_the_sidecar_with_upstreams_labels_and_bounds
    stub_site
    result = sync!
    assert result.written
    data = sidecar
    assert_equal "2026-11-18", data["retrieved"]
    ancient = data.dig("bands", "ancient")
    assert_equal "עת עתיקה ופיוט (עד 900 לספירה)", ancient["label"]
    assert_nil ancient["not_before"]
    assert_equal 900, ancient["not_after"]
    assert_equal 2, ancient["authors"]
    medieval = data.dig("bands", "medieval")
    assert_equal "ימי הביניים והרנסאנס (900 עד 1700)", medieval["label"]
    assert_equal [900, 1700], [medieval["not_before"], medieval["not_after"]]
    assert_equal 6, medieval["authors"]
    assert_equal 3, medieval["pages"]
    assert_equal({ "band" => "ancient", "name" => "יניי", "works" => 33 }, data.dig("authors", "1470"))
    assert_equal({ "band" => "medieval", "name" => "הלוי, יהודה", "works" => 586 }, data.dig("authors", "161"))
    assert_equal 1, data.dig("authors", "606", "works"), "\"(יצירה אחת)\" — one work"
    assert_equal %w[49 161 210 223 606 1457 1470 1903], data["authors"].keys, "numeric id order"
  end

  def test_the_cursor_pagination_is_followed_to_the_last_page
    stub_site
    sync!
    [ANCIENT_1, MEDIEVAL_1, cursor_url("medieval", "2852", "2", "הנובר, נתן נטע "),
     cursor_url("medieval", "1423", "3", "שנירי, יצחק ")].each do |url|
      assert_requested :get, url, times: 1
    end
  end

  def test_an_unchanged_band_list_leaves_the_sidecar_untouched
    stub_site
    sync!
    before = File.read(File.join(@dir, FETCH::SIDECAR))
    result = sync!(retrieved: Date.new(2026, 12, 1))
    refute result.written, "same authors, same bands — no rewrite, the retrieved stamp stays"
    assert_equal before, File.read(File.join(@dir, FETCH::SIDECAR))
  end

  def test_a_page_count_that_disagrees_with_the_walk_aborts
    # page 2 answered with the last page's body: "page 3 of 3" at walk step 2
    stub_site(second_medieval_page: page("authors-medieval-3"))
    error = assert_raises(FETCH::Error) { sync! }
    assert_match(/page/, error.message)
    refute File.exist?(File.join(@dir, FETCH::SIDECAR)), "a failed walk writes nothing"
  end

  def test_a_band_page_without_entries_aborts
    stub_site
    stub_request(:get, ANCIENT_1).to_return(status: 200, body: "<html><body>maintenance</body></html>")
    assert_raises(FETCH::Error) { sync! }
    refute File.exist?(File.join(@dir, FETCH::SIDECAR))
  end

  def test_an_http_failure_is_a_fetch_error
    stub_site
    stub_request(:get, MEDIEVAL_1).to_return(status: 503, body: "")
    assert_raises(FETCH::Error) { sync! }
  end

  def test_parse_page_reads_entries_the_next_cursor_and_the_page_count
    parsed = FETCH.parse_page(page("authors-medieval-1"))
    assert_equal([["161", "הלוי, יהודה"], ["49", "הנגיד, שמואל"]],
                 parsed.entries.map { |entry| [entry.id, entry.name] })
    assert_equal [586, 1857], parsed.entries.map(&:works)
    assert_equal [1, 3], [parsed.page, parsed.pages]
    assert_equal({ "search_after_id" => "2852", "page" => "2", "reverse" => "false",
                   "search_after_value" => "הנובר, נתן נטע " }, parsed.next_cursor)
    last = FETCH.parse_page(page("authors-medieval-3"))
    assert_nil last.next_cursor, "the last page carries only the first/previous buttons"
    single = FETCH.parse_page(page("authors-ancient"))
    assert_equal [1, 1], [single.page, single.pages], "a one-page band prints no paging row"
  end
end
