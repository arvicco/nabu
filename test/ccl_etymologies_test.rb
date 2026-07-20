# frozen_string_literal: true

require "test_helper"

# Nabu::CclEtymologies (P28-3): the egy↔cop diachronic bridge. The ccl
# adapter parses ORAEC's coptic_etymologies crosswalk into ancestor
# DictionaryCitations on the CCL entries; this producer re-derives them
# into kind=etymology links-journal edges after every ccl sync — from
# urn:nabu:dict:ccl:<C-id> to urn:nabu:dict:aed:<TLA lemma id> (the P28-1
# sibling shelf's contract) and urn:nabu:dict:tla-demotic:<word id>
# (dangling-but-stable — no bulk demotic lemma list exists; the dil.ie
# precedent). Exercised over the REAL fixture through the real adapter +
# DictionaryLoader, not hand-built rows.
class CclEtymologiesTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("ccl")

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    @source = Nabu::Store::Source.create(
      slug: "ccl", name: "CCL", adapter_class: "Nabu::Adapters::Ccl", license_class: "attribution"
    )
    Nabu::Store::DictionaryLoader.new(db: @catalog, source: @source)
                                 .load_from(Nabu::Adapters::Ccl.new, workdir: FIXTURES)
  end

  def teardown
    @journal.disconnect
  end

  def producer
    Nabu::CclEtymologies.new(catalog: @catalog, journal: @journal)
  end

  # The chain e2e: one real crosswalk row (C1494,159410,6439 — ⲕⲁϩ ← qꜣḥ
  # ← qh) becomes both ancestor edges, visible via the links reader.
  def test_the_kah_row_mints_both_ancestor_edges
    producer.run("ccl")

    result = Nabu::Query::Links.new(catalog: @catalog, journal: @journal).run("urn:nabu:dict:ccl:C1494")
    refute_nil result
    edges = result.groups.fetch("etymology")
    # The aed leg carries the SHELF's real entry urn — the crosswalk's bare
    # "159410" re-minted with the "tla" prefix the AED @xml:id space uses
    # (P36-4); the demotic leg rides its verbatim word id (no shelf).
    assert_equal %w[urn:nabu:dict:aed:tla159410 urn:nabu:dict:tla-demotic:6439],
                 edges.map(&:urn).sort
    edges.each do |edge|
      assert_equal :out, edge.direction, "the descendant asserts its ancestors"
      assert_nil edge.score, "a curated crosswalk row is not a mined similarity"
      assert_includes edge.detail, "ⲕⲁϩ", "the edge names the Coptic headword"
      refute edge.resolved?, "ancestor shelves are not ingested here — honestly unresolved"
    end
    assert_equal "ⲕⲁϩ — #{Nabu::Adapters::Ccl::TITLE}", result.title,
                 "the queried dictionary-entry urn resolves to its own headword"
  end

  # The P36-4 acceptance oracle: with the AED shelf ingested BESIDE ccl, the
  # C1494 egy↔cop tour resolves through the aed leg end to end — Coptic ⲕⲁϩ
  # → Egyptian qꜣḥ (urn:nabu:dict:aed:tla159410). The ORAEC crosswalk stores
  # the bare TLA lemma id "159410"; the AED shelf mints its urns from the
  # upstream @xml:id verbatim ("tla159410", never renumbered), so the
  # producer must re-mint the aed leg with the "tla" prefix or the edge
  # dangles (the P34-2 defect: 0/1,695 resolved). The demotic leg stays
  # dangling BY DESIGN — no demotic dictionary shelf exists.
  def test_the_aed_leg_resolves_end_to_end_with_the_shelf_on_the_catalog
    aed = Nabu::Store::Source.create(
      slug: "aed", name: "AED", adapter_class: "Nabu::Adapters::Aed", license_class: "attribution"
    )
    Nabu::Store::DictionaryLoader.new(db: @catalog, source: aed)
                                 .load_from(Nabu::Adapters::Aed.new, workdir: Nabu::TestSupport.fixtures("aed"))
    producer.run("ccl")

    result = Nabu::Query::Links.new(catalog: @catalog, journal: @journal).run("urn:nabu:dict:ccl:C1494")
    etymology = result.groups.fetch("etymology")

    aed_edge = etymology.find { |edge| edge.urn.start_with?("urn:nabu:dict:aed:") }
    assert_equal "urn:nabu:dict:aed:tla159410", aed_edge.urn,
                 "the crosswalk's bare 159410 re-mints to the shelf's tla-prefixed urn"
    assert aed_edge.resolved?, "the aed leg lands on the ingested Egyptian shelf entry"
    assert_equal "egy", aed_edge.language
    assert_match(/qꜣḥ/, aed_edge.title, "resolves to the Egyptian headword — Ägyptische Wortliste")

    demotic_edge = etymology.find { |edge| edge.urn.start_with?("urn:nabu:dict:tla-demotic:") }
    refute demotic_edge.resolved?,
           "the demotic leg still dangles BY DESIGN (no demotic dictionary shelf)"
  end

  def test_mints_every_crosswalk_edge_of_the_fixture
    result = producer.run("ccl")

    # Fixture crosswalk: C5 (hiero-only), C6 (entry not in the trim — no
    # citation, no edge), C9 (demotic-only), C74 (both, negative demotic),
    # C1494 + C1495 (both) → 4 aed + 4 tla-demotic edges.
    assert_equal 8, result.edges_written
    assert_equal 0, result.edges_refreshed
    edges = @journal[:links].all
    assert_equal ["etymology"], edges.map { |edge| edge[:kind] }.uniq
    assert_equal(4, edges.count { |edge| edge[:to_urn].start_with?("urn:nabu:dict:aed:") })
    assert_equal(4, edges.count { |edge| edge[:to_urn].start_with?("urn:nabu:dict:tla-demotic:") })

    negative = @journal[:links].first(from_urn: "urn:nabu:dict:ccl:C74",
                                      to_urn: "urn:nabu:dict:tla-demotic:-1427")
    refute_nil negative, "negative TLA demotic word ids ride verbatim"
    assert_includes negative[:detail], "ⲁⲗⲱⲟⲩⲉ"

    run = @journal[:link_runs].first(id: result.run_id)
    assert_equal "ccl", run[:producer]
    assert_equal "ccl", run[:scope]
    assert_equal({ "kind" => "etymology" }, JSON.parse(run[:params_json]))
  end

  def test_rerun_supersedes_the_prior_edges
    first = producer.run("ccl")
    second = producer.run("ccl")

    assert_equal first.edges_written, second.edges_written
    assert_equal 1, second.superseded_runs
    assert_equal first.edges_written, second.superseded_edges
    assert_equal first.edges_written, @journal[:links].count,
                 "the journal holds exactly the current derivation"
  end

  def test_withdrawn_entries_contribute_nothing
    @catalog[:dictionary_entries].where(entry_id: "C1494").update(withdrawn: true)
    producer.run("ccl")
    assert_equal 0, @journal[:links].where(from_urn: "urn:nabu:dict:ccl:C1494").count
  end

  def test_other_sources_contribute_nothing
    other = Nabu::Store::Source.create(slug: "other", name: "O", adapter_class: "X", license_class: "open")
    dict = Nabu::Store::Dictionary.create(source_id: other.id, slug: "other-dict", title: "O", language: "grc")
    entry = Nabu::Store::DictionaryEntry.create(
      dictionary_id: dict.id, urn: "urn:nabu:dict:other-dict:x1", entry_id: "x1",
      key_raw: "x", headword: "χ", headword_folded: "χ", body: "χ",
      content_sha256: "x", revision: 1, withdrawn: false
    )
    Nabu::Store::DictionaryCitation.create(
      dictionary_entry_id: entry.id, seq: 0, urn_raw: "urn:nabu:dict:aed:1",
      cts_work: nil, citation: nil, label: "TLA 1"
    )

    producer.run("ccl")
    assert_equal 0, @journal[:links].where(from_urn: "urn:nabu:dict:other-dict:x1").count
  end

  def test_the_adapter_declares_the_producer_on_the_shared_seam
    assert Nabu::Adapters::Ccl.reference_edges?
    built = Nabu::Adapters::Ccl.reference_producer(catalog: @catalog, journal: @journal)
    assert_instance_of Nabu::CclEtymologies, built
  end
end
