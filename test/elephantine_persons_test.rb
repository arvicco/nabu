# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::ElephantinePersons: the Elephantine ancient-persons authority
# (elephantine_erc_db_ancient_persons.tei.xml — 7,577 <person> records,
# fetched with the record crawl but never read before) projected into
# the "elephantine" person-index slice beside CBDB's. Fixture: a
# byte-verbatim trim of the real authority file (README).
class ElephantinePersonsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("elephantine")
  AUTHORITY_FILE = File.join(FIXTURES, "elephantine_erc_db_ancient_persons.tei.xml")

  def setup
    @catalog = store_test_db
  end

  def persons
    @persons ||= Nabu::ElephantinePersons.each_person(AUTHORITY_FILE).to_h { |p| [p.person_id, p] }
  end

  def test_walks_historical_and_mythological_persons
    assert_equal 13, persons.size, "11 historical + 2 mythological in the trim"
    assert_includes persons.keys, "d1", "deities keep upstream's own d-prefixed ids"
    assert_equal "Amun", persons["d1"].name
    assert_equal "Jmn", persons["d1"].name_han, "the untagged original-language form"
  end

  def test_names_sex_and_trismegistos_refs
    p30 = persons["p30"]
    assert_equal "elephantine", p30.authority
    assert_equal "Bienchis, son of Pachnoumis (P.23690)", p30.name
    assert_equal "By-Ꜥnḫ sꜢ Pa-H̱nm", p30.name_han, "the original-language form rides the native-name lane"
    assert_equal "http://www.trismegistos.org/per/detail.php?pnr=57217 " \
                 "http://www.trismegistos.org/nam/detail.php?record=103", p30.refs,
                 "the TM person link first, then the TM name record — verbatim URLs"
    refute p30.female
    assert persons["p2635"].female, "sex value 2 is female"
    assert_equal "http://www.trismegistos.org/nam/detail.php?record=298", persons["p20"].refs,
                 "p20 has a TM name record but no TM person link"
    assert_nil persons["p9665"].refs, "no TM links at all → nil, never empty"
  end

  def test_every_name_form_keys_including_epithets
    keys = persons["d1"].name_keys
    assert_includes keys, Nabu::Pleiades.name_key("Amun")
    assert_includes keys, Nabu::Pleiades.name_key("Jmn")
    assert_includes keys, Nabu::Pleiades.name_key("nb"), "epithets are spellings texts cite"
    assert_includes persons["p21875"].name_keys, Nabu::Pleiades.name_key("Πραξοῦς Πετεχῶντος")
  end

  def test_producer_derives_the_slice_beside_other_authorities
    workdir = Dir.mktmpdir
    FileUtils.cp(AUTHORITY_FILE, workdir)
    census = Nabu::ElephantinePersons::Producer.new(catalog: @catalog).run("elephantine", workdir: workdir)
    assert_equal 13, census.persons
    assert_operator census.seconds, :>, 0

    resolver = Nabu::Store::PersonIndex.resolver(@catalog, authority: "elephantine")
    hatres = resolver.person("p19245")
    assert_equal "Hatres (praktor sitikon)", hatres.name
    assert_includes hatres.refs, "pnr=299720"
    assert_equal ["p19245"], resolver.named("Hatres (praktor sitikon)").map(&:person_id)
    refute Nabu::Store::PersonIndex.populated?(@catalog, authority: "cbdb"),
           "one authority's derive never touches another's slice"

    2.times { Nabu::ElephantinePersons::Producer.new(catalog: @catalog).run("elephantine", workdir: workdir) }
    assert_equal 13, @catalog[:person_index].where(authority: "elephantine").count, "wholesale, never accreting"
  ensure
    FileUtils.remove_entry(workdir) if workdir
  end

  def test_producer_without_the_authority_file_is_an_honest_noop
    assert_nil Nabu::ElephantinePersons::Producer.new(catalog: @catalog).run("elephantine", workdir: Dir.mktmpdir)
  end

  def test_the_adapter_declares_the_seam
    assert Nabu::Adapters::Elephantine.person_index_producer?
    assert_instance_of Nabu::ElephantinePersons::Producer,
                       Nabu::Adapters::Elephantine.person_index_producer(catalog: @catalog)
  end

  def test_the_person_desk_resolves_an_elephantine_ref
    workdir = Dir.mktmpdir
    FileUtils.cp(AUTHORITY_FILE, workdir)
    Nabu::ElephantinePersons::Producer.new(catalog: @catalog).run("elephantine", workdir: workdir)
    cards = Nabu::Query::Person.new(catalog: @catalog).run("elephantine:p100").cards
    assert_equal ["Harchebis"], cards.map(&:name)
  ensure
    FileUtils.remove_entry(workdir) if workdir
  end
end
