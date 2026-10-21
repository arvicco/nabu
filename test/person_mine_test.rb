# frozen_string_literal: true

require "test_helper"

# Nabu::PersonMine + Query::Person (P97-2 — owner-ruled 2026-09-11, option b): the
# census-only person-name scan and the person desk card. The miner has
# NO write path by design — the ruling's own condition: the apply gate opens
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
    assert_equal :han, census.lane, "a Han-keyed authority scans in the Han lane"
    assert_operator census.names_off_lane, :>=, 2
    assert_operator census.seconds, :>, 0
  end

  # --- the word lane (the epigraphic estates: EDH, Elephantine) ---------------

  # Real EDH lines (HD000001, HD000002 — the line-grain passages as held)
  # against the edh authority's own keys: names match as whole-word
  # sequences under the shared fold, never as substrings, and a name
  # whose words are not contiguous in the text does not attest.
  def seed_edh
    source = Nabu::Store::Source.create(slug: "edh", name: "EDH", adapter_class: "X", license_class: "attribution")
    doc = Nabu::Store::Document.create(source_id: source.id, urn: "urn:nabu:edh:HD000001", language: "lat",
                                       title: "t", canonical_path: "x", content_sha256: "1" * 64)
    ["Dis Manibus", "Noniae Publi filiae Optatae", "et Caio Iulio Artemoni",
     "Caius Iulius Cai filius Optatus", "Caius Sextius Paris", "Sextiusparis"].each_with_index do |text, i|
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:nabu:edh:HD000001:#{i}", language: "lat",
                                  text: text, text_normalized: text.downcase,
                                  content_sha256: Digest::SHA256.hexdigest(text), sequence: i, revision: 1)
    end
    persons = [
      edh_person("HD000001/2", "C. Iulio Artemoni", ["c. iulio artemoni", "c. iulius artemo", "iulius artemo"]),
      edh_person("HD000001/3", "C. Iulius C.f. Optatus", ["c. iulius c.f. optatus", "iulius optatus"]),
      edh_person("HD000002/1", "C. Sextius Paris", ["c. sextius paris", "sextius paris"]),
      edh_person("HD000009/1", "[F]elix", ["felix"]),
      edh_person("HD000009/2", "Felix", ["felix"]),
      edh_person("HD000009/3", "Felix", ["felix"]),
      edh_person("HD000009/4", "Felix", ["felix"]),
      edh_person("HD000009/5", "Ti.", ["ti"])
    ]
    Nabu::Store::PersonIndex.derive!(@catalog, authority: "edh", persons: persons)
  end

  def edh_person(id, name, keys)
    Person.new(authority: "edh", person_id: id, name: name, name_han: nil, birth_year: nil, death_year: nil,
               index_year: nil, dynasty: nil, dynasty_han: nil, female: false, name_keys: keys)
  end

  def test_the_word_lane_matches_whole_word_name_sequences
    seed_edh
    census = Nabu::PersonMine.new(catalog: @catalog, authority: "edh").census(source: "edh")
    hits = census.name_hits.to_h
    assert_equal :word, census.lane, "an authority keyed in alphabetic script scans by words"
    assert_equal 6, census.passages
    assert_equal 1, hits["sextius paris"], "the whole-word sequence attests (not the run-together token)"
    refute hits.key?("iulius optatus"), "a name whose words are interrupted in the text does not attest"
    refute hits.key?("felix"), "a key naming more than the cap's persons is ambiguous, censused"
    assert_equal 1, census.names_ambiguous
    refute hits.key?("ti"), "a key under the letter floor never scans"
  end

  def test_the_word_lane_folds_the_inscribed_case_and_leiden_sigla
    seed_edh
    @catalog[:passages].where(urn: "urn:nabu:edh:HD000001:4").update(text: "CAIVS SEXTIVS [PA]RIS")
    @catalog[:passages].where(urn: "urn:nabu:edh:HD000001:5").update(text: "C(aius) Sex[tius] Paris")
    hits = Nabu::PersonMine.new(catalog: @catalog, authority: "edh").census(source: "edh").name_hits.to_h
    assert_equal 1, hits["sextius paris"],
                 "Leiden brackets fold out of the matching form (the EDH key rule); V/U spelling stays verbatim"
  end

  def test_a_scope_names_its_authority_and_an_unscanned_authority_is_empty
    seed_edh
    census = Nabu::PersonMine.new(catalog: @catalog, authority: "elephantine").census(source: "edh")
    assert_equal "elephantine", census.authority
    assert_equal 0, census.names_loaded
    assert_empty census.name_hits
  end

  def test_the_miner_has_no_write_path
    refute Nabu::PersonMine.method_defined?(:apply!),
           "census only — the apply gate does not exist yet, not even flagged off"
  end

  # --- the card --------------------------------------------------------------

  def test_card_resolves_by_ref_and_by_name_in_either_script
    query = Nabu::Query::Person.new(catalog: @catalog)
    assert_equal "王安石", query.run("cbdb:1762").cards.first.name_han
    assert_equal "王安石", query.run("介甫").cards.first.name_han, "the courtesy name resolves"
    assert_equal "蘇軾", query.run("Su Shi").cards.first.name_han, "pinyin resolves"
  end

  # A second authority (EDH's attested persons) resolves by its own ref
  # shape ("HD000001/3") and by name beside cbdb — names search every
  # derived authority, cbdb first.
  def test_card_resolves_across_authorities
    Nabu::Store::PersonIndex.derive!(
      @catalog, authority: "edh",
                persons: [Person.new(authority: "edh", person_id: "HD000001/3",
                                     name: "C. Iulius C.f. Optatus", name_han: nil,
                                     birth_year: nil, death_year: nil, index_year: nil,
                                     dynasty: nil, dynasty_han: nil, female: false,
                                     name_keys: ["c. iulius optatus", "iulius optatus"])]
    )
    query = Nabu::Query::Person.new(catalog: @catalog)
    assert_equal "C. Iulius C.f. Optatus", query.run("edh:HD000001/3").cards.first.name
    assert_equal ["edh"], query.run("Iulius Optatus").cards.map(&:authority)
    assert_equal ["cbdb"], query.run("Su Shi").cards.map(&:authority)
  end

  def test_card_misses_are_honest_errors
    query = Nabu::Query::Person.new(catalog: @catalog)
    assert_raises(Nabu::Query::Person::Error) { query.run("岳飛") }
    assert_raises(Nabu::Query::Person::Error) { query.run("cbdb:999999") }
    assert_raises(Nabu::Query::Person::Error) { query.run("  ") }
  end
end
