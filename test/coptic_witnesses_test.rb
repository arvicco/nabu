# frozen_string_literal: true

require "test_helper"
require "json"

# Nabu::CopticWitnesses — the Coptic Scriptorium reference producer: the
# header `witness` field's upstream-asserted parallel-witness CTS urns
# become kind=parallel-witness edges between the two manuscripts' documents,
# beside the Trismegistos "tm:<n>" reference edges the producer has always
# carried (one producer, one run per sync — both edge families supersede
# together). Prose witness notes ("none", "unique", "MONB.XO 80-82 … not
# published by Coptic Scriptorium") name no stable id and mint nothing.
class CopticWitnessesTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("coptic-scriptorium")
  SLUG = "coptic-scriptorium"
  KIND = "parallel-witness"

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    @source = Nabu::Store::Source.create(slug: SLUG, name: "Coptic Scriptorium",
                                         adapter_class: "Nabu::Adapters::CopticScriptorium", license_class: "nc")
  end

  def teardown
    @journal.disconnect
  end

  def producer = Nabu::Adapters::CopticScriptorium.reference_producer(catalog: @catalog, journal: @journal)

  def make_document(tail, witness: nil, related: nil, withdrawn: false)
    metadata = {}
    metadata["witness"] = witness if witness
    metadata["related"] = related if related
    Nabu::Store::Document.create(
      source_id: @source.id, urn: "urn:nabu:coptic-scriptorium:#{tail}", title: tail, language: "cop",
      metadata_json: JSON.generate(metadata), content_sha256: "x", revision: 1, withdrawn: withdrawn
    )
  end

  def witness_edges = @journal[:links].where(kind: KIND).order(:from_urn, :to_urn).all

  # [[from, to], …] of the witness edges, urn order.
  def edge_ends = witness_edges.map { |edge| [edge[:from_urn], edge[:to_urn]] }

  def sole_witness_edge
    edges = witness_edges
    assert_equal 1, edges.size, "exactly one parallel-witness edge"
    edges.first
  end

  # --- the urn extraction (pure) ----------------------------------------------

  # The censused value shapes: one bare urn, several comma-joined urns mixed
  # with unpublished sigla, urns embedded in prose with a sentence-final
  # period, and prose/none values that name no urn at all.
  def test_witness_targets_extract_every_cts_urn_and_nothing_else
    targets = Nabu::Adapters::CopticScriptorium.method(:witness_targets)
    assert_equal ["urn:nabu:coptic-scriptorium:shenoute.abraham.monbzh:18-22"],
                 targets.call("urn:cts:copticLit:shenoute.abraham.monbzh:18-22")
    assert_equal %w[urn:nabu:coptic-scriptorium:shenoute.eagerness.monbgl_54_60
                    urn:nabu:coptic-scriptorium:shenoute.eagerness.monbgl_61_63],
                 targets.call("urn:cts:copticLit:shenoute.eagerness.monbgl_54_60, " \
                              "urn:cts:copticLit:shenoute.eagerness.monbgl_61_63, " \
                              "MONB.DD 219-220 (not published by Coptic SCRIPTORIUM)")
    assert_equal %w[urn:nabu:coptic-scriptorium:shenoute.abraham.monbya:10-18
                    urn:nabu:coptic-scriptorium:shenoute.abraham.monbya:21-27],
                 targets.call("Beginning has parallel with urn:cts:copticLit:shenoute.abraham.monbya:10-18. " \
                              "End has parallel with urn:cts:copticLit:shenoute.abraham.monbya:21-27")
    assert_empty targets.call("none")
    assert_empty targets.call("unique")
    assert_empty targets.call("A parallel witness exists in MONB.ZC 283-84, which has not been published")
    assert_empty targets.call(nil)
  end

  # The magical-papyri namespace keeps its full urn as the document tail
  # (the frozen copticMag minting), so a copticMag witness maps the same way.
  def test_coptic_mag_witness_urns_follow_the_frozen_document_minting
    assert_equal ["urn:nabu:coptic-scriptorium:urn:cts:copticMag:kyprianos.tm98063.kypt340"],
                 Nabu::Adapters::CopticScriptorium.witness_targets("urn:cts:copticMag:kyprianos.tm98063.kypt340")
  end

  # --- the producer -----------------------------------------------------------

  def test_mints_parallel_witness_edges_with_the_upstream_assertion_as_detail
    make_document("shenoute.dirt.monbgl:0-5", witness: "urn:cts:copticLit:shenoute.dirt.monbxj:3-5")
    make_document("shenoute.dirt.monbxj:3-5")
    result = producer.run(SLUG)

    edge = sole_witness_edge
    assert_equal "urn:nabu:coptic-scriptorium:shenoute.dirt.monbgl:0-5", edge[:from_urn]
    assert_equal "urn:nabu:coptic-scriptorium:shenoute.dirt.monbxj:3-5", edge[:to_urn]
    assert_nil edge[:score], "an upstream assertion carries no fake similarity score"
    assert_equal "witness urn:cts:copticLit:shenoute.dirt.monbxj:3-5", edge[:detail]
    assert_equal 1, result.witness_documents
    assert_equal 1, result.witness_asserted
    assert_equal 1, result.witness_resolved
    assert_equal 0, result.unknown_ids
  end

  # Both manuscripts usually name each other: ONE edge per pair, the detail
  # saying the assertion is mutual.
  def test_a_mutual_assertion_is_one_edge
    make_document("theodosiusalex.michael.budge_ai_ed:9-30",
                  witness: "urn:cts:copticLit:theodosiusalex.michael.budge_al_ed:9-30")
    make_document("theodosiusalex.michael.budge_al_ed:9-30",
                  witness: "urn:cts:copticLit:theodosiusalex.michael.budge_ai_ed:9-30")
    result = producer.run(SLUG)

    edge = sole_witness_edge
    assert_equal "urn:nabu:coptic-scriptorium:theodosiusalex.michael.budge_ai_ed:9-30", edge[:from_urn]
    assert_equal "witness urn:cts:copticLit:theodosiusalex.michael.budge_al_ed:9-30 (asserted by both)",
                 edge[:detail]
    assert_equal 2, result.witness_asserted
    assert_equal 2, result.witness_resolved
  end

  # An urn the catalog does not hold still mints (upstream's own stable id
  # space — the edge resolves the day the document loads) and is counted
  # unresolved, never dropped silently; prose and "none" values count as
  # prose, never edges; a withdrawn document asserts nothing.
  def test_unresolved_targets_mint_and_count_and_prose_counts_as_prose
    make_document("shenoute.abraham.monbya:21-27", witness: "urn:cts:copticLit:shenoute.abraham.monbzh:18-22")
    make_document("shenoute.crushed.amelineau:18-20",
                  witness: "A parallel witness to this fragment appears in MONB.XO 80-82.")
    make_document("helias.martyrdom.sobhy_ed:0-15", witness: "none")
    make_document("shenoute.dirt.monbxj:5-7", witness: "urn:cts:copticLit:shenoute.dirt.monbgl:5-7", withdrawn: true)
    result = producer.run(SLUG)

    assert_equal ["urn:nabu:coptic-scriptorium:shenoute.abraham.monbzh:18-22"], edge_ends.map(&:last)
    assert_equal 1, result.witness_documents
    assert_equal 2, result.witness_prose
    assert_equal 1, result.witness_asserted
    assert_equal 0, result.witness_resolved
    assert_equal 1, result.unknown_ids, "the sync tail's ?N unknown-upstream counter"
  end

  # The one censused urn that is NOT a parallel witness: MONB.GL 29's note
  # points at the document holding the REST of the same manuscript
  # (monbgl_29 → monbgl_29_30 — same work, same codex siglum once the page
  # suffix drops). Same-manuscript continuations mint nothing and are
  # counted; different codices of one work (monbgl vs monbxj, Budge ai vs
  # al) stay witnesses.
  def test_a_same_manuscript_continuation_is_not_a_witness
    make_document("shenoute.eagerness.monbgl_29",
                  witness: "The first part of MONB.GL 29-30 has no parallel witnesses; the remainder of " \
                           "MONB.GL 29-30, which is parallel to MONB.XJ 33-34, is in " \
                           "urn:cts:copticLit:shenoute.eagerness.monbgl_29_30")
    make_document("shenoute.eagerness.monbgl_29_30", witness: "urn:cts:copticLit:shenoute.eagerness.monbxj_33_34")
    make_document("shenoute.eagerness.monbxj_33_34")
    result = producer.run(SLUG)

    assert_equal [%w[urn:nabu:coptic-scriptorium:shenoute.eagerness.monbgl_29_30
                     urn:nabu:coptic-scriptorium:shenoute.eagerness.monbxj_33_34]],
                 edge_ends
    assert_equal 1, result.witness_same_manuscript
    assert_equal 1, result.witness_asserted
  end

  # The Trismegistos edges this producer always carried ride the same run:
  # the witness family joins them, it does not replace them.
  def test_trismegistos_reference_edges_ride_the_same_run
    make_document("besa.food.monbbb", related: ["tm:108395"],
                                      witness: "urn:cts:copticLit:besa.vigilance.monbba")
    result = producer.run(SLUG)

    assert_equal %w[parallel-witness reference], @journal[:links].order(:kind).select_map(:kind)
    assert_equal 2, result.edges_written
    run = @journal[:link_runs].first(id: result.run_id)
    assert_equal SLUG, run[:producer]
    assert_equal SLUG, run[:scope]
  end

  def test_a_rerun_supersedes_the_prior_run
    make_document("shenoute.dirt.monbgl:0-5", witness: "urn:cts:copticLit:shenoute.dirt.monbxj:3-5")
    producer.run(SLUG)
    @catalog[:documents].where(urn: "urn:nabu:coptic-scriptorium:shenoute.dirt.monbgl:0-5").update(withdrawn: true)
    result = producer.run(SLUG)

    assert_empty witness_edges, "a withdrawn assertion drops its edge"
    assert_equal 1, result.superseded_edges
  end

  # End to end over the real fixture headers, through the adapter and the
  # loader: theodosius and abraham name urns (their partner manuscripts are
  # not in the trimmed fixture set — counted unresolved), considering /
  # helias / OCrum carry prose ("no known extant parallel witnesses",
  # "none", "unique").
  def test_fixture_headers_through_the_loader
    Nabu::Store::Loader.new(db: @catalog, source: @source)
                       .load_from(Nabu::Adapters::CopticScriptorium.new, workdir: FIXTURES)
    result = producer.run(SLUG)

    assert_equal [["urn:nabu:coptic-scriptorium:shenoute.abraham.monbya:21-27",
                   "urn:nabu:coptic-scriptorium:shenoute.abraham.monbzh:18-22"],
                  ["urn:nabu:coptic-scriptorium:theodosiusalex.michael.budge_al_ed:9-30",
                   "urn:nabu:coptic-scriptorium:theodosiusalex.michael.budge_ai_ed:9-30"]],
                 edge_ends
    assert_equal 2, result.witness_documents
    assert_equal 3, result.witness_prose
    assert_equal 2, result.witness_asserted
    assert_equal 2, result.unknown_ids
  end
end
