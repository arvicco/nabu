# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::DprrPersons: the DPRR persons projected into the "dprr"
# person-index slice from the two SPARQL answers the adapter lands.
# Fixtures: four real persons (test/fixtures/dprr/README.md).
class DprrPersonsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("dprr")

  def setup
    @catalog = store_test_db
    @workdir = Dir.mktmpdir
    %w[persons.json dates.json].each { |f| FileUtils.cp(File.join(FIXTURES, f), @workdir) }
  end

  def teardown
    FileUtils.remove_entry(@workdir)
  end

  def persons
    @persons ||= Nabu::DprrPersons.each_person(@workdir).to_a
  end

  def person(id)
    persons.find { |p| p.person_id == id }
  end

  def key(name) = Nabu::Pleiades.name_key(name)

  def test_walks_every_person_with_the_styled_name_and_entity_uri
    assert_equal %w[1 146 1016 1698], persons.map(&:person_id)
    brutus = person("1")
    assert_equal "L. Iunius (46a, Supb. 5.356ff.) M. f. Brutus", brutus.name,
                 "DPRR's own styled name, its DPRR-id prefix dropped"
    assert_nil brutus.name_han, "Latin is already the native form — no second lane"
    assert_equal "http://romanrepublic.ac.uk/rdf/entity/Person/1", brutus.refs
    assert_equal "Aemilia (153)", person("1698").name, "the double space after the id squeezes"
  end

  def test_exact_birth_and_death_years_only
    brutus = person("1")
    assert_equal(-540, brutus.birth_year)
    assert_equal(-509, brutus.death_year, "a violent death is a death")
    assert_equal(-458, person("146").death_year)
    assert_equal(-230, person("1016").birth_year)
    aemilia = person("1698")
    assert_nil aemilia.birth_year, "'before -140' (interval B) is not a year"
    assert_equal(-114, aemilia.death_year)
    assert aemilia.female
    refute brutus.female
  end

  def test_nominative_name_keys
    keys = person("1").name_keys
    assert_includes keys, key("L. Iunius Brutus")
    assert_includes keys, key("Lucius Iunius Brutus")
    assert_includes keys, key("Iunius Brutus")
    refute_includes keys, key("Brutus"), "a lone cognomen is never a key — homonym swamp"
    refute_includes keys, key("Iunius")

    scipio = person("1016").name_keys
    assert_includes scipio, key("L. Cornelius Scipio Asiaticus")
    assert_includes scipio, key("Cornelius Scipio Asiaticus")
    assert_includes scipio, key("L. Cornelius Scipio"), "the agnomen-less form keys too"
    assert_includes scipio, key("Cornelius Scipio")
  end

  def test_sigla_fold_out_and_placeholders_never_key
    keys = person("146").name_keys
    assert_includes keys, key("Furius Carvetus"), "( ) ? fold out of keys, never out of the name"
    refute(keys.any? { |k| k.include?("-") }, "the -. unknown-praenomen placeholder never keys")
    assert_equal [key("Aemilia")], person("1698").name_keys, "a nomen-only name keys whole"
  end

  def test_part_rule_rejects_alternatives_and_fragments
    assert_equal "Philo", Nabu::DprrPersons.part_key("Philo (or Chilo)")
    assert_equal "Mallius", Nabu::DprrPersons.part_key("Mallius (Manlius)")
    assert_nil Nabu::DprrPersons.part_key("(Veturius) or (Publilius)")
    assert_nil Nabu::DprrPersons.part_key("(Cornelius or Mucius)")
    assert_nil Nabu::DprrPersons.part_key("-onius")
    assert_nil Nabu::DprrPersons.part_key("-")
    assert_nil Nabu::DprrPersons.part_key("Sca.u.la (Scapula or Scaevola)")
    assert_equal "Achilles Romanus", Nabu::DprrPersons.part_key("'Achilles Romanus'")
  end

  def test_producer_derives_a_resolvable_slice_idempotently
    producer = Nabu::DprrPersons::Producer.new(catalog: @catalog)
    census = producer.run("dprr", workdir: @workdir)
    assert_equal 4, census.persons
    assert_operator census.seconds, :>, 0
    producer.run("dprr", workdir: @workdir)
    resolver = Nabu::Store::PersonIndex.resolver(@catalog, authority: "dprr")
    assert_equal 4, resolver.size, "reruns supersede, never accrete"
    assert_equal ["1"], resolver.named("Lucius Iunius Brutus").map(&:person_id)
    assert_equal "http://romanrepublic.ac.uk/rdf/entity/Person/1016", resolver.person("1016").refs
  end

  def test_producer_without_the_answers_is_an_honest_noop
    assert_nil Nabu::DprrPersons::Producer.new(catalog: @catalog).run("dprr", workdir: Dir.mktmpdir)
  end

  def test_the_adapter_declares_the_seam
    assert Nabu::Adapters::Dprr.person_index_producer?
    assert_instance_of Nabu::DprrPersons::Producer,
                       Nabu::Adapters::Dprr.person_index_producer(catalog: @catalog)
    assert_includes Nabu::Store::PersonIndex::AUTHORITIES, "dprr"
  end
end
