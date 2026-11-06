# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

# Nabu::Adapters::LemeFetch — the polite walk over LEME's TSpace collection through
# the DSpace 7 REST API: discovery listing → item records (embedded
# bundles/bitstreams) → each item's ONE named XML bitstream, MD5-checked.
# WebMock only; the bodies are the real fixtures (test/fixtures/leme).
class LemeFetchTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("leme")
  KLASS = Nabu::Adapters::LemeFetch
  KEYS = %w[102105 102611 124555 131265].freeze

  def fixture(path) = File.binread(File.join(FIXTURES, path))

  def item(key) = JSON.parse(fixture("items/#{key}.json"))

  def stub_listing
    (0..3).each do |page|
      stub_request(:get, KLASS.list_url(page))
        .to_return(status: 200, body: fixture("rest/listing-#{page}.json"),
                   headers: { "Content-Type" => "application/json" })
    end
  end

  def stub_items(keys = KEYS)
    keys.each do |key|
      record = item(key)
      stub_request(:get, KLASS.item_url(record["uuid"])).to_return(status: 200, body: fixture("items/#{key}.json"))
      bitstream = KLASS.accepted_bitstream(record)
      stub_request(:get, KLASS.content_url(bitstream["uuid"])).to_return(status: 200, body: fixture("xml/#{key}.xml"))
    end
  end

  def sync(dir) = KLASS.sync!(dir: dir, delay: 0)

  def test_lands_every_listed_item_record_and_its_xml
    stub_listing
    stub_items
    Dir.mktmpdir do |dir|
      result = sync(dir)
      assert_equal 314, result.advertised, "the listing's own totalElements"
      assert_equal 4, result.listed
      assert_equal 3, result.held
      assert_equal ["1807/131265"], result.failed,
                   "the trimmed Martinez fixture fails the listed MD5 — a body that fails its checksum never lands"
      assert_equal [4, 3], [result.items_fetched, result.xml_fetched]
      assert_match(/\A\h{64}\z/, result.sha)
      assert_equal fixture("xml/102611.xml"), File.binread(File.join(dir, "xml/102611.xml"))
      assert File.file?(File.join(dir, "items/131265.json"))
      refute File.exist?(File.join(dir, "xml/131265.xml"))
      state = JSON.parse(File.read(File.join(dir, KLASS::STATE_FILE)))["items"]
      assert_equal "1807/124555", state.dig("124555", "handle")
      listed = KLASS.accepted_bitstream(item("124555")).dig("checkSum", "value")
      assert_equal listed, state.dig("124555", "md5")
      assert_equal Digest::MD5.file(File.join(dir, "xml/124555.xml")).hexdigest, listed
    end
  end

  def test_unnamed_bitstreams_are_never_requested
    stub_listing
    stub_items
    unnamed = KLASS.original_bitstreams(item("102611")).select { |b| b["name"].to_s.empty? }
    assert_equal 1, unnamed.size
    Dir.mktmpdir do |dir|
      sync(dir)
      assert_not_requested :get, KLASS.content_url(unnamed.first["uuid"])
    end
  end

  def test_an_unchanged_item_is_never_requested_again
    stub_listing
    stub_items
    Dir.mktmpdir do |dir|
      sync(dir)
      WebMock.reset!
      stub_listing
      stub_items(["131265"]) # still failing its MD5: retried every sync
      result = sync(dir)
      assert_equal [1, 0, 3], [result.items_fetched, result.xml_fetched, result.held],
                   "only the failed item's record is asked for again (a failed item records no state)"
      assert_not_requested :get, KLASS.item_url(item("102611")["uuid"])
      assert_not_requested :get, KLASS.content_url(KLASS.accepted_bitstream(item("102611"))["uuid"])
    end
  end

  def test_a_changed_last_modified_refetches_the_record_but_not_a_matching_xml
    stub_listing
    stub_items
    Dir.mktmpdir do |dir|
      sync(dir)
      state_path = File.join(dir, KLASS::STATE_FILE)
      state = JSON.parse(File.read(state_path))
      state["items"]["124555"]["modified"] = "2020-01-01T00:00:00.000Z"
      File.write(state_path, JSON.generate(state))
      WebMock.reset!
      stub_listing
      stub_items(%w[124555 131265])
      result = sync(dir)
      assert_equal [2, 0], [result.items_fetched, result.xml_fetched]
    end
  end

  def test_a_busy_server_is_retried
    stub_listing
    stub_items(KEYS - ["124555"])
    record = item("124555")
    stub_request(:get, KLASS.item_url(record["uuid"]))
      .to_return({ status: 503 }, { status: 503 }, { status: 200, body: fixture("items/124555.json") })
    stub_request(:get, KLASS.content_url(KLASS.accepted_bitstream(record)["uuid"]))
      .to_return(status: 200, body: fixture("xml/124555.xml"))
    Dir.mktmpdir do |dir|
      assert_equal 3, sync(dir).held
    end
  end

  def test_an_unreachable_item_is_reported_and_the_rest_lands
    stub_listing
    stub_items(KEYS - ["102611"])
    stub_request(:get, KLASS.item_url(item("102611")["uuid"])).to_return(status: 500)
    Dir.mktmpdir do |dir|
      result = sync(dir)
      assert_equal %w[1807/102611 1807/131265], result.failed.sort
      assert_equal 2, result.held
      refute File.exist?(File.join(dir, "items/102611.json"))
    end
  end

  def test_a_failing_listing_aborts_before_any_write
    stub_request(:get, KLASS.list_url(0)).to_return(status: 500)
    Dir.mktmpdir do |dir|
      target = File.join(dir, "leme")
      assert_raises(KLASS::Error) { sync(target) }
      refute Dir.exist?(target)
    end
  end

  def test_a_listing_naming_no_item_is_an_error
    empty = JSON.parse(fixture("rest/listing-2.json"))
    empty["_embedded"]["searchResult"]["page"]["totalPages"] = 1
    stub_request(:get, KLASS.list_url(0)).to_return(status: 200, body: JSON.generate(empty))
    Dir.mktmpdir do |dir|
      error = assert_raises(KLASS::Error) { sync(dir) }
      assert_match(/names no item/, error.message)
    end
  end

  def test_the_accepted_bitstream_is_the_one_named_xml_file
    assert_equal "1393_Baldwin_Canticles_1549_v1.xml", KLASS.accepted_bitstream(item("102611"))["name"]
    record = item("102611")
    record["_embedded"]["bundles"]["_embedded"]["bundles"].each do |bundle|
      next unless bundle["name"] == "ORIGINAL"

      bundle["_embedded"]["bitstreams"]["_embedded"]["bitstreams"].each { |b| b["name"] = "" }
    end
    assert_raises(KLASS::Error) { KLASS.accepted_bitstream(record) }
  end

  def test_a_handle_outside_the_repository_is_refused
    assert_equal "102611", KLASS.key_for("1807/102611")
    assert_raises(KLASS::Error) { KLASS.key_for("2000/1") }
    assert_raises(KLASS::Error) { KLASS.key_for("1807/../x") }
  end
end
