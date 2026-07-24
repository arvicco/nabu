# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Show (P4-3). Catalog is a fresh in-memory SQLite (the house
  # store-test pattern). Provenance-bearing rows are seeded through the real
  # Loader so the "loaded" journal events exist exactly as production writes
  # them; withdrawn rows are created directly to prove show reveals them.
  class ShowTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "src", name: "Source", adapter_class: "TestAdapter", license_class: "open"
      )
      @loader = Nabu::Store::Loader.new(db: @catalog, source: @source)
    end

    # -- helpers -------------------------------------------------------------

    def load_document(slug, passages, title: "Iliad")
      document = Nabu::Document.new(
        urn: "urn:d:#{slug}", language: "grc", title: title,
        canonical_path: "/canonical/src/#{slug}.txt"
      )
      passages.each_with_index do |(suffix, text), index|
        document << Nabu::Passage.new(
          urn: "urn:d:#{slug}:#{suffix}", language: "grc",
          text: text, text_normalized: text.downcase, sequence: index
        )
      end
      @loader.load([document], full: false)
    end

    def show(urn)
      Nabu::Query::Show.new(catalog: @catalog).run(urn)
    end

    # -- passage -------------------------------------------------------------

    def test_passage_urn_returns_passage_detail_with_provenance
      load_document("1", [%w[1 μῆνιν], %w[2 ἄειδε]])

      result = show("urn:d:1:1")
      assert_kind_of Nabu::Query::Show::PassageResult, result
      assert_equal "urn:d:1:1", result.urn
      assert_equal "grc", result.language
      assert_equal 0, result.sequence
      assert_equal 1, result.revision
      refute result.withdrawn
      assert_equal "μῆνιν", result.text
      assert_equal "urn:d:1", result.document_urn
      assert_equal "Iliad", result.document_title
      assert_equal "src", result.source_slug
      assert_equal "open", result.license_class

      events = result.provenance.map(&:event)
      assert_includes events, "loaded", "the loader's provenance is surfaced"
      assert(result.provenance.all?(Nabu::Query::Show::ProvenanceEvent))
    end

    # H9 (P35-6): a corrupt annotations_json row must not silently drop the
    # annotation lane — the parse failure is MARKED so renderers can say so
    # (skip-with-note over silent skip; the passage text itself still serves).
    def test_unreadable_annotations_json_is_marked_not_silently_dropped
      load_document("1", [%w[1 μῆνιν]])
      Nabu::Store::Passage.first(urn: "urn:d:1:1").update(annotations_json: "{not json")

      result = show("urn:d:1:1")
      assert_equal({ Nabu::Query::Show::ANNOTATIONS_UNREADABLE => true }, result.annotations)

      line = show("urn:d:1").passages.first
      assert_equal({ Nabu::Query::Show::ANNOTATIONS_UNREADABLE => true }, line.annotations,
                   "document-grain lines carry the marker too")
    end

    def test_provenance_is_chronological
      load_document("1", [%w[1 μῆνιν]])
      passage = Nabu::Store::Passage.first(urn: "urn:d:1:1")
      Nabu::Store::Provenance.create(
        event: "enriched", passage_id: passage.id, tool: "later", at: Time.now + 60
      )

      events = show("urn:d:1:1").provenance
      assert_equal %w[loaded enriched], events.map(&:event)
    end

    # -- document ------------------------------------------------------------

    def test_document_urn_returns_header_and_ordered_passages
      load_document("1", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεά]])

      result = show("urn:d:1")
      assert_kind_of Nabu::Query::Show::DocumentResult, result
      assert_equal "urn:d:1", result.urn
      assert_equal "Iliad", result.title
      assert_equal "grc", result.language
      assert_equal "src", result.source_slug
      assert_equal "open", result.license_class
      refute result.withdrawn
      refute result.retired_upstream
      assert_equal %w[urn:d:1:1 urn:d:1:2 urn:d:1:3], result.passages.map(&:urn)
      assert_equal %w[μῆνιν ἄειδε θεά], result.passages.map(&:text)
    end

    # A retired document (upstream scrapped it; the attic kept it — P5-2) is
    # shown live, honestly labeled.
    def test_retired_document_is_shown_and_flagged
      load_document("1", [%w[1 μῆνιν]])
      Nabu::Store::Document.first(urn: "urn:d:1").update(retired_upstream: true)

      result = show("urn:d:1")
      assert result.retired_upstream
      refute result.withdrawn, "retired is not withdrawn"
    end

    # -- the findspot line (P44-2: places as the third dimension) ------------

    PLEIADES_DUMP = File.join(Nabu::TestSupport.fixtures("pleiades"), "dump.json")

    def load_placed_document(slug, pleiades_id)
      document = Nabu::Document.new(
        urn: "urn:d:#{slug}", language: "grc", title: "Stone",
        canonical_path: "/canonical/src/#{slug}.xml",
        metadata: { "place" => { "ancient" => "Sparta", "pleiades" => pleiades_id }.compact }
      )
      document << Nabu::Passage.new(
        urn: "urn:d:#{slug}:1", language: "grc", text: "χαῖρε",
        text_normalized: "χαιρε", sequence: 0
      )
      @loader.load([document], full: false)
    end

    def test_findspot_resolves_the_captured_pleiades_id_through_the_dump
      load_placed_document("p1", "570685")
      show = Nabu::Query::Show.new(catalog: @catalog, pleiades: Nabu::Pleiades.load(PLEIADES_DUMP))

      document = show.run("urn:d:p1")
      refute_nil document.findspot
      assert_equal "570685", document.findspot.id
      assert_equal "Sparta", document.findspot.title
      assert_equal %w[settlement temple temple-2 archaeological-site], document.findspot.place_types

      passage = show.run("urn:d:p1:1")
      assert_equal "Sparta", passage.findspot.title, "passage grain resolves through its document"
    end

    def test_findspot_is_nil_without_a_resolver_the_degrade_silently_contract
      load_placed_document("p1", "570685")
      result = Nabu::Query::Show.new(catalog: @catalog).run("urn:d:p1")
      assert_nil result.findspot, "no dump on disk → byte-identical output (the LiLa precedent)"
    end

    def test_findspot_is_nil_when_no_id_was_captured_or_the_dump_lacks_the_place
      load_placed_document("p1", nil)
      load_placed_document("p2", "999999")
      show = Nabu::Query::Show.new(catalog: @catalog, pleiades: Nabu::Pleiades.load(PLEIADES_DUMP))
      assert_nil show.run("urn:d:p1").findspot, "no captured id → nothing to resolve"
      assert_nil show.run("urn:d:p2").findspot, "an id the dump lacks stays silent, never invented"
    end

    # -- edges ---------------------------------------------------------------

    def test_unknown_urn_returns_nil
      load_document("1", [%w[1 μῆνιν]])
      assert_nil show("urn:d:nope")
    end

    # -- credit (P43-2) ------------------------------------------------------

    # The generic per-source credit line reaches every show grain (passage,
    # document, range) — the CLI card and MCP payload render from these results.
    CREDIT = "TITUS (J. Gippert, Frankfurt) — Avesta ed. Geldner/Westergaard, corr. Gippert et al."

    def load_credited_document
      source = Nabu::Store::Source.create(
        slug: "titus", name: "TITUS", adapter_class: "TestAdapter",
        license_class: "nc", credit: CREDIT
      )
      loader = Nabu::Store::Loader.new(db: @catalog, source: source)
      document = Nabu::Document.new(urn: "urn:t:1", language: "ave", title: "Avesta",
                                    canonical_path: "/canonical/titus/1.htm")
      [%w[a frauuarāne], %w[b hāuuanə̄e], %w[c yasnāica]].each_with_index do |(suffix, text), index|
        document << Nabu::Passage.new(urn: "urn:t:1:#{suffix}", language: "ave", text: text, sequence: index)
      end
      loader.load([document], full: false)
    end

    def test_credit_reaches_passage_document_and_range_results
      load_credited_document

      assert_equal CREDIT, show("urn:t:1:a").credit, "passage card carries the source credit"
      assert_equal CREDIT, show("urn:t:1").credit, "document card carries it"
      assert_equal CREDIT, show("urn:t:1:a-b").credit, "a range carries it too"
    end

    def test_credit_is_nil_for_an_ordinary_uncredited_source
      load_document("1", [%w[1 μῆνιν], %w[2 ἄειδε]])

      assert_nil show("urn:d:1:1").credit
      assert_nil show("urn:d:1").credit
    end

    # -- ranges (P7-6) -------------------------------------------------------
    # A range urn = a document urn + `:<start-suffix>-<end-suffix>`: an
    # inclusive, sequence-ordered slice of ONE document between two resolved
    # citation suffixes. Split rule: literal passage/document FIRST (a real
    # urn is never misparsed as a range), then split on the LAST hyphen.

    # P44 (owner test-drive friction): a CITATION PREFIX between document and
    # passage grain — show urn:…:avest020:Y.19.1 when passages are Y.19.1.a,
    # Y.19.1.b — must list everything below it, boundary-exact (Y.19.1 never
    # swallows Y.19.10), and render through the existing RangeResult shape.
    def test_citation_prefix_lists_the_passages_below_it
      load_document("av", [["Y.19.1.a", "pərəsat̰"], ["Y.19.1.b", "zaraϑuštrō"],
                           ["Y.19.10.a", "ahurəm"], ["Y.19.2.a", "mazdąm"]])

      result = show("urn:d:av:Y.19.1")
      assert_instance_of Nabu::Query::Show::RangeResult, result
      assert_equal %w[urn:d:av:Y.19.1.a urn:d:av:Y.19.1.b],
                   result.passages.map(&:urn),
                   "the prefix opens into exactly its own children — Y.19.10 stays out"
      assert_equal 4, result.total, "the [N of M] note carries the document total"
    end

    def test_citation_prefix_is_literal_first_but_reaches_occurrence_tails
      load_document("rep", [["Y.0.13.Q1c", "first"], ["Y.0.13.Q1c#2", "second"]])

      exact = show("urn:d:rep:Y.0.13.Q1c")
      assert_instance_of Nabu::Query::Show::PassageResult, exact,
                         "an exact passage urn stays literal-first — the class doctrine"

      prefix = show("urn:d:rep:Y.0.13")
      assert_equal ["urn:d:rep:Y.0.13.Q1c", "urn:d:rep:Y.0.13.Q1c#2"],
                   prefix.passages.map(&:urn),
                   "the prefix one level up lists both recitations, # tail included"
    end

    def test_citation_prefix_with_no_children_is_still_urn_not_found
      load_document("z", [["1.1", "text"]])
      assert_nil show("urn:d:z:9.9")
    end

    def test_range_returns_inclusive_sequence_ordered_slice
      load_document("1", [%w[1 α], %w[2 β], %w[3 γ], %w[4 δ], %w[5 ε]])

      result = show("urn:d:1:1-3")
      assert_kind_of Nabu::Query::Show::RangeResult, result
      assert_equal "urn:d:1", result.urn, "the range header is the document"
      assert_equal "Iliad", result.title
      assert_equal "grc", result.language
      assert_equal "src", result.source_slug
      assert_equal %w[urn:d:1:1 urn:d:1:2 urn:d:1:3], result.passages.map(&:urn)
      assert_equal %w[α β γ], result.passages.map(&:text)
      assert_equal 3, result.passages.size
      assert_equal 5, result.total, "the honest [N of M] note counts the whole document"
      assert_equal "urn:d:1:1", result.start_urn
      assert_equal "urn:d:1:3", result.end_urn
    end

    def test_range_endpoints_are_inclusive
      load_document("1", [%w[1 α], %w[2 β], %w[3 γ]])
      assert_equal %w[urn:d:1:2 urn:d:1:3], show("urn:d:1:2-3").passages.map(&:urn)
    end

    def test_single_passage_range_returns_exactly_that_passage
      load_document("1", [%w[1 α], %w[2 β], %w[3 γ]])
      result = show("urn:d:1:2-2")
      assert_equal %w[urn:d:1:2], result.passages.map(&:urn)
      assert_equal 1, result.passages.size
    end

    # The slice is by STORED SEQUENCE, whatever citation shapes lie between —
    # a papyri restart block (P5-1) crossed by the range is sliced through.
    def test_range_slices_across_a_papyri_restart_block
      load_document("p", [%w[1 first], ["b2:1", "restart"], ["b2:2", "next"], ["b3:11", "tail"]])

      result = show("urn:d:p:1-b2:2")
      assert_equal %w[urn:d:p:1 urn:d:p:b2:1 urn:d:p:b2:2], result.passages.map(&:urn)
      assert_equal "urn:d:p:b2:2", result.end_urn
    end

    def test_range_end_not_found_names_the_endpoint
      load_document("1", [%w[1 α], %w[2 β]])
      error = assert_raises(Nabu::Query::Range::Error) { show("urn:d:1:1-99") }
      assert_match(/range end not found/i, error.message)
      assert_match(/urn:d:1:99/, error.message, "the error names the failing endpoint")
    end

    def test_range_start_not_found_names_the_endpoint
      load_document("1", [%w[1 α], %w[2 β]])
      error = assert_raises(Nabu::Query::Range::Error) { show("urn:d:1:9-2") }
      assert_match(/range start not found/i, error.message)
      assert_match(/urn:d:1:9/, error.message)
    end

    def test_reversed_range_errors_and_suggests_swapping
      load_document("1", [%w[1 α], %w[2 β], %w[3 γ]])
      error = assert_raises(Nabu::Query::Range::Error) { show("urn:d:1:3-1") }
      assert_match(/reversed/i, error.message)
      assert_match(/swap/i, error.message)
    end

    # Literal-first precedence: a passage urn that CONTAINS a hyphen resolves
    # to that passage, never a range (existing reachability preserved).
    def test_literal_passage_urn_with_a_hyphen_is_never_parsed_as_a_range
      load_document("1", [%w[a-b hyphenated], %w[2 β]])
      result = show("urn:d:1:a-b")
      assert_kind_of Nabu::Query::Show::PassageResult, result
      assert_equal "urn:d:1:a-b", result.urn
      assert_equal "hyphenated", result.text
    end

    def test_non_range_unknown_urn_is_still_nil
      load_document("1", [%w[1 α]])
      assert_nil show("urn:d:1:nope"), "no hyphen, unknown → nil (urn not found)"
    end

    # Show is an inspection tool, not a corpus view: a withdrawn passage IS
    # returned, honestly flagged (unlike Search/Export, which hide it).
    def test_withdrawn_passage_is_shown_and_flagged
      document = Nabu::Store::Document.create(
        source_id: @source.id, urn: "urn:d:1", title: "Iliad", language: "grc",
        content_sha256: "x", revision: 1, withdrawn: false
      )
      Nabu::Store::Passage.create(
        document_id: document.id, urn: "urn:d:1:1", sequence: 0, language: "grc",
        text: "μῆνιν", text_normalized: "μηνιν", content_sha256: "x",
        revision: 1, withdrawn: true
      )

      result = show("urn:d:1:1")
      assert_kind_of Nabu::Query::Show::PassageResult, result
      assert result.withdrawn, "withdrawn passage is shown, flagged withdrawn"
    end

    # -- the timeline (P15-2) -----------------------------------------

    def test_document_carries_its_timeline_when_present
      load_document("1", [%w[1 μῆνιν]])
      doc = @catalog[:documents].where(urn: "urn:d:1").first
      @catalog[:document_axes].insert(
        document_id: doc.fetch(:id), not_before: -113, not_after: -113,
        precision: "exact", date_raw: "26. Aug. 113 v.Chr.",
        place_name: "Pathyris", place_ref: "https://pleiades.stoa.org/places/786084", axis_source: "hgv"
      )

      timeline = show("urn:d:1").timeline
      refute_nil timeline
      assert_equal(-113, timeline.not_before)
      assert_equal "Pathyris", timeline.place_name
      # A passage of the same document reports the document's timeline too.
      assert_equal(-113, show("urn:d:1:1").timeline.not_before)
    end

    def test_undated_document_has_nil_timeline
      load_document("2", [%w[1 ἄειδε]])
      assert_nil show("urn:d:2").timeline
      assert_nil show("urn:d:2:1").timeline
    end

    # -- facets (P17-2) --------------------------------------------------------

    def test_document_carries_its_facets_when_present
      load_document("1", [%w[1 μῆνιν]])
      doc = @catalog[:documents].where(urn: "urn:d:1").first
      @catalog[:document_facets].insert(document_id: doc.fetch(:id), facet: "genre",
                                        value: "epitaph", raw: "titsep?")
      @catalog[:document_facets].insert(document_id: doc.fetch(:id), facet: "province",
                                        value: "Germania inferior", raw: "GeI")

      facets = show("urn:d:1").facets
      assert_equal %w[genre province], facets.map(&:facet)
      assert_equal "epitaph", facets.first.value
      assert_equal "titsep?", facets.first.raw, "the certainty rider stays visible"
    end

    def test_unfaceted_document_has_empty_facets
      load_document("2", [%w[1 ἄειδε]])
      assert_empty show("urn:d:2").facets
    end

    # -- dictionary-entry urns (P22-2) ----------------------------------------

    def test_show_routes_dictionary_entry_urns_to_the_define_result
      dict_id = @catalog[:dictionaries].insert(source_id: @source.id, slug: "lsj",
                                               title: "LSJ", language: "grc")
      @catalog[:dictionary_entries].insert(
        dictionary_id: dict_id, urn: "urn:nabu:dict:lsj:n1", entry_id: "n1",
        key_raw: "μῆνις", headword: "μῆνις", headword_folded: "μηνις",
        gloss: "wrath", body: "μῆνις body", content_sha256: "x", revision: 1, withdrawn: false
      )
      result = Nabu::Query::Show.new(catalog: @catalog).run("urn:nabu:dict:lsj:n1")
      assert_instance_of Nabu::Query::Define::Result, result
      assert_equal "μῆνις", result.headword
      assert_nil Nabu::Query::Show.new(catalog: @catalog).run("urn:nabu:dict:lsj:missing")
    end

    # -- meter enrichment (P44-7) ---------------------------------------------
    # The consumer seam: a passage carrying a pedecerto scansion reports it; an
    # ordinary passage reports nil (the CLI's meter line is absent byte-for-byte).

    def attach_meter(urn, meter:, pattern:)
      passage = Nabu::Store::Passage.first(urn: urn)
      @catalog[:enrichments].insert(
        passage_id: passage.id, kind: "meter", model: "pedecerto",
        model_version: "pedecerto-scansions/1", at: Time.now,
        payload_json: JSON.generate("meter" => meter, "pattern" => pattern, "words" => [])
      )
    end

    def test_passage_with_a_meter_enrichment_reports_it
      load_document("1", [%w[1 μῆνιν]])
      attach_meter("urn:d:1:1", meter: "H", pattern: "DSDS")

      meter = show("urn:d:1:1").meter
      refute_nil meter
      assert_equal "H", meter.meter
      assert_equal "DSDS", meter.pattern
      assert_equal "pedecerto", meter.producer
    end

    def test_passage_without_a_meter_enrichment_reports_nil
      load_document("1", [%w[1 μῆνιν]])
      assert_nil show("urn:d:1:1").meter, "an unscanned passage carries no meter"
    end
  end
end
