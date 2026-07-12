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

    # -- edges ---------------------------------------------------------------

    def test_unknown_urn_returns_nil
      load_document("1", [%w[1 μῆνιν]])
      assert_nil show("urn:d:nope")
    end

    # -- ranges (P7-6) -------------------------------------------------------
    # A range urn = a document urn + `:<start-suffix>-<end-suffix>`: an
    # inclusive, sequence-ordered slice of ONE document between two resolved
    # citation suffixes. Split rule: literal passage/document FIRST (a real
    # urn is never misparsed as a range), then split on the LAST hyphen.

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

    # -- the date/place axis (P15-2) -----------------------------------------

    def test_document_carries_its_axis_when_present
      load_document("1", [%w[1 μῆνιν]])
      doc = @catalog[:documents].where(urn: "urn:d:1").first
      @catalog[:document_axes].insert(
        document_id: doc.fetch(:id), not_before: -113, not_after: -113,
        precision: "exact", date_raw: "26. Aug. 113 v.Chr.",
        place_name: "Pathyris", place_ref: "https://pleiades.stoa.org/places/786084", axis_source: "hgv"
      )

      axis = show("urn:d:1").axis
      refute_nil axis
      assert_equal(-113, axis.not_before)
      assert_equal "Pathyris", axis.place_name
      # A passage of the same document reports the document's axis too.
      assert_equal(-113, show("urn:d:1:1").axis.not_before)
    end

    def test_undated_document_has_nil_axis
      load_document("2", [%w[1 ἄειδε]])
      assert_nil show("urn:d:2").axis
      assert_nil show("urn:d:2:1").axis
    end
  end
end
