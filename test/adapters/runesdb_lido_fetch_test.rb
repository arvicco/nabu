# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::Adapters::RunesdbLidoFetch (P160): the paced, resumable per-find
# LIDO harvest. Stub bodies are the real fixture records under
# test/fixtures/runesdb/lido/; the adapter test covers the zip+harvest
# choreography, this file the harvester's failure taxonomy.
class RunesdbLidoFetchTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("runesdb")
  URL = "https://www.runesdb.de/lido/%s"
  Fetch = Nabu::Adapters::RunesdbLidoFetch

  def setup
    @dir = Dir.mktmpdir("runesdb-lido-fetch")
  end

  def teardown
    FileUtils.remove_entry(@dir)
    super
  end

  def record(id) = File.binread(File.join(FIXTURES, "lido", "#{id}.xml"))

  def sync(ids) = Fetch.sync!(dir: @dir, find_ids: ids, delay: 0)

  def test_a_transient_5xx_retries_then_lands_the_record
    stub_request(:get, format(URL, 629)).to_return({ status: 503 }, { status: 200, body: record(629) })
    result = sync(%w[629])
    assert_equal [1, 0, []], [result.fetched, result.cached, result.missing]
    assert_equal record(629), File.binread(File.join(@dir, "lido", "629.xml"))
  end

  def test_a_body_that_is_not_this_finds_record_is_censused_never_landed
    stub_request(:get, format(URL, 1)).to_return(status: 200, body: record(629))
    stub_request(:get, format(URL, 629)).to_return(status: 200, body: "<html><body>maintenance</body></html>")
    stub_request(:get, format(URL, "200143")).to_return(status: 404)
    result = sync(%w[1 629 200143])
    assert_equal %w[1 629 200143], result.missing, "a mis-routed record, an HTML page and a 404"
    assert_empty Dir.glob(File.join(@dir, "lido", "*.xml"))
  end

  def test_a_systemic_miss_aborts_after_landing_what_it_could
    ids = (1..7).map(&:to_s)
    stub_request(:get, format(URL, 1)).to_return(status: 200, body: record(1))
    stub_request(:get, %r{\Ahttps://www\.runesdb\.de/lido/[2-7]\z}).to_return(status: 302)
    error = assert_raises(Fetch::Error) { sync(ids) }
    assert_match(/6 of 7 finds have no LIDO record — a systemic miss/, error.message)
    assert_path_exists File.join(@dir, "lido", "1.xml"), "resume keeps what landed"
  end

  def test_a_hard_4xx_is_an_error_not_a_hole
    stub_request(:get, format(URL, 629)).to_return(status: 403)
    assert_raises(Fetch::Error) { sync(%w[629]) }
  end

  def test_the_ledger_is_deterministic_and_untouched_by_a_no_op_resync
    stub_request(:get, format(URL, 629)).to_return(status: 200, body: record(629))
    first = sync(%w[629])
    ledger = File.join(@dir, "lido", ".lido-fetch.json")
    mtime = File.mtime(ledger)
    second = sync(%w[629])
    assert_equal first.sha, second.sha
    assert_equal [0, 1], [second.fetched, second.cached]
    assert_equal mtime, File.mtime(ledger), "an unchanged ledger is never rewritten"
    assert_equal({ "url" => URL, "records" => 1, "held" => 1, "missing" => [], "sha256" => first.sha },
                 JSON.parse(File.read(ledger)))
  end

  def test_requests_carry_the_house_user_agent
    stub_request(:get, format(URL, 629)).with(headers: { "User-Agent" => %r{\Anabu/.*CC BY-SA 4\.0} })
                                        .to_return(status: 200, body: record(629))
    assert_equal 1, sync(%w[629]).fetched
  end
end
