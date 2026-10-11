# frozen_string_literal: true

require "test_helper"

# Nabu::LitopysFetch (P117, row 252): the censused-page-list fetch over the
# Izbornyk static site — plain HTTP by design (the HTTPS cert is broken
# upstream), the izbornyk.org.ua mirror as per-page fallback, verbatim
# windows-1251 bytes, sha pins, and the TitusFetch attic/guard contract.
# No network: WebMock stubs throughout.
class LitopysFetchTest < Minitest::Test
  PRIMARY = "http://litopys.org.ua/"
  MIRROR = "http://izbornyk.org.ua/"
  PAGES = %w[ipatlet/ipat01.htm zyzlex/zyz100.htm].freeze
  class Breaker < Nabu::Error; end

  CP1251 = "\xCB\xB3\xF2\xEE\xEF\xE8\xF1".b # "Літопис" in windows-1251

  def setup
    @root = Dir.mktmpdir("litopys-fetch-test")
    @dir = File.join(@root, "litopys")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def sync!(pages: PAGES, guard: nil)
    Nabu::LitopysFetch.sync!(pages: pages, dir: @dir, attic_dir: @attic, delay: 0, guard: guard)
  end

  def stub_page(host, rel, body, status: 200)
    stub_request(:get, "#{host}#{rel}").to_return(status: status, body: body)
  end

  def test_fetches_every_listed_page_over_plain_http_verbatim
    stub_page(PRIMARY, "ipatlet/ipat01.htm", CP1251)
    stub_page(PRIMARY, "zyzlex/zyz100.htm", "zyz")
    result = sync!

    assert_equal CP1251, File.binread(File.join(@dir, "ipatlet", "ipat01.htm")),
                 "windows-1251 bytes land verbatim — decoding is the parser's job"
    assert_equal "zyz", File.binread(File.join(@dir, "zyzlex", "zyz100.htm"))
    assert_equal 2, result.page_count
    assert_equal 2, result.changed
    assert_empty result.mirrored
    assert_match(/\A[0-9a-f]{64}\z/, result.sha)
    assert_requested :get, "#{PRIMARY}ipatlet/ipat01.htm", times: 1
  end

  def test_a_failing_primary_falls_back_to_the_mirror_and_records_it
    stub_page(PRIMARY, "ipatlet/ipat01.htm", CP1251)
    stub_page(PRIMARY, "zyzlex/zyz100.htm", "", status: 503)
    stub_page(MIRROR, "zyzlex/zyz100.htm", "from-mirror")
    result = sync!

    assert_equal "from-mirror", File.binread(File.join(@dir, "zyzlex", "zyz100.htm"))
    assert_equal ["zyzlex/zyz100.htm"], result.mirrored
    state = JSON.parse(File.read(File.join(@dir, Nabu::LitopysFetch::STATE_FILE)))
    assert_equal MIRROR, state.dig("pages", "zyzlex/zyz100.htm", "host")
    assert_equal PRIMARY, state.dig("pages", "ipatlet/ipat01.htm", "host")
  end

  def test_a_page_failing_on_both_hosts_raises_and_leaves_the_tree_untouched
    stub_page(PRIMARY, "ipatlet/ipat01.htm", CP1251)
    stub_page(PRIMARY, "zyzlex/zyz100.htm", "", status: 404)
    stub_page(MIRROR, "zyzlex/zyz100.htm", "", status: 404)
    error = assert_raises(Nabu::LitopysFetch::Error) { sync! }
    assert_match(/every host failed/, error.message)
    refute File.exist?(File.join(@dir, "ipatlet", "ipat01.htm")), "nothing is written before both phases pass"
  end

  def test_an_unchanged_refetch_rewrites_nothing
    stub_page(PRIMARY, "ipatlet/ipat01.htm", CP1251)
    stub_page(PRIMARY, "zyzlex/zyz100.htm", "zyz")
    first = sync!
    second = sync!
    assert_equal first.sha, second.sha
    assert_equal 0, second.changed
  end

  def test_a_delisted_page_is_atticked_through_the_guard
    stub_page(PRIMARY, "ipatlet/ipat01.htm", CP1251)
    stub_page(PRIMARY, "zyzlex/zyz100.htm", "zyz")
    sync!
    seen = nil
    result = sync!(pages: ["ipatlet/ipat01.htm"], guard: ->(doomed) { seen = doomed })

    assert_equal [File.join(@dir, "zyzlex", "zyz100.htm")], seen
    assert_equal ["zyzlex/zyz100.htm"], result.atticked
    refute File.exist?(File.join(@dir, "zyzlex", "zyz100.htm"))
    assert_equal "zyz", File.binread(File.join(@attic, "zyzlex", "zyz100.htm"))
  end

  def test_a_raising_guard_aborts_with_the_tree_unchanged
    stub_page(PRIMARY, "ipatlet/ipat01.htm", CP1251)
    stub_page(PRIMARY, "zyzlex/zyz100.htm", "zyz")
    sync!
    assert_raises(Breaker) do
      sync!(pages: ["ipatlet/ipat01.htm"], guard: ->(_doomed) { raise Breaker, "breaker" })
    end
    assert File.exist?(File.join(@dir, "zyzlex", "zyz100.htm"))
  end
end
