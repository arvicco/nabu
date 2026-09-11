# frozen_string_literal: true

require "test_helper"

# Nabu::CbdbPersons + Store::PersonIndex (P97-2 — №R-62 option b): the
# CBDB thin slice — BIOG_MAIN + ALTNAME_DATA + DYNASTIES from the held
# sqlite artifact derived into the "cbdb" person-index slice, resolvable
# in either script through the shared fold. Fixture: real rows
# (test/fixtures/cbdb/README.md) — Wang Anshi with three alt names,
# Su Shi without, Wu Shi with the 0-year unknown shape.
class CbdbPersonsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("cbdb")

  def setup
    @catalog = store_test_db
    @workdir = Dir.mktmpdir
    @sqlite = File.join(@workdir, "cbdb_20260905.sqlite3")
    db = Sequel.sqlite(@sqlite)
    sql = File.read(File.join(FIXTURES, "person_sample.sql"))
              .lines.reject { |l| l.start_with?("--") }.join
    sql.split(";\n").map(&:strip).reject(&:empty?).each { |stmt| db.run(stmt) }
    db.disconnect
  end

  def teardown
    FileUtils.remove_entry(@workdir)
  end

  def persons
    @persons ||= Nabu::CbdbPersons.each_person(@sqlite).to_a
  end

  def wang
    persons.find { |p| p.person_id == "1762" }
  end

  # --- the artifact walk ----------------------------------------------------

  def test_walks_all_fixture_persons_with_dynasty_resolved
    assert_equal 3, persons.size
    assert_equal "Wang Anshi", wang.name
    assert_equal "王安石", wang.name_han
    assert_equal 1021, wang.birth_year
    assert_equal 1086, wang.death_year
    assert_equal "Song", wang.dynasty
    assert_equal "宋", wang.dynasty_han
    refute wang.female
  end

  def test_alt_names_key_in_both_scripts_and_zero_years_are_nil
    assert_includes wang.name_keys, Nabu::Pleiades.name_key("介甫"),
                    "the courtesy name keys — texts cite people by zi"
    assert_includes wang.name_keys, Nabu::Pleiades.name_key("Jiefu")
    assert_includes wang.name_keys, Nabu::Pleiades.name_key("王荊公")

    wu = persons.find { |p| p.person_id == "38653" }
    assert_nil wu.birth_year, "CBDB's 0 means unknown — an honest nil"
    assert_equal 1024, wu.index_year
    assert wu.female
  end

  # --- the derive + resolver -------------------------------------------------

  def test_producer_derives_the_slice_resolvable_in_either_script
    census = Nabu::CbdbPersons::Producer.new(catalog: @catalog).run("cbdb", workdir: @workdir)
    assert_equal 3, census.persons
    assert_operator census.seconds, :>, 0, "elapsed rides the census (owner rule 2026-09-11)"

    resolver = Nabu::Store::PersonIndex.resolver(@catalog, authority: "cbdb")
    assert_equal 3, resolver.size
    assert_equal "王安石", resolver.person("1762").name_han
    assert_equal ["王安石"], resolver.named("王安石").map(&:name_han), "hanzi resolves"
    assert_equal ["王安石"], resolver.named("Wang Anshi").map(&:name_han), "pinyin resolves"
    assert_equal ["王安石"], resolver.named("介甫").map(&:name_han), "the courtesy name resolves"
  end

  def test_derive_is_idempotent_and_wholesale
    producer = Nabu::CbdbPersons::Producer.new(catalog: @catalog)
    2.times { producer.run("cbdb", workdir: @workdir) }
    assert_equal 3, @catalog[:person_index].count, "reruns supersede, never accrete"
    assert_equal 3, Nabu::Store::PersonIndex.resolver(@catalog).size
  end

  def test_producer_without_the_artifact_is_an_honest_noop
    assert_nil Nabu::CbdbPersons::Producer.new(catalog: @catalog).run("cbdb", workdir: Dir.mktmpdir)
  end

  def test_the_adapter_declares_the_seam
    assert Nabu::Adapters::Cbdb.person_index_producer?
    assert_instance_of Nabu::CbdbPersons::Producer,
                       Nabu::Adapters::Cbdb.person_index_producer(catalog: @catalog)
  end
end
