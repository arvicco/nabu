# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::HonkokuNdlCatalog: honkoku v3 materials whose IIIF manifest is an
# NDL Digital Collections item (dl.ndl.go.jp/api/iiif/<pid>/manifest.json)
# gain that item's NDL catalog record — author (raw + role-split parts),
# publication date, subjects — from the held ndl-kotenseki census.tsv, under
# metadata "ndl_catalog" (the label: every field is the NDL record's claim,
# never honkoku's). Derived by construction: f(canonical/ndl-kotenseki +
# loaded honkoku rows), re-run before the builders at rebuild, builder
# refresh and after honkoku/ndl-kotenseki syncs (the AesAedTitles mold).
class HonkokuNdlCatalogTest < Minitest::Test
  FIXTURES_ROOT = Nabu::TestSupport::FIXTURES_ROOT

  JOINED = "urn:nabu:honkoku:p:joined"
  DATED = "urn:nabu:honkoku:p:dated"
  UNMATCHED = "urn:nabu:honkoku:p:unmatched"
  ELSEWHERE = "urn:nabu:honkoku:p:elsewhere"

  def setup
    @catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(@catalog)
    @honkoku = source("honkoku")
    @other = source("other")
    doc(@honkoku, JOINED, "manifest" => manifest(2_541_107), "label" => "古今武者揃")
    doc(@honkoku, DATED, "manifest" => manifest(2_532_153))
    doc(@honkoku, UNMATCHED, "manifest" => manifest(1))
    doc(@honkoku, ELSEWHERE, "manifest" => "https://ourarchives.amane-project.jp/iiif/x/manifest")
    @canonical = Dir.mktmpdir
    File.symlink(File.join(FIXTURES_ROOT, "ndl-kotenseki"), File.join(@canonical, "ndl-kotenseki"))
  end

  def teardown
    @catalog.disconnect
    FileUtils.remove_entry(@canonical)
  end

  def source(slug)
    @catalog[:sources].insert(slug: slug, name: slug, adapter_class: "X", license_class: "attribution")
  end

  def manifest(pid) = "https://dl.ndl.go.jp/api/iiif/#{pid}/manifest.json"

  def doc(source_id, urn, metadata)
    @catalog[:documents].insert(source_id: source_id, urn: urn, language: "jpn", content_sha256: "x",
                                metadata_json: Nabu::Store::ContentHash.canonical_json(metadata))
  end

  def metadata(urn)
    JSON.parse(@catalog[:documents].where(urn: urn).get(:metadata_json))
  end

  def run_pass(canonical_dir = @canonical)
    Nabu::HonkokuNdlCatalog.new(catalog: @catalog, canonical_dir: canonical_dir).run
  end

  def test_an_ndl_manifest_gains_the_catalog_record
    result = run_pass
    record = metadata(JOINED)["ndl_catalog"]
    assert_equal "2541107", record["pid"]
    assert_equal "https://dl.ndl.go.jp/pid/2541107", record["record"]
    assert_equal "夷福山人 作||広重 画", record["author"], "the raw 著者 string rides verbatim"
    assert_equal [{ "name" => "夷福山人", "role" => "作" }, { "name" => "広重", "role" => "画" }],
                 record["authors"]
    assert_equal %w[夷福山人 広重], record["author_names"]
    assert_equal ["赤本"], record["subjects"]
    assert_equal "古今武者揃", metadata(JOINED)["label"], "honkoku's own fields stay untouched"
    assert_equal 2, result.joined
    assert_equal 1, result.unmatched, "an NDL pid absent from the census is counted, never guessed"
  end

  def test_the_ndl_publication_date_rides_labeled
    record = (run_pass && metadata(DATED))["ndl_catalog"]
    assert_equal({ "not_before" => 1605, "not_after" => 1605, "raw" => "[慶長10(1605)]" }, record["date"])
    assert_equal %w[倭玉篇 辞書], record["subjects"]
    assert_nil record["author"], "an empty 著者 claims nothing"
  end

  def test_non_ndl_and_unmatched_materials_stay_untouched
    run_pass
    assert_nil metadata(UNMATCHED)["ndl_catalog"]
    assert_nil metadata(ELSEWHERE)["ndl_catalog"]
  end

  def test_other_sources_are_never_touched
    doc(@other, "urn:nabu:other:x", "manifest" => manifest(2_541_107))
    run_pass
    assert_nil metadata("urn:nabu:other:x")["ndl_catalog"]
  end

  def test_rerun_is_idempotent
    run_pass
    before = @catalog[:documents].order(:urn).select_map(:metadata_json)
    run_pass
    assert_equal before, @catalog[:documents].order(:urn).select_map(:metadata_json)
  end

  def test_an_absent_census_strips_a_stale_join
    run_pass
    result = run_pass(Dir.mktmpdir)
    assert_nil metadata(JOINED)["ndl_catalog"], "db/ stays f(canonical): no census, no record"
    assert_equal 0, result.joined
  end
end
