# frozen_string_literal: true

require "test_helper"

module MCP
  # Nabu::MCP::Tools (P8-1) — the tool contract over the Query classes. Same
  # rig as the query tests: fresh in-memory catalog + separate in-memory
  # fulltext, real Indexer rebuild. The contract points under test are the
  # packet's fixed ones: bounded outputs with honest truncation notes,
  # urn + language + license_class on EVERY passage, research_private/
  # restricted default-excluded from every tool, no-match coverage hints,
  # and the graceful degradation shapes (missing index, missing catalog,
  # SQLITE_BUSY).
  class ToolsTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @open = Nabu::Store::Source.create(
        slug: "perseus", name: "Perseus", adapter_class: "TestAdapter",
        license_class: "open", enabled: true, last_sync_at: Time.utc(2026, 7, 1)
      )
      @private = Nabu::Store::Source.create(
        slug: "adhoc", name: "Ad hoc", adapter_class: "TestAdapter",
        license_class: "research_private", enabled: true
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- rig -------------------------------------------------------------------

    def tools(catalog: @catalog, fulltext: @fulltext)
      Nabu::MCP::Tools.new(catalog: catalog, fulltext: fulltext)
    end

    def make_document(source: @open, urn: "urn:d:1", title: "Iliad", language: "grc",
                      license_override: nil, withdrawn: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: title, language: language,
        license_override: license_override, content_sha256: "x",
        revision: 1, withdrawn: withdrawn
      )
    end

    def make_passage(document, urn:, text:, sequence:, language: "grc", lemmas: nil, tokens: nil)
      annotations = if lemmas || tokens
                      pairs = (lemmas || []).map { |lemma, form| { "lemma" => lemma, "form" => form } }
                      JSON.generate({ "tokens" => pairs + (tokens || []) })
                    else
                      "{}"
                    end
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        annotations_json: annotations, content_sha256: "x", revision: 1
      )
    end

    def rebuild!
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    # A small corpus: an open Greek document with three passages, an English
    # sibling edition (same CTS work) for --parallel, and one research_private
    # passage carrying a UNIQUE token (μυστικον) so leak tests can probe for it.
    def seed_corpus
      @grc = make_document(urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2")
      make_passage(@grc, urn: "#{@grc.urn}:1.1", text: "μῆνιν ἄειδε θεά", sequence: 0)
      make_passage(@grc, urn: "#{@grc.urn}:1.2", text: "οὐλομένην ἄειδε", sequence: 1)
      make_passage(@grc, urn: "#{@grc.urn}:1.3", text: "ἄλγε ἔθηκεν", sequence: 2)
      @eng = make_document(urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-eng4",
                           title: "Iliad (English)", language: "eng")
      make_passage(@eng, urn: "#{@eng.urn}:1.1", text: "Sing, goddess, the wrath", sequence: 0,
                         language: "eng")
      @secret = make_document(source: @private, urn: "urn:nabu:adhoc:notes",
                              title: "Private notes", language: "grc")
      make_passage(@secret, urn: "urn:nabu:adhoc:notes:1", text: "μυστικον ἄειδε σημειον",
                            sequence: 0)
      rebuild!
    end

    def call(name, arguments = {})
      tools.call(name, arguments)
    end

    def payload(result)
      JSON.parse(result[:content].fetch(0).fetch(:text))
    end

    def text_of(result)
      result[:content].fetch(0).fetch(:text)
    end

    # -- definitions -----------------------------------------------------------

    def test_definitions_lists_the_six_tools_with_json_schemas
      defs = tools.definitions
      assert_equal(%w[nabu_search nabu_show nabu_concord nabu_align nabu_define nabu_status],
                   defs.map { |d| d[:name] })
      defs.each do |definition|
        refute_empty definition[:description]
        schema = definition[:inputSchema]
        assert_equal "object", schema[:type]
        assert_kind_of Hash, schema[:properties]
      end
    end

    def test_descriptions_teach_the_license_stance_and_urn_shapes
      defs = tools.definitions.to_h { |d| [d[:name], d[:description]] }
      assert_match(/license/i, defs.fetch("nabu_search"))
      assert_match(/urn:cts:/, defs.fetch("nabu_show"), "show teaches a urn example")
    end

    # -- nabu_search: text + lemma modes ----------------------------------------

    def test_search_returns_hits_with_urn_language_and_license_on_every_passage
      seed_corpus
      result = call("nabu_search", { "query" => "μηνιν" })

      refute result[:isError]
      hits = payload(result).fetch("matches")
      assert_equal 1, hits.size
      hit = hits.first
      assert_equal "#{@grc.urn}:1.1", hit.fetch("urn")
      assert_equal "grc", hit.fetch("language")
      assert_equal "open", hit.fetch("license_class")
      assert_equal "perseus", hit.fetch("source")
      assert_equal "μῆνιν ἄειδε θεά", hit.fetch("text")
    end

    def test_search_lemma_mode_finds_inflected_attestations
      doc = make_document(urn: "urn:d:tb", title: "Treebank")
      make_passage(doc, urn: "urn:d:tb:1", text: "σὺ δὲ εἶπας.", sequence: 0,
                        lemmas: [%w[λέγω εἶπας]])
      rebuild!

      hits = payload(call("nabu_search", { "lemma" => "λέγω" })).fetch("matches")
      assert_equal(%w[urn:d:tb:1], hits.map { |hit| hit.fetch("urn") })
      assert_equal "λέγω", hits.first.fetch("lemma")
      assert_equal "εἶπας", hits.first.fetch("surface_forms")
      assert_equal "open", hits.first.fetch("license_class")
    end

    def test_search_lemma_hits_carry_their_dictionary_gloss
      doc = make_document(urn: "urn:d:tb", title: "Treebank")
      make_passage(doc, urn: "urn:d:tb:1", text: "σὺ δὲ εἶπας.", sequence: 0,
                        lemmas: [%w[λέγω εἶπας]])
      rebuild!
      shelf = Nabu::Store::Dictionary.create(source_id: @open.id, slug: "lsj",
                                             title: "LSJ", language: "grc")
      Nabu::Store::DictionaryEntry.create(
        dictionary_id: shelf.id, urn: "urn:nabu:dict:lsj:n1", entry_id: "n1",
        key_raw: "le/gw", headword: "λέγω", headword_folded: "λεγω",
        gloss: "say, speak", body: "…", content_sha256: "x", revision: 1, withdrawn: false
      )

      hits = payload(call("nabu_search", { "lemma" => "λέγω" })).fetch("matches")
      assert_equal "say, speak", hits.first.fetch("gloss")
    end

    def test_search_requires_exactly_one_of_query_and_lemma
      seed_corpus
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { call("nabu_search", {}) }
      assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_search", { "query" => "a", "lemma" => "b" })
      end
    end

    # -- nabu_search: morph facets (P13-6) -------------------------------------

    def test_search_morph_filters_lemma_hits_and_shows_evidence
      doc = make_document(urn: "urn:d:tb", title: "Treebank")
      make_passage(doc, urn: "urn:d:tb:1", text: "τοῖς λόγοις", sequence: 0, tokens: [
                     { "lemma" => "λόγος", "form" => "λόγοις", "feats" => "Case=Dat|Number=Plur" }
                   ])
      make_passage(doc, urn: "urn:d:tb:2", text: "ὁ λόγος", sequence: 1, tokens: [
                     { "lemma" => "λόγος", "form" => "λόγος", "feats" => "Case=Nom|Number=Sing" }
                   ])
      rebuild!

      hits = payload(call("nabu_search", { "lemma" => "λόγος", "morph" => "case=dat,number=pl" }))
             .fetch("matches")
      assert_equal(%w[urn:d:tb:1], hits.map { |hit| hit.fetch("urn") })
      assert_equal "λόγοις", hits.first.fetch("surface_forms")
      assert_equal "number=plur|case=dat", hits.first.fetch("morph")
    end

    def test_search_morph_requires_lemma
      seed_corpus
      assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_search", { "query" => "μηνιν", "morph" => "case=dat" })
      end
    end

    def test_search_malformed_morph_is_invalid_arguments
      doc = make_document(urn: "urn:d:tb", title: "Treebank")
      make_passage(doc, urn: "urn:d:tb:1", text: "x", sequence: 0, lemmas: [%w[λέγω εἶπας]])
      rebuild!
      assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_search", { "lemma" => "λέγω", "morph" => "case" })
      end
    end

    # -- nabu_search: proximity (near/window) -----------------------------------

    def test_search_near_keeps_only_the_close_pair_both_terms_highlighted
      doc = make_document(urn: "urn:d:jn", title: "John")
      make_passage(doc, urn: "urn:d:jn:1", text: "θεὸς ἦν ὁ λόγος", sequence: 0)
      make_passage(doc, urn: "urn:d:jn:2",
                        text: "λόγος μὲν οὖν ἐστιν ἀρχὴ πάντων καὶ τέλος ὁ θεός", sequence: 1)
      rebuild!

      hits = payload(call("nabu_search", { "query" => "λόγος", "near" => "θεός", "window" => 3 })).fetch("matches")
      assert_equal(%w[urn:d:jn:1], hits.map { |hit| hit.fetch("urn") })
      snippet = hits.first.fetch("snippet")
      assert_includes snippet, "[θεοσ]"
      assert_includes snippet, "[λογοσ]", "both proximity terms are bracketed in the snippet"
    end

    def test_search_near_expands_a_lemma_anchor_to_surface_forms
      doc = make_document(urn: "urn:d:lxx", title: "LXX")
      make_passage(doc, urn: "urn:d:lxx:1", text: "καὶ εἶπε κύριος", sequence: 0,
                        lemmas: [%w[λέγω εἶπε], %w[κύριος κύριος]])
      rebuild!

      hits = payload(call("nabu_search", { "lemma" => "λέγω", "near" => "κύριος", "window" => 2 })).fetch("matches")
      assert_equal(%w[urn:d:lxx:1], hits.map { |hit| hit.fetch("urn") },
                   "the suppletive aorist εἶπε counts as λέγω near κύριος")
    end

    def test_search_near_does_not_compose_with_morph
      doc = make_document(urn: "urn:d:tb", title: "Treebank")
      make_passage(doc, urn: "urn:d:tb:1", text: "x", sequence: 0, lemmas: [%w[λέγω εἶπας]])
      rebuild!
      assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_search", { "lemma" => "λέγω", "near" => "κύριος", "morph" => "case=nom" })
      end
    end

    def test_search_rejects_an_unknown_license_class
      seed_corpus
      error = assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_search", { "query" => "μηνιν", "license" => "copyleft" })
      end
      assert_match(/open/, error.message, "the message teaches the valid classes")
    end

    def test_unknown_tool_raises
      assert_raises(Nabu::MCP::Tools::UnknownTool) { call("nabu_frobnicate", {}) }
    end

    def test_search_truncates_at_the_limit_with_an_honest_note
      doc = make_document(urn: "urn:d:many")
      12.times { |i| make_passage(doc, urn: "urn:d:many:#{i}", text: "aurora venit", sequence: i) }
      rebuild!

      body = payload(call("nabu_search", { "query" => "aurora", "limit" => 5 }))
      assert_equal 5, body.fetch("matches").size
      assert_match(/showing 5/i, body.fetch("note"))
      assert_match(/more/i, body.fetch("note"), "the note admits more matches exist")
    end

    def test_search_limit_is_hard_capped
      doc = make_document(urn: "urn:d:many")
      60.times { |i| make_passage(doc, urn: "urn:d:many:#{i}", text: "aurora venit", sequence: i) }
      rebuild!

      body = payload(call("nabu_search", { "query" => "aurora", "limit" => 500 }))
      assert_operator body.fetch("matches").size, :<=, Nabu::MCP::Tools::SEARCH_MAX_LIMIT
    end

    def test_search_no_match_carries_a_coverage_hint
      seed_corpus
      body = payload(call("nabu_search", { "query" => "nonexistentword" }))
      assert_empty body.fetch("matches")
      coverage = body.fetch("coverage")
      assert_match(/grc/, coverage, "the hint names the corpus languages")
      assert_match(/passage/i, coverage)
    end

    # -- default exclusion of research_private/restricted ------------------------

    def test_search_hides_research_private_passages_by_default
      seed_corpus
      body = payload(call("nabu_search", { "query" => "αειδε" }))
      urns = body.fetch("matches").map { |hit| hit.fetch("urn") }
      refute_includes urns, "urn:nabu:adhoc:notes:1"
      refute_match(/μυστικον/, JSON.generate(body), "no private text leaks")
    end

    def test_search_include_restricted_opts_in
      seed_corpus
      body = payload(call("nabu_search", { "query" => "μυστικον", "include_restricted" => true }))
      assert_equal(%w[urn:nabu:adhoc:notes:1], body.fetch("matches").map { |h| h.fetch("urn") })
      assert_equal "research_private", body.fetch("matches").first.fetch("license_class")
    end

    def test_search_for_a_restricted_license_class_without_opt_in_explains_itself
      seed_corpus
      result = call("nabu_search", { "query" => "αειδε", "license" => "research_private" })
      refute result[:isError]
      assert_match(/excluded by default/i, text_of(result))
      refute_match(/μυστικον/, text_of(result))
    end

    def test_show_withholds_a_research_private_passage_by_default
      seed_corpus
      result = call("nabu_show", { "urn" => "urn:nabu:adhoc:notes:1" })
      refute result[:isError]
      assert_match(/research_private/, text_of(result), "names the class honestly")
      assert_match(/include_restricted/, text_of(result), "teaches the opt-in")
      refute_match(/μυστικον/, text_of(result), "the text itself does not leak")
    end

    def test_show_include_restricted_reveals_the_passage
      seed_corpus
      body = payload(call("nabu_show", { "urn" => "urn:nabu:adhoc:notes:1",
                                         "include_restricted" => true }))
      assert_equal "μυστικον ἄειδε σημειον", body.fetch("text")
      assert_equal "research_private", body.fetch("license_class")
    end

    def test_status_excludes_restricted_material_from_coverage_counts
      seed_corpus
      body = payload(call("nabu_status"))
      assert_equal 4, body.fetch("totals").fetch("passages"),
                   "the research_private passage is not in the default coverage"
      assert_equal({ "research_private" => 1 }, body.fetch("excluded_by_default"))
      refute_match(/μυστικον/, JSON.generate(body))
    end

    # -- nabu_show: passage / document / range / parallel ------------------------

    def test_show_passage_carries_full_attribution
      seed_corpus
      body = payload(call("nabu_show", { "urn" => "#{@grc.urn}:1.1" }))
      assert_equal "passage", body.fetch("type")
      assert_equal "μῆνιν ἄειδε θεά", body.fetch("text")
      assert_equal "grc", body.fetch("language")
      assert_equal "open", body.fetch("license_class")
      assert_equal "perseus", body.fetch("source")
      assert_equal @grc.urn, body.fetch("document_urn")
    end

    def test_show_document_lists_passages_each_with_license_fields
      seed_corpus
      body = payload(call("nabu_show", { "urn" => @grc.urn }))
      assert_equal "document", body.fetch("type")
      assert_equal 3, body.fetch("passages").size
      body.fetch("passages").each do |line|
        assert_equal "grc", line.fetch("language")
        assert_equal "open", line.fetch("license_class")
        assert line.fetch("urn").start_with?(@grc.urn)
      end
    end

    def test_show_document_truncates_with_an_honest_note
      doc = make_document(urn: "urn:d:long")
      10.times { |i| make_passage(doc, urn: "urn:d:long:#{i}", text: "line #{i}", sequence: i) }
      rebuild!

      body = payload(call("nabu_show", { "urn" => "urn:d:long", "max_passages" => 4 }))
      assert_equal 4, body.fetch("passages").size
      assert_match(/showing 4 of 10/i, body.fetch("note"))
      assert_match(/range/i, body.fetch("note"), "the note teaches the range-urn escape hatch")
    end

    def test_show_range_slices_inclusively_and_reports_the_bounds
      seed_corpus
      body = payload(call("nabu_show", { "urn" => "#{@grc.urn}:1.1-1.2" }))
      assert_equal "range", body.fetch("type")
      assert_equal 2, body.fetch("passages").size
      assert_equal 3, body.fetch("total")
      assert_equal "#{@grc.urn}:1.1", body.fetch("start_urn")
    end

    def test_show_bad_range_endpoint_is_a_tool_error_not_a_crash
      seed_corpus
      result = call("nabu_show", { "urn" => "#{@grc.urn}:1.1-9.9" })
      assert result[:isError]
      assert_match(/range end not found/i, text_of(result))
    end

    def test_show_unknown_urn_is_informative_not_an_error
      seed_corpus
      result = call("nabu_show", { "urn" => "urn:d:nope" })
      refute result[:isError]
      assert_match(/not found/i, text_of(result))
      assert_match(/nabu_search|nabu_status/, text_of(result), "points at the discovery tools")
    end

    def test_show_parallel_aligns_the_sibling_edition
      seed_corpus
      body = payload(call("nabu_show", { "urn" => "#{@grc.urn}:1.1", "parallel" => true }))
      assert_equal "parallel", body.fetch("type")
      assert_equal @eng.urn, body.fetch("right").fetch("urn")
      row = body.fetch("rows").fetch(0)
      assert_equal "Sing, goddess, the wrath", row.fetch("right").fetch("text")
      %w[left right].each do |side|
        line = row.fetch(side)
        assert line.key?("urn") && line.key?("language") && line.key?("license_class"),
               "every aligned passage carries urn/language/license_class"
      end
    end

    # P8-1b: the seed eng edition is ONE card (:1.1) owning three grc lines —
    # a coarse block. Its row carries the coverage fields so a model knows the
    # single translation block owns the whole grc span, not just line 1.1.
    def test_show_parallel_coarse_block_carries_coverage_fields
      seed_corpus
      body = payload(call("nabu_show", { "urn" => @grc.urn, "parallel" => true }))
      assert_equal "parallel", body.fetch("type")
      row = body.fetch("rows").fetch(0)
      assert_equal ":1.1", row.fetch("anchor")
      assert_equal ":1.1", row.fetch("covers_first")
      assert_equal ":1.3", row.fetch("covers_last")
      assert_equal false, row.fetch("clipped")
      assert_equal "Sing, goddess, the wrath", row.fetch("right").fetch("text")
      %w[urn language license_class].each { |k| assert row.fetch("left").key?(k) }
    end

    def test_show_parallel_range_clip_reports_the_shown_subrange
      seed_corpus
      body = payload(call("nabu_show", { "urn" => "#{@grc.urn}:1.2-1.3", "parallel" => true }))
      row = body.fetch("rows").fetch(0)
      assert row.fetch("clipped"), "the block extends past the sliced range"
      assert_equal ":1.1", row.fetch("covers_first")
      assert_equal ":1.3", row.fetch("covers_last")
      assert_equal ":1.2", row.fetch("shown_first")
      assert_equal ":1.3", row.fetch("shown_last")
    end

    def test_show_requires_a_urn
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { call("nabu_show", {}) }
    end

    # -- nabu_status --------------------------------------------------------------

    def test_status_reports_sources_languages_and_recency
      seed_corpus
      body = payload(call("nabu_status"))
      perseus = body.fetch("sources").find { |s| s.fetch("slug") == "perseus" }
      assert_equal 2, perseus.fetch("documents")
      assert_equal 4, perseus.fetch("passages")
      assert_match(/2026-07-01/, perseus.fetch("last_sync_at").to_s)
      assert_equal({ "grc" => 3, "eng" => 1 }, body.fetch("languages"))
      assert_equal({ "open" => 4 }, body.fetch("license_classes"))
    end

    # P11-10: a dictionary source (lexica) reports its entry count in status —
    # documents/passages are 0 for the reference shelf, so entries is the count
    # that stops it reading as an empty source. The totals carry the shelf sum.
    def test_status_reports_dictionary_entries_for_the_reference_shelf
      seed_corpus
      seed_shelf
      body = payload(call("nabu_status"))
      lexica = body.fetch("sources").find { |s| s.fetch("slug") == "lexica" }
      refute_nil lexica, "the lexica shelf must appear in status"
      assert_equal 0, lexica.fetch("documents")
      assert_equal 0, lexica.fetch("passages")
      assert_operator lexica.fetch("entries"), :>, 0, "the shelf's entry count must surface"
      assert_equal lexica.fetch("entries"), body.fetch("totals").fetch("dictionary_entries")
      # A passage source carries entries=0, never a nil/absent field.
      perseus = body.fetch("sources").find { |s| s.fetch("slug") == "perseus" }
      assert_equal 0, perseus.fetch("entries")
    end

    # -- nabu_concord (P8-3) -------------------------------------------------------

    def test_concord_returns_kwic_rows_with_urn_language_and_license
      seed_corpus
      body = payload(call("nabu_concord", { "query" => "μηνιν", "width" => 6 }))
      rows = body.fetch("rows")
      assert_equal 1, rows.size
      row = rows.first
      assert_equal "#{@grc.urn}:1.1", row.fetch("urn")
      assert_equal "grc", row.fetch("language")
      assert_equal "open", row.fetch("license_class")
      assert_equal "perseus", row.fetch("source")
      assert_equal "μῆνιν", row.fetch("keyword"), "the pristine accented keyword"
      assert row.key?("left") && row.key?("right"), "structured KWIC context"
      assert_equal 6, body.fetch("width")
    end

    def test_concord_lemma_mode_locates_the_surface_form
      doc = make_document(urn: "urn:d:tb", title: "Treebank")
      make_passage(doc, urn: "urn:d:tb:1", text: "σὺ δὲ εἶπας.", sequence: 0,
                        lemmas: [%w[λέγω εἶπας]])
      rebuild!

      rows = payload(call("nabu_concord", { "lemma" => "λέγω" })).fetch("rows")
      assert_equal(%w[urn:d:tb:1], rows.map { |r| r.fetch("urn") })
      assert_equal "εἶπας", rows.first.fetch("keyword")
    end

    def test_concord_requires_exactly_one_of_query_and_lemma
      seed_corpus
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { call("nabu_concord", {}) }
      assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_concord", { "query" => "a", "lemma" => "b" })
      end
    end

    def test_concord_truncates_at_the_limit_with_an_honest_note
      doc = make_document(urn: "urn:d:many")
      12.times { |i| make_passage(doc, urn: "urn:d:many:#{i}", text: "aurora venit", sequence: i) }
      rebuild!

      body = payload(call("nabu_concord", { "query" => "aurora", "limit" => 5 }))
      assert_equal 5, body.fetch("rows").size
      assert_match(/showing 5/i, body.fetch("note"))
      assert_match(/more/i, body.fetch("note"))
    end

    def test_concord_hides_research_private_rows_by_default
      seed_corpus
      body = payload(call("nabu_concord", { "query" => "αειδε" }))
      urns = body.fetch("rows").map { |r| r.fetch("urn") }
      refute_includes urns, "urn:nabu:adhoc:notes:1"
      refute_match(/μυστικον/, JSON.generate(body), "no private text leaks")
    end

    def test_concord_include_restricted_opts_in
      seed_corpus
      body = payload(call("nabu_concord", { "query" => "μυστικον", "include_restricted" => true }))
      assert_equal(%w[urn:nabu:adhoc:notes:1], body.fetch("rows").map { |r| r.fetch("urn") })
      assert_equal "research_private", body.fetch("rows").first.fetch("license_class")
    end

    def test_concord_no_match_carries_a_coverage_hint
      seed_corpus
      body = payload(call("nabu_concord", { "query" => "nonexistentword" }))
      assert_empty body.fetch("rows")
      assert_match(/grc/, body.fetch("coverage"))
    end

    # -- nabu_define (P11-4) -----------------------------------------------------

    # The real lexica fixtures, loaded through the real DictionaryLoader.
    def seed_shelf(source: @open)
      lexica = Nabu::Store::Source.create(
        slug: "lexica", name: "Perseus Lexica", adapter_class: "Nabu::Adapters::Lexica",
        license: "CC BY-SA 4.0", license_class: source.license_class, enabled: true
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: lexica)
                                   .load_from(Nabu::Adapters::Lexica.new,
                                              workdir: Nabu::TestSupport.fixtures("lexica"))
      lexica
    end

    def test_define_returns_entries_with_license_labels_and_resolved_citations
      seed_shelf
      iliad = make_document(urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2")
      make_passage(iliad, urn: "#{iliad.urn}:1.1", text: "μῆνιν ἄειδε θεά", sequence: 0)

      entries = payload(call("nabu_define", { "lemma" => "μῆνις" })).fetch("entries")
      assert_equal 1, entries.size
      entry = entries.first
      assert_equal "μῆνις", entry.fetch("headword")
      assert_equal "lsj", entry.fetch("dictionary")
      assert_equal "open", entry.fetch("license_class")
      assert_equal "lexica", entry.fetch("source")
      assert_equal "wrath", entry.fetch("gloss")
      iliad_cite = entry.fetch("citations").find { |c| c.fetch("label") == "Il. 1.1" }
      assert_equal "#{iliad.urn}:1.1", iliad_cite.fetch("resolved_urn")
      unresolved = entry.fetch("citations").find { |c| c.fetch("label").start_with?("Pl. R.") }
      assert_nil unresolved.fetch("resolved_urn")
    end

    def test_define_truncates_long_bodies_with_an_honest_note
      seed_shelf
      entry = payload(call("nabu_define", { "lemma" => "λόγος" })).fetch("entries").first
      assert_operator entry.fetch("body").length, :<=, Nabu::MCP::Tools::DEFINE_BODY_CAP + 1
      assert entry.fetch("body_truncated")
      assert_match(/nabu define/, entry.fetch("note"), "the note points at the unbounded CLI surface")
    end

    def test_define_requires_a_lemma
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { call("nabu_define", {}) }
    end

    def test_define_no_match_is_informative
      seed_shelf
      result = call("nabu_define", { "lemma" => "βλαβλα" })
      refute result[:isError]
      assert_match(/no dictionary entry/i, payload(result).fetch("note"))
    end

    # P12-3: the Old English shelf — content_kind inheritance made concrete on
    # the MCP surface: nabu_define reaches Bosworth-Toller through the same
    # tool, lang=ang is a legal shelf filter, and the ASCII folded form
    # (aethele) reaches the æðele entry.
    def test_define_covers_the_old_english_shelf
      bt = Nabu::Store::Source.create(
        slug: "bosworth-toller", name: "Bosworth-Toller",
        adapter_class: "Nabu::Adapters::BosworthToller",
        license: "CC BY 4.0", license_class: "attribution", enabled: true
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: bt)
                                   .load_from(Nabu::Adapters::BosworthToller.new,
                                              workdir: Nabu::TestSupport.fixtures("bosworth-toller"))

      entries = payload(call("nabu_define", { "lemma" => "aethele", "lang" => "ang" })).fetch("entries")
      assert_equal 1, entries.size
      entry = entries.first
      assert_equal "æðele", entry.fetch("headword")
      assert_equal "bosworth-toller", entry.fetch("dictionary")
      assert_equal "noble", entry.fetch("gloss")
      assert_equal "attribution", entry.fetch("license_class")
      assert_empty entry.fetch("citations"), "no OE crosswalk yet — citations start empty"
      assert_includes Nabu::MCP::Tools::DEFINE_SCHEMA.dig(:properties, :lang, :enum), "ang"
    end

    # P13-10: the OCS shelf — nabu_define reaches Wiktionary-OCS through the
    # same tool, lang=chu is a legal shelf filter, the Cyrillic headword
    # resolves via the generic chu fold, and the etymology (the reconstruction
    # seed) rides in the body.
    def test_define_covers_the_ocs_shelf
      wk = Nabu::Store::Source.create(
        slug: "wiktionary-cu", name: "Wiktionary OCS (kaikki.org)",
        adapter_class: "Nabu::Adapters::WiktionaryCu",
        license: "CC-BY-SA + GFDL", license_class: "attribution", enabled: true
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: wk)
                                   .load_from(Nabu::Adapters::WiktionaryCu.new,
                                              workdir: Nabu::TestSupport.fixtures("wiktionary-cu"))

      entries = payload(call("nabu_define", { "lemma" => "богъ", "lang" => "chu" })).fetch("entries")
      assert_equal 1, entries.size
      entry = entries.first
      assert_equal "богъ", entry.fetch("headword")
      assert_equal "wiktionary-cu", entry.fetch("dictionary")
      assert_equal "god", entry.fetch("gloss")
      assert_equal "attribution", entry.fetch("license_class")
      assert_includes entry.fetch("body"), "Inherited from Proto-Slavic *bogъ.",
                      "the etymology chain must survive into the MCP body"
      assert_empty entry.fetch("citations"), "Wiktionary quotes are unanchored — citations start empty"
      assert_includes Nabu::MCP::Tools::DEFINE_SCHEMA.dig(:properties, :lang, :enum), "chu"
    end

    def test_define_withholds_restricted_dictionaries_by_default
      seed_shelf(source: @private)
      result = call("nabu_define", { "lemma" => "μῆνις" })
      assert_empty payload(result).fetch("entries")
      revealed = payload(call("nabu_define", { "lemma" => "μῆνις", "include_restricted" => true }))
      assert_equal 1, revealed.fetch("entries").size
    end

    def test_define_without_the_shelf_migration_degrades_gracefully
      bare = Nabu::Store.connect("sqlite::memory:")
      result = tools(catalog: bare, fulltext: @fulltext).call("nabu_define", { "lemma" => "μῆνις" })
      refute result[:isError]
      assert_match(/shelf|dictionar/i, text_of(result))
    ensure
      bare&.disconnect
    end

    def test_concord_with_a_missing_fts_table_degrades_gracefully
      seed_corpus
      @fulltext.drop_table(Nabu::Store::Indexer::TABLE)
      result = call("nabu_concord", { "query" => "μηνιν" })
      refute result[:isError], "a rebuild window is a state, not a fault"
      assert_match(/rebuilding.*retry shortly/i, text_of(result))
    end

    # -- degradation ---------------------------------------------------------------

    def test_search_with_a_missing_fts_table_degrades_to_a_retry_note
      seed_corpus
      @fulltext.drop_table(Nabu::Store::Indexer::TABLE) # mid-reindex window
      result = call("nabu_search", { "query" => "μηνιν" })
      refute result[:isError], "a rebuild window is a state, not a fault"
      assert_match(/rebuilding.*retry shortly/i, text_of(result))
    end

    def test_lemma_search_with_a_missing_lemma_table_degrades_gracefully
      seed_corpus
      @fulltext.drop_table(Nabu::Store::Indexer::LEMMA_TABLE)
      result = call("nabu_search", { "lemma" => "λέγω" })
      refute result[:isError]
      assert_match(/rebuilding|rebuild/i, text_of(result))
    end

    def test_missing_catalog_degrades_to_a_no_corpus_note
      absent = tools(catalog: nil, fulltext: nil)
      %w[nabu_search nabu_show nabu_concord nabu_status].each do |name|
        args = { "nabu_search" => { "query" => "x" }, "nabu_show" => { "urn" => "urn:x" },
                 "nabu_concord" => { "query" => "x" }, "nabu_status" => {} }.fetch(name)
        result = absent.call(name, args)
        refute result[:isError]
        assert_match(/no corpus.*sync.*rebuild/im, result[:content].fetch(0).fetch(:text))
      end
    end

    def test_sqlite_busy_is_retried_then_succeeds
      seed_corpus
      attempts = 0
      flaky_catalog = lambda do
        attempts += 1
        raise Sequel::DatabaseError, "SQLite3::BusyException: database is locked" if attempts == 1

        @catalog
      end
      result = tools(catalog: flaky_catalog, fulltext: @fulltext)
               .call("nabu_search", { "query" => "μηνιν" })
      refute result[:isError]
      assert_equal 1, payload(result).fetch("matches").size
    end

    def test_sqlite_busy_exhaustion_degrades_gracefully
      always_busy = -> { raise Sequel::DatabaseError, "database is locked (SQLITE_BUSY)" }
      result = tools(catalog: always_busy, fulltext: @fulltext)
               .call("nabu_status", {})
      refute result[:isError], "busy is a state, not a fault"
      assert_match(/busy.*retry/im, text_of(result))
    end

    # -- nabu_align (P11-3) ------------------------------------------------------

    ALIGN_REGISTRY_YAML = <<~YAML
      nt:
        title: "New Testament (parallel witnesses)"
        witnesses:
          - document: urn:nabu:proiel:greek-nt
          - document: urn:nabu:proiel:marianus
    YAML

    def align_registry(yaml = ALIGN_REGISTRY_YAML)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "alignments.yml")
        File.write(path, yaml)
        return Nabu::AlignmentRegistry.load(path)
      end
    end

    # Two nc witnesses attesting MARK 2.3 (sentence-id urns, verse identity in
    # the token citation_parts — the live five-way shape, trimmed to two).
    def seed_aligned_corpus(source: nil)
      source ||= Nabu::Store::Source.create(
        slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter",
        license_class: "nc", enabled: true
      )
      [["greek-nt", "grc", "καὶ ἔρχονται φέροντες πρὸς αὐτὸν παραλυτικὸν"],
       ["marianus", "chu", "Ꙇ придѫ къ немоу носѧште ослабленъ жилами"]].each do |tail, lang, text|
        doc = make_document(source: source, urn: "urn:nabu:proiel:#{tail}",
                            title: tail, language: lang)
        Nabu::Store::Passage.create(
          document_id: doc.id, urn: "#{doc.urn}:1", sequence: 0, language: lang,
          text: text, text_normalized: text, content_sha256: "x", revision: 1,
          annotations_json: JSON.generate(
            "tokens" => [{ "citation_part" => "MARK 2.3", "form" => "x" }]
          )
        )
      end
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    alignments: align_registry)
    end

    def align_tools(registry = align_registry)
      Nabu::MCP::Tools.new(catalog: @catalog, fulltext: @fulltext, alignments: registry)
    end

    def test_align_renders_witnesses_with_the_full_license_contract
      seed_aligned_corpus
      result = align_tools.call("nabu_align", { "ref" => "mark 2:3" })

      refute result[:isError]
      body = payload(result)
      assert_equal "MARK 2.3", body.fetch("ref"), "the query ref is normalized"
      witnesses = body.fetch("witnesses")
      assert_equal(%w[greek-nt marianus], witnesses.map { |witness| witness.fetch("label") })
      witnesses.each do |witness|
        assert_equal "nc", witness.fetch("license_class")
        assert_equal "ok", witness.fetch("status")
        witness.fetch("sentences").each do |sentence|
          assert_match(/\Aurn:nabu:proiel:/, sentence.fetch("urn"))
          assert sentence.key?("language")
          assert_equal "nc", sentence.fetch("license_class")
          assert_equal "proiel", sentence.fetch("source")
        end
      end
      assert_match(/2 of 2/, body.fetch("note"))
    end

    PSALMS_REGISTRY_YAML = <<~YAML
      psalms:
        title: "Psalms"
        witnesses:
          - label: LXX
            extractor: cts-verse
            documents:
              PSA: urn:cts:greekLit:tlg0527.tlg027.1st1K-grc1
          - label: WEB (English)
            extractor: cts-verse
            numbering:
              system: "Hebrew (Masoretic)"
              ranges:
                - { from: 11, to: 113, shift: -1 }
            documents:
              PSA: urn:nabu:eng-web:psa
    YAML

    def test_align_surfaces_the_numbering_divergence_and_native_ref
      registry = align_registry(PSALMS_REGISTRY_YAML)
      source = Nabu::Store::Source.create(
        slug: "bible", name: "Bible", adapter_class: "TestAdapter", license_class: "attribution", enabled: true
      )
      [["urn:cts:greekLit:tlg0527.tlg027.1st1K-grc1", "grc", "22.1", "Κύριος ποιμαίνει με"],
       ["urn:nabu:eng-web:psa", "eng", "23.1", "Yahweh is my shepherd"]].each do |doc_urn, lang, tail, text|
        doc = make_document(source: source, urn: doc_urn, title: "Psalms", language: lang)
        Nabu::Store::Passage.create(
          document_id: doc.id, urn: "#{doc_urn}:#{tail}", sequence: 0, language: lang,
          text: text, text_normalized: text, content_sha256: "x", revision: 1, annotations_json: "{}"
        )
      end
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, alignments: registry)

      body = payload(align_tools(registry).call("nabu_align", { "ref" => "PSA 22.1" }))
      lxx, web = body.fetch("witnesses")
      refute lxx.key?("numbering"), "the Greek witness is the work vocabulary — no numbering flag"
      assert_equal "Hebrew (Masoretic)", web.fetch("numbering"), "the WEB column is flagged as remapped"
      sentence = web.fetch("sentences").first
      assert_equal "urn:nabu:eng-web:psa:23.1", sentence.fetch("urn")
      assert_equal "PSA 23.1", sentence.fetch("native_ref"), "and reports its native Hebrew ref"
    end

    def test_align_missing_ref_is_invalid_arguments
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { align_tools.call("nabu_align", {}) }
    end

    def test_align_without_a_registry_notes_how_to_register
      seed_aligned_corpus
      result = tools.call("nabu_align", { "ref" => "MARK 2.3" })
      refute result[:isError], "an unconfigured hub is a state, not a fault"
      assert_match(/no alignment works registered/i, text_of(result))
    end

    def test_align_with_a_missing_index_table_degrades_gracefully
      seed_aligned_corpus
      @fulltext.drop_table?(Nabu::Store::AlignmentIndexer::TABLE)
      result = align_tools.call("nabu_align", { "ref" => "MARK 2.3" })
      refute result[:isError]
      assert_match(/alignment index/i, text_of(result))
    end

    def test_align_unknown_work_is_a_tool_error
      seed_aligned_corpus
      result = align_tools.call("nabu_align", { "ref" => "MARK 2.3", "work" => "iliad" })
      assert result[:isError], "a bad work id is caller-fixable — isError so the model corrects"
      assert_match(/iliad/, text_of(result))
    end

    def test_align_withholds_restricted_witnesses_by_default
      seed_aligned_corpus(source: @private)
      result = align_tools.call("nabu_align", { "ref" => "MARK 2.3" })

      refute result[:isError]
      body = payload(result)
      body.fetch("witnesses").each do |witness|
        assert_equal "withheld", witness.fetch("status")
        assert_empty witness.fetch("sentences")
      end
      refute_match(/παραλυτικὸν/, text_of(result), "restricted text must not leak")

      opted = payload(align_tools.call("nabu_align", { "ref" => "MARK 2.3",
                                                       "include_restricted" => true }))
      assert_equal(%w[ok ok], opted.fetch("witnesses").map { |witness| witness.fetch("status") })
    end

    def test_align_missing_catalog_degrades_to_no_corpus
      result = Nabu::MCP::Tools.new(catalog: nil, fulltext: @fulltext, alignments: align_registry)
                               .call("nabu_align", { "ref" => "MARK 2.3" })
      refute result[:isError]
      assert_match(/no corpus/i, text_of(result))
    end

    # -- nabu_align ranges / chapters (P11-8) -----------------------------------

    RANGE_REGISTRY_YAML = <<~YAML
      ot:
        witnesses:
          - label: full
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-a:jon
          - label: partial
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-b:jon
    YAML

    def seed_range_corpus
      source = Nabu::Store::Source.create(
        slug: "bible", name: "Bible", adapter_class: "TestAdapter", license_class: "open", enabled: true
      )
      full = make_document(source: source, urn: "urn:nabu:src-a:jon", title: "Jonah", language: "grc")
      (1..10).each { |v| make_passage(full, urn: "#{full.urn}:1.#{v}", text: "greek verse #{v}", sequence: v - 1) }
      partial = make_document(source: source, urn: "urn:nabu:src-b:jon", title: "Jonas", language: "lat")
      make_passage(partial, urn: "#{partial.urn}:1.1", text: "latin one", sequence: 0)
      make_passage(partial, urn: "#{partial.urn}:1.3", text: "latin three", sequence: 1, language: "lat")
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    alignments: align_registry(RANGE_REGISTRY_YAML))
    end

    def test_align_chapter_returns_a_refs_array_in_document_order
      seed_range_corpus
      body = payload(align_tools(align_registry(RANGE_REGISTRY_YAML)).call("nabu_align", { "ref" => "JON 1" }))

      assert_equal "alignment_range", body.fetch("type")
      assert_equal "JON 1", body.fetch("query")
      assert_equal 10, body.fetch("total_refs")
      assert_equal((1..10).map { |v| "JON 1.#{v}" }, body.fetch("refs").map { |r| r.fetch("ref") })
      first = body.fetch("refs").first.fetch("witnesses")
      assert_equal(%w[ok ok], first.map { |w| w.fetch("status") }, "verse 1 attested by both")
      second = body.fetch("refs")[1].fetch("witnesses")
      assert_equal(%w[ok no_match], second.map { |w| w.fetch("status") }, "verse 2 only in full")
    end

    def test_align_range_is_inclusive_and_carries_a_cap_accounting
      seed_range_corpus
      body = payload(align_tools(align_registry(RANGE_REGISTRY_YAML)).call("nabu_align", { "ref" => "JON 1.3-1.5" }))
      assert_equal((3..5).map { |v| "JON 1.#{v}" }, body.fetch("refs").map { |r| r.fetch("ref") })
      refute body.fetch("truncated")
      assert_equal 3, body.fetch("shown_refs")
    end

    def test_align_reversed_range_is_a_tool_error
      seed_range_corpus
      result = align_tools(align_registry(RANGE_REGISTRY_YAML)).call("nabu_align", { "ref" => "JON 1.5-1.3" })
      assert result[:isError]
      assert_match(/reversed range/, text_of(result))
    end

    # P11-9: a witness absent from every ref of a range is summarized once in
    # absent_witnesses and dropped from the per-ref witness columns.
    ABSENT_RANGE_REGISTRY_YAML = <<~YAML
      ot:
        witnesses:
          - label: full
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-a:jon
          - label: partial
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-b:jon
          - label: ghost
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-z:jon
    YAML

    def test_align_range_lifts_all_absent_witnesses_out_of_the_per_ref_columns
      seed_range_corpus # seeds src-a + src-b; src-z (ghost) is never synced
      registry = align_registry(ABSENT_RANGE_REGISTRY_YAML)
      # Re-index so the registry the tools use matches the seeded index.
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, alignments: registry)
      body = payload(align_tools(registry).call("nabu_align", { "ref" => "JON 1" }))

      assert_equal([{ "label" => "ghost", "reason" => "not_synced" }],
                   body.fetch("absent_witnesses"))
      body.fetch("refs").each do |group|
        labels = group.fetch("witnesses").map { |witness| witness.fetch("label") }
        assert_equal %w[full partial], labels, "the not_synced witness is gone from every ref"
      end
    end

    # -- read-only enforcement ------------------------------------------------------

    def test_readonly_connection_refuses_writes
      Dir.mktmpdir do |dir|
        path = File.join(dir, "catalog.sqlite3")
        rw = Nabu::Store.connect(path)
        Nabu::Store.migrate!(rw)
        rw.disconnect

        ro = Nabu::Store.connect(path, readonly: true)
        error = assert_raises(Sequel::DatabaseError) do
          ro[:sources].insert(slug: "evil", name: "Evil", adapter_class: "X",
                              license_class: "open")
        end
        assert_match(/readonly|read.only/i, error.message)
        assert_equal [], ro[:sources].all, "reads still work"
      ensure
        ro&.disconnect
      end
    end
  end
end
