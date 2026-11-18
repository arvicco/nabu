# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# TAGNT adapter tests: STEPBible-Data's Translators Amalgamated Greek NT, two
# word-per-row files, one document per NT book. Includes the shared
# AdapterConformance suite against the checked-in excerpts (README.md there);
# the TAHOT specimen pins the rejected OT grain. No network: fetch runs
# against WebMock stubs of the pinned raw URLs.
class StepbibleTagntTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("stepbible-tagnt")
  ADAPTER = Nabu::Adapters::StepbibleTagnt

  BOOK_URNS = %w[matt john acts jas 3john rev].map { |tail| "urn:nabu:stepbible-tagnt:#{tail}" }.freeze

  def conformance_adapter
    ADAPTER.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "stepbible-tagnt"
  end

  def document(tail)
    adapter = ADAPTER.new
    adapter.parse(adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:stepbible-tagnt:#{tail}" })
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_source
    manifest = ADAPTER.manifest
    assert_equal "stepbible-tagnt", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/\ACC BY 4\.0/, manifest.license)
    assert_equal "https://github.com/STEPBible/STEPBible-Data", manifest.upstream_url
    assert_equal "tagnt-tsv", manifest.parser_family
  end

  def test_parts_pin_raw_urls_at_the_commit
    assert_equal 2, ADAPTER::PARTS.size
    assert_equal "https://raw.githubusercontent.com/STEPBible/STEPBible-Data/" \
                 "5de0a47f35f0fc13dfe1430d104e5db8a4285f9c/Translators%20Amalgamated%20OT%2BNT/" \
                 "TAGNT%20Mat-Jhn%20-%20Translators%20Amalgamated%20Greek%20NT%20-%20STEPBible.org%20CC-BY.txt",
                 ADAPTER::PARTS.first.url
    assert(ADAPTER::PARTS.all? { |p| p.sha256.match?(/\A\h{64}\z/) })
    assert_equal 27, ADAPTER::BOOKS.size
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_book_in_canonical_order
    refs = ADAPTER.new.discover(FIXTURES).to_a
    assert_equal BOOK_URNS, refs.map(&:id)
    assert(refs.all? { |r| r.source_id == "stepbible-tagnt" && r.metadata["language"] == "grc" })
    assert_equal(["Matthew", "John", "Acts", "James", "3 John", "Revelation"], refs.map { |r| r.metadata["title"] })
  end

  # The urn tails are sblgnt's own book stems, so the two Greek NT witnesses
  # share book identity.
  def test_urn_tails_mirror_sblgnt
    sblgnt = Nabu::Adapters::Sblgnt.new.discover(Nabu::TestSupport.fixtures("sblgnt")).map { |r| r.id.split(":").last }
    ours = ADAPTER::BOOKS.values.map(&:first)
    assert_empty sblgnt - ours
    assert_includes ours, "phlm"
    assert_includes ours, "1thess"
  end

  def test_the_ot_hebrew_grain_is_skipped_by_rule
    skips = ADAPTER.new.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert skips.clean?
    assert_match(/\ATAHOT Job-Sng .*skipped by rule — OT Hebrew grain/, skips.notes.first)
    refute(ADAPTER.new.discover(FIXTURES).any? { |r| r.path.include?("TAHOT") })
  end

  def test_a_stray_text_file_is_unrecognized
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "notes.txt"), "x")
      skips = ADAPTER.new.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      refute skips.clean?
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty ADAPTER.new.discover(dir).to_a }
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_round_trips_three_john_whole
    doc = document("3john")
    assert_equal "urn:nabu:stepbible-tagnt:3john", doc.urn
    assert_equal "grc", doc.language
    assert_equal "3 John", doc.title
    assert_equal (1..15).map { |v| "urn:nabu:stepbible-tagnt:3john:1.#{v}" }, doc.map(&:urn)
    assert_equal "Ὁ πρεσβύτερος Γαΐῳ τῷ ἀγαπητῷ ὃν ἐγὼ ἀγαπῶ ἐν ἀληθείᾳ.", doc.first.text
  end

  def test_fixture_passage_counts
    counts = BOOK_URNS.to_h { |urn| [urn.split(":").last, document(urn.split(":").last).size] }
    assert_equal({ "matt" => 6, "john" => 2, "acts" => 2, "jas" => 1, "3john" => 15, "rev" => 1 }, counts)
  end

  def test_the_apparatus_rides_the_tokens
    rev = document("rev").first
    assert_equal "urn:nabu:stepbible-tagnt:rev:22.21", rev.urn
    last = rev.annotations["tokens"].last
    assert_equal "Rev.22.21#12", last["id"]
    assert_equal "KO", last["type"]
    assert_equal "Tyn+TR+Byz", last["editions"]
    variant = rev.annotations["tokens"][10]
    assert_equal "K(O)", variant["type"]
    assert_match(/\Aἁγίων \(O=hagiōn\) saints\. .* in: Tyn\+WH\+Treg\+Byz\z/, variant["meaning_variants"])
  end

  def test_parse_is_idempotent
    first = document("matt")
    second = document("matt")
    assert_equal first.map(&:urn), second.map(&:urn)
    assert_equal first.map(&:text), second.map(&:text)
    assert_equal first.map(&:annotations), second.map(&:annotations)
  end

  # --- fetch (WebMock only, no network) ------------------------------------------

  def test_fetch_lands_both_files_and_verifies_the_pins
    bodies = stub_parts
    Dir.mktmpdir do |dir|
      report = ADAPTER.new(pins: pins_for(bodies)).fetch(dir)
      assert_equal ADAPTER::COMMIT, report.sha
      ADAPTER::PARTS.each do |part|
        assert_equal bodies.fetch(part.filename), File.binread(File.join(dir, part.dir, part.filename))
      end
      assert_equal BOOK_URNS, ADAPTER.new.discover(dir).map(&:id)
    end
  end

  def test_fetch_aborts_on_sha_drift_with_the_tree_untouched
    bodies = stub_parts
    pins = pins_for(bodies).merge(ADAPTER::PARTS.last.filename => "0" * 64)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new(pins: pins).fetch(dir) }
      assert_match(/drifted/, error.message)
      assert_empty Dir.children(dir), "neither file is written when either pin fails"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    ADAPTER::PARTS.each { |part| stub_request(:get, part.url).to_return(status: 500) }
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(dir) }
    end
  end

  # --- registry round-trip -------------------------------------------------------

  def test_registry_resolves_the_source_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["stepbible-tagnt"]
    refute_nil entry, "stepbible-tagnt must be registered in config/sources.yml"
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "unwired until the first real sync is verified"
    assert_equal ADAPTER.manifest, entry.manifest
  end

  private

  def stub_parts
    ADAPTER::PARTS.to_h do |part|
      body = File.binread(File.join(FIXTURES, part.dir, part.filename))
      stub_request(:get, part.url).to_return(status: 200, body: body)
      [part.filename, body]
    end
  end

  def pins_for(bodies)
    bodies.transform_values { |body| Digest::SHA256.hexdigest(body) }
  end
end
