# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::KokubunkenPersons: the listPerson personographies of NIJL's TEI
# files (the 古今和歌集's 194 dated records with readings, aliases and
# VIAF links; the 万葉集 files' name-only records) projected into the
# "kokubunken" person-index slice. Fixtures: the real listPerson trimmed
# to a handful of records (test/fixtures/kokubunken/README.md).
class KokubunkenPersonsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("kokubunken")

  def setup
    @catalog = store_test_db
  end

  def persons
    @persons ||= Nabu::KokubunkenPersons.each_person(FIXTURES).to_h { |p| [p.person_id, p] }
  end

  def test_kokin_records_carry_dates_aliases_sex_and_viaf
    assert_equal 9, persons.size, "5 kokin + 4 manyo records, ids distinct"
    teika = persons["藤原定家"]
    assert_equal "kokubunken", teika.authority
    assert_equal "藤原定家", teika.name, "the first persName, its surname/given ／ dropped"
    assert_equal "藤原定家", teika.name_han
    assert_equal 1162, teika.birth_year
    assert_equal 1241, teika.death_year
    refute teika.female
    assert_equal "http://viaf.org/viaf/29592327", teika.refs
    %w[京極中納言 明静 ふじわらのていか 藤原定家].each do |alias_form|
      assert_includes teika.name_keys, Nabu::Pleiades.name_key(alias_form), "#{alias_form} keys"
    end
    assert_includes teika.name_keys, Nabu::Pleiades.name_key("藤原 定家"), "the spaced split keys too"
  end

  def test_unknown_dates_sex_and_placeholder_idnos
    ise = persons["伊勢"]
    assert ise.female, "sex 2 is female"
    assert_equal 875, ise.birth_year
    assert_nil ise.death_year, "不明 with no @when stays nil"
    assert_nil persons["安倍清行"].refs, "ナシ placeholders are no link"
    assert_equal 825, persons["安倍清行"].birth_year, "a zero-padded @when reads as its year"
  end

  def test_manyo_name_only_records
    jito = persons["持統天皇"]
    assert_equal "持統天皇", jito.name
    assert_includes jito.name_keys, Nabu::Pleiades.name_key("沙羅羅大后"), "the second name keys"
    assert_nil jito.birth_year
    assert_nil jito.female, "no sex attribute — unknown"
  end

  def test_producer_derives_the_slice_and_the_desk_resolves_a_han_ref
    census = Nabu::KokubunkenPersons::Producer.new(catalog: @catalog).run("kokubunken", workdir: FIXTURES)
    assert_equal 9, census.persons
    cards = Nabu::Query::Person.new(catalog: @catalog).run("kokubunken:藤原定家").cards
    assert_equal [1162], cards.map(&:birth_year), "a kanji authority id resolves as a ref"
    assert_equal ["藤原定家"], Nabu::Query::Person.new(catalog: @catalog).run("京極中納言").cards.map(&:person_id)
    2.times { Nabu::KokubunkenPersons::Producer.new(catalog: @catalog).run("kokubunken", workdir: FIXTURES) }
    assert_equal 9, @catalog[:person_index].where(authority: "kokubunken").count
  end

  def test_producer_without_tei_files_is_an_honest_noop
    assert_nil Nabu::KokubunkenPersons::Producer.new(catalog: @catalog).run("kokubunken", workdir: Dir.mktmpdir)
  end

  def test_the_adapter_declares_the_seam
    assert Nabu::Adapters::Kokubunken.person_index_producer?
    assert_instance_of Nabu::KokubunkenPersons::Producer,
                       Nabu::Adapters::Kokubunken.person_index_producer(catalog: @catalog)
  end
end
