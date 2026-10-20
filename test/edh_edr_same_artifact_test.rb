# frozen_string_literal: true

require "test_helper"

# Nabu::EdhEdrSameArtifact — kind=same-artifact edges between an EDH and an
# EDR edition of ONE physical inscription, joined on the Trismegistos text
# number both upstreams record, with the per-field preferred-witness hint
# in each edge's detail. Trimmed-real fixtures: three whole EDH records +
# their text/pers CSV rows and the three whole EDR records sharing their TM
# numbers (test/fixtures/edh_edr_same_artifact/README.md).
class EdhEdrSameArtifactTest < Minitest::Test
  include StoreTestDB

  ROOT = Nabu::TestSupport.fixtures("edh_edr_same_artifact")

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    { "edh" => Nabu::Adapters::Edh, "edr" => Nabu::Adapters::Edr }.each do |slug, klass|
      source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: klass.name,
                                          license_class: "attribution")
      Nabu::Store::Loader.new(db: @catalog, source: source).load_from(klass.new, workdir: File.join(ROOT, slug))
    end
    Nabu::Store::TimelineBuilder.rebuild!(catalog: @catalog, canonical_dir: ROOT)
  end

  def teardown
    @journal.disconnect
  end

  def producer = Nabu::EdhEdrSameArtifact.new(catalog: @catalog, journal: @journal)

  def edge(from, to)
    @journal[:links].first(from_urn: from, to_urn: to, kind: "same-artifact")
  end

  # --- the join ------------------------------------------------------------------

  def test_mints_one_edge_per_shared_trismegistos_number
    result = producer.run("edr")
    assert_equal 3, result.edges_written
    assert_equal 3, result.shared_tm_ids
    assert_equal 3, @journal[:links].where(kind: "same-artifact").count
    refute_nil edge("urn:nabu:edh:hd002664", "urn:nabu:edr:edr078741"), "TM 248008"
    refute_nil edge("urn:nabu:edh:hd008415", "urn:nabu:edr:edr080335"), "TM 251503"
    refute_nil edge("urn:nabu:edh:hd003323", "urn:nabu:edr:edr092812"), "TM 249515"
  end

  def test_edges_are_assertions_not_scores_and_never_merge_documents
    producer.run("edr")
    row = edge("urn:nabu:edh:hd002664", "urn:nabu:edr:edr078741")
    assert_nil row[:score]
    assert_equal 6, @catalog[:documents].count, "both editions stay documents of their own"
  end

  def test_an_unpartnered_witness_mints_nothing
    @catalog[:documents].where(urn: "urn:nabu:edr:edr092812").update(withdrawn: true)
    result = producer.run("edr")
    assert_equal 2, result.edges_written
    assert_nil edge("urn:nabu:edh:hd003323", "urn:nabu:edr:edr092812"), "a withdrawn witness is not held"
  end

  # --- the preferred-witness hint ------------------------------------------------

  # TM 248008: EDR's "Gai Caecinae" (3 supplied of 11) beats EDH's "Caecina"
  # (2 of 7); EDR's 1–100 is narrower than EDH's 1–200; only EDH's findspot
  # carries a Pleiades id.
  def test_hint_splits_fields_across_witnesses
    producer.run("edr")
    assert_equal "Trismegistos 248008 · prefer text=edr date=edr findspot=edh",
                 edge("urn:nabu:edh:hd002664", "urn:nabu:edr:edr078741")[:detail]
  end

  # TM 251503: EDH's "Artemo" (1 of 6 supplied) beats EDR's lacunose lines;
  # EDH carries no date, so EDR's range is the narrower; EDH's Pleiades id.
  def test_undated_witness_loses_the_date_field
    producer.run("edr")
    assert_equal "Trismegistos 251503 · prefer text=edh date=edr findspot=edh",
                 edge("urn:nabu:edh:hd008415", "urn:nabu:edr:edr080335")[:detail]
  end

  # TM 249515: identical text ("Vicimus", nothing supplied) and identical
  # dates tie through to EDH; with both findspots on Pleiades (EDR's via the
  # place-apply projection, as in the live catalog) the longer one wins.
  def test_ties_fall_to_edh_and_the_longer_findspot_wins_between_two_pleiades_ids
    doc = @catalog[:documents].first(urn: "urn:nabu:edr:edr092812")
    @catalog[:document_axes].where(document_id: doc[:id]).update(place_ref: "pleiades:433032")
    producer.run("edr")
    assert_equal "Trismegistos 249515 · prefer text=edh date=edh findspot=edr",
                 edge("urn:nabu:edh:hd003323", "urn:nabu:edr:edr092812")[:detail]
  end

  def test_preference_rule_unit
    witness = lambda do |slug, letters:, supplied:, from: nil, to: nil, pleiades: false, findspot: ""|
      Nabu::EdhEdrSameArtifact::Witness.new(urn: slug, slug: slug, letters: letters, supplied: supplied,
                                            not_before: from, not_after: to, pleiades: pleiades,
                                            findspot: findspot)
    end
    edh = witness.call("edh", letters: 10, supplied: 5, from: 1, to: 100, findspot: "Roma")
    edr = witness.call("edr", letters: 20, supplied: 10, from: 1, to: 100, findspot: "Roma, via Appia")
    pref = Nabu::EdhEdrSameArtifact.preference(edh, edr)
    assert_equal "edr", pref.text, "equal supplied share → the fuller text"
    assert_equal "edh", pref.date, "equal ranges → EDH"
    assert_equal "edr", pref.findspot, "no Pleiades on either side → the longer findspot"

    open_ended = witness.call("edr", letters: 1, supplied: 1, from: 50, findspot: "")
    assert_equal "edh", Nabu::EdhEdrSameArtifact.preference(edh, open_ended).date,
                 "an open-ended date is no narrower than a closed range"
    empty = witness.call("edh", letters: 0, supplied: 0)
    assert_equal "edr", Nabu::EdhEdrSameArtifact.preference(empty, edr).text,
                 "a letterless witness never wins the text field"
  end

  # --- run mechanics ---------------------------------------------------------------

  def test_rerun_from_either_side_supersedes_the_one_run
    producer.run("edh")
    second = producer.run("edr")
    assert_equal 1, second.superseded_runs, "edh and edr syncs share ONE (producer, scope) run"
    assert_equal 3, @journal[:links].where(kind: "same-artifact").count
    assert_equal 1, @journal[:link_runs].where(producer: Nabu::EdhEdrSameArtifact::PRODUCER).count
  end

  def test_rerun_is_idempotent_and_rebuild_equivalent
    producer.run("edr")
    first = @journal[:links].where(kind: "same-artifact").order(:from_urn).select_map(%i[from_urn to_urn detail])
    @journal[:links].delete
    @journal[:link_runs].delete
    producer.run("edr")
    again = @journal[:links].where(kind: "same-artifact").order(:from_urn).select_map(%i[from_urn to_urn detail])
    assert_equal first, again
  end

  def test_both_adapters_declare_the_producer
    [Nabu::Adapters::Edh, Nabu::Adapters::Edr].each do |klass|
      assert klass.reference_edges?, "#{klass} re-derives the concordance after its sync"
      assert_instance_of Nabu::EdhEdrSameArtifact, klass.reference_producer(catalog: @catalog, journal: @journal)
    end
  end
end
