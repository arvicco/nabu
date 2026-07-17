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

    def tools(catalog: @catalog, fulltext: @fulltext, ledger: nil, links: nil, registry: nil)
      Nabu::MCP::Tools.new(catalog: catalog, fulltext: fulltext, ledger: ledger, links: links,
                           registry: registry)
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

    def test_definitions_lists_the_ten_tools_with_json_schemas
      defs = tools.definitions
      assert_equal(%w[nabu_search nabu_show nabu_concord nabu_align nabu_define nabu_etym
                      nabu_parallels nabu_cognates nabu_links nabu_status],
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

    # -- nabu_search date/place axis (P15-2) -----------------------------------

    def test_search_from_to_filters_by_date
      a = make_document(urn: "urn:nabu:ddbdp:a")
      make_passage(a, urn: "urn:nabu:ddbdp:a:1", text: "στρατηγος", sequence: 0)
      b = make_document(urn: "urn:nabu:ddbdp:b")
      make_passage(b, urn: "urn:nabu:ddbdp:b:1", text: "στρατηγος", sequence: 0)
      @catalog[:document_axes].insert(document_id: a.id, not_before: -113, not_after: -113,
                                      place_name: "Oxyrhynchus", axis_source: "hgv")
      @catalog[:document_axes].insert(document_id: b.id, not_before: 591, not_after: 602,
                                      place_name: "Arsinoites", axis_source: "hgv")
      rebuild!

      urns = payload(call("nabu_search", { "query" => "στρατηγος", "from" => -300, "to" => -30 }))
             .fetch("matches").map { |h| h.fetch("urn") }
      assert_equal %w[urn:nabu:ddbdp:a:1], urns
      places = payload(call("nabu_search", { "query" => "στρατηγος", "place" => "oxyrhynch%" }))
               .fetch("matches").map { |h| h.fetch("urn") }
      assert_equal %w[urn:nabu:ddbdp:a:1], places
    end

    def test_search_date_does_not_compose_with_lemma
      assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_search", { "lemma" => "λέγω", "from" => -300 })
      end
    end

    def test_search_year_zero_is_invalid
      error = assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        call("nabu_search", { "query" => "x", "from" => 0 })
      end
      assert_match(/no year 0/i, error.message)
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

    # P19-4 end-to-end pin: the local-library shelf (source class
    # research_private) is MCP-excluded by default through the EXISTING
    # machinery — no shelf-specific code — while a manifest entry's explicit
    # open override serves normally with its label.
    def test_local_library_shelf_is_mcp_excluded_by_default_with_open_overrides_served
      shelf = Nabu::Store::Source.create(
        slug: "local-library", name: "Local library",
        adapter_class: "Nabu::Adapters::LocalLibrary", license_class: "research_private", enabled: true
      )
      article = make_document(source: shelf, urn: "urn:nabu:local-library:c:leskien",
                              title: "Leskien 1871", language: "deu")
      make_passage(article, urn: "urn:nabu:local-library:c:leskien:p1",
                            text: "vertraulich altbulgarischen", sequence: 0, language: "deu")
      note = make_document(source: shelf, urn: "urn:nabu:local-library:c:note",
                           title: "Open note", language: "eng", license_override: "open")
      make_passage(note, urn: "urn:nabu:local-library:c:note:1",
                         text: "offen altbulgarischen", sequence: 0, language: "eng")
      rebuild!

      urns = payload(call("nabu_search", { "query" => "altbulgarischen" }))
             .fetch("matches").map { |hit| hit.fetch("urn") }
      assert_equal %w[urn:nabu:local-library:c:note:1], urns,
                   "the shelf default hides; the explicit open entry serves"

      opted = payload(call("nabu_search", { "query" => "altbulgarischen", "include_restricted" => true }))
      classes = opted.fetch("matches").to_h { |hit| [hit.fetch("urn"), hit.fetch("license_class")] }
      assert_equal "research_private", classes.fetch("urn:nabu:local-library:c:leskien:p1")
      assert_equal "open", classes.fetch("urn:nabu:local-library:c:note:1")

      shown = call("nabu_show", { "urn" => "urn:nabu:local-library:c:leskien:p1" })
      assert_match(/research_private/, text_of(shown))
      refute_match(/vertraulich/, text_of(shown), "the shelf's text never leaks by default")
    end

    # -- P24-1: owner notes served by default, withheld with their target ---------

    def seed_note(urn:, note:, topic: "notes", tags: nil, added: "2026-07-16")
      @catalog[:urn_notes].insert(urn: urn, note: note, topic: topic, added: added,
                                  tags: tags && JSON.generate(tags),
                                  provenance: "local-notes/#{topic}.yml")
    end

    def test_show_serves_owner_notes_by_default_with_the_document_child_count
      seed_corpus
      seed_note(urn: @grc.urn, note: "Collate against the OCT.", tags: %w[collation])
      seed_note(urn: "#{@grc.urn}:1.1", note: "The invocation line.")

      body = payload(call("nabu_show", { "urn" => @grc.urn }))
      notes = body.fetch("notes")
      assert_equal(["Collate against the OCT."], notes.map { |n| n.fetch("note") })
      assert_equal %w[collation], notes.first.fetch("tags")
      assert_equal "notes", notes.first.fetch("topic")
      assert_equal 1, body.fetch("passage_note_count"), "the document counts its passage-note children"

      passage = payload(call("nabu_show", { "urn" => "#{@grc.urn}:1.1" }))
      assert_equal(["The invocation line."], passage.fetch("notes").map { |n| n.fetch("note") })
    end

    def test_show_omits_the_notes_lane_when_unnoted
      seed_corpus
      body = payload(call("nabu_show", { "urn" => @grc.urn }))
      refute body.key?("notes"), "zero-signal silence, not an empty list"
      refute body.key?("passage_note_count")
    end

    # The withholding rule: a note on a research_private/restricted document
    # follows the DOCUMENT's withholding — the withheld response carries no
    # notes, so a note can never leak a withheld text's content frame.
    def test_notes_on_a_withheld_document_are_withheld_with_it
      seed_corpus
      seed_note(urn: "urn:nabu:adhoc:notes:1", note: "The μυστικον passage frames the private survey.")

      withheld = call("nabu_show", { "urn" => "urn:nabu:adhoc:notes:1" })
      refute_match(/μυστικον/, text_of(withheld))
      refute_match(/private survey/, text_of(withheld), "the note is withheld with its target")

      opted = payload(call("nabu_show", { "urn" => "urn:nabu:adhoc:notes:1",
                                          "include_restricted" => true }))
      assert_match(/private survey/, opted.fetch("notes").first.fetch("note"),
                   "the deliberate opt-in serves the note beside its target")
    end

    def test_define_serves_entry_notes_by_default
      seed_shelf
      bare = payload(call("nabu_define", { "lemma" => "λόγος" })).fetch("entries").first
      refute bare.key?("notes"), "zero-signal silence before any note exists"
      entry_urn = bare.fetch("urn")
      seed_note(urn: entry_urn, note: "Anchor for the John 1.1 comparison.")

      entry = payload(call("nabu_define", { "lemma" => "λόγος" })).fetch("entries").first
      assert_equal(["Anchor for the John 1.1 comparison."], entry.fetch("notes").map { |n| n.fetch("note") })

      shown = payload(call("nabu_show", { "urn" => entry_urn }))
      assert_equal ["Anchor for the John 1.1 comparison."], shown.fetch("notes").map { |n| n.fetch("note") },
                   "show on the minted dict urn carries the same lane"
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

    # P24-0: each source's dossier description (canonical/local-source →
    # source_records) rides the status payload by default — the owner's own
    # library metadata is useful context. Absent dossier = absent key.
    def test_status_serves_source_dossier_descriptions_by_default
      seed_corpus
      @catalog[:source_records].insert(slug: "perseus", kind: "description",
                                       body: "The Greek canon.", provenance: "dossier")
      body = payload(call("nabu_status"))
      perseus = body.fetch("sources").find { |s| s.fetch("slug") == "perseus" }
      assert_equal "The Greek canon.", perseus.fetch("description")
      undescribed = body.fetch("sources").find { |s| s.fetch("slug") != "perseus" }
      refute undescribed.key?("description"), "no dossier description = absent key, never a null"
    end

    # P23-3b: the registry is AUTHORITATIVE for enablement — a registry flip
    # reaches the db row only at the source's next sync, so status surfaces
    # the registry value for registered slugs. An unregistered catalog source
    # (no registry line) keeps its db value, honestly.
    def test_status_enabled_comes_from_the_registry_when_registered
      seed_corpus
      @catalog[:sources].where(slug: "perseus").update(enabled: false) # stale db row
      registry = Nabu::SourceRegistry.new([
                                            Nabu::SourceRegistry::Entry.new(
                                              slug: "perseus", adapter_class_name: "TestAdapter",
                                              enabled: true, sync_policy: "manual"
                                            )
                                          ])
      body = payload(tools(registry: registry).call("nabu_status", {}))
      sources = body.fetch("sources")
      assert sources.find { |s| s.fetch("slug") == "perseus" }.fetch("enabled"),
             "registry enabled: true must win over the stale db row"
      # adhoc has no registry line: the db value is all there is.
      assert sources.find { |s| s.fetch("slug") == "adhoc" }.fetch("enabled")
    end

    # P14-12: nabu_status surfaces the CACHED upstream-drift verdict per source
    # from the ledger — a bounded status read, never a live probe.
    def test_status_surfaces_cached_upstream_verdict
      seed_corpus
      ledger = ledger_test_db
      Nabu::Store::Probe.create(source_slug: "perseus", checked_at: Time.utc(2026, 7, 10, 12),
                                drift: "behind", license: "unchanged",
                                detail: "behind: https://github.com/acme/one")
      body = payload(tools(ledger: ledger).call("nabu_status", {}))

      perseus = body.fetch("sources").find { |s| s.fetch("slug") == "perseus" }
      upstream = perseus.fetch("upstream")
      assert_equal "behind", upstream.fetch("drift")
      assert_equal "unchanged", upstream.fetch("license")
      assert_match(/2026-07-10/, upstream.fetch("checked_at"))
      assert_match(/behind: /, upstream.fetch("detail"))
      assert_match(/never probes upstreams live/, body.fetch("note"))
    end

    # A source with no cache row (or no ledger at all) reports never_probed,
    # never a nil/absent upstream field.
    def test_status_upstream_never_probed_without_a_cache_row
      seed_corpus
      # ledger present but empty (adhoc/perseus have no probe rows)
      body = payload(tools(ledger: ledger_test_db).call("nabu_status", {}))
      perseus = body.fetch("sources").find { |s| s.fetch("slug") == "perseus" }
      assert_equal "never_probed", perseus.fetch("upstream").fetch("drift")

      # and with no ledger configured at all, still never_probed, no crash
      body2 = payload(call("nabu_status"))
      p2 = body2.fetch("sources").find { |s| s.fetch("slug") == "perseus" }
      assert_equal "never_probed", p2.fetch("upstream").fetch("drift")
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

    # -- nabu_parallels (P15-1 intertext) -----------------------------------------

    PROEM = "ἄνδρα μοι ἔννεπε μοῦσα πολύτροπον ὃς μάλα πολλὰ"

    # An anchor, an OPEN quoter, and a RESEARCH_PRIVATE quoter of the same line —
    # so the default-exclusion and include_restricted contract can be probed.
    def seed_parallels
      anchor = make_document(urn: "urn:d:od", title: "Odyssey")
      make_passage(anchor, urn: "urn:d:od:1.1", text: PROEM, sequence: 0)
      openq = make_document(urn: "urn:d:pol", title: "Histories")
      make_passage(openq, urn: "urn:d:pol:1", text: "φησιν #{PROEM}", sequence: 0)
      secret = make_document(source: @private, urn: "urn:d:secret", title: "Private")
      make_passage(secret, urn: "urn:d:secret:1", text: "λέγει #{PROEM}", sequence: 0)
      rebuild!
    end

    def test_parallels_returns_hits_with_the_license_contract
      seed_parallels
      body = payload(call("nabu_parallels", { "urn" => "urn:d:od:1.1" }))
      assert_equal "parallels", body["type"]
      assert_equal "urn:d:od:1.1", body.dig("anchor", "urn")
      hit = body["hits"].find { |h| h["urn"] == "urn:d:pol:1" }
      refute_nil hit, "the open quoter is a hit"
      %w[urn language license_class source score shared_grams evidence].each do |field|
        assert hit.key?(field), "every hit carries #{field}"
      end
      assert_equal "open", hit["license_class"]
      assert(hit["evidence"].any? { |span| span.include?("ανδρα μοι εννεπε μουσα") }, "shared phrase evidence")
    end

    def test_parallels_excludes_restricted_candidates_by_default
      seed_parallels
      urns = payload(call("nabu_parallels", { "urn" => "urn:d:od:1.1" }))["hits"].map { |h| h["urn"] }
      refute_includes urns, "urn:d:secret:1", "the research_private quoter is excluded by default"

      opened = payload(call("nabu_parallels", { "urn" => "urn:d:od:1.1", "include_restricted" => true }))
      assert_includes opened["hits"].map { |h| h["urn"] }, "urn:d:secret:1",
                      "include_restricted: true opts the private quoter back in"
    end

    def test_parallels_missing_urn_is_an_invalid_argument
      seed_parallels
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { call("nabu_parallels", {}) }
    end

    def test_parallels_unknown_urn_is_a_graceful_note
      seed_parallels
      result = call("nabu_parallels", { "urn" => "urn:d:nope:1" })
      refute result[:isError]
      assert_match(/not found/i, text_of(result))
    end

    def test_parallels_without_index_reports_rebuilding
      empty = Nabu::Store.connect_fulltext("sqlite::memory:")
      result = tools(fulltext: empty).call("nabu_parallels", { "urn" => "urn:d:od:1.1" })
      refute result[:isError]
      assert_match(/rebuilding/i, text_of(result))
    ensure
      empty&.disconnect
    end

    # -- nabu_links (P16-1 links journal) ------------------------------------------

    def seed_links_journal
      journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
      run_id = Nabu::Store::LinksJournal.record_run!(
        journal, producer: "parallels", scope: "urn:d:od", params: { min_score: 0.05 },
                 code_version: "t/1"
      )
      Nabu::Store::LinksJournal.write_edge!(journal, from_urn: "urn:d:od:1.1", to_urn: "urn:d:pol:1",
                                                     kind: "parallel", score: 2.0, run_id: run_id)
      Nabu::Store::LinksJournal.write_edge!(journal, from_urn: "urn:d:od:1.1", to_urn: "urn:d:secret:1",
                                                     kind: "parallel", score: 1.0, run_id: run_id)
      journal
    end

    def test_links_returns_grouped_edges_with_resolution_and_run_provenance
      seed_parallels
      journal = seed_links_journal
      body = payload(tools(links: journal).call("nabu_links", { "urn" => "urn:d:od:1.1" }))
      assert_equal "links", body["type"]
      assert_equal "Odyssey", body["document"]
      edge = body.dig("kinds", "parallel").find { |e| e["urn"] == "urn:d:pol:1" }
      assert_equal %w[out Histories grc open],
                   [edge["direction"], edge["document"], edge["language"], edge["license_class"]]
      run = body["runs"].first
      assert_equal ["parallels", "urn:d:od", "t/1"], [run["producer"], run["scope"], run["code_version"]]
      assert_match(/PRESERVE license/, body["note"])
    ensure
      journal&.disconnect
    end

    def test_links_edge_detail_rides_the_payload
      seed_parallels
      journal = seed_links_journal
      run_id = Nabu::Store::LinksJournal.record_run!(
        journal, producer: "cognates", scope: "nt", params: { kind: "cognate" }, code_version: "t/1"
      )
      Nabu::Store::LinksJournal.write_edge!(
        journal, from_urn: "urn:d:od:1.1", to_urn: "urn:d:pol:1", kind: "cognate",
                 score: 1.0, detail: "MARK 1.1 · *bʰeh₂g- [ine-pro]", run_id: run_id
      )
      body = payload(tools(links: journal).call("nabu_links", { "urn" => "urn:d:od:1.1" }))
      cognate = body.dig("kinds", "cognate").first
      assert_equal "MARK 1.1 · *bʰeh₂g- [ine-pro]", cognate["detail"],
                   "the per-edge meet (P16-2) reaches MCP consumers"
      parallel = body.dig("kinds", "parallel").first
      assert_nil parallel["detail"]
    ensure
      journal&.disconnect
    end

    def test_links_excludes_restricted_counterparts_by_default
      seed_parallels
      journal = seed_links_journal
      urns = payload(tools(links: journal).call("nabu_links", { "urn" => "urn:d:od:1.1" }))
             .dig("kinds", "parallel").map { |e| e["urn"] }
      refute_includes urns, "urn:d:secret:1", "the research_private counterpart is excluded by default"

      opened = payload(tools(links: journal)
               .call("nabu_links", { "urn" => "urn:d:od:1.1", "include_restricted" => true }))
      assert_includes opened.dig("kinds", "parallel").map { |e| e["urn"] }, "urn:d:secret:1"
    ensure
      journal&.disconnect
    end

    def test_links_without_a_journal_is_a_graceful_note
      seed_parallels
      result = call("nabu_links", { "urn" => "urn:d:od:1.1" })
      refute result[:isError]
      assert_match(/no links journal.*parallels --batch/im, text_of(result))
    end

    def test_links_unknown_urn_is_a_graceful_note_and_missing_urn_invalid
      seed_parallels
      journal = seed_links_journal
      result = tools(links: journal).call("nabu_links", { "urn" => "urn:d:nope:9" })
      refute result[:isError]
      assert_match(/not found/i, text_of(result))
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { tools(links: journal).call("nabu_links", {}) }
    ensure
      journal&.disconnect
    end

    # -- nabu_etym (P14-1) --------------------------------------------------------

    def seed_recon_shelf(source: nil)
      recon = source || Nabu::Store::Source.create(
        slug: "wiktionary-recon", name: "Wiktionary reconstructions",
        adapter_class: "Nabu::Adapters::WiktionaryRecon",
        license: "CC-BY-SA + GFDL", license_class: "attribution", enabled: true
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: recon)
                                   .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                              workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
    end

    def test_etym_walks_an_attested_lemma_with_counts_and_ancestors
      seed_recon_shelf
      doc = make_document(urn: "urn:nabu:test:chu", title: "Zographensis", language: "chu")
      make_passage(doc, urn: "urn:nabu:test:chu:1", text: "ба", sequence: 0, language: "chu",
                        lemmas: [%w[богъ ба]])
      rebuild!

      entries = payload(call("nabu_etym", { "lemma" => "богъ", "lang" => "chu" })).fetch("entries")
      assert_equal 1, entries.size
      entry = entries.first
      assert_equal "*bogъ", entry.fetch("headword")
      assert_equal "urn:nabu:dict:wiktionary-sla-pro:bogъ:noun:2", entry.fetch("urn")
      assert_equal "attribution", entry.fetch("license_class")
      assert_equal({ "language" => "chu", "word" => "богъ", "roman" => "bogŭ",
                     "borrowed" => false },
                   entry.fetch("matched_via"))
      cognate = entry.fetch("cognates").first
      assert_equal 1, cognate.fetch("attested_count"), "attested cognates sort first"
      assert_operator entry.fetch("cognates_total"), :>, entry.fetch("cognates").size,
                      "the cognate list is bounded with an honest total"
      assert_includes entry.fetch("ancestors").map { |a| a.fetch("headword") }, "*bʰeh₂g-",
                      "one proto-to-proto hop rides along"
    end

    # -- P26-0: the lemma tier mirrors the CLI labels ---------------------------
    # attested_count stays gold-only in every payload; silver rows ride as a
    # separate, labeled silver_count key — never summed, never a bare number.

    def seed_tiered_bog_corpus
      seed_recon_shelf
      gold_doc = make_document(urn: "urn:nabu:test:chu", title: "Zographensis", language: "chu")
      make_passage(gold_doc, urn: "urn:nabu:test:chu:1", text: "ба", sequence: 0, language: "chu",
                             lemmas: [%w[богъ ба]])
      silver_source = Nabu::Store::Source.create(
        slug: "auto", name: "Auto", adapter_class: "TestAdapter", license_class: "open", enabled: true
      )
      silver_doc = make_document(source: silver_source, urn: "urn:nabu:test:auto:chu",
                                 title: "Auto", language: "chu")
      2.times do |i|
        make_passage(silver_doc, urn: "urn:nabu:test:auto:chu:#{i + 1}", text: "богъ",
                                 sequence: i, language: "chu", lemmas: [%w[богъ богъ]])
      end
      silver_orv = make_document(source: silver_source, urn: "urn:nabu:test:auto:orv",
                                 title: "Auto orv", language: "orv")
      3.times do |i|
        make_passage(silver_orv, urn: "urn:nabu:test:auto:orv:#{i + 1}", text: "богъ",
                                 sequence: i, language: "orv", lemmas: [%w[богъ богъ]])
      end
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    lemma_tiers: { "auto" => "silver" })
    end

    def test_etym_payload_serves_gold_attested_count_with_labeled_silver_beside_it
      seed_tiered_bog_corpus
      entries = payload(call("nabu_etym", { "lemma" => "богъ", "lang" => "chu" })).fetch("entries")
      cognates = entries.first.fetch("cognates")
      chu = cognates.find { |c| c["language"] == "chu" && c["word"] == "богъ" }
      assert_equal 1, chu.fetch("attested_count"), "gold-only, never gold+silver summed"
      assert_equal 2, chu.fetch("silver_count"), "the automatic count rides beside it, labeled"
      orv = cognates.find { |c| c["language"] == "orv" && c["word"] == "богъ" }
      assert_nil orv.fetch("attested_count"), "silver-only never claims gold attestation"
      assert_equal 3, orv.fetch("silver_count")
      bare = cognates.find { |c| c["attested_count"].nil? && !c.key?("silver_count") }
      refute_nil bare, "unattested cognates carry NO silver_count key — absence stays honest"
    end

    def test_search_lemma_payload_labels_silver_hits
      seed_tiered_bog_corpus
      matches = payload(call("nabu_search", { "lemma" => "богъ", "lang" => "chu" })).fetch("matches")
      gold_hit = matches.find { |m| m.fetch("urn") == "urn:nabu:test:chu:1" }
      silver_hit = matches.find { |m| m.fetch("urn") == "urn:nabu:test:auto:chu:1" }
      refute_nil gold_hit
      refute_nil silver_hit
      refute gold_hit.key?("tier"), "gold hits stay unlabeled (the CLI mirror)"
      assert_equal "silver", silver_hit.fetch("tier"), "silver hits say so"
    end

    # P17-3: the payload nests the full shelf-visited chain and labels loan
    # edges — прьстъ → *pьrstъ → (nested) *pírštan → (nested) *per-, and
    # хлѣбъ's *hlaibaz ancestor carries edge_borrowed: true.
    def test_etym_payload_nests_the_multi_hop_chain_with_loan_edges
      seed_recon_shelf
      rebuild!
      entries = payload(call("nabu_etym", { "lemma" => "прьстъ" })).fetch("entries")
      pers = entries.find { |e| e.fetch("headword") == "*pьrstъ" } || flunk("*pьrstъ missing")
      pbs = pers.fetch("ancestors").find { |a| a.fetch("headword") == "*pírštan" } ||
            flunk("the PBS intermediate must nest")
      assert_includes pbs.fetch("ancestors").map { |a| a.fetch("headword") }, "*per-",
                      "the chain nests to the PIE root"

      bread = payload(call("nabu_etym", { "lemma" => "хлѣбъ" })).fetch("entries")
      xleb = bread.find { |e| e.fetch("headword") == "*xlěbъ" } || flunk("*xlěbъ missing")
      hlaibaz = xleb.fetch("ancestors").find { |a| a.fetch("headword") == "*hlaibaz" } ||
                flunk("*hlaibaz missing")
      assert_equal true, hlaibaz.fetch("edge_borrowed"), "the loan edge says so in the payload"
    end

    def test_etym_needs_a_lemma
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { call("nabu_etym", {}) }
    end

    def test_etym_no_match_words_the_absence
      seed_recon_shelf
      rebuild!
      result = call("nabu_etym", { "lemma" => "βλαβλα" })
      refute result[:isError]
      assert_empty payload(result).fetch("entries")
      note = payload(result).fetch("note")
      assert_match(/no reconstruction/i, note)
      assert_match(/'\*form'/, note, "the miss note must show the quoted-star syntax")
    end

    # -- P24-2: define/etym coordination ----------------------------------------

    # The starling shelves: piet/germet/baltet crosswalk WITH reflex rows,
    # vasmer prose-only (rus, zero reflex rows) — the incident fixture.
    def seed_starling_shelf
      source = Nabu::Store::Source.create(
        slug: "starling", name: "StarLing IE", adapter_class: "Nabu::Adapters::Starling",
        license: Nabu::Adapters::Starling::MANIFEST.license, license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: source)
                                   .load_from(Nabu::Adapters::Starling.new,
                                              workdir: Nabu::TestSupport.fixtures("starling"))
    end

    # The owner incident (2026-07-16): a crosswalk miss where the
    # dictionary shelf holds the etymology (Vasmer сига́ть,) — nabu_etym
    # mirrors the CLI fallback: define_payload entries under
    # dictionary_entries + an explanatory note, entries honestly empty.
    def test_etym_crosswalk_miss_falls_back_to_define_payload_entries_with_a_note
      seed_starling_shelf
      result = payload(call("nabu_etym", { "lemma" => "сигать" }))
      assert_empty result.fetch("entries"), "no crosswalk path — no etym-shaped hits"
      entries = result.fetch("dictionary_entries")
      assert_equal(["urn:nabu:dict:starling-vasmer:12561"], entries.map { |e| e.fetch("urn") })
      assert_equal "сига́ть,", entries.first.fetch("headword"), "the define payload shape, verbatim"
      assert_match(/Near etymology:/, entries.first.fetch("body"))
      assert_match(/no reconstruction path in the crosswalk/, result.fetch("note"))
    end

    # The genuine total miss enumerates the crosswalk shelves DB-DRIVEN
    # (the P11 DEFINE_LANGS lesson): exactly the languages with reflex
    # rows, never the stale hardcoded proto roll call.
    def test_etym_total_miss_note_enumerates_the_live_crosswalk_shelves
      seed_starling_shelf
      result = payload(call("nabu_etym", { "lemma" => "зззз" }))
      assert_empty result.fetch("entries")
      refute result.key?("dictionary_entries"), "nothing anywhere — no fallback block"
      note = result.fetch("note")
      assert_match(/bat-pro, gem-pro, ine-pro\b/, note, "derived from the live catalog")
      refute_match(%r{Proto-Slavic/PIE/Proto-Germanic}, note, "the hardcoded enumeration is gone")
      assert_match(/'\*form'/, note, "the quoting hint stays")
    end

    def test_etym_fallback_withholds_restricted_dictionary_entries
      source = Nabu::Store::Source.create(
        slug: "starling", name: "StarLing IE", adapter_class: "Nabu::Adapters::Starling",
        license: "grant", license_class: "research_private"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: source)
                                   .load_from(Nabu::Adapters::Starling.new,
                                              workdir: Nabu::TestSupport.fixtures("starling"))
      result = payload(call("nabu_etym", { "lemma" => "сигать" }))
      refute result.key?("dictionary_entries"),
             "a restricted shelf must not leak through the fallback"
      revealed = payload(call("nabu_etym", { "lemma" => "сигать", "include_restricted" => true }))
      assert_equal(["urn:nabu:dict:starling-vasmer:12561"],
                   revealed.fetch("dictionary_entries").map { |e| e.fetch("urn") })
    end

    def test_etym_falls_back_to_a_bare_proto_headword_when_reflexes_miss
      seed_recon_shelf
      rebuild!
      # P14-10: nabu_etym shares Query::Etym's bare-form fallback — a proto
      # form typed directly (asterisk optional), ASCII-folded and
      # hyphen-tolerant, resolves to its reconstruction entry.
      entries = payload(call("nabu_etym", { "lemma" => "gwhew" })).fetch("entries")
      assert_equal 1, entries.size
      assert_equal "*gʷʰew-", entries.first.fetch("headword")
      refute entries.first.key?("matched_via"), "a direct headword hit, no reflex walk"
    end

    def test_etym_withholds_restricted_shelves_by_default
      restricted = Nabu::Store::Source.create(
        slug: "wiktionary-recon", name: "Wiktionary reconstructions",
        adapter_class: "Nabu::Adapters::WiktionaryRecon",
        license: "CC-BY-SA + GFDL", license_class: "research_private", enabled: true
      )
      seed_recon_shelf(source: restricted)
      rebuild!
      assert_empty payload(call("nabu_etym", { "lemma" => "*bogъ" })).fetch("entries")
      revealed = payload(call("nabu_etym", { "lemma" => "*bogъ", "include_restricted" => true }))
      refute_empty revealed.fetch("entries")
    end

    def test_etym_without_the_crosswalk_migration_degrades_gracefully
      bare = Nabu::Store.connect("sqlite::memory:")
      result = tools(catalog: bare, fulltext: @fulltext).call("nabu_etym", { "lemma" => "богъ" })
      refute result[:isError]
      assert_match(/reconstruction shelf/i, text_of(result))
    ensure
      bare&.disconnect
    end

    def test_define_carries_reflexes_on_reconstruction_entries
      seed_recon_shelf
      entries = payload(call("nabu_define", { "lemma" => "*bogъ", "lang" => "sla-pro" })).fetch("entries")
      refute_empty entries
      entry = entries.find { |e| e.fetch("urn").end_with?("bogъ:noun:2") }
      assert_equal "*bogъ", entry.fetch("headword")
      refute_empty entry.fetch("reflexes")
      assert_kind_of Integer, entry.fetch("reflexes_total")
    end

    # P18-3: the MCP payloads ride the DEDUPED ReflexViews (never raw
    # crosswalk rows) — a duplicate reflex row (multi-subtree descent, the
    # prīmus ×3 defect) appears once in both nabu_etym cognates and
    # nabu_define reflexes.
    def test_etym_and_define_payloads_ride_the_deduped_reflex_views
      seed_recon_shelf
      entry_row_id = @catalog[:dictionary_entries]
                     .where(urn: "urn:nabu:dict:wiktionary-sla-pro:bogъ:noun:2").get(:id)
      chu_row = @catalog[:dictionary_reflexes]
                .where(dictionary_entry_id: entry_row_id, language: "chu", word: "богъ").first
      dupe = chu_row.dup
      dupe.delete(:id)
      dupe[:seq] = 9_999
      @catalog[:dictionary_reflexes].insert(dupe)
      # Attest chu богъ so it sorts into the bounded cognate page.
      doc = make_document(urn: "urn:nabu:test:chu", title: "Zographensis", language: "chu")
      make_passage(doc, urn: "urn:nabu:test:chu:1", text: "ба", sequence: 0, language: "chu",
                        lemmas: [%w[богъ ба]])
      rebuild!

      etym_entries = payload(call("nabu_etym", { "lemma" => "*bogъ" })).fetch("entries")
      entry = etym_entries.find { |e| e.fetch("urn").end_with?("bogъ:noun:2") }
      chu = entry.fetch("cognates").select { |c| c["language"] == "chu" && c["word"] == "богъ" }
      assert_equal 1, chu.size, "nabu_etym serves the grouped view, one row per word"

      define_entries = payload(call("nabu_define", { "lemma" => "*bogъ", "lang" => "sla-pro" }))
                       .fetch("entries")
      reflexes = define_entries.find { |e| e.fetch("urn").end_with?("bogъ:noun:2") }
                               .fetch("reflexes")
                               .select { |c| c["language"] == "chu" && c["word"] == "богъ" }
      assert_equal 1, reflexes.size, "nabu_define serves the same grouped view"
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

    # -- nabu_align collate (P15-4) ---------------------------------------------

    COLLATE_REGISTRY_YAML = <<~YAML
      nt:
        title: "New Testament (parallel witnesses)"
        witnesses:
          - { document: urn:nabu:proiel:marianus, label: marianus }
          - { document: urn:nabu:ccmh:assemanianus, label: ccmh-assemanianus }
          - { document: urn:nabu:ccmh:marianus, label: ccmh-marianus }
    YAML

    # A chu corpus with the Cyrillic PROIEL Marianus + two Helsinki-ASCII CCMH
    # codices, so a chu/Latin cell collates and the Cyrillic witness is aside.
    def seed_collation_corpus(source: nil)
      source ||= Nabu::Store::Source.create(
        slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter", license_class: "nc", enabled: true
      )
      [["urn:nabu:proiel:marianus", "Ꙇ придѫ къ немоу носѧште ослабленъ жилами", source],
       ["urn:nabu:ccmh:assemanianus", "*/i pridO k$ nemu nosEqe /oslablena ZIlamI", @open],
       ["urn:nabu:ccmh:marianus", "*J pridO k& nemu nosESte oslablen& Zilami", @open]].each do |urn, text, src|
        doc = make_document(source: src, urn: urn, title: urn.split(":").last, language: "chu")
        make_passage(doc, urn: "#{doc.urn}:1", text: text, sequence: 0, language: "chu",
                          tokens: [{ "citation_part" => "MARK 2.3", "form" => "x" }])
      end
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    alignments: align_registry(COLLATE_REGISTRY_YAML))
    end

    def test_collate_returns_an_apparatus_with_a_cross_script_aside
      seed_collation_corpus
      body = payload(align_tools(align_registry(COLLATE_REGISTRY_YAML))
                     .call("nabu_align", { "ref" => "MARK 2.3", "collate" => true }))

      assert_equal "collation", body.fetch("type")
      ref = body.fetch("refs").first
      cell = ref.fetch("cells").find { |candidate| candidate.fetch("script") == "Latin" }
      assert_equal "ccmh-assemanianus", cell.fetch("base"), "base is first in registry order"
      variant = cell.fetch("witnesses").find { |witness| witness.fetch("label") == "ccmh-marianus" }
      assert_equal false, variant.fetch("agrees")
      ops = variant.fetch("edits").map { |edit| edit.fetch("op") }
      assert_includes ops, "sub", "the real CCMH divergence is a substitution"

      aside = ref.fetch("asides").find { |candidate| candidate.fetch("label") == "marianus" }
      assert_equal "Cyrillic", aside.fetch("script")
      assert_equal "cross_script", aside.fetch("reason")
      assert_match(/придѫ/, aside.fetch("text"))
    end

    def test_collate_withholds_restricted_witnesses_from_the_diff
      restricted = Nabu::Store::Source.create(
        slug: "closed", name: "Closed", adapter_class: "TestAdapter", license_class: "restricted", enabled: true
      )
      seed_collation_corpus(source: restricted) # the Cyrillic marianus is now restricted
      tools = align_tools(align_registry(COLLATE_REGISTRY_YAML))

      body = payload(tools.call("nabu_align", { "ref" => "MARK 2.3", "collate" => true }))
      refute_match(/придѫ/, text_of(tools.call("nabu_align", { "ref" => "MARK 2.3", "collate" => true })),
                   "restricted witness text must not leak into the apparatus")
      withheld = body.fetch("refs").first.fetch("missing").find { |missing| missing.fetch("label") == "marianus" }
      assert_equal "withheld", withheld.fetch("status")

      opted = payload(tools.call("nabu_align",
                                 { "ref" => "MARK 2.3", "collate" => true, "include_restricted" => true }))
      labels = opted.fetch("refs").first.fetch("asides").map { |aside| aside.fetch("label") }
      assert_includes labels, "marianus", "include_restricted brings the withheld witness back"
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

    # -- nabu_cognates (P15-3) ----------------------------------------------------

    COGNATES_REGISTRY_YAML = <<~YAML
      nt:
        title: "New Testament (test witnesses)"
        witnesses:
          - document: urn:nabu:test:grc-nt
          - document: urn:nabu:test:marianus
          - document: urn:nabu:test:oe-mark
    YAML

    # The real recon shelf + three witnesses with gold lemmas in citation-
    # bearing tokens: MARK 1.1 meets grc ἔφᾰγον × chu богъ at PIE *bʰeh₂g-,
    # MARK 2.1 meets ang cāsere × chu цѣсар҄ь at gem-pro *kaisaraz (a loan).
    def seed_cognates_corpus(marianus_override: nil)
      recon = Nabu::Store::Source.create(
        slug: "wiktionary-recon", name: "Wiktionary reconstructions", license: "CC-BY-SA + GFDL",
        adapter_class: "Nabu::Adapters::WiktionaryRecon", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: recon)
                                   .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                              workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
      nc = Nabu::Store::Source.create(
        slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter",
        license_class: "nc", enabled: true
      )
      [["grc-nt", "grc", nil, [["MARK 1.1", "ἔφᾰγον", "ἔφαγεν"]]],
       ["marianus", "chu", marianus_override,
        [["MARK 1.1", "богъ", "ба"], ["MARK 2.1", "цѣсар҄ь", "цѣсар҄ь"]]],
       ["oe-mark", "ang", nil, [["MARK 2.1", "cāsere", "cāsere"]]]].each do |tail, lang, override, rows|
        doc = make_document(source: nc, urn: "urn:nabu:test:#{tail}", title: tail,
                            language: lang, license_override: override)
        rows.each_with_index do |(ref, lemma, form), seq|
          Nabu::Store::Passage.create(
            document_id: doc.id, urn: "#{doc.urn}:#{seq + 1}", sequence: seq, language: lang,
            text: form, text_normalized: form, content_sha256: "x", revision: 1,
            annotations_json: JSON.generate(
              "citation" => ref,
              "tokens" => [{ "citation_part" => ref, "lemma" => lemma, "form" => form }]
            )
          )
        end
      end
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    alignments: cognates_registry)
    end

    def cognates_registry
      align_registry(COGNATES_REGISTRY_YAML)
    end

    def cognates_tools
      Nabu::MCP::Tools.new(catalog: @catalog, fulltext: @fulltext, alignments: cognates_registry)
    end

    def test_cognates_groups_carry_the_root_shelf_and_witness_licenses
      seed_cognates_corpus
      result = cognates_tools.call("nabu_cognates", { "target" => "MARK 1.1" })

      refute result[:isError]
      body = payload(result)
      assert_equal "nt", body.fetch("work")
      assert_equal 1, body.fetch("total")
      group = body.fetch("groups").first
      assert_equal "MARK 1.1", group.fetch("ref")
      root = group.fetch("root")
      assert_equal "*bʰeh₂g-", root.fetch("headword")
      assert_equal "ine-pro", root.fetch("shelf")
      assert_equal "attribution", root.fetch("license_class")
      assert_equal "CC-BY-SA + GFDL", root.fetch("license")
      witnesses = group.fetch("witnesses")
      assert_equal(%w[chu grc], witnesses.map { |witness| witness.fetch("language") })
      witnesses.each do |witness|
        # P17-3: the per-edge loan flag rides every witness word — both
        # *bʰeh₂g- descents parsed unflagged, an honest false (null would
        # mean "predates the flag reparse").
        assert_equal false, witness.fetch("borrowed")
        witness.fetch("documents").each do |doc|
          assert_equal "nc", doc.fetch("license_class")
          assert_equal "proiel", doc.fetch("source")
        end
      end
    end

    def test_cognates_notes_the_borrowing_caveat_and_is_bounded
      seed_cognates_corpus
      body = payload(cognates_tools.call("nabu_cognates", { "target" => "nt", "limit" => 1 }))

      assert_equal 2, body.fetch("total")
      assert_equal 1, body.fetch("groups").size
      assert_match(/showing 1/, body.fetch("note"))
      assert_match(/borrowing/, body.fetch("note"))
    end

    # P18-3: nabu_cognates rides the hash-keyed Query::Cognates join — a
    # forced duplicate closure row still yields one group with one witness
    # word per language in the payload.
    def test_cognates_payload_rides_the_deduped_join
      seed_cognates_corpus
      table = @fulltext[Nabu::Store::ReflexRootsIndexer::TABLE]
      row = table.where(language: "chu", lemma_folded: "богъ",
                        root_urn: "urn:nabu:dict:wiktionary-ine-pro:bʰeh₂g-:root").first
      refute_nil row, "the closure must hold the chu богъ → *bʰeh₂g- row"
      table.insert(row)

      body = payload(cognates_tools.call("nabu_cognates", { "target" => "MARK 1.1" }))
      assert_equal 1, body.fetch("total"), "one (verse, root) group, not one per closure row"
      witnesses = body.fetch("groups").first.fetch("witnesses")
      assert_equal(%w[chu grc], witnesses.map { |w| w.fetch("language") },
                   "one witness word per language, the duplicate row invisible")
    end

    def test_cognates_langs_restricts_the_pair
      seed_cognates_corpus
      body = payload(cognates_tools.call("nabu_cognates",
                                         { "target" => "nt", "langs" => %w[ang chu] }))
      assert_equal(["*kaisaraz"], body.fetch("groups").map { |g| g.fetch("root").fetch("headword") })
    end

    def test_cognates_withholds_restricted_witnesses_by_default
      seed_cognates_corpus(marianus_override: "research_private")
      body = payload(cognates_tools.call("nabu_cognates", { "target" => "nt" }))
      assert_equal 0, body.fetch("total"),
                   "every meet involves the now-private chu witness — nothing may leak"

      shown = payload(cognates_tools.call("nabu_cognates",
                                          { "target" => "nt", "include_restricted" => true }))
      assert_equal 2, shown.fetch("total")
    end

    def test_cognates_needs_a_target
      assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        cognates_tools.call("nabu_cognates", {})
      end
    end

    def test_cognates_unattested_ref_is_a_tool_error
      seed_cognates_corpus
      result = cognates_tools.call("nabu_cognates", { "target" => "JOHN 99.1" })
      assert result[:isError]
      assert_match(/not attested/, text_of(result))
    end

    def test_cognates_without_a_registry_notes_how_to_register
      result = tools.call("nabu_cognates", { "target" => "nt" })
      refute result[:isError]
      assert_match(/alignments\.yml/, text_of(result))
    end

    def test_cognates_with_a_missing_roots_table_degrades_gracefully
      seed_cognates_corpus
      @fulltext.drop_table(Nabu::Store::ReflexRootsIndexer::TABLE)
      result = cognates_tools.call("nabu_cognates", { "target" => "MARK 1.1" })
      refute result[:isError], "a missing derived table is a state, not a fault"
      assert_match(/rebuild/, text_of(result))
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

    def test_show_resolves_a_dictionary_entry_urn_to_the_define_payload
      dict_id = @catalog[:dictionaries].insert(source_id: @open.id, slug: "lsj",
                                               title: "LSJ", language: "grc")
      @catalog[:dictionary_entries].insert(
        dictionary_id: dict_id, urn: "urn:nabu:dict:lsj:n1", entry_id: "n1",
        key_raw: "μῆνις", headword: "μῆνις", headword_folded: "μηνις",
        gloss: "wrath", body: "μῆνις body", content_sha256: "x", revision: 1, withdrawn: false
      )
      urn = "urn:nabu:dict:lsj:n1"
      result = call("nabu_show", { "urn" => urn })
      body = payload(result)
      entry = body.key?("entries") ? body.fetch("entries").first : body
      assert_equal urn, entry.fetch("urn")
      assert entry.fetch("headword")
    end
  end
end
