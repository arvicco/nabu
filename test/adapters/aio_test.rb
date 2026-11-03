# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# AIO adapter tests (P154): Attic Inscriptions Online — the CC BY-SA 3.0
# translations (and AIO's own Greek editions) of the inscriptions of
# Attica. The fixture workdir (test/fixtures/aio, README) is the fetch
# layout: two trimmed listing pages at the root (the REJECTED manifest
# grain — skipped by rule) and three real record pairs under records/.
class AioTest < Minitest::Test
  include AdapterConformance

  FIXTURES = File.expand_path("../fixtures/aio", __dir__)

  def conformance_adapter = Nabu::Adapters::Aio.new(delay: 0)

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "aio"

  def adapter = conformance_adapter

  # --- manifest ----------------------------------------------------------------

  def test_manifest_records_the_cc_by_sa_badge
    manifest = Nabu::Adapters::Aio.manifest
    assert_equal "aio", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA 3\.0/, manifest.license)
    assert_match(%r{creativecommons\.org/licenses/by-sa/3\.0}, manifest.license, "the badge target, verbatim")
    assert_equal "aio-record", manifest.parser_family
    assert_equal "https://www.atticinscriptions.com", manifest.upstream_url
    assert_match(/Lambert/, manifest.credit)
  end

  # --- discover ----------------------------------------------------------------

  def test_discover_mints_the_greek_and_translation_layers_in_key_order
    ids = adapter.discover(FIXTURES).map(&:id)
    assert_equal %w[urn:nabu:aio:2103 urn:nabu:aio:2103-en urn:nabu:aio:2586-en urn:nabu:aio:3869-en], ids,
                 "the Greek document only where the record carries AIO's own text"
  end

  def test_translation_refs_carry_the_kind_marker
    refs = adapter.discover(FIXTURES).to_a
    assert_equal(%w[translation translation translation], refs.filter_map { |ref| ref.metadata["kind"] })
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # --- censused skips (the rejected grains) --------------------------------------

  def test_the_listing_sidecars_skip_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule, "list-page-1.json + list-page-2.json — the manifest grain"
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("2 listing pages") })
  end

  def test_a_half_pair_is_censused_unrecognized_never_minted
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "records"))
      FileUtils.cp(File.join(FIXTURES, "records", "aio-2586.json"), File.join(dir, "records"))
      FileUtils.cp(File.join(FIXTURES, "records", "aio-3869.html"), File.join(dir, "records"))
      assert_empty adapter.discover(dir).to_a
      skips = adapter.discovery_skips(dir)
      assert_equal 2, skips.unrecognized
      assert(skips.notes.any? { |note| note.start_with?("aio-2586.json: half a record pair") })
    end
  end

  # --- parse -----------------------------------------------------------------------

  def test_parse_reaches_known_text
    document = adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id == "urn:nabu:aio:2586-en" })
    assert_equal "Gods.", document.passages.first.text
    assert_equal "urn:nabu:aio:2586-en:p1:19", document.passages.last.urn
  end

  def test_idempotent_double_parse
    first = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref).passages.map(&:text) }
    second = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref).passages.map(&:text) }
    assert_equal first, second
  end

  # --- fetch (WebMock'd) -----------------------------------------------------------------

  def test_fetch_wraps_crawl_failures_as_fetch_errors
    stub_request(:get, %r{atticinscriptions\.com/inscription/list_all_inscriptions\.json}).to_return(status: 404)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
      assert_match(/aio fetch failed/, error.message)
    end
  end
end
