# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::NikhPersons: the person authorities the NIKH index markup carries
# — sillok's M_ ids and the goryeosa family's p ids aggregated across a
# source's passages into its own person-index slice (person_id = the id,
# name = the surface tagged in the most passages, every surface a name key).
# Fixtures: the sources' own real members (test/fixtures/<slug>/).
class NikhPersonsTest < Minitest::Test
  include StoreTestDB

  def setup
    @catalog = store_test_db
  end

  def producer(slug) = Nabu::NikhPersons::Producer.new(catalog: @catalog, authority: slug)

  def persons(slug)
    adapter = Nabu::NikhPersons.adapter_for(slug)
    Nabu::NikhPersons.each_person(adapter, Nabu::TestSupport.fixtures(slug), authority: slug)
                     .to_h { |person| [person.person_id, person] }
  end

  def test_sillok_aggregates_m_ids_with_the_most_frequent_surface_as_name
    sillok = persons("sillok")
    junmyeong = sillok.fetch("M_0006771")
    assert_equal "sillok", junmyeong.authority
    assert_equal "純明皇后", junmyeong.name, "a 1–1 tie keeps the first-seen surface"
    assert_equal "純明皇后", junmyeong.name_han, "the native-form lane carries the same Han name"
    assert_equal %w[純明皇后 純明孝皇后].map { |n| Nabu::Pleiades.name_key(n) }, junmyeong.name_keys,
                 "every tagged surface keys"
    haryun = sillok.fetch("M_0059127")
    assert_equal "晋山府院君", haryun.name, "晋山府院君 and 河崙 tie 1–1: document order breaks it"
    assert_includes haryun.name_keys, Nabu::Pleiades.name_key("河崙"), "both surfaces key the one person"
    assert(sillok.keys.all? { |id| id.match?(/\AM_\d+\z/) }, "only the authority's own M_ ids")
  end

  def test_goryeosa_aggregates_its_p_ids_and_never_its_office_or_place_ids
    goryeosa = persons("goryeosa")
    jo = goryeosa.fetch("p094190")
    assert_equal "浚", jo.name, "the surface in the most passages wins (the biography's bare given name)"
    assert_includes jo.name_keys, Nabu::Pleiades.name_key("趙浚")
    assert_includes jo.name_keys, Nabu::Pleiades.name_key("明仲"), "the courtesy name groups under the id"
    assert(goryeosa.keys.all? { |id| id.match?(/\Ap\d+\z/) }, "offices (o), places (t), orgs (m) are not persons")
  end

  def test_jeoryo_derives_its_own_slice_from_its_own_passages
    jeoryo = persons("goryeosa-jeoryo")
    assert_equal "興邦", jeoryo.fetch("p054180").name
    refute_includes jeoryo.keys, nil
  end

  def test_producer_derives_the_slice_wholesale_and_the_desk_resolves_it
    census = producer("goryeosa").run("goryeosa", workdir: Nabu::TestSupport.fixtures("goryeosa"))
    assert_operator census.persons, :>, 100
    count = @catalog[:person_index].where(authority: "goryeosa").count
    assert_equal census.persons, count
    producer("goryeosa").run("goryeosa", workdir: Nabu::TestSupport.fixtures("goryeosa"))
    assert_equal count, @catalog[:person_index].where(authority: "goryeosa").count, "wholesale, never accreting"
    refute Nabu::Store::PersonIndex.populated?(@catalog, authority: "sillok"), "one slice per authority"

    desk = Nabu::Query::Person.new(catalog: @catalog)
    assert_equal ["浚"], desk.run("goryeosa:p094190").cards.map(&:name)
    assert_includes desk.run("明仲").cards.map(&:person_id), "p094190", "a name search reaches the slice"
  end

  def test_a_nikh_ref_fans_out_across_the_nikh_authorities
    producer("goryeosa").run("goryeosa", workdir: Nabu::TestSupport.fixtures("goryeosa"))
    producer("goryeosa-jeoryo").run("goryeosa-jeoryo", workdir: Nabu::TestSupport.fixtures("goryeosa-jeoryo"))
    cards = Nabu::Query::Person.new(catalog: @catalog).run("nikh:p102380").cards
    assert_equal %w[goryeosa goryeosa-jeoryo], cards.map(&:authority),
                 "崔瑩 is tagged in both chronicles — the two share NIKH's Goryeo person id space"
    assert_raises(Nabu::Query::Person::Error) { Nabu::Query::Person.new(catalog: @catalog).run("nikh:p999999999") }
  end

  def test_an_empty_workdir_is_an_honest_noop
    Dir.mktmpdir { |dir| assert_nil producer("sillok").run("sillok", workdir: dir) }
  end

  def test_the_id_bearing_adapters_declare_the_seam
    { "sillok" => Nabu::Adapters::Sillok, "goryeosa" => Nabu::Adapters::Goryeosa,
      "goryeosa-jeoryo" => Nabu::Adapters::GoryeosaJeoryo }.each do |slug, adapter|
      assert adapter.person_index_producer?, slug
      assert_equal slug, adapter.person_index_producer(catalog: @catalog).authority
    end
    refute Nabu::Adapters::Sjw.person_index_producer?, "sjw tags carry no person ids"
    refute Nabu::Adapters::Bibyeonsa.person_index_producer?
    assert_equal %w[sillok goryeosa goryeosa-jeoryo], Nabu::Store::PersonIndex::AUTHORITIES.last(3)
  end
end
