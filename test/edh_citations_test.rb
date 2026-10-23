# frozen_string_literal: true

require "test_helper"

# Nabu::EdhCitations — EDH's AE/CIL bibliography and GODOT calendar-date
# records as kind=reference edges from the EDH document urn, and
# Nabu::EdhReferences, the EDH adapter's composed reference producer. Real
# fixtures: the edh adapter fixture (HD000001/HD000082/HD029093 carry AE,
# CIL and CIL² citations) and test/fixtures/edh_identities (HD072020 — a
# GODOT-dated altar with AE + CIL + PIR citations).
class EdhCitationsTest < Minitest::Test
  include StoreTestDB

  def teardown
    @journal&.disconnect
  end

  def load_edh(root)
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    source = Nabu::Store::Source.create(slug: "edh", name: "EDH", adapter_class: Nabu::Adapters::Edh.name,
                                        license_class: "attribution")
    Nabu::Store::Loader.new(db: @catalog, source: source).load_from(Nabu::Adapters::Edh.new, workdir: root)
  end

  def producer = Nabu::EdhCitations.new(catalog: @catalog, journal: @journal)

  def targets(urn)
    @journal[:links].where(from_urn: urn, kind: "reference").order(:to_urn).select_map(%i[to_urn detail])
  end

  # -- the id grammar (real citation strings from the 2021 dump) -------------

  def test_citation_ids_follow_edh_numbering
    {
      "AE 1983, 0192." => "ae:1983,0192",
      "AE 1917/18, 0064. (B)" => "ae:1917/18,0064",
      "AE 1975, 0141a." => "ae:1975,0141a",
      "AE 1983, 0352bis. (B)" => "ae:1983,0352bis",
      "AE 2010, 0776, Nr. 18." => "ae:2010,0776",
      "CIL 06, 41026; Foto." => "cil:06,41026",
      "CIL 13, 04, 06548 add. p. 100." => "cil:13,04,06548",
      "CIL 02 (2. Aufl.) 05, 00274; Foto." => "cil:02(2),05,00274",
      "CIL 03, 04496 a. (B)" => "cil:03,04496a",
      "CIL 03, 11097 add. p. 2192." => "cil:03,11097",
      "CIL 03, 14188, 1. (B)" => "cil:03,14188",
      "CIL 10, 01084*. (C)" => "cil:10,01084*",
      "CIL 02, 06345a. (B)" => "cil:02,06345a"
    }.each { |cite, id| assert_equal id, Nabu::EdhCitations.citation_id(cite), cite }
  end

  def test_page_citations_name_no_inscription_and_mint_nothing
    ["AE 1948, p. 44 s. n. 112.", "AE 1942/43, p. 11 s. n. 24.", "CIL 02, p. 1054. (B)"].each do |cite|
      assert_nil Nabu::EdhCitations.citation_id(cite), cite
    end
  end

  # -- the producer over loaded documents ------------------------------------

  def test_mints_ae_and_cil_edges_from_each_document
    load_edh(Nabu::TestSupport.fixtures("edh"))
    result = producer.run("edh")
    assert_equal [["ae:1983,0192", "EDH bibliography: AE 1983, 0192."]], targets("urn:nabu:edh:hd000001")
    assert_equal %w[ae:1983,0046 cil:06,41026], targets("urn:nabu:edh:hd000082").map(&:first),
                 "IGUR and the monographs are not AE/CIL — no edge"
    assert_equal ["cil:02(2),07,00604a"], targets("urn:nabu:edh:hd029093").map(&:first)
    assert_equal 4, result.citations
    assert_equal 4, result.edges_written
    assert_equal 0, result.godot
  end

  def test_godot_record_and_corpus_citations_of_a_dated_altar
    load_edh(Nabu::TestSupport.fixtures("edh_identities/edh"))
    result = producer.run("edh")
    edges = targets("urn:nabu:edh:hd072020")
    assert_equal ["ae:1901,0234", "cil:03,15180", "https://godot.date/id/p48LHaNtU64BgoQKhHgZyJ"],
                 edges.map(&:first), "PIR citations are persons, not inscriptions — the person layer carries them"
    assert_equal "EDH dating: GODOT calendar-date record", edges.last.last
    assert_equal 1, result.godot
    assert_nil @journal[:links].first(to_urn: "ae:1901,0234")[:score], "an assertion, not a similarity"
  end

  def test_rerun_supersedes_its_one_run_and_is_rebuild_equivalent
    load_edh(Nabu::TestSupport.fixtures("edh"))
    producer.run("edh")
    first = @journal[:links].order(:from_urn, :to_urn).select_map(%i[from_urn to_urn detail])
    again = producer.run("edh")
    assert_equal 1, again.superseded_runs
    assert_equal first, @journal[:links].order(:from_urn, :to_urn).select_map(%i[from_urn to_urn detail])
    assert_equal 1, @journal[:link_runs].where(producer: Nabu::EdhCitations::PRODUCER).count
  end

  def test_withdrawn_documents_assert_nothing
    load_edh(Nabu::TestSupport.fixtures("edh"))
    @catalog[:documents].where(urn: "urn:nabu:edh:hd000082").update(withdrawn: true)
    producer.run("edh")
    assert_empty targets("urn:nabu:edh:hd000082")
  end

  # -- the composed adapter producer -----------------------------------------

  def test_the_edh_adapter_composes_same_artifact_and_citations
    load_edh(Nabu::TestSupport.fixtures("edh"))
    composed = Nabu::Adapters::Edh.reference_producer(catalog: @catalog, journal: @journal)
    assert_instance_of Nabu::EdhReferences, composed
    result = composed.run("edh", workdir: nil)
    assert_equal [Nabu::EdhEdrSameArtifact::Result, Nabu::EdhCitations::Result], result.parts.map(&:class)
    assert_equal 4, result.edges_written, "no EDR side here: the citation edges alone"
    assert_equal 0, result.superseded_edges
  end
end
