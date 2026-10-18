# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::AozoraPersons: the Aozora Bunko person columns of the
# person×work index (人物ID + 姓/名 + readings + romaji + life dates)
# projected into the "aozora" person-index slice. The index CSV is the
# authority — one stable id per person across every work row. Fixture:
# the trimmed real index (test/fixtures/aozora/README.md).
class AozoraPersonsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("aozora")

  def setup
    @catalog = store_test_db
  end

  def persons
    @persons ||= Nabu::AozoraPersons.each_person(FIXTURES).to_h { |p| [p.person_id, p] }
  end

  def test_one_person_per_id_across_every_work_row
    assert_equal %w[000235 000608 000621 000913 000915 001257 001258 001494 001657 001708 001931 001932],
                 persons.keys.sort, "deduped by 人物ID, in-copyright works' persons included"
    irving = persons["001257"]
    assert_equal "aozora", irving.authority
    assert_equal "Irving Washington", irving.name, "the index's own romaji, surname first"
    assert_equal "アーヴィング ワシントン", irving.name_han, "the native-form lane carries the index's own form"
    assert_equal 1783, irving.birth_year
    assert_equal 1859, irving.death_year
    assert_nil irving.female, "the index carries no sex column — unknown, never false"
    assert_nil irving.refs
  end

  def test_bce_dates_and_blank_dates
    plato = persons["000915"]
    assert_equal "Plato", plato.name, "an empty given name never leaves a dangling space"
    assert_equal "プラトン", plato.name_han
    assert_equal(-427, plato.birth_year, "前427 is 427 BCE")
    assert_equal(-347, plato.death_year)
    sogo = persons["000913"]
    assert_nil sogo.birth_year
    assert_nil sogo.death_year
  end

  def test_life_year_reader
    year = Nabu::AozoraPersons.method(:life_year)
    assert_equal 1874, year.call("1874-10-30")
    assert_equal 1861, year.call("1861")
    assert_equal 1905, year.call("1905- 1-08 ")
    assert_equal 800, year.call("800")
    assert_equal(-427, year.call("前427"))
    assert_nil year.call("192X"), "an unknown digit is never guessed"
    assert_nil year.call("紀元前7世紀末"), "century prose stays unparsed"
    assert_nil year.call("不詳")
    assert_nil year.call("")
  end

  def test_every_spelling_keys
    keys = persons["000608"].name_keys
    ["杉村 楚人冠", "杉村楚人冠", "すぎむら そじんかん", "Sugimura Sojinkan"].each do |form|
      assert_includes keys, Nabu::Pleiades.name_key(form)
    end
  end

  def test_producer_derives_the_slice_and_the_desk_resolves_it
    census = Nabu::AozoraPersons::Producer.new(catalog: @catalog).run("aozora", workdir: FIXTURES)
    assert_equal 12, census.persons
    resolver = Nabu::Store::PersonIndex.resolver(@catalog, authority: "aozora")
    assert_equal ["001932"], resolver.named("山東京山").map(&:person_id)
    assert_equal ["Santo Kyozan"], Nabu::Query::Person.new(catalog: @catalog).run("aozora:001932").cards.map(&:name)
    assert_equal ["001932"], Nabu::Query::Person.new(catalog: @catalog).run("山東 京山").cards.map(&:person_id),
                 "a bare name search reaches the aozora slice"

    2.times { Nabu::AozoraPersons::Producer.new(catalog: @catalog).run("aozora", workdir: FIXTURES) }
    assert_equal 12, @catalog[:person_index].where(authority: "aozora").count, "wholesale, never accreting"
  end

  def test_producer_without_an_index_is_an_honest_noop
    assert_nil Nabu::AozoraPersons::Producer.new(catalog: @catalog).run("aozora", workdir: Dir.mktmpdir)
  end

  def test_the_adapter_declares_the_seam
    assert Nabu::Adapters::Aozora.person_index_producer?
    assert_instance_of Nabu::AozoraPersons::Producer,
                       Nabu::Adapters::Aozora.person_index_producer(catalog: @catalog)
  end
end
