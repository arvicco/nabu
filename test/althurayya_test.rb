# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::AlthurayyaIndex + the althurayya instrument adapter (the
# chgis/nrct gazetteer-module mold): the al-Ṯurayyā Gazetteer's
# master/places_new_structure.geojson → the "thurayya" place-index
# slice. Name keys are every Arabic and transliterated form the record
# carries (common, the ،/,-separated variant lists, the search forms,
# the ŧ-transliteration); the region display rides as the parent
# discriminator. All assertions run against the real ten-block trim in
# test/fixtures/althurayya/.
class AlthurayyaTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("althurayya")

  def rows
    @rows ||= Nabu::AlthurayyaIndex.rows(workdir_copy)
  end

  def row(id)
    rows.find { |r| r.id == id } || flunk("fixture row #{id} not derived")
  end

  def key(name) = Nabu::Pleiades.name_key(name)

  def test_registry_carries_the_module_row_manual_and_wired
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    entry = registry["althurayya"]
    refute_nil entry
    assert_equal "module", entry.kind
    assert_equal "manual", entry.sync_policy
    assert entry.wired, "wired: true — first sync verified 2026-10-10 (2,331 places derived)"
  end

  def test_manifest_records_the_cc_by_data_license
    manifest = Nabu::Adapters::Althurayya.manifest
    assert_equal "althurayya", manifest.id
    assert_equal "attribution", manifest.license_class,
                 "DATA-LICENSE.md puts the place records under CC BY 4.0 (Apache-2.0 is the code)"
    assert_includes manifest.license, "CC BY 4.0"
  end

  def test_discover_yields_no_documents_and_parse_is_unreachable
    adapter = Nabu::Adapters::Althurayya.new
    assert_empty adapter.discover(FIXTURES).to_a, "a gazetteer instrument mints no documents"
    ref = Nabu::DocumentRef.new(source_id: "althurayya", id: "urn:x", path: "/x")
    assert_raises(Nabu::ParseError) { adapter.parse(ref) }
  end

  def test_fetch_is_the_sparse_gitfetch_cone
    adapter = Nabu::Adapters::Althurayya.new
    captured = nil
    adapter.define_singleton_method(:git_fetch!) { |**kw| captured = kw }
    adapter.fetch("/tmp/nowhere")
    assert_equal "https://github.com/althurayya/althurayya.github.io.git", captured[:repo_url]
    assert_includes captured[:sparse], "master/places_new_structure.geojson"
    assert_includes captured[:sparse], "master/regions.json"
    assert_includes captured[:sparse], "DATA-LICENSE.md"
  end

  def test_a_settlement_carries_arabic_and_transliterated_keys_region_and_point
    baghdad = row("BAGHDAD_443E333N_S")
    assert_equal "Baġdād", baghdad.title, "the title is the project's full transliteration"
    assert_includes baghdad.name_keys, "بغداد"
    assert_includes baghdad.name_keys, key("Baghdad"), "the simplified search form is its own key"
    assert_includes baghdad.name_keys, key("Baġdād")
    assert_equal "al-ʿIrāq", baghdad.parent, "the regions.json display label discriminates homonyms"
    assert_equal ["metropoles"], baghdad.place_types
    assert_in_delta 33.35932, baghdad.lat, 0.00001
    assert_in_delta 44.35693, baghdad.lon, 0.00001
    assert_empty baghdad.time_periods, "the gazetteer carries no per-place dates (declared)"
  end

  def test_variant_lists_split_on_the_arabic_and_latin_commas
    saraqusa = row("SARAQUSA_009W416N_S")
    %w[سرقوسة سرقوسطة].each { |n| assert_includes saraqusa.name_keys, n }
    %w[Saraqūsaŧ Saraqūsṭaŧ Saraqusa Saraqusta].each do |n|
      assert_includes saraqusa.name_keys, key(n)
    end
    refute(saraqusa.name_keys.any? { |k| k.include?(",") || k.include?("،") },
           "no joined list survives as a key")
  end

  def test_an_english_exonym_is_findable
    assert_includes row("IRBIL_440E361N_S").name_keys, key("Erbil")
  end

  def test_region_and_settlement_twins_stay_distinct_places
    assert_equal ["regions"], row("SARAQUSA_009W416N_R").place_types
    assert_equal ["towns"], row("SARAQUSA_009W416N_S").place_types
  end

  def test_the_duplicate_uri_coalesces_first_record_wins
    cairo = rows.select { |r| r.id == "QAHIRA_312E300N_S" }
    assert_equal 1, cairo.size, "the upstream duplicate URI coalesces to one place"
    cairo = cairo.first
    assert_in_delta 30.0444, cairo.lat, 0.00001, "first record's point wins"
    assert_equal %w[metropoles quarters], cairo.place_types, "type lists union"
    assert_includes cairo.name_keys, key("Cairo")
    assert_includes cairo.name_keys, key("al-Qahira"), "the second record's search form unions in"
    assert_includes cairo.name_keys, key("al-Madīnaŧ al-Qāhiraŧ")
  end

  def test_anonymous_route_junctions_are_skipped
    refute(rows.any? { |r| r.id.start_with?("ROUTPOINT") }, "xroads carry placeholder names, not toponyms")
    refute_includes rows.flat_map(&:name_keys), key("RoutPoint0107")
  end

  def test_fixture_census_and_the_namespace_id_shape
    assert_equal 8, rows.size, "10 blocks − 1 xroads − 1 duplicate URI"
    assert_equal rows.size, rows.map(&:id).uniq.size
    assert(rows.all? { |r| r.id.match?(Nabu::AlthurayyaIndex::ID_PATTERN) }, "the namespace mint's id shape")
    assert(rows.all? { |r| r.name_keys.all? { |k| k == k.unicode_normalize(:nfc) } }, "NFC keys")
  end

  def test_producer_derives_the_thurayya_slice_resolvable_in_both_scripts
    db = store_test_db
    census = Nabu::AlthurayyaIndex::Producer.new(catalog: db).run("althurayya", workdir: workdir_copy)
    assert_equal 8, census.places
    resolver = Nabu::Store::PlaceIndex::Resolver.new(db, gazetteer: "thurayya")
    assert_equal "Baġdād", resolver.place("BAGHDAD_443E333N_S").title
    [key("بغداد"), key("Baghdad")].each do |name|
      hit = db[:place_index_names].where(gazetteer: "thurayya", name_key: name).get(:place_id)
      assert_equal "BAGHDAD_443E333N_S", hit
    end
  end

  def test_producer_is_idempotent
    db = store_test_db
    producer = Nabu::AlthurayyaIndex::Producer.new(catalog: db)
    dir = workdir_copy
    producer.run("althurayya", workdir: dir)
    first = [db[:place_index].where(gazetteer: "thurayya").count,
             db[:place_index_names].where(gazetteer: "thurayya").count]
    producer.run("althurayya", workdir: dir)
    assert_equal first, [db[:place_index].where(gazetteer: "thurayya").count,
                         db[:place_index_names].where(gazetteer: "thurayya").count]
  end

  def test_producer_without_the_geojson_is_an_honest_noop
    Dir.mktmpdir do |dir|
      assert_nil Nabu::AlthurayyaIndex::Producer.new(catalog: store_test_db).run("althurayya", workdir: dir)
    end
  end

  def test_missing_regions_file_leaves_the_region_uri_as_parent
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "master"))
      FileUtils.cp(File.join(FIXTURES, "places_new_structure.geojson"), File.join(dir, "master"))
      assert_equal "Iraq_RE", Nabu::AlthurayyaIndex.rows(dir).find { |r| r.id.start_with?("BAGHDAD") }.parent
    end
  end

  def teardown
    Array(@tmpdirs).each { |d| FileUtils.rm_rf(d) }
    super
  end

  private

  # The canonical tree shape: both files under master/.
  def workdir_copy
    dir = Dir.mktmpdir
    (@tmpdirs ||= []) << dir
    FileUtils.mkdir_p(File.join(dir, "master"))
    %w[places_new_structure.geojson regions.json].each do |f|
      FileUtils.cp(File.join(FIXTURES, f), File.join(dir, "master", f))
    end
    dir
  end
end
