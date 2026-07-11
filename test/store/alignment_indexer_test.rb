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

    # -- cts-verse (P11-5): verse-grain CTS-style editions ----------------------

    OT_REGISTRY = <<~YAML
      ot:
        witnesses:
          - label: lxx
            extractor: cts-verse
            documents:
              GEN: urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1
              EXO: urn:cts:greekLit:tlg0527.tlg002.1st1K-grc1
    YAML

    def make_verse(document, urn:, sequence:)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: "grc",
        text: "t", text_normalized: "t", content_sha256: "x", revision: 1
      )
    end

    def test_cts_verse_indexes_book_token_plus_urn_tail_across_a_multi_document_witness
      genesis = make_document(urn: "urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1")
      make_verse(genesis, urn: "urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1:1.1", sequence: 0)
      make_verse(genesis, urn: "urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1:1.2", sequence: 1)
      exodus = make_document(urn: "urn:cts:greekLit:tlg0527.tlg002.1st1K-grc1")
      make_verse(exodus, urn: "urn:cts:greekLit:tlg0527.tlg002.1st1K-grc1:1.1", sequence: 0)

      assert_equal 3, rebuild!(registry(OT_REGISTRY))
      assert_equal [["EXO 1.1", "urn:cts:greekLit:tlg0527.tlg002.1st1K-grc1"],
                    ["GEN 1.1", "urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1"],
                    ["GEN 1.2", "urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1"]],
                   refs.order(:ref).select_map(%i[ref document_urn])
    end

    def test_cts_verse_needs_no_annotations
      doc = make_document(urn: "urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1")
      make_verse(doc, urn: "urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1:1.1", sequence: 0)
      refute_includes Nabu::Store::Passage.first[:annotations_json].to_s, "citation"

      assert_equal 1, rebuild!(registry(OT_REGISTRY))
      assert_equal ["GEN 1.1"], refs.select_map(:ref)
    end

    def test_cts_verse_indexes_flat_single_level_tails
      # The Epistula Jeremiae reality: a single-chapter book cites bare verse
      # numbers — "LJE 5" folds and stays addressable like any other ref.
      yaml = <<~YAML
        ot:
          witnesses:
            - label: lxx
              extractor: cts-verse
              documents:
                LJE: urn:cts:greekLit:tlg0527.tlg052.1st1K-grc1
      YAML
      doc = make_document(urn: "urn:cts:greekLit:tlg0527.tlg052.1st1K-grc1")
      make_verse(doc, urn: "urn:cts:greekLit:tlg0527.tlg052.1st1K-grc1:5", sequence: 0)

      rebuild!(registry(yaml))
      assert_equal ["LJE 5"], refs.select_map(:ref)
    end

    # -- numbering remap (P13-5): the Psalms versification divergence -----------

    NUMBERING_REGISTRY = <<~YAML
      psalms:
        witnesses:
          - label: WEB (English)
            extractor: cts-verse
            numbering:
              system: "Hebrew (Masoretic)"
              ranges:
                - { from: 1, to: 8, shift: 0 }
                - { from: 11, to: 113, shift: -1 }
                - { from: 148, to: 150, shift: 0 }
            documents:
              PSA: urn:nabu:eng-web:psa
    YAML

    def test_numbering_remaps_hebrew_psalm_refs_into_the_greek_work_vocabulary
      # Hebrew 23.1 (the shepherd verse) indexes under Greek 22.1; the identity
      # spans (1–8, 148–150) pass through unchanged.
      doc = make_document(urn: "urn:nabu:eng-web:psa")
      make_verse(doc, urn: "urn:nabu:eng-web:psa:23.1", sequence: 0)
      make_verse(doc, urn: "urn:nabu:eng-web:psa:1.1", sequence: 1)
      make_verse(doc, urn: "urn:nabu:eng-web:psa:150.1", sequence: 2)

      assert_equal 3, rebuild!(registry(NUMBERING_REGISTRY))
      assert_equal [["PSA 1.1", "urn:nabu:eng-web:psa:1.1"],
                    ["PSA 150.1", "urn:nabu:eng-web:psa:150.1"],
                    ["PSA 22.1", "urn:nabu:eng-web:psa:23.1"]],
                   refs.order(:ref).select_map(%i[ref passage_urn])
    end

    def test_numbering_drops_the_join_split_psalms_it_cannot_map_one_to_one
      # Hebrew 9, 116, 147 fall in no range (the LXX joins/splits them): the
      # remap returns nil, so those refs are NOT indexed — never false-aligned.
      doc = make_document(urn: "urn:nabu:eng-web:psa")
      make_verse(doc, urn: "urn:nabu:eng-web:psa:9.1", sequence: 0)
      make_verse(doc, urn: "urn:nabu:eng-web:psa:116.1", sequence: 1)
      make_verse(doc, urn: "urn:nabu:eng-web:psa:147.1", sequence: 2)
      make_verse(doc, urn: "urn:nabu:eng-web:psa:23.1", sequence: 3)

      assert_equal 1, rebuild!(registry(NUMBERING_REGISTRY))
      assert_equal ["PSA 22.1"], refs.select_map(:ref)
    end

    def test_cts_verse_skips_a_passage_urn_that_does_not_extend_its_document_urn
      doc = make_document(urn: "urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1")
      make_verse(doc, urn: "urn:nabu:oddball:1.1", sequence: 0)

      assert_equal 0, rebuild!(registry(OT_REGISTRY))
    end

    def test_a_work_can_mix_proiel_citation_and_cts_verse_witnesses
      yaml = <<~YAML
        nt:
          witnesses:
            - document: urn:nabu:proiel:greek-nt
            - label: sblgnt
              extractor: cts-verse
              documents:
                MARK: urn:nabu:sblgnt:mark
      YAML
      treebank = make_document(urn: "urn:nabu:proiel:greek-nt")
      make_sentence(treebank, urn: "urn:nabu:proiel:greek-nt:1", sequence: 0, parts: ["MARK 2.3"])
      edition = make_document(urn: "urn:nabu:sblgnt:mark")
      make_verse(edition, urn: "urn:nabu:sblgnt:mark:2.3", sequence: 0)

      assert_equal 2, rebuild!(registry(yaml))
      assert_equal [["MARK 2.3", "urn:nabu:proiel:greek-nt:1"],
                    ["MARK 2.3", "urn:nabu:sblgnt:mark:2.3"]],
                   refs.order(:passage_urn).select_map(%i[ref passage_urn])
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
