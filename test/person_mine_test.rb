# frozen_string_literal: true

require "test_helper"

# Nabu::PersonMine + Query::Person (P97-2 — №R-62 option b): the
# census-only person-name scan and the person desk card. The miner has
# NO write path by design — №R-62's own condition: the apply gate opens
# only after the owner reads a census.
class PersonMineTest < Minitest::Test
  include StoreTestDB

  Person = Nabu::Store::PersonIndex::Person

  def setup
    @catalog = store_test_db
    Nabu::Store::PersonIndex.derive!(
      @catalog, authority: "cbdb",
                persons: [
                  Person.new(authority: "cbdb", person_id: "1762", name: "Wang Anshi",
                             name_han: "王安石", birth_year: 1021, death_year: 1086,
                             index_year: 1021, dynasty: "Song", dynasty_han: "宋",
                             female: false,
                             name_keys: ["王安石", "wang anshi", "介甫", "半山"]),
                  Person.new(authority: "cbdb", person_id: "3767", name: "Su Shi",
                             name_han: "蘇軾", birth_year: 1036, death_year: 1101,
                             index_year: 1036, dynasty: "Song", dynasty_han: "宋",
                             female: false, name_keys: ["蘇軾", "su shi", "東坡"])
                ]
    )
    seed_passages
  end

  def seed_passages
    source = Nabu::Store::Source.create(slug: "kanripo", name: "K",
                                        adapter_class: "X", license_class: "attribution")
    doc = Nabu::Store::Document.create(source_id: source.id, urn: "urn:nabu:kanripo:d1",
                                       language: "lzh", title: "t", canonical_path: "x",
                                       content_sha256: "0" * 64)
    %w[王安石變法之議 東坡居士遊於赤壁 無關之文也].each_with_index do |text, i|
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:nabu:kanripo:d1:#{i}",
                                  language: "lzh", text: text, text_normalized: text,
                                  content_sha256: i.to_s * 64, sequence: i, revision: 1)
    end
  end

  # --- the census ------------------------------------------------------------

  def test_census_tallies_attestations_in_han_and_carries_elapsed
    census = Nabu::PersonMine.new(catalog: @catalog).census(source: "kanripo")
    hits = census.name_hits.to_h
    assert_equal 3, census.passages
    assert_equal 1, hits["王安石"]
    assert_equal 1, hits["東坡"], "the studio name attests — the zi/hao substrate is the point"
    refute hits.key?("wang anshi"), "Latin keys are filtered (the Han lane) and censused"
    assert_operator census.names_non_han, :>=, 2
    assert_operator census.seconds, :>, 0
  end

  def test_the_miner_has_no_write_path
    refute Nabu::PersonMine.method_defined?(:apply!),
           "№R-62: census only — the apply gate does not exist yet, not even flagged off"
  end

  # --- the card --------------------------------------------------------------

  def test_card_resolves_by_ref_and_by_name_in_either_script
    query = Nabu::Query::Person.new(catalog: @catalog)
    assert_equal "王安石", query.run("cbdb:1762").cards.first.name_han
    assert_equal "王安石", query.run("介甫").cards.first.name_han, "the courtesy name resolves"
    assert_equal "蘇軾", query.run("Su Shi").cards.first.name_han, "pinyin resolves"
  end

  def test_card_misses_are_honest_errors
    query = Nabu::Query::Person.new(catalog: @catalog)
    assert_raises(Nabu::Query::Person::Error) { query.run("岳飛") }
    assert_raises(Nabu::Query::Person::Error) { query.run("cbdb:999999") }
    assert_raises(Nabu::Query::Person::Error) { query.run("  ") }
  end
end
