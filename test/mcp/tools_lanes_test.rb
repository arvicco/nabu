# frozen_string_literal: true

require "test_helper"

module MCP
  # The 2026-10-22 MCP contract bump (one deliberate widening, pinned here):
  # nabu_search gains the CLI's three further lanes — `fuzzy` (search
  # --fuzzy), `translations` (search --translations), `sense` (the `nabu
  # sense` desk) — and nabu_show the `senses` flag (show --senses). Split
  # from tools_test.rb because each lane needs its own real-fixture rig
  # (the trigram scope, the coptic/cdli translation layers, the dcs
  # chapters + sense shelf); the shared assertions stay the contract's:
  # urn + language + license_class + source on every hit, bounded pages,
  # restricted classes excluded by default, absent machinery a note.
  class ToolsLanesTest < Minitest::Test
    include StoreTestDB

    def teardown
      @fulltext&.disconnect
    end

    def payload(result) = JSON.parse(result[:content].fetch(0).fetch(:text))
    def text_of(result) = result[:content].fetch(0).fetch(:text)

    def tools(facet_map: nil)
      Nabu::MCP::Tools.new(catalog: @catalog, fulltext: @fulltext, facet_map: facet_map)
    end

    def call(name, args, facet_map: nil) = tools(facet_map: facet_map).call(name, args)

    # -- the pinned contract (bump 2026-10-22) --------------------------------

    # The schema key sets are frozen; this pin moves only with a deliberate,
    # dated bump (docs/mcp.md records each).
    def test_the_search_and_show_schemas_carry_the_bumped_key_sets
      search = Nabu::MCP::Tools::SEARCH_SCHEMA.fetch(:properties).keys
      assert_equal %i[query similar_to lemma morph gloss near window lang license from to century date_basis
                      place script kind facets meter meter_pattern words lect fuzzy translations sense
                      sense_gloss limit include_restricted], search
      show = Nabu::MCP::Tools::SHOW_SCHEMA.fetch(:properties).keys
      assert_equal %i[urn parallel parallel_lang max_passages segmented senses include_restricted], show
    end

    # The tool-annotations bump (2026-10-22): every registered tool advertises
    # a human-readable title (top-level and in the MCP `annotations` object)
    # and readOnlyHint: true — the surface has no write tools, and clients use
    # the hint to skip confirmation prompts on read-only calls.
    def test_every_tool_carries_a_title_and_the_read_only_hint
      defs = Nabu::MCP::Tools.new(catalog: nil, fulltext: nil).definitions
      assert_equal Nabu::MCP::Tools::TOOLS.size, defs.size
      defs.each do |definition|
        title = definition[:title]
        assert_kind_of String, title, "#{definition[:name]} carries a title"
        refute_empty title.strip, "#{definition[:name]} title is not blank"
        refute_equal definition[:name], title, "#{definition[:name]} title is a display name, not the id"
        assert_equal({ title: title, readOnlyHint: true }, definition[:annotations],
                     "#{definition[:name]} annotations pinned")
      end
      assert_equal defs.size, defs.map { |d| d[:title] }.uniq.size, "titles are distinct"
    end

    # -- fuzzy -----------------------------------------------------------------

    def seed_papyri
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      pap = Nabu::Store::Source.create(slug: "pap", name: "Papyri", adapter_class: "TestAdapter",
                                       license_class: "open")
      private_source = Nabu::Store::Source.create(slug: "adhoc", name: "Ad hoc", adapter_class: "TestAdapter",
                                                  license_class: "research_private")
      add_passage(pap, "urn:d:pap", "urn:d:pap:1", "τῶι στρατηγῶι χαίρειν")
      add_passage(private_source, "urn:d:adhoc", "urn:d:adhoc:1", "στρατηγὸς μυστικός")
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, fuzzy_slugs: %w[pap adhoc])
    end

    def add_passage(source, doc_urn, urn, text)
      doc = Nabu::Store::Document.create(source_id: source.id, urn: doc_urn, title: "t", language: "grc",
                                         content_sha256: "x", revision: 1, withdrawn: false)
      Nabu::Store::Passage.create(document_id: doc.id, urn: urn, sequence: 0, language: "grc", text: text,
                                  text_normalized: Nabu::Normalize.search_form(text, language: "grc"),
                                  content_sha256: "x", revision: 1, withdrawn: false)
    end

    def test_fuzzy_matches_an_infix_fragment_with_the_hit_contract
      seed_papyri
      body = payload(call("nabu_search", { "query" => "ρατηγ", "fuzzy" => true }))
      assert_equal ["urn:d:pap:1"], body.fetch("matches").map { |hit| hit.fetch("urn") },
                   "the research_private hit is excluded by default"
      hit = body.fetch("matches").first
      assert_equal %w[grc open pap], hit.values_at("language", "license_class", "source")
      assert_match(/\[ρατηγ\]/, hit.fetch("snippet"), "the fragment is bracketed in the folded snippet")
      assert_equal %w[adhoc pap], body.fetch("coverage")
      assert_match(/fuzzy substring/, body.fetch("note"))

      both = payload(call("nabu_search", { "query" => "ρατηγ", "fuzzy" => true, "include_restricted" => true }))
      assert_equal 2, both.fetch("matches").size
    end

    def test_fuzzy_refuses_the_flags_the_cli_refuses
      seed_papyri
      %w[near lemma morph lect script meter words translations].each do |key|
        value = %w[words translations].include?(key) || "x"
        args = { "query" => "ρατηγ", "fuzzy" => true, key => value }
        args.delete("query") if key == "lemma"
        assert_raises(Nabu::MCP::Tools::InvalidArguments, key) { call("nabu_search", args) }
      end
      error = assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_search", { "query" => "ρα", "fuzzy" => true })
      end
      assert_match(/under 3 characters/, error.message, "the trigram floor is a usage error, named")
    end

    def test_fuzzy_without_the_trigram_index_is_a_note
      seed_papyri
      @fulltext.drop_table(Nabu::Store::Indexer::TRIGRAM_TABLE)
      assert_match(/no fuzzy index/, text_of(call("nabu_search", { "query" => "ρατηγ", "fuzzy" => true })))
    end

    # -- translations ----------------------------------------------------------

    def seed_translations(build: true)
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      coptic = Nabu::Store::Source.create(slug: "coptic-scriptorium", name: "Coptic SCRIPTORIUM",
                                          adapter_class: "Nabu::Adapters::CopticScriptorium",
                                          license_class: "attribution")
      Nabu::Store::Loader.new(db: @catalog, source: coptic)
                         .load_from(Nabu::Adapters::CopticScriptorium.new,
                                    workdir: Nabu::TestSupport.fixtures("coptic-scriptorium"), full: true)
      Nabu::Store::TranslationIndex.rebuild!(catalog: @catalog, fulltext: @fulltext) if build
    end

    def test_translations_finds_the_original_passage_and_names_its_layer
      seed_translations
      body = payload(call("nabu_search", { "query" => '"brothers according to the flesh"',
                                           "translations" => true }))
      hit = body.fetch("matches").first
      assert_equal "urn:nabu:coptic-scriptorium:ap.100.monbeg:1.1", hit.fetch("urn")
      assert_equal %w[cop attribution coptic-scriptorium translation],
                   hit.values_at("language", "license_class", "source", "layer")
      assert_match(/\[brothers\] according to the flesh/, hit.fetch("snippet"))
      refute_empty hit.fetch("text"), "the original passage rides along"
      assert_equal "coptic-scriptorium", body.fetch("coverage").first.fetch("source")
    end

    def test_translations_composes_with_lang_license_limit_only
      seed_translations
      assert_empty payload(call("nabu_search", { "query" => "brothers", "translations" => true,
                                                 "lang" => "akk" })).fetch("matches")
      error = assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_search", { "query" => "brothers", "translations" => true, "from" => -100 })
      end
      assert_match(/translations composes with .* only \(not from\)/, error.message)
    end

    def test_translations_without_the_lane_is_the_build_hint_note
      seed_translations(build: false)
      assert_match(/rake index:translations/,
                   text_of(call("nabu_search", { "query" => "brothers", "translations" => true })))
    end

    # -- the sense desk + show senses (real dcs fixtures) -----------------------

    ANGULA = "urn:nabu:dcs:5:3363:2612"

    def facet_map
      @facet_map ||= Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
    end

    def seed_dcs
      @fulltext = nil
      map = facet_map
      @catalog = class_template_db do |db|
        source = Nabu::Store::Source.create(slug: "dcs", name: "DCS", adapter_class: "Nabu::Adapters::Dcs",
                                            license_class: "attribution")
        fixtures = Nabu::TestSupport.fixtures("dcs")
        Nabu::Store::Loader.new(db: db, source: source, ledger: nil)
                           .load_from(Nabu::Adapters::Dcs.new, workdir: fixtures)
        Nabu::Store::DictionaryLoader.new(db: db, source: source)
                                     .load_from(Nabu::Adapters::DcsLexiconLane.new, workdir: fixtures)
        Nabu::Store::PassageFacetBuilder.rebuild!(catalog: db, facet_map: map)
      end
    end

    def test_the_sense_desk_serves_senses_and_citing_tokens
      seed_dcs
      body = payload(call("nabu_search", { "sense" => "finger" }, facet_map: facet_map))
      assert_equal %w[sense finger], body.values_at("type", "query")
      assert_equal [1, 1], body.values_at("sense_total", "passage_total")
      sense = body.fetch("senses").first
      assert_equal %w[59344 dcs-senses finger], sense.values_at("id", "shelf", "headword")
      hit = body.fetch("matches").first
      assert_equal [ANGULA, "attribution", "dcs"], hit.values_at("urn", "license_class", "source")
      assert_equal 25, hit.fetch("tokens").size
      assert_includes hit.fetch("tokens"), { "form" => "aṅgulāni", "lemma" => "aṅgula", "ids" => %w[59344] }

      gloss = payload(call("nabu_search", { "sense" => "linear measure", "sense_gloss" => true },
                           facet_map: facet_map))
      assert_equal(%w[59344], gloss.fetch("senses").map { |row| row.fetch("id") })
    end

    def test_the_sense_desk_refuses_other_search_args_and_notes_absent_machinery
      seed_dcs
      assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_search", { "sense" => "finger", "lang" => "san" }, facet_map: facet_map)
      end
      assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_search", { "query" => "x", "sense_gloss" => true }, facet_map: facet_map)
      end
      assert_match(/facet map/, text_of(call("nabu_search", { "sense" => "finger" })))
    end

    def test_show_senses_lists_the_citing_tokens_and_resolves_their_ids
      seed_dcs
      shown = payload(call("nabu_show", { "urn" => ANGULA, "senses" => true }, facet_map: facet_map))
      rows = shown.fetch("senses")
      assert_includes rows, { "form" => "sthaulyāni", "lemma" => "sthaulya", "ids" => %w[25248 25258] }
      assert_equal "finger", shown.dig("sense_entries", "59344", "headword")

      plain = payload(call("nabu_show", { "urn" => ANGULA }, facet_map: facet_map))
      refute plain.key?("senses"), "flag off = byte-identical payload"
      refute plain.key?("sense_entries")
    end

    def test_show_senses_on_a_document_marks_each_citing_passage
      seed_dcs
      document = @catalog[:passages].where(Sequel[:passages][:urn] => ANGULA).join(:documents, id: :document_id)
                                    .get(Sequel[:documents][:urn])
      shown = payload(call("nabu_show", { "urn" => document, "senses" => true, "max_passages" => 200 },
                           facet_map: facet_map))
      line = shown.fetch("passages").find { |row| row.fetch("urn") == ANGULA }
      assert_equal(25, line.fetch("senses").count { |row| row.fetch("ids") == %w[59344] })
      assert shown.fetch("sense_entries").key?("59344")
    end
  end
end
