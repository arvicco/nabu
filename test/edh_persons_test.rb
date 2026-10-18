# frozen_string_literal: true

require "test_helper"

# Nabu::EdhPersons: EDH's structured prosopography (edh_data_pers.csv,
# one row per attested person) derived into the "edh" person-index slice
# beside CBDB's. Fixture: the real trimmed pers CSV (test/fixtures/edh/
# README.md) — the three HD000001 persons (dative inscribed names,
# filiation, kinship), HD000082's Crassus (Leiden brackets inside the
# inscribed name, "++" markers on the cognomen), HD080825's fragmentary
# "[---](?) Severu[s]" with "0?" placeholder name parts.
class EdhPersonsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("edh")

  def setup
    @catalog = store_test_db
  end

  def persons
    @persons ||= Nabu::EdhPersons.each_person(File.join(FIXTURES, "pers", "edh_data_pers.csv")).to_a
  end

  def person(id) = persons.find { |p| p.person_id == id }

  def key(name) = Nabu::Pleiades.name_key(name)

  # --- the CSV walk ------------------------------------------------------------

  def test_walks_every_attested_person_under_the_upstream_row_id
    assert_equal %w[HD000001/1 HD000001/2 HD000001/3 HD000082/1 HD080825/1], persons.map(&:person_id)
    assert(persons.all? { |p| p.authority == "edh" })
  end

  def test_the_inscribed_name_rides_verbatim_and_sex_maps_to_female
    nonia = person("HD000001/1")
    assert_equal "Noniae P.f. Optatae", nonia.name, "the name as inscribed (dative) — canonical"
    assert nonia.female, "geschlecht W"
    refute person("HD000001/3").female, "geschlecht M"
    assert_nil nonia.name_han
    assert_nil nonia.birth_year, "EDH records no life years — never invented"
  end

  def test_name_keys_cover_the_inscribed_and_the_nominative_forms
    optatus = person("HD000001/3")
    assert_includes optatus.name_keys, key("C. Iulius C.f. Optatus"), "the inscribed name"
    assert_includes optatus.name_keys, key("C. Iulius Optatus"), "praenomen nomen cognomen"
    assert_includes optatus.name_keys, key("Iulius Optatus"), "nomen cognomen"
    nonia = person("HD000001/1")
    assert_includes nonia.name_keys, key("Nonia Optata"), "the nominative form a reader searches by"
  end

  def test_leiden_sigla_and_upstream_markers_fold_out_of_the_keys
    crassus = person("HD000082/1")
    assert_equal "L. Licinius L.[[f. Crassu]]s", crassus.name, "verbatim in the record"
    assert_includes crassus.name_keys, key("L. Licinius L.f. Crassus"), "brackets stripped for the key"
    assert_includes crassus.name_keys, key("L. Licinius Crassus"), "the ++ marker is not name"

    severus = person("HD080825/1")
    assert_includes severus.name_keys, key("Severus"), "0? placeholders and lacunae drop out"
    refute(severus.name_keys.any? { |k| k.include?("0") || k.include?("-") || k.include?("?") })
  end

  # --- the derive + resolver ---------------------------------------------------

  def test_producer_derives_the_edh_slice_beside_cbdb
    Nabu::Store::PersonIndex.derive!(
      @catalog, authority: "cbdb",
                persons: [Nabu::Store::PersonIndex::Person.new(
                  authority: "cbdb", person_id: "1762", name: "Wang Anshi", name_han: "王安石",
                  birth_year: 1021, death_year: 1086, index_year: nil, dynasty: nil,
                  dynasty_han: nil, female: false, name_keys: [key("Wang Anshi")]
                )]
    )
    census = Nabu::EdhPersons::Producer.new(catalog: @catalog).run("edh", workdir: FIXTURES)
    assert_equal 5, census.persons
    assert_operator census.seconds, :>, 0

    resolver = Nabu::Store::PersonIndex.resolver(@catalog, authority: "edh")
    assert_equal 5, resolver.size
    assert_equal ["HD000001/3"], resolver.named("Iulius Optatus").map(&:person_id)
    assert_equal 1, Nabu::Store::PersonIndex.resolver(@catalog, authority: "cbdb").size,
                 "the cbdb slice is untouched — derive! is per authority"
  end

  def test_derive_is_idempotent
    producer = Nabu::EdhPersons::Producer.new(catalog: @catalog)
    2.times { producer.run("edh", workdir: FIXTURES) }
    assert_equal 5, @catalog[:person_index].where(authority: "edh").count
  end

  def test_producer_without_the_csv_is_an_honest_noop
    assert_nil Nabu::EdhPersons::Producer.new(catalog: @catalog).run("edh", workdir: Dir.mktmpdir)
  end

  def test_the_adapter_declares_the_seam
    assert Nabu::Adapters::Edh.person_index_producer?
    assert_instance_of Nabu::EdhPersons::Producer, Nabu::Adapters::Edh.person_index_producer(catalog: @catalog)
  end
end
