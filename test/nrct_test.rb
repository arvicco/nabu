# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::NrctIndex + the nrct instrument adapter (P108-2, the chgis
# mold): the 日本歴史地名大系 placename CSV → the "nrct" place-index
# slice. Name keys are the 名称 verbatim, the 読み reading, and the
# 歴史地名 historical name when it differs; the 上位地名 rides as the
# parent discriminator. All assertions run against the real 30-line
# head trim in test/fixtures/nrct/.
class NrctTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("nrct")
  CSV_PATH = File.join(FIXTURES, "nrct.csv")

  def rows
    @rows ||= Nabu::NrctIndex.each_row(CSV_PATH).to_a
  end

  def row(id)
    rows.find { |r| r.id == id } || flunk("fixture row #{id} not parsed")
  end

  def test_registry_carries_the_module_row_manual
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    entry = registry["nrct"]
    refute_nil entry
    assert_equal "module", entry.kind
    assert_equal "manual", entry.sync_policy
    assert_includes entry.axes, "japonic"
  end

  def test_manifest_is_cc_by_attribution
    manifest = Nabu::Adapters::Nrct.manifest
    assert_equal "nrct", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "CC BY 4.0"
  end

  def test_discover_yields_no_documents_and_parse_is_unreachable
    adapter = Nabu::Adapters::Nrct.new
    assert_empty adapter.discover(FIXTURES).to_a, "a gazetteer instrument mints no documents"
    ref = Nabu::DocumentRef.new(source_id: "nrct", id: "urn:x", path: "/x")
    assert_raises(Nabu::ParseError) { adapter.parse(ref) }
  end

  def test_a_row_carries_name_reading_parent_and_coordinates
    omachi = row("010000037300")
    assert_equal "大町", omachi.title
    assert_includes omachi.name_keys, "大町"
    assert_includes omachi.name_keys, "おおまち", "the 読み reading is its own key"
    assert_equal "函館市", omachi.parent
    assert_in_delta 41.769485, omachi.lat, 0.0001
    assert_in_delta 140.709671, omachi.lon, 0.0001
  end

  def test_a_differing_historical_name_becomes_an_extra_key
    kaji = row("010000040000")
    assert_equal "鍛冶町", kaji.title
    assert_includes kaji.name_keys, "鍛冶村",
                    "the 歴史地名 column's DIFFERENT historical name must be findable"
  end

  def test_all_fixture_rows_parse_with_unique_ids
    assert_equal 29, rows.size
    assert_equal rows.size, rows.map(&:id).uniq.size
    assert(rows.all? { |r| r.id.match?(/\A\d{12}\z/) }, "the namespace mint's id shape")
  end

  def test_producer_derives_the_nrct_slice_resolvable_by_reading
    Dir.mktmpdir do |dir|
      FileUtils.cp(CSV_PATH, File.join(dir, Nabu::NrctIndex::CSV_FILENAME))
      db = store_test_db
      census = Nabu::NrctIndex::Producer.new(catalog: db).run("nrct", workdir: dir)
      assert_equal 29, census.places
      hit = db[:place_index_names].where(name_key: Nabu::Pleiades.name_key("おおまち")).first
      refute_nil hit, "the reading resolves through the index"
      assert_equal "nrct", db[:place_index].where(place_id: "010000037300").get(:gazetteer)
    end
  end

  def test_producer_without_the_csv_is_an_honest_noop
    Dir.mktmpdir do |dir|
      assert_nil Nabu::NrctIndex::Producer.new(catalog: store_test_db).run("nrct", workdir: dir)
    end
  end
end
