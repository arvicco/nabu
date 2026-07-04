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
  end
end
