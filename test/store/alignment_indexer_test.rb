# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Store
  # Nabu::Store::AlignmentIndexer (P11-3, architecture §10): the derived
  # citation-ref index behind the alignment hub. Same rig as IndexerTest —
  # fresh in-memory catalog, separate in-memory fulltext connection held open
  # for the test's lifetime.
  class AlignmentIndexerTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @source = Nabu::Store::Source.create(
        slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter", license_class: "nc"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- helpers ---------------------------------------------------------------

    def registry(yaml)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "alignments.yml")
        File.write(path, yaml)
        return Nabu::AlignmentRegistry.load(path)
      end
    end

    NT_REGISTRY = <<~YAML
      nt:
        witnesses:
          - document: urn:nabu:proiel:greek-nt
          - document: urn:nabu:proiel:marianus
    YAML

    def make_document(urn:, withdrawn: false)
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: "t", language: "grc",
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    # The stored PROIEL sentence shape (verified against the live catalog):
    # tokens carry per-verse "citation_part"; the passage-level "citation" is
    # the first token's part only, so extraction reads the TOKENS.
    def make_sentence(document, urn:, sequence:, parts:, withdrawn: false)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: "grc",
        text: "t", text_normalized: "t", content_sha256: "x", revision: 1,
        withdrawn: withdrawn,
        annotations_json: JSON.generate(
          "citation" => parts.first,
          "tokens" => parts.map { |part| { "citation_part" => part, "form" => "x", "lemma" => "x" } }
        )
      )
    end

    def rebuild!(reg = registry(NT_REGISTRY))
      Nabu::Store::AlignmentIndexer.rebuild!(catalog: @catalog, fulltext: @fulltext, registry: reg)
    end

    def refs = @fulltext[Nabu::Store::AlignmentIndexer::TABLE]

    # -- tests -------------------------------------------------------------------

    def test_indexes_one_row_per_passage_and_distinct_ref
      doc = make_document(urn: "urn:nabu:proiel:greek-nt")
      make_sentence(doc, urn: "urn:nabu:proiel:greek-nt:1", sequence: 0, parts: ["MARK 2.3"])
      # A sentence spanning a verse boundary: one row per verse covered.
      make_sentence(doc, urn: "urn:nabu:proiel:greek-nt:2", sequence: 1,
                         parts: ["MARK 2.3", "MARK 2.3", "MARK 2.4"])

      assert_equal 3, rebuild!
      assert_equal [["MARK 2.3", "urn:nabu:proiel:greek-nt:1"],
                    ["MARK 2.3", "urn:nabu:proiel:greek-nt:2"],
                    ["MARK 2.4", "urn:nabu:proiel:greek-nt:2"]],
                   refs.order(:seq, :ref).select_map(%i[ref passage_urn])
    end

    def test_rows_carry_work_document_urn_passage_id_and_seq
      doc = make_document(urn: "urn:nabu:proiel:greek-nt")
      passage = make_sentence(doc, urn: "urn:nabu:proiel:greek-nt:1", sequence: 7, parts: ["MARK 2.3"])
      rebuild!

      row = refs.first
      assert_equal "nt", row[:work]
      assert_equal "urn:nabu:proiel:greek-nt", row[:document_urn]
      assert_equal passage.id, row[:passage_id]
      assert_equal 7, row[:seq]
    end

    def test_unregistered_documents_contribute_nothing
      doc = make_document(urn: "urn:nabu:proiel:cic-off")
      make_sentence(doc, urn: "urn:nabu:proiel:cic-off:1", sequence: 0, parts: ["1.1"])

      assert_equal 0, rebuild!
      assert_equal 0, refs.count
    end

    def test_registered_but_absent_documents_are_skipped_silently
      # The OE Mark day-one state: registry names a witness not yet synced.
      doc = make_document(urn: "urn:nabu:proiel:greek-nt")
      make_sentence(doc, urn: "urn:nabu:proiel:greek-nt:1", sequence: 0, parts: ["MARK 2.3"])

      assert_equal 1, rebuild! # marianus absent, no error, no rows
    end

    def test_withdrawn_passages_and_documents_are_excluded
      live = make_document(urn: "urn:nabu:proiel:greek-nt")
      make_sentence(live, urn: "urn:nabu:proiel:greek-nt:1", sequence: 0,
                          parts: ["MARK 2.3"], withdrawn: true)
      dead = make_document(urn: "urn:nabu:proiel:marianus", withdrawn: true)
      make_sentence(dead, urn: "urn:nabu:proiel:marianus:1", sequence: 0, parts: ["MARK 2.3"])

      assert_equal 0, rebuild!
    end

    def test_refs_are_normalized_and_book_aliases_apply
      yaml = <<~YAML
        nt:
          witnesses:
            - document: urn:nabu:proiel:wscp
              books:
                MK: MARK
      YAML
      doc = make_document(urn: "urn:nabu:proiel:wscp")
      make_sentence(doc, urn: "urn:nabu:proiel:wscp:1", sequence: 0, parts: ["Mk 2:3"])
      rebuild!(registry(yaml))

      assert_equal ["MARK 2.3"], refs.select_map(:ref)
    end

    def test_tokens_without_citation_parts_contribute_nothing
      doc = make_document(urn: "urn:nabu:proiel:greek-nt")
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "urn:nabu:proiel:greek-nt:1", sequence: 0,
        language: "grc", text: "t", text_normalized: "t", content_sha256: "x",
        revision: 1, annotations_json: JSON.generate("tokens" => [{ "form" => "x" }])
      )

      assert_equal 0, rebuild!
    end

    def test_empty_registry_still_creates_the_table
      rebuild!(registry(""))
      assert @fulltext.table_exists?(Nabu::Store::AlignmentIndexer::TABLE),
             "an empty registry must still create the (empty) table so queries degrade to " \
             "'no rows', not 'index missing'"
    end

    def test_rebuild_is_drop_and_recreate_idempotent
      doc = make_document(urn: "urn:nabu:proiel:greek-nt")
      make_sentence(doc, urn: "urn:nabu:proiel:greek-nt:1", sequence: 0, parts: ["MARK 2.3"])

      assert_equal 1, rebuild!
      assert_equal 1, rebuild!
      assert_equal 1, refs.count
    end

    def test_indexer_rebuild_builds_alignment_refs_alongside_fts
      doc = make_document(urn: "urn:nabu:proiel:greek-nt")
      make_sentence(doc, urn: "urn:nabu:proiel:greek-nt:1", sequence: 0, parts: ["MARK 2.3"])

      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    alignments: registry(NT_REGISTRY))
      assert_equal 1, refs.count
      assert_equal 1, @fulltext[:passages_fts].count
    end

    def test_indexer_rebuild_without_alignments_creates_an_empty_table
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      assert @fulltext.table_exists?(Nabu::Store::AlignmentIndexer::TABLE)
    end
  end
end
