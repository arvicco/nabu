# frozen_string_literal: true

require "test_helper"

# Nabu::CorphDilReferences (P25-0): the eDIL bridge. CorPH's LEMMATA table
# keys most lemmas to dil.ie's stable id space (DIL_Headword); the adapter
# carries those ids per token ("dil"), and this producer journals one
# kind=reference edge per DISTINCT (document, dil id) pair — from the corph
# document urn into urn:nabu:dict:edil:<id>, the urn the future eDIL
# dictionary shelf will mint (the dictionary-urn convention
# urn:nabu:dict:<slug>:<entry id>). Reruns supersede, the batch-producer
# contract. Exercised over the REAL fixture dump through the real adapter +
# loader, not hand-built rows.
class CorphDilReferencesTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("corph")

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    @source = Nabu::Store::Source.create(
      slug: "corph", name: "CorPH", adapter_class: "Nabu::Adapters::Corph", license_class: "attribution"
    )
    Nabu::Store::Loader.new(db: @catalog, source: @source)
                       .load_from(Nabu::Adapters::Corph.new, workdir: FIXTURES, full: true)
  end

  def teardown
    @journal.disconnect
  end

  def producer
    Nabu::CorphDilReferences.new(catalog: @catalog, journal: @journal)
  end

  def test_mints_one_edge_per_distinct_document_dil_pair
    result = producer.run("corph")

    assert_operator result.edges_written, :>, 100, "the fixture texts attest hundreds of DIL headwords"
    edges = @journal[:links].all
    assert_equal ["reference"], edges.map { |edge| edge[:kind] }.uniq
    assert(edges.all? { |edge| edge[:to_urn].start_with?("urn:nabu:dict:edil:") })
    assert_nil edges.first[:score], "a headword key is upstream curation, not a mined similarity"

    caur = @journal[:links].first(from_urn: "urn:nabu:corph:0003", to_urn: "urn:nabu:dict:edil:8406")
    refute_nil caur, "Baile Chuinn attests caur → dil.ie/8406"
    assert_includes caur[:detail], "caur", "the edge names the lemma that carries it"
    assert_includes caur[:detail], "dil.ie/8406"

    pairs = edges.map { |edge| [edge[:from_urn], edge[:to_urn]] }
    assert_equal pairs.uniq.size, pairs.size, "one edge per (document, id) pair, however often attested"

    run = @journal[:link_runs].first(id: result.run_id)
    assert_equal "corph", run[:producer]
    assert_equal "corph", run[:scope]
  end

  def test_rerun_supersedes_the_prior_edges
    first = producer.run("corph")
    second = producer.run("corph")

    assert_equal first.edges_written, second.edges_written
    assert_equal 1, second.superseded_runs
    assert_equal first.edges_written, second.superseded_edges
    assert_equal first.edges_written, @journal[:links].count,
                 "the journal holds exactly the current mining"
  end

  def test_withdrawn_documents_contribute_nothing
    @catalog[:documents].where(urn: "urn:nabu:corph:0003").update(withdrawn: true)
    producer.run("corph")
    assert_equal 0, @journal[:links].where(from_urn: "urn:nabu:corph:0003").count
  end

  def test_other_sources_contribute_nothing
    other = Nabu::Store::Source.create(slug: "other", name: "O", adapter_class: "X", license_class: "open")
    doc = Nabu::Store::Document.create(
      source_id: other.id, urn: "urn:other:doc", title: "t", language: "sga",
      content_sha256: "x", revision: 1, withdrawn: false
    )
    Nabu::Store::Passage.create(
      document_id: doc.id, urn: "urn:other:doc:1", language: "sga", sequence: 0,
      text: "x", text_normalized: "x", content_sha256: "x", revision: 1, withdrawn: false,
      annotations_json: JSON.generate({ "tokens" => [{ "lemma" => "caur", "dil" => ["8406"] }] })
    )
    producer.run("corph")
    assert_equal 0, @journal[:links].where(from_urn: "urn:other:doc").count
  end
end
