# frozen_string_literal: true

require "test_helper"

# Nabu::TmGeo (P63-3) — the Trismegistos Geo read seam over the Manual
# Adapter holding, deriving the "tm" slice of the NAMESPACED place index
# (migration 025, ruling Dp-b). Exercised against the trimmed REAL dump
# fixture (test/fixtures/trismegistos-geo/ — the `";` endings, ghost rows,
# multilingual name columns).
class TmGeoTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("trismegistos-geo")
  CSV = File.join(FIXTURES, "TM_geo.csv")

  def rows
    @rows ||= Nabu::TmGeo.each_row(CSV).to_a
  end

  def row(id)
    rows.find { |r| r.id == id }
  end

  # --- the CSV parse ----------------------------------------------------------

  def test_every_fixture_row_parses_despite_the_semicolon_endings
    assert_equal 10, rows.size
    assert_equal %w[1 4 5 10 100 604 1767 2355 2788 3311], rows.map(&:id)
  end

  def test_pompeii_carries_title_status_and_coordinates
    pompeii = row("2788")
    assert_equal "Pompeii", pompeii.title
    assert_in_delta 40.74941, pompeii.lat
    assert_in_delta 14.485429, pompeii.lon
    assert_includes pompeii.place_types, "city: colonia"
  end

  def test_philai_folds_standard_and_latin_variant_names_into_keys
    philai = row("1767")
    assert_equal "Philai", philai.title
    %w[philai philae filae].each do |key|
      assert_includes philai.name_keys, key, "standard + every ' - ' Latin variant must key"
    end
  end

  def test_greek_unicode_names_key_case_folded
    topos = row("4") # Ἀαλαβιν τόπος
    assert_includes topos.name_keys, Nabu::Pleiades.name_key("Ἀαλαβιν τόπος")
  end

  def test_a_ghost_name_row_is_kept_and_marked_never_dropped
    ghost = row("1")
    assert_includes ghost.place_types, "ghost name"
    assert_nil ghost.lat
    refute_empty ghost.title, "even a ghost row titles (the attested string)"
  end

  def test_a_coordinateless_row_is_honest_nil_never_zero
    thebes = row("2355")
    refute_nil thebes.lat, "Thebes has coordinates in the dump"
    assert_nil row("5").lat, "Aanemooch Topos does not — nil, not 0.0"
  end

  # --- the namespaced derive (migration 025) ---------------------------------

  def make_pleiades_place(id, title)
    Nabu::Pleiades::Place.new(id: id, title: title, lat: 1.0, lon: 2.0,
                              place_types: [], time_periods: [])
  end

  def test_producer_derives_the_tm_slice_and_the_resolver_reads_it
    db = store_test_db
    census = Nabu::TmGeo::Producer.new(catalog: db).run("trismegistos-geo", workdir: FIXTURES)
    assert_equal 10, census.places
    resolver = Nabu::Store::PlaceIndex.resolver(db, gazetteer: "tm")
    refute_nil resolver
    assert_equal "Pompeii", resolver.place("2788").title
    assert_equal ["Doura"], resolver.titled("doura").map(&:title)
    assert_equal ["Philai"], resolver.titled("Philae").map(&:title), "Latin variants answer titled()"
  end

  def test_gazetteer_slices_are_isolated_wholesale
    db = store_test_db
    Nabu::Store::PlaceIndex.derive!(db, gazetteer: "pleiades",
                                        places: [make_pleiades_place("912855", "Girsu")])
    Nabu::TmGeo::Producer.new(catalog: db).run("trismegistos-geo", workdir: FIXTURES)
    # Re-deriving tm supersedes ONLY tm rows; pleiades rows survive verbatim.
    Nabu::TmGeo::Producer.new(catalog: db).run("trismegistos-geo", workdir: FIXTURES)
    assert_equal "Girsu", Nabu::Store::PlaceIndex.resolver(db).place("912855").title
    assert_equal 10, Nabu::Store::PlaceIndex.resolver(db, gazetteer: "tm").size
    assert_equal 1, Nabu::Store::PlaceIndex.resolver(db, gazetteer: "pleiades").size
  end

  def test_pleiades_populated_never_answers_for_a_tm_only_index
    db = store_test_db
    Nabu::TmGeo::Producer.new(catalog: db).run("trismegistos-geo", workdir: FIXTURES)
    refute Nabu::Store::PlaceIndex.populated?(db),
           "a tm-only index must NOT switch the pleiades surfaces off their dump fallback"
    assert Nabu::Store::PlaceIndex.populated?(db, gazetteer: "tm")
  end

  def test_producer_without_a_held_csv_is_an_honest_no_op
    Dir.mktmpdir do |dir|
      assert_nil Nabu::TmGeo::Producer.new(catalog: store_test_db).run("trismegistos-geo", workdir: dir)
    end
  end

  def test_derive_is_idempotent_row_identical
    db = store_test_db
    producer = Nabu::TmGeo::Producer.new(catalog: db)
    producer.run("trismegistos-geo", workdir: FIXTURES)
    first = db[:place_index].where(gazetteer: "tm").order(:place_id).all
    producer.run("trismegistos-geo", workdir: FIXTURES)
    assert_equal first, db[:place_index].where(gazetteer: "tm").order(:place_id).all
  end
end
