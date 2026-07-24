# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Trismegistos + Nabu::TrismegistosCrosswalk (P43-3) — the
  # TexRelations crosswalk registered as a FEATURE MODULE (kind: module), not
  # a text source: discover yields NOTHING and parse is unreachable (the
  # bridging shape). Its work is the links-journal producer #8, exercised
  # against two REAL dataservices responses (retrieved 2026-07-24):
  # 102617.json (partners PHI/CPI, no held source — Type-A-only) and
  # 175903.json (EDH HD007132 — a HELD nabu source, so the same-stone
  # internal edge fires when the catalog holds the edh witness and the links
  # journal carries the isicily→tm:175903 concordance edge).
  class TrismegistosTest < Minitest::Test
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("trismegistos")

    ISIC_URN = "urn:nabu:isicily:isic000123"
    EDH_URN = "urn:nabu:edh:hd007132"

    def setup
      @catalog = store_test_db
      @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    end

    def teardown
      @journal.disconnect
    end

    def producer
      Nabu::TrismegistosCrosswalk.new(catalog: @catalog, journal: @journal)
    end

    # A held witness in the catalog (edh + isicily are the P43-3 held schemes).
    def hold!(urn, slug)
      source = Nabu::Store::Source.find(slug: slug) ||
               Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "X", license_class: "open")
      Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn, language: "und",
                                   metadata_json: "{}", content_sha256: "x", revision: 1, withdrawn: false)
    end

    # The isicily concordance edge this producer READS (recorded under the
    # "isicily" producer, exactly as the isicily reference producer would).
    def seed_isicily_tm_edge!(from:, tm_id:)
      run_id = Nabu::Store::LinksJournal.record_run!(@journal, producer: "isicily", scope: "isicily",
                                                               params: {}, code_version: "test")
      Nabu::Store::LinksJournal.write_edge!(@journal, from_urn: from, to_urn: "tm:#{tm_id}",
                                                      kind: "reference", score: nil, run_id: run_id)
    end

    # --- the module row / manifest --------------------------------------------

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["trismegistos"]
      refute_nil entry, "trismegistos must be registered in config/sources.yml"
      assert entry.feature_module?, "a links instrument is a kind: module row"
      refute entry.enabled, "a feature module serves no documents — enabled stays false permanently"
      assert_equal "manual", entry.sync_policy
    end

    def test_manifest_is_by_sa_attribution_verbatim
      manifest = Nabu::Adapters::Trismegistos.manifest
      assert_equal "trismegistos", manifest.id
      assert_equal "attribution", manifest.license_class, "the house CC BY-SA class"
      assert_includes manifest.license, "CC BY-SA 4.0"
      assert_includes manifest.license, "open access to our data"
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::Trismegistos.new
      assert_empty adapter.discover(FIXTURES).to_a, "a links instrument mints no documents"
      assert Nabu::Adapters::Trismegistos.reference_edges?, "its data rides the links journal"
      ref = Nabu::DocumentRef.new(source_id: "trismegistos", id: "urn:nabu:trismegistos:x",
                                  path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/links instrument/, error.message)
    end

    def test_adapter_reference_producer_is_the_crosswalk
      p = Nabu::Adapters::Trismegistos.reference_producer(catalog: @catalog, journal: @journal)
      assert_instance_of Nabu::TrismegistosCrosswalk, p
    end

    # --- Type A: the crosswalk hub --------------------------------------------

    def test_mints_external_crosswalk_edges_from_the_tm_hub
      result = producer.run("trismegistos", workdir: FIXTURES)

      assert_equal 2, result.files, "both fixture responses read"
      # 102617: PHI 228245 + CPI CPI-093 (neither held).
      phi = @journal[:links].first(from_urn: "tm:102617", to_urn: "phi:228245")
      refute_nil phi, "the tm hub now points outward to its PHI partner"
      assert_equal "reference", phi[:kind]
      assert_nil phi[:score], "a crosswalk assertion is not a mined similarity"
      assert_equal "Trismegistos concordance: PHI", phi[:detail]
      assert_equal "cpi:CPI-093",
                   @journal[:links].first(from_urn: "tm:102617", to_urn: "cpi:CPI-093")[:to_urn]
      # 175903: EDH is HELD → the hub targets the resolvable urn:nabu form;
      # EDCS is not a nabu source → a compact external id.
      assert_equal EDH_URN, @journal[:links].first(from_urn: "tm:175903", to_urn: EDH_URN)[:to_urn],
                   "a held partner is addressed by its resolvable catalog urn"
      assert_equal "edcs:09300551",
                   @journal[:links].first(from_urn: "tm:175903", to_urn: "edcs:09300551")[:to_urn]
      assert_equal 4, result.external_edges, "PHI + CPI + EDH(urn) + EDCS"
    end

    # --- Type B: same-stone identity inside the library -----------------------

    def test_mints_the_internal_same_stone_edge_when_two_held_witnesses_meet
      hold!(EDH_URN, "edh")
      hold!(ISIC_URN, "isicily")
      seed_isicily_tm_edge!(from: ISIC_URN, tm_id: "175903")

      result = producer.run("trismegistos", workdir: FIXTURES)

      edge = @journal[:links].first(from_urn: ISIC_URN, to_urn: EDH_URN) ||
             @journal[:links].first(from_urn: EDH_URN, to_urn: ISIC_URN)
      refute_nil edge, "the same stone held under isicily AND edh, joined via Trismegistos 175903"
      assert_equal "reference", edge[:kind]
      assert_equal "same text (Trismegistos 175903)", edge[:detail]
      assert_equal 1, result.internal_edges
      # 102617 has no held partner and no referencing witness → no internal edge.
      assert_equal 0, @journal[:links].where(detail: "same text (Trismegistos 102617)").count
    end

    def test_no_internal_edge_without_a_second_held_witness
      hold!(EDH_URN, "edh") # the partner is held, but nothing references tm:175903
      result = producer.run("trismegistos", workdir: FIXTURES)
      assert_equal 0, result.internal_edges, "one witness is not a same-stone assertion"
    end

    # --- run mechanics: idempotency + rebuild-equivalence ---------------------

    def test_rerun_supersedes_and_is_idempotent
      hold!(EDH_URN, "edh")
      hold!(ISIC_URN, "isicily")
      seed_isicily_tm_edge!(from: ISIC_URN, tm_id: "175903")

      first = producer.run("trismegistos", workdir: FIXTURES)
      second = producer.run("trismegistos", workdir: FIXTURES)

      assert_equal first.edges_written, second.edges_written
      assert_equal first.external_edges, second.external_edges
      assert_equal first.internal_edges, second.internal_edges
      assert_equal 1, second.superseded_runs
      assert_equal first.edges_written, second.superseded_edges
      assert_equal first.edges_written + 1, @journal[:links].count,
                   "the journal holds exactly the current crosswalk plus the untouched isicily→tm edge"
    end

    # Rebuild-equivalence: dropping links and re-deriving yields identical
    # edges — SO LONG AS the concordance producers re-run first (the crosswalk
    # reads their tm: edges from the journal; on `nabu rebuild` isicily's
    # reference producer runs before trismegistos's, by registry order). The
    # re-seed here simulates exactly that ordering.
    def test_rebuild_equivalence_after_dropping_the_journal
      hold!(EDH_URN, "edh")
      hold!(ISIC_URN, "isicily")
      seed_isicily_tm_edge!(from: ISIC_URN, tm_id: "175903")
      first = producer.run("trismegistos", workdir: FIXTURES)
      before = crosswalk_edges

      @journal.disconnect
      @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
      seed_isicily_tm_edge!(from: ISIC_URN, tm_id: "175903") # the concordance producer, re-run first
      second = producer.run("trismegistos", workdir: FIXTURES)

      assert_equal first.edges_written, second.edges_written
      assert_equal before, crosswalk_edges, "identical edges re-derived from canonical + catalog + journal"
    end

    def test_a_workdir_without_the_tree_is_a_no_op_that_supersedes_nothing
      producer.run("trismegistos", workdir: FIXTURES)
      count = @journal[:links].count
      Dir.mktmpdir do |empty|
        result = producer.run("trismegistos", workdir: empty)
        assert_equal 0, result.edges_written
        assert_equal 0, result.superseded_runs, "a parse-only sync before the fetch must not wipe edges"
        assert_nil result.run_id
      end
      assert_equal count, @journal[:links].count
    end

    def test_malformed_response_stops_loudly
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "texrelations"))
        File.write(File.join(dir, "texrelations", "1.json"), "[{")
        assert_raises(Nabu::ParseError) { producer.run("trismegistos", workdir: dir) }
      end
    end

    private

    # The trismegistos-minted edges (excludes the seeded isicily→tm edge),
    # normalized to sorted [from, to, detail] triples for comparison.
    def crosswalk_edges
      @journal[:links].exclude(Sequel.like(:to_urn, "tm:%")).select_map(%i[from_urn to_urn detail]).sort
    end
  end
end
