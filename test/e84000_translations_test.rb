# frozen_string_literal: true

require "test_helper"
require "json"

# Nabu::E84000Translations (P48-6): the Kangyur↔84000 translation crosswalk —
# each 84000 English publication's Toh-base keys (the P48-2 parser's pinned
# "toh_base" metadata, the canonical join rule) become kind=translation edges
# e84000-document ↔ derge-document, shelf routed by the publication's own
# "collection" metadata (kangyur → derge-kangyur, tengyur → derge-tengyur).
# Fixtures are the real in-tree samples of BOTH sides: the four e84000
# publications (toh846a, the multi-Toh toh539e,774,1074, the duplicate-pair
# winner toh761, tengyur toh3156) and the derge volume slices whose markers
# overlap on toh846a (Kangyur vol 100) — so one edge resolves end-to-end and
# the rest pin the dangling-but-stable P32-6 posture.
class E84000TranslationsTest < Minitest::Test
  include StoreTestDB

  E_TOH846A = "urn:nabu:e84000:toh846a"
  E_TOH539E = "urn:nabu:e84000:toh539e"
  D_TOH846A = "urn:nabu:derge-kangyur:toh846a"
  D_TOH1 = "urn:nabu:derge-kangyur:toh1"

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
  end

  def teardown
    @journal.disconnect
  end

  def producer
    Nabu::E84000Translations.new(catalog: @catalog, journal: @journal)
  end

  # --- minting: one edge per (publication, toh base) -------------------------

  def test_mints_one_edge_per_publication_toh_base_pair
    load_e84000!
    result = producer.run("e84000")

    assert_equal 7, result.edges_written,
                 "toh846a + toh761 + toh3156 + the toh1-6 part publication mint one each; " \
                 "the multi-Toh toh539e,774,1074 mints three"
    assert_equal 0, result.edges_refreshed
    assert_equal 0, result.skipped_unmapped
    assert_equal 7, @journal[:links].count
    assert_equal ["translation"], @journal[:links].select_map(:kind).uniq
    assert_equal [nil], @journal[:links].select_map(:score).uniq,
                 "a curated translation record is not a mined similarity — no fake number"
    assert(@journal[:links].select_map(:from_urn).all? { |urn| urn.start_with?("urn:nabu:e84000:") },
           "the 84000 publication carries the Toh keys — it is always the from side")
  end

  def test_multi_toh_publication_fans_out_to_every_base
    load_e84000!
    producer.run("e84000")

    to_urns = @journal[:links].where(from_urn: E_TOH539E).select_map(:to_urn).sort
    assert_equal %w[
      urn:nabu:derge-kangyur:toh1074
      urn:nabu:derge-kangyur:toh539e
      urn:nabu:derge-kangyur:toh774
    ], to_urns, "all keys of a multi-Toh file join (the P48-2 metadata contract), " \
                "dangling-but-stable until the derge sync — the P32-6 precedent"
  end

  def test_collection_routes_the_derge_shelf
    load_e84000!
    producer.run("e84000")

    edge = @journal[:links].first(from_urn: "urn:nabu:e84000:toh3156")
    assert_equal "urn:nabu:derge-tengyur:toh3156", edge[:to_urn],
                 "a tengyur publication joins the derge-tengyur shelf, never the kangyur"
  end

  # --- the toh846a edge, pinned end-to-end (both sides fixture-loaded) -------

  def test_pins_the_toh846a_edge_end_to_end
    load_e84000!
    load_derge!
    producer.run("e84000")

    edge = @journal[:links].first(from_urn: E_TOH846A, to_urn: D_TOH846A)
    refute_nil edge, "the crosswalk anchor: 84000's Threefold Ritual joins Derge Toh 846a"
    assert_equal "translation", edge[:kind]
    assert_nil edge[:score]
    assert_equal "translates toh846a — The Threefold Ritual", edge[:detail],
                 "detail carries the direction and the 84000 title (readable before any derge sync)"

    result = Nabu::Query::Links.new(catalog: @catalog, journal: @journal).run(D_TOH846A)
    counterparts = result.groups.fetch("translation")
    assert_equal [E_TOH846A], counterparts.map(&:urn),
                 "`nabu links` on the Derge text serves the English translation document"
    assert counterparts.first.resolved?
    assert_equal "The Threefold Ritual", counterparts.first.title

    back = Nabu::Query::Links.new(catalog: @catalog, journal: @journal).run(E_TOH846A)
    assert_equal [D_TOH846A], back.groups.fetch("translation").map(&:urn),
                 "and vice versa: links on the 84000 document serves the Derge original"
    assert back.groups.fetch("translation").first.resolved?,
           "the derge fixture holds toh846a — the counterpart resolves"
  end

  def test_a_part_publication_joins_its_base_toh_container
    load_e84000!
    load_derge!
    insert_e84000_document(
      urn: "urn:nabu:e84000:toh1-1", title: "The Chapter on Going Forth",
      metadata: { "collection" => "kangyur", "toh" => ["toh1-1"], "toh_base" => ["toh1"] }
    )
    producer.run("e84000")

    edge = @journal[:links].first(from_urn: "urn:nabu:e84000:toh1-1")
    assert_equal D_TOH1, edge[:to_urn],
                 "toh_base strips the part suffix — the join lands on the derge toh1 CONTAINER document"
    assert_equal "translates toh1 (via toh1-1) — The Chapter on Going Forth", edge[:detail],
                 "the part key that carried the join rides the detail"

    result = Nabu::Query::Links.new(catalog: @catalog, journal: @journal).run(D_TOH1)
    assert result.groups.fetch("translation").first.resolved?,
           "the container document (0 passages, container:true) still resolves the edge"
  end

  # --- honesty ---------------------------------------------------------------

  def test_a_publication_without_toh_metadata_is_counted_not_minted
    load_e84000!
    insert_e84000_document(urn: "urn:nabu:e84000:tohless", title: "A Stray",
                           metadata: { "collection" => "kangyur" })
    result = producer.run("e84000")

    assert_equal 7, result.edges_written
    assert_equal 1, result.skipped_unmapped,
                 "a document without toh_base metadata mints nothing and is counted"
  end

  def test_an_unknown_collection_is_counted_not_minted
    load_e84000!
    insert_e84000_document(urn: "urn:nabu:e84000:toh9999", title: "A Stray Shelf",
                           metadata: { "collection" => "mystery", "toh" => ["toh9999"],
                                       "toh_base" => ["toh9999"] })
    result = producer.run("e84000")

    assert_equal 7, result.edges_written,
                 "an unknown collection routes to no derge shelf — never guessed"
    assert_equal 1, result.skipped_unmapped
  end

  def test_a_withdrawn_publication_mints_nothing
    load_e84000!
    @catalog[:documents].where(urn: E_TOH846A).update(withdrawn: true)
    result = producer.run("e84000")

    assert_equal 6, result.edges_written
    assert_nil @journal[:links].first(from_urn: E_TOH846A)
  end

  # --- run mechanics ---------------------------------------------------------

  def test_rerun_supersedes_the_prior_edges
    load_e84000!
    first = producer.run("e84000")
    second = producer.run("e84000")

    assert_equal first.edges_written, second.edges_written
    assert_equal 1, second.superseded_runs
    assert_equal first.edges_written, second.superseded_edges
    assert_equal first.edges_written, @journal[:links].count,
                 "the journal holds exactly the current publications' assertions"
    run = @journal[:link_runs].first(id: second.run_id)
    assert_equal "e84000", run[:producer]
    assert_equal "e84000", run[:scope]
    assert_equal "translation", JSON.parse(run[:params_json]).fetch("kind")
  end

  def test_a_catalog_without_e84000_documents_is_a_no_op_that_supersedes_nothing
    load_e84000!
    producer.run("e84000")

    empty_catalog = store_test_db
    begin
      result = Nabu::E84000Translations.new(catalog: empty_catalog, journal: @journal).run("e84000")
      assert_equal 0, result.edges_written
      assert_equal 0, result.superseded_runs,
                   "a parse-only sync before the first e84000 fetch must never wipe standing edges"
      assert_nil result.run_id
    ensure
      empty_catalog.disconnect
    end
    assert_equal 7, @journal[:links].count
  end

  private

  def load_e84000!
    source = Nabu::Store::Source.create(
      slug: "e84000", name: "84000 English Kangyur translations",
      adapter_class: "Nabu::Adapters::E84000", license_class: "nc"
    )
    Nabu::Store::Loader.new(db: @catalog, source: source)
                       .load_from(Nabu::Adapters::E84000.new,
                                  workdir: Nabu::TestSupport.fixtures("e84000"), full: true)
    source
  end

  def load_derge!
    { "derge-kangyur" => Nabu::Adapters::DergeKangyur, "derge-tengyur" => Nabu::Adapters::DergeTengyur }
      .each do |slug, adapter_class|
      source = Nabu::Store::Source.create(
        slug: slug, name: slug, adapter_class: adapter_class.name, license_class: "open"
      )
      Nabu::Store::Loader.new(db: @catalog, source: source)
                         .load_from(adapter_class.new,
                                    workdir: Nabu::TestSupport.fixtures(slug), full: true)
    end
  end

  # The producer's input contract is catalog rows carrying the P48-2 parser's
  # pinned metadata keys; the fixture set's own part publication (toh1-6,
  # P48-r2) is a different chapter, so this row supplies toh1-1 in exactly
  # the shape the parser tests pin (test/adapters/e84000_test.rb) — a
  # producer-contract row, not a faked upstream file.
  def insert_e84000_document(urn:, title:, metadata:)
    source_id = @catalog[:sources].where(slug: "e84000").get(:id)
    @catalog[:documents].insert(
      source_id: source_id, urn: urn, title: title, language: "en",
      content_sha256: Digest::SHA256.hexdigest(urn), metadata_json: JSON.generate(metadata)
    )
  end
end
