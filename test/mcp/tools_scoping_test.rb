# frozen_string_literal: true

require "test_helper"

module MCP
  # nabu_search's `source` / `axis` scoping (additive contract bump
  # 2026-11-10): the CLI's --source/--axis pair on the MCP surface,
  # resolved through the SAME Query::SourceScope the CLI search family
  # uses, threaded into the same query classes' source:/sources: filters.
  # An unknown slug or axis is an isError refusal naming the valid set —
  # never an empty page a model would read as "unattested".
  class ToolsScopingTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    end

    def teardown
      @fulltext&.disconnect
    end

    def payload(result) = JSON.parse(result[:content].fetch(0).fetch(:text))

    def registry
      axes = Nabu::AxisRegistry.new([
                                      Nabu::AxisRegistry::Axis.new(name: "classical", persona: "p", desc: "d",
                                                                   order: 0),
                                      Nabu::AxisRegistry::Axis.new(name: "documentary", persona: "p", desc: "d",
                                                                   order: 1)
                                    ])
      entries = { "perseus" => "classical", "pap" => "documentary", "cantus" => "classical",
                  "korpus16" => "documentary" }.map do |slug, axis|
        Nabu::SourceRegistry::Entry.new(slug: slug, adapter_class_name: "TestAdapter", wired: true,
                                        sync_policy: "manual", axes: [axis])
      end
      Nabu::SourceRegistry.new(entries, axes: axes)
    end

    def call(args, registry: self.registry)
      Nabu::MCP::Tools.new(catalog: @catalog, fulltext: @fulltext, registry: registry).call("nabu_search", args)
    end

    def urns(args, **)
      payload(call(args, **)).fetch("matches").map { |hit| hit.fetch("urn") }
    end

    def add_passage(source, doc_urn, urn, text, lemmas: nil)
      doc = Nabu::Store::Document.create(source_id: source.id, urn: doc_urn, title: "t", language: "grc",
                                         content_sha256: "x", revision: 1, withdrawn: false)
      annotations = lemmas ? JSON.generate({ "tokens" => lemmas.map { |l, f| { "lemma" => l, "form" => f } } }) : "{}"
      Nabu::Store::Passage.create(document_id: doc.id, urn: urn, sequence: 0, language: "grc", text: text,
                                  text_normalized: Nabu::Normalize.search_form(text, language: "grc"),
                                  annotations_json: annotations, content_sha256: "x", revision: 1,
                                  withdrawn: false)
    end

    # Two open sources on different axes, each holding the same words.
    def seed_two_sources
      perseus = Nabu::Store::Source.create(slug: "perseus", name: "Perseus", adapter_class: "TestAdapter",
                                           license_class: "open")
      pap = Nabu::Store::Source.create(slug: "pap", name: "Papyri", adapter_class: "TestAdapter",
                                       license_class: "open")
      add_passage(perseus, "urn:d:lit", "urn:d:lit:1", "τῶι στρατηγῶι εἶπας θεά", lemmas: [%w[λέγω εἶπας]])
      add_passage(pap, "urn:d:pap", "urn:d:pap:1", "τῶι στρατηγῶι εἶπας χαίρειν", lemmas: [%w[λέγω εἶπας]])
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, fuzzy_slugs: %w[perseus pap])
    end

    # -- the schema (additive) -------------------------------------------------

    def test_the_schema_documents_source_and_axis
      properties = Nabu::MCP::Tools::SEARCH_SCHEMA.fetch(:properties)
      assert_equal "string", properties.dig(:source, :type)
      assert_equal "string", properties.dig(:axis, :type)
      assert_match(/source slug/i, properties.dig(:source, :description))
      assert_match(/axes/i, properties.dig(:axis, :description))
      assert_match(/comma/i, properties.dig(:axis, :description), "the CLI's NAME[,NAME…] shape is named")
    end

    # -- the ranked text search ------------------------------------------------

    def test_source_scopes_text_hits_to_that_source
      seed_two_sources
      assert_equal 2, urns({ "query" => "στρατηγωι" }).size, "unscoped: both sources answer"
      assert_equal ["urn:d:pap:1"], urns({ "query" => "στρατηγωι", "source" => "pap" })
      assert_equal ["urn:d:lit:1"], urns({ "query" => "στρατηγωι", "source" => "perseus" })
    end

    def test_axis_scopes_text_hits_to_its_member_sources
      seed_two_sources
      assert_equal ["urn:d:pap:1"], urns({ "query" => "στρατηγωι", "axis" => "documentary" })
      assert_equal ["urn:d:lit:1"], urns({ "query" => "στρατηγωι", "axis" => "classical" })
      assert_equal 2, urns({ "query" => "στρατηγωι", "axis" => "classical,documentary" }).size,
                   "a comma list is the union of the members (the CLI's NAME[,NAME…])"
    end

    # -- lemma and proximity carry the same scoping (as on the CLI) ------------

    def test_source_and_axis_scope_lemma_hits
      seed_two_sources
      assert_equal 2, urns({ "lemma" => "λέγω" }).size
      assert_equal ["urn:d:pap:1"], urns({ "lemma" => "λέγω", "source" => "pap" })
      assert_equal ["urn:d:lit:1"], urns({ "lemma" => "λέγω", "axis" => "classical" })
    end

    def test_source_and_axis_scope_proximity_hits
      seed_two_sources
      assert_equal 2, urns({ "query" => "στρατηγωι", "near" => "ειπας" }).size
      assert_equal ["urn:d:pap:1"], urns({ "query" => "στρατηγωι", "near" => "ειπας", "source" => "pap" })
      assert_equal ["urn:d:lit:1"], urns({ "query" => "στρατηγωι", "near" => "ειπας", "axis" => "classical" })
    end

    # -- the lanes that mirror a CLI path carrying --source/--axis -------------

    def test_source_and_axis_scope_the_fuzzy_lane
      seed_two_sources
      assert_equal 2, urns({ "query" => "ρατηγ", "fuzzy" => true }).size
      assert_equal ["urn:d:pap:1"], urns({ "query" => "ρατηγ", "fuzzy" => true, "source" => "pap" })
      assert_equal ["urn:d:lit:1"], urns({ "query" => "ρατηγ", "fuzzy" => true, "axis" => "classical" })
    end

    def test_source_and_axis_scope_the_annotations_lane
      Nabu::TestSupport.load_annotation_corpus(@catalog)
      Nabu::Store::AnnotationIndex.rebuild!(catalog: @catalog, fulltext: @fulltext)
      # praesul answers from cantus (classical), prasnik from korpus16 (documentary).
      refute_empty urns({ "query" => "prasnik", "annotations" => true, "source" => "korpus16" })
      assert_empty urns({ "query" => "prasnik", "annotations" => true, "source" => "cantus" })
      refute_empty urns({ "query" => "praesul", "annotations" => true, "axis" => "classical" })
      assert_empty urns({ "query" => "praesul", "annotations" => true, "axis" => "documentary" })
    end

    def test_the_translations_and_gloss_lanes_accept_the_scoping_pair
      seed_two_sources
      %w[translations].each do |lane|
        # An unbuilt lane answers its build-hint note — the point is that
        # the scoping pair is IN the lane's composition set (no clash).
        call({ "query" => "x", lane => true, "source" => "pap", "axis" => "classical" })
      end
      call({ "gloss" => "king", "source" => "pap", "axis" => "classical" })
    end

    def test_the_sense_lane_takes_source_but_refuses_axis
      seed_two_sources
      call({ "sense" => "finger", "source" => "pap" })
      error = assert_raises(Nabu::MCP::Tools::InvalidArguments) { call({ "sense" => "finger", "axis" => "classical" }) }
      assert_match(/sense composes with .* only \(not axis\)/, error.message)
    end

    def test_similar_to_refuses_the_scoping_pair
      seed_two_sources
      %w[source axis].each do |key|
        error = assert_raises(Nabu::MCP::Tools::InvalidArguments, key) do
          call({ "similar_to" => "urn:d:pap:1", key => "pap" })
        end
        assert_match(/similar_to composes with limit/, error.message)
      end
    end

    # -- refusals: an isError naming the valid set, never an empty page --------

    def test_an_unknown_source_is_refused_naming_the_held_slugs
      seed_two_sources
      error = assert_raises(Nabu::MCP::Tools::InvalidArguments) { call({ "query" => "στρατηγωι", "source" => "nope" }) }
      assert_equal 'unknown source "nope" — the catalog holds: pap, perseus', error.message
    end

    def test_an_unknown_axis_is_refused_naming_the_known_set
      seed_two_sources
      error = assert_raises(Nabu::MCP::Tools::InvalidArguments) { call({ "query" => "στρατηγωι", "axis" => "nope" }) }
      assert_match(/\Asearch: unknown axis "nope" — known axes: classical, documentary · functional sets: /,
                   error.message)
    end

    def test_an_unknown_source_on_a_lane_is_refused_too
      seed_two_sources
      assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call({ "query" => "ρατηγ", "fuzzy" => true, "source" => "nope" })
      end
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { call({ "lemma" => "λέγω", "axis" => "nope" }) }
    end

    def test_axis_without_a_registry_is_refused_not_ignored
      seed_two_sources
      error = assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call({ "query" => "στρατηγωι", "axis" => "classical" }, registry: nil)
      end
      assert_match(/axis needs the source registry/, error.message)
      assert_equal ["urn:d:pap:1"], urns({ "query" => "στρατηγωι", "source" => "pap" }, registry: nil),
                   "source needs only the catalog"
    end
  end
end
