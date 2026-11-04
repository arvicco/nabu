# frozen_string_literal: true

require "test_helper"
require "json"

# Nabu::ChantIdentity (the liturgy wave): the gregobase×cantus Cantus-ID
# join as kind=chant-identity edges — from the modern transcription to each
# manuscript record sharing the id, pinned to one scope so either shelf's
# sync re-derives the layer whole. Rows are seeded directly (the join reads
# only urn + metadata_json), with the shapes the first sync censused: a
# shared id with fan-out, an id no cantus record carries (the honest miss),
# and a cantus record whose id no gregobase chant cites (never an edge
# source — the join is deliberately one-directional).
class ChantIdentityTest < Minitest::Test
  include StoreTestDB

  G_HARTKER = "urn:nabu:gregobase:14738"
  G_LONELY = "urn:nabu:gregobase:99999"
  C_SG390 = "urn:nabu:cantus:455849"
  C_KLOSTER = "urn:nabu:cantus:600001"
  C_ORPHAN = "urn:nabu:cantus:600002"

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    seed!
  end

  def teardown
    @journal.disconnect
  end

  def producer = Nabu::ChantIdentity.new(catalog: @catalog, journal: @journal)

  def edges = @journal[:links].select_map(%i[from_urn to_urn kind detail])

  def test_mints_one_edge_per_shared_id_pair_and_counts_the_unmatched
    result = producer.run("gregobase")

    assert_equal 2, result.edges_written,
                 "the shared id 001737 joins the gregobase chant to BOTH cantus records carrying it"
    assert_equal 1, result.skipped_unmatched,
                 "the gregobase chant whose id no cantus record carries mints nothing, counted"
    assert_equal [[G_HARTKER, C_SG390, "chant-identity", "the same chant — Cantus ID 001737"],
                  [G_HARTKER, C_KLOSTER, "chant-identity", "the same chant — Cantus ID 001737"]],
                 edges.sort
  end

  def test_the_orphan_cantus_record_is_never_an_edge_source
    producer.run("cantus")

    refute edges.any? { |from, _to, _kind, _detail| from == C_ORPHAN },
           "the join is gregobase → cantus only; cantus×cantus closure is deliberately not minted"
  end

  def test_either_triggering_slug_supersedes_the_one_pinned_scope
    first = producer.run("gregobase")
    second = producer.run("cantus")

    assert_equal first.run_id + 1, second.run_id
    assert_equal 1, second.superseded_runs, "one scope: the second run replaces the first whole"
    assert_equal 2, @journal[:links].where(run_id: second.run_id).count
    assert_equal 2, result_rows_live, "no duplicate layer under a second scope"
  end

  def test_a_catalog_without_gregobase_rows_is_the_noop_that_supersedes_nothing
    @catalog[:documents].where(source_id: @gregobase.id).delete
    result = producer.run("gregobase")

    assert_nil result.run_id
    assert_equal 0, @journal[:links].count
  end

  private

  # supersede! DELETES prior runs and their edges (the journal keeps only
  # the current mining of a scope), so live = everything still present.
  def result_rows_live
    @journal[:links].count
  end

  def seed!
    @gregobase = Nabu::Store::Source.create(slug: "gregobase", name: "GregoBase",
                                            adapter_class: "Nabu::Adapters::Gregobase", license_class: "open")
    @cantus = Nabu::Store::Source.create(slug: "cantus", name: "Cantus Database",
                                         adapter_class: "Nabu::Adapters::Cantus", license_class: "nc")
    doc!(@gregobase, G_HARTKER, "001737")
    doc!(@gregobase, G_LONELY, "g99999")
    doc!(@cantus, C_SG390, "001737")
    doc!(@cantus, C_KLOSTER, "001737")
    doc!(@cantus, C_ORPHAN, "008111")
  end

  def doc!(source, urn, cantus_id)
    @catalog[:documents].insert(source_id: source.id, urn: urn, title: urn.split(":").last,
                                metadata_json: JSON.generate({ "cantus_id" => cantus_id }),
                                withdrawn: false, revision: 1,
                                content_sha256: Digest::SHA256.hexdigest(urn))
  end
end
