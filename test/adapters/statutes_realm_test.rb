# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# statutes-realm adapter tests (P160-7): the Statutes of the Realm vols 5–7
# (Raithby's Record Commission edition, 1819–1820) as British History Online
# serves them. The fixture workdir (test/fixtures/statutes-realm, README) is
# the fetch layout: TOC sidecars under toc/ (the manifest grain, skipped by
# rule) and act pages under vol<N>/. The TOC rows pin every rejected grain —
# an engraving, the preface, the chronological table, two index letters —
# and vol5/p1.html is the engraving's own page, on disk but never minted.
class StatutesRealmTest < Minitest::Test
  include AdapterConformance

  FIXTURES = File.expand_path("../fixtures/statutes-realm", __dir__)

  def conformance_adapter = Nabu::Adapters::StatutesRealm.new(delay: 0)

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "statutes-realm"

  def adapter = conformance_adapter

  # --- manifest ----------------------------------------------------------------

  def test_manifest_records_the_per_page_public_domain_statement
    manifest = Nabu::Adapters::StatutesRealm.manifest
    assert_equal "statutes-realm", manifest.id
    assert_equal "open", manifest.license_class
    assert_includes manifest.license, "This free content was digitised by double rekeying. Public Domain."
    assert_includes manifest.license, "Unless otherwise stated", "the site-wide terms it overrides, named"
    assert_equal "https://www.british-history.ac.uk/series/statutes-realm", manifest.upstream_url
    assert_match(/Raithby/, manifest.credit)
  end

  # --- discover ----------------------------------------------------------------

  def test_discover_mints_the_accepted_rows_in_toc_order
    ids = adapter.discover(FIXTURES).map(&:id)
    assert_equal %w[urn:nabu:statutes-realm:vol5:p1a urn:nabu:statutes-realm:vol5:pp255-259
                    urn:nabu:statutes-realm:vol5:pp421-422
                    urn:nabu:statutes-realm:vol7:p641a urn:nabu:statutes-realm:vol7:p750], ids
  end

  def test_refs_carry_their_toc_row
    ref = adapter.discover(FIXTURES).find { |r| r.id.end_with?("pp255-259") }
    assert_equal "255-259", ref.metadata["pages"]
    assert_equal "act", ref.metadata["grain"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # --- censused skips (the rejected grains) --------------------------------------

  def test_rejected_grains_and_toc_sidecars_skip_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    # 4 TOC sidecars + 1 engraving + 2 front matter + 2 index rows
    assert_equal 9, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("4 TOC pages") })
    assert(skips.notes.any? { |note| note.include?("2 index") })
    assert(skips.notes.any? { |note| note.include?("2 front-matter") })
    assert(skips.notes.any? { |note| note.include?("1 engraving") })
  end

  def test_a_listed_page_missing_on_disk_is_a_fetch_hole
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "toc"), dir)
      FileUtils.mkdir_p(File.join(dir, "vol5"))
      FileUtils.cp(File.join(FIXTURES, "vol5", "p1a.html"), File.join(dir, "vol5"))
      assert_equal ["urn:nabu:statutes-realm:vol5:p1a"], adapter.discover(dir).map(&:id)
      skips = adapter.discovery_skips(dir)
      assert_equal 4, skips.unrecognized
      assert(skips.notes.any? { |note| note.start_with?("vol5/pp255-259: listed act page missing") })
    end
  end

  def test_a_page_no_toc_row_names_is_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")), dir)
      FileUtils.cp(File.join(dir, "vol5", "p1a.html"), File.join(dir, "vol5", "p999.html"))
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |note| note.start_with?("vol5/p999.html: on disk but named by no TOC row") })
    end
  end

  # --- parse -----------------------------------------------------------------------

  def test_parse_reaches_known_text_and_dates
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert document.passages.first.text.start_with?("FORASMUCH as there is nothing more acceptable to God")
    assert_equal({ "not_before" => 1625, "not_after" => 1626, "raw" => "Charles I, 1625" }, document.metadata["date"])
    assert_equal "1", document.metadata["pages"]
  end

  def test_idempotent_double_parse
    first = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref).passages.map(&:text) }
    second = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref).passages.map(&:text) }
    assert_equal first, second
  end

  # --- fetch (WebMock'd) -----------------------------------------------------------------

  def test_fetch_wraps_crawl_failures_as_fetch_errors
    stub_request(:get, %r{british-history\.ac\.uk/statutes-realm/vol5}).to_return(status: 404)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
      assert_match(/statutes-realm fetch failed/, error.message)
    end
  end
end
