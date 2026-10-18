# frozen_string_literal: true

require "test_helper"
require "json"

# Nabu::OpenitiRelations: the OpenITI book sidecars' RELATED work↔work
# assertions ("0458Bayhaqi.ShucabIman (ABR.mukhtasar)") as kind=reference
# edges in the links journal — joined at BOOK grain against the held
# versions (a book's every held version asserts the edge to the target
# book's every held version), the KitabReuse catalog-join mold. The
# metadata shapes here are exactly what Adapters::Openiti#parse emits
# from the real fixture sidecars (test/adapters/openiti_test.rb).
class OpenitiRelationsTest < Minitest::Test
  include StoreTestDB

  QAZWINI = "urn:nabu:openiti:0699IbnCabdRahmanQazwiniShafici.MukhtasarShucabIman.JK000027-ara1"
  BAYHAQI_A = "urn:nabu:openiti:0458Bayhaqi.ShucabIman.JK000025-ara1"
  BAYHAQI_B = "urn:nabu:openiti:0458Bayhaqi.ShucabIman.Shamela0001018-ara1"
  NAFS = "urn:nabu:openiti:0428IbnSina.ShifaNafs.Shamela0007066-ara1"
  SHIFA = "urn:nabu:openiti:0428IbnSina.Shifa.AOCP0000001-ara1"

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    @source = Nabu::Store::Source.create(slug: "openiti", name: "OpenITI", adapter_class: "X",
                                         license_class: "nc")
    held(QAZWINI, { "related_works" => [{ "work" => "0458Bayhaqi.ShucabIman", "relation" => "ABR.mukhtasar" }] })
    held(BAYHAQI_A)
    held(BAYHAQI_B)
    held(NAFS, { "related_works" => [{ "work" => "0428IbnSina.Shifa", "relation" => "PART" },
                                     { "work" => "0428IbnSina.Tabiciyyat", "relation" => "PART" },
                                     { "work" => "0001Aristotle.DeAnima", "relation" => "COMM" }] })
    held(SHIFA)
  end

  def teardown
    @journal.disconnect
  end

  def held(urn, metadata = {})
    @counter = (@counter || 0) + 1
    Nabu::Store::Document.create(source_id: @source.id, urn: urn, language: "ara", title: urn,
                                 canonical_path: "x", content_sha256: @counter.to_s.rjust(64, "0"),
                                 metadata_json: JSON.generate(metadata))
  end

  def run_producer
    Nabu::Adapters::Openiti.reference_producer(catalog: @catalog, journal: @journal).run("openiti", workdir: nil)
  end

  def test_the_openiti_adapter_declares_the_reference_producer
    assert Nabu::Adapters::Openiti.reference_edges?
    assert_instance_of Nabu::OpenitiRelations,
                       Nabu::Adapters::Openiti.reference_producer(catalog: @catalog, journal: @journal)
  end

  def test_book_grain_join_mints_one_edge_per_held_version_pair
    result = run_producer
    assert_equal 3, result.edges_written, "Qazwini → both Bayhaqi versions, Nafs → Shifa"
    assert_equal 2, result.skipped_unheld, "Tabiciyyat and Aristotle's De anima are not held"
    edges = @journal[:links].where(kind: "reference").order(:from_urn, :to_urn).select_map(%i[from_urn to_urn])
    assert_equal [[NAFS, SHIFA], [QAZWINI, BAYHAQI_A], [QAZWINI, BAYHAQI_B]], edges
    detail = @journal[:links].first(from_urn: QAZWINI, to_urn: BAYHAQI_A)[:detail]
    assert_includes detail, "ABR.mukhtasar"
    assert_includes detail, "0699IbnCabdRahmanQazwiniShafici.MukhtasarShucabIman → 0458Bayhaqi.ShucabIman"
    assert_nil @journal[:links].first(from_urn: QAZWINI)[:score], "a curated assertion carries no score"
  end

  def test_a_rerun_supersedes_and_a_withdrawn_target_never_joins
    run_producer
    @catalog[:documents].where(urn: BAYHAQI_B).update(withdrawn: true)
    result = run_producer
    assert_equal 1, result.superseded_runs
    assert_equal 2, result.edges_written
    assert_equal 0, @journal[:links].where(to_urn: BAYHAQI_B).count
  end
end
