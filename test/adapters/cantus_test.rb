# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Cantus adapter tests: the Cantus Database's chant inventories of
# medieval manuscript sources (CC BY-NC-SA 4.0). The fixture workdir
# (test/fixtures/cantus, README) is the fetch layout: json-sources.json +
# three trimmed Browse Sources pages at the root (the metadata grain) and
# four real per-source CSV exports under sources/ (two whole, two trimmed)
# — 42 chant records, 28 carrying full text (accepted) and 14 incipit-only
# (the REJECTED grain, skipped by rule).
class CantusTest < Minitest::Test
  include AdapterConformance

  FIXTURES = File.expand_path("../fixtures/cantus", __dir__)

  def conformance_adapter = Nabu::Adapters::Cantus.new(delay: 0)

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "cantus"

  def adapter = conformance_adapter

  # --- manifest ----------------------------------------------------------------

  def test_manifest_records_the_cc_by_nc_sa_footer
    manifest = Nabu::Adapters::Cantus.manifest
    assert_equal "cantus", manifest.id
    assert_equal "nc", manifest.license_class
    assert_match(/CC BY-NC-SA 4\.0/, manifest.license)
    assert_match(%r{creativecommons\.org/licenses/by-nc-sa/4\.0}, manifest.license, "the footer's link, verbatim")
    assert_equal "cantus-csv", manifest.parser_family
    assert_equal "https://cantusdatabase.org", manifest.upstream_url
    assert_match(/Lacoste/, manifest.credit)
  end

  # --- discover ----------------------------------------------------------------

  def test_discover_mints_one_document_per_full_text_chant_in_source_order
    ids = adapter.discover(FIXTURES).map(&:id)
    assert_equal 28, ids.size
    assert_equal "urn:nabu:cantus:455842", ids.first, "source 123717 (the lowest id) first, file order"
    assert_equal %w[urn:nabu:cantus:276273 urn:nabu:cantus:276290], ids[23, 2],
                 "Badija V: only its two standardized full texts"
    assert_equal "urn:nabu:cantus:1017752", ids.last
    refute_includes ids, "urn:nabu:cantus:276139", "an incipit-only record is never minted"
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # --- censused skips (the rejected grain) ----------------------------------------

  def test_incipit_only_records_skip_by_rule_with_their_notes
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 14, skips.skipped_by_rule, "42 records − 28 accepted"
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.start_with?("11 incipit-only chant records") })
    assert(skips.notes.any? { |note| note.start_with?("3 chant records whose standardized text only repeats") })
  end

  def test_a_stray_file_in_sources_is_censused_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "sources"))
      FileUtils.cp(File.join(FIXTURES, "sources", "693666.csv"), File.join(dir, "sources"))
      File.write(File.join(dir, "sources", "notes.txt"), "x")
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |note| note.start_with?("notes.txt") })
    end
  end

  # --- parse -------------------------------------------------------------------------

  def test_parse_reaches_known_text_and_metadata
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:cantus:455849" }
    document = adapter.parse(ref)
    assert_equal "Alma redemptoris", document.passages.first.text
    assert_equal "001356", document.metadata["cantus_id"]
    assert_equal "CH-SGs 390", document.metadata["siglum"]
    assert_equal 975, document.metadata.dig("date", "not_before")
  end

  def test_parse_of_a_source_missing_from_the_listing_keeps_the_row_metadata
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "sources"))
      FileUtils.cp(File.join(FIXTURES, "sources", "693666.csv"), File.join(dir, "sources"))
      document = adapter.parse(adapter.discover(dir).first)
      assert_equal "g00533", document.metadata["cantus_id"]
      refute document.metadata.key?("siglum")
    end
  end

  def test_an_attic_copy_parses_with_the_live_source_metadata
    Dir.mktmpdir do |dir|
      FileUtils.cp(Dir.glob(File.join(FIXTURES, "sources-page-*.html")), dir)
      attic_sources = File.join(dir, ".attic", "sources")
      FileUtils.mkdir_p(attic_sources)
      FileUtils.cp(File.join(FIXTURES, "sources", "693666.csv"), File.join(attic_sources, "693666.0a1b2c3d.csv"))
      refs = adapter.discover_with_attic(dir).to_a
      assert_equal %w[urn:nabu:cantus:693667 urn:nabu:cantus:693668], refs.map(&:id)
      document = adapter.parse(refs.first)
      assert_equal "CDN-Mrb MS Medieval 0209", document.metadata["siglum"]
    end
  end

  # --- the axis lanes ------------------------------------------------------------------

  def test_the_timeline_projects_the_source_century_and_provenance
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["cantus"]
    document = adapter.parse(adapter.discover(FIXTURES).first)
    row = Nabu::Store::TimelineBuilder::MetadataDates.axis_row(
      { id: 1, metadata_json: JSON.generate(document.metadata) }, :structured
    )
    assert_equal [975, 1000], [row[:not_before], row[:not_after]]
    assert_equal "St. Gall (Sankt-Gallen)", row[:place_name]
    assert_nil row[:date_class], "the witness's own (artifact) date — no class label"
  end

  def test_the_kind_lane_folds_the_genre_facet
    kinds = Nabu::Kinds.load(classes_path: File.expand_path("../../config/kind_classes.yml", __dir__),
                             map_path: File.expand_path("../../config/kind_map.yml", __dir__))
    assert_equal "genre", kinds.facet_for("cantus")
    assert_equal ["ritual/liturgy"], kinds.normalize("cantus", "Responsory")
    assert_equal ["hymn-prayer/hymn"], kinds.normalize("cantus", "Hymn")
    unmapped = Nabu::Adapters::CantusCsvParser::GENRES.values.select { |name| kinds.normalize("cantus", name) == ["unmapped"] }
    assert_empty unmapped, "every upstream genre name folds"
  end

  def test_idempotent_double_parse
    first = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref).passages.map(&:text) }
    second = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref).passages.map(&:text) }
    assert_equal first, second
  end

  # --- fetch (WebMock'd) -------------------------------------------------------------

  def test_fetch_wraps_crawl_failures_as_fetch_errors
    stub_request(:get, "https://cantusdatabase.org/json-sources/").to_return(status: 404)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
      assert_match(/cantus fetch failed/, error.message)
    end
  end
end
