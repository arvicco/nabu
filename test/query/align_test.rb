# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Query
  # Nabu::Query::Align (P11-3, architecture §10): the cross-source alignment
  # query. Catalog + fulltext are separate in-memory connections (the house
  # index-query rig); the witness set mirrors the live five-way NT — sentence-
  # id passage urns, verse identity in the token citation_parts, real text
  # snippets from the live catalog (MARK 2.3, the paralytic borne of four).
  class AlignTest < Minitest::Test
    include StoreTestDB

    REGISTRY_YAML = <<~YAML
      nt:
        title: "New Testament (parallel witnesses)"
        witnesses:
          - document: urn:nabu:proiel:greek-nt
          - document: urn:nabu:proiel:latin-nt
          - document: urn:nabu:proiel:gothic-nt
          - document: urn:nabu:proiel:armenian-nt
          - document: urn:nabu:proiel:marianus
    YAML

    # [urn tail, language, MARK 2.3 text] — real live-catalog snippets.
    WITNESSES = [
      ["greek-nt", "grc", "καὶ ἔρχονται φέροντες πρὸς αὐτὸν παραλυτικὸν αἰρόμενον ὑπὸ τεσσάρων."],
      ["latin-nt", "lat", "et venerunt ferentes ad eum paralyticum qui a quattuor portabatur"],
      ["gothic-nt", "got", "jah qemun at imma usliþan bairandans, hafanana fram fidworim."],
      ["armenian-nt", "xcl", "Ew gayin ar̄ na"],
      ["marianus", "chu", "Ꙇ придѫ къ немоу носѧште ослабленъ жилами. носимъ четꙑрьми."]
    ].freeze

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @registry = load_registry(REGISTRY_YAML)
      @source = Nabu::Store::Source.create(
        slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter", license_class: "nc"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- rig ---------------------------------------------------------------------

    def load_registry(yaml)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "alignments.yml")
        File.write(path, yaml)
        return Nabu::AlignmentRegistry.load(path)
      end
    end

    # Raw-dataset seeding (no Store models — the rebuild-survival test runs
    # two catalogs side by side, and models bind globally to the latest one).
    def seed_five_witnesses(catalog = @catalog, source: @source)
      WITNESSES.each do |tail, language, text|
        doc_urn = "urn:nabu:proiel:#{tail}"
        catalog[:documents].insert(
          source_id: source.id, urn: doc_urn, title: tail.capitalize,
          language: language, content_sha256: "x", revision: 1, withdrawn: false
        )
        add_sentence(catalog, doc_urn, urn_tail: "1", sequence: 0, language: language,
                                       text: text, parts: ["MARK 2.3"])
      end
    end

    def add_sentence(catalog, doc_urn, urn_tail:, sequence:, language:, text:, parts:)
      doc_id = catalog[:documents].where(urn: doc_urn).get(:id)
      catalog[:passages].insert(
        document_id: doc_id, urn: "#{doc_urn}:#{urn_tail}", sequence: sequence,
        language: language, text: text, text_normalized: text, content_sha256: "x",
        revision: 1, withdrawn: false,
        annotations_json: JSON.generate(
          "citation" => parts.first,
          "tokens" => parts.map { |part| { "citation_part" => part, "form" => "x" } }
        )
      )
    end

    def reindex!(registry = @registry, catalog: @catalog)
      Nabu::Store::AlignmentIndexer.rebuild!(catalog: catalog, fulltext: @fulltext, registry: registry)
    end

    def align(ref, work: nil, registry: @registry, catalog: @catalog)
      Nabu::Query::Align.new(catalog: catalog, fulltext: @fulltext, registry: registry)
                        .run(ref, work: work)
    end

    # -- the five-way flagship -----------------------------------------------------

    def test_a_verse_renders_five_way_in_registry_order_with_license_labels
      seed_five_witnesses
      reindex!

      result = align("MARK 2.3")
      assert_equal "nt", result.work
      assert_equal "MARK 2.3", result.ref
      assert_equal %w[greek-nt latin-nt gothic-nt armenian-nt marianus],
                   result.witnesses.map(&:label)
      assert_equal %w[grc lat got xcl chu], result.witnesses.map(&:language)
      assert(result.witnesses.all? { |witness| witness.license_class == "nc" },
             "every aligned witness must carry its license label")
      assert(result.witnesses.all? { |witness| witness.source_slug == "proiel" },
             "attribution needs the source slug on every witness")
      assert(result.witnesses.all? { |witness| witness.status == :ok })
      assert_includes result.witnesses.first.sentences.first.text, "παραλυτικὸν"
      assert_includes result.witnesses.last.sentences.first.text, "носѧште"
    end

    def test_query_ref_is_normalized_before_lookup
      seed_five_witnesses
      reindex!

      result = align("mark 2:3")
      assert_equal "MARK 2.3", result.ref
      assert_equal(5, result.witnesses.count { |witness| witness.status == :ok })
    end

    def test_multiple_sentences_of_a_verse_come_in_sequence_order
      seed_five_witnesses
      add_sentence(@catalog, "urn:nabu:proiel:armenian-nt",
                   urn_tail: "2", sequence: 1, language: "xcl",
                   text: "berein andamaloyc mi barjeal ı̈ čʻoricʻ;", parts: ["MARK 2.3"])
      reindex!

      witness = align("MARK 2.3").witnesses.find { |candidate| candidate.label == "armenian-nt" }
      assert_equal ["urn:nabu:proiel:armenian-nt:1", "urn:nabu:proiel:armenian-nt:2"],
                   witness.sentences.map(&:urn)
    end

    def test_a_sentence_spanning_verses_reports_its_full_ref_span
      seed_five_witnesses
      add_sentence(@catalog, "urn:nabu:proiel:greek-nt",
                   urn_tail: "2", sequence: 1, language: "grc",
                   text: "spanning", parts: ["MARK 2.3", "MARK 2.4"])
      reindex!

      witness = align("MARK 2.3").witnesses.first
      spanning = witness.sentences.find { |sentence| sentence.urn.end_with?(":2") }
      assert_equal ["MARK 2.3", "MARK 2.4"], spanning.refs,
                   "a multi-verse sentence must be labeled with everything it covers"
    end

    # -- honest absence ------------------------------------------------------------

    def test_a_synced_witness_lacking_the_verse_reads_no_match
      seed_five_witnesses
      reindex!

      result = align("JOHN 1.1") # the packet's example verse — absent everywhere here
      assert(result.witnesses.all? { |witness| witness.status == :no_match })
      assert(result.witnesses.all? { |witness| witness.sentences.empty? })
      assert_equal %w[nc] * 5, result.witnesses.map(&:license_class),
                   "license labels ride even on no-match witnesses"
    end

    def test_a_registered_but_unsynced_witness_reads_not_synced
      yaml = "#{REGISTRY_YAML}    - document: urn:nabu:proiel:wscp\n      label: oe-mark\n"
      registry = load_registry(yaml)
      seed_five_witnesses
      reindex!(registry)

      result = align("MARK 2.3", registry: registry)
      oe_mark = result.witnesses.last
      assert_equal "oe-mark", oe_mark.label
      assert_equal :not_synced, oe_mark.status
      assert_nil oe_mark.license_class
      assert_equal(5, result.witnesses.count { |witness| witness.status == :ok })
    end

    # -- multi-document witnesses (P11-5: cts-verse editions) -----------------------

    TRIO_YAML = <<~YAML
      nt:
        witnesses:
          - document: urn:nabu:proiel:greek-nt
          - label: sblgnt
            extractor: cts-verse
            documents:
              MARK: urn:nabu:sblgnt:mark
              JOHN: urn:nabu:sblgnt:john
    YAML

    def seed_verse_document(doc_urn, language:, title:, verses:, source: @source)
      @catalog[:documents].insert(
        source_id: source.id, urn: doc_urn, title: title,
        language: language, content_sha256: "x", revision: 1, withdrawn: false
      )
      doc_id = @catalog[:documents].where(urn: doc_urn).get(:id)
      verses.each_with_index do |(tail, text), sequence|
        @catalog[:passages].insert(
          document_id: doc_id, urn: "#{doc_urn}:#{tail}", sequence: sequence,
          language: language, text: text, text_normalized: text, content_sha256: "x",
          revision: 1, withdrawn: false, annotations_json: "{}"
        )
      end
    end

    def test_a_cts_verse_witness_aligns_beside_the_treebank_with_the_hit_books_header
      registry = load_registry(TRIO_YAML)
      seed_five_witnesses
      seed_verse_document("urn:nabu:sblgnt:mark", language: "grc", title: "ΚΑΤΑ ΜΑΡΚΟΝ",
                                                  verses: [["2.3", "καὶ ἔρχονται φέροντες πρὸς αὐτὸν παραλυτικὸν"]])
      reindex!(registry)

      result = align("MARK 2.3", registry: registry)
      sblgnt = result.witnesses.last
      assert_equal "sblgnt", sblgnt.label
      assert_equal :ok, sblgnt.status
      assert_equal "urn:nabu:sblgnt:mark", sblgnt.document_urn
      assert_equal "ΚΑΤΑ ΜΑΡΚΟΝ", sblgnt.title, "the hit book's title heads the witness"
      assert_equal ["urn:nabu:sblgnt:mark:2.3"], sblgnt.sentences.map(&:urn)
      assert_equal [["MARK 2.3"]], sblgnt.sentences.map(&:refs)
    end

    def test_a_partially_synced_multi_document_witness_reads_no_match_without_a_misleading_title
      registry = load_registry(TRIO_YAML)
      seed_five_witnesses
      seed_verse_document("urn:nabu:sblgnt:john", language: "grc", title: "ΚΑΤΑ ΙΩΑΝΝΗΝ",
                                                  verses: [["1.1", "Ἐν ἀρχῇ ἦν ὁ λόγος"]])
      reindex!(registry)

      sblgnt = align("MARK 2.3", registry: registry).witnesses.last
      assert_equal :no_match, sblgnt.status
      assert_nil sblgnt.title, "a multi-book witness must not head a MARK miss with another book's title"
      assert_equal "grc", sblgnt.language
      assert_equal "nc", sblgnt.license_class, "license labels ride even on no-match witnesses"
    end

    def test_a_multi_document_witness_with_no_live_documents_reads_not_synced
      registry = load_registry(TRIO_YAML)
      seed_five_witnesses
      reindex!(registry)

      sblgnt = align("MARK 2.3", registry: registry).witnesses.last
      assert_equal :not_synced, sblgnt.status
      assert_nil sblgnt.license_class
    end

    def test_a_not_synced_multi_document_witness_cites_the_ref_relevant_book_urn
      registry = load_registry(TRIO_YAML)
      seed_five_witnesses
      reindex!(registry)

      # TRIO_YAML maps MARK and JOHN; a JOHN query must not cite the mark urn.
      add_sentence(@catalog, "urn:nabu:proiel:greek-nt",
                   urn_tail: "2", sequence: 1, language: "grc",
                   text: "Ἐν ἀρχῇ ἦν ὁ λόγος", parts: ["JOHN 1.1"])
      reindex!(registry)

      sblgnt = align("JOHN 1.1", registry: registry).witnesses.last
      assert_equal :not_synced, sblgnt.status
      assert_equal "urn:nabu:sblgnt:john", sblgnt.document_urn,
                   "the not-synced example urn should be the queried ref's book"
    end

    def test_a_not_synced_multi_document_witness_with_the_book_unmapped_cites_no_urn
      # TRIO_YAML maps MARK and JOHN only; a LUKE ref has no relevant book
      # urn to cite — nil, so renderers phrase it neutrally instead of
      # naming an unrelated book.
      registry = load_registry(TRIO_YAML)
      seed_five_witnesses
      add_sentence(@catalog, "urn:nabu:proiel:greek-nt",
                   urn_tail: "2", sequence: 1, language: "grc",
                   text: "λόγον", parts: ["LUKE 1.1"])
      reindex!(registry)

      sblgnt = align("LUKE 1.1", registry: registry).witnesses.last
      assert_equal :not_synced, sblgnt.status
      assert_nil sblgnt.document_urn
    end

    def test_two_works_index_and_query_independently
      yaml = TRIO_YAML + <<~YAML
        ot:
          witnesses:
            - label: lxx
              extractor: cts-verse
              documents:
                GEN: urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1
      YAML
      registry = load_registry(yaml)
      seed_five_witnesses
      seed_verse_document("urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1",
                          language: "grc", title: "Genesis",
                          verses: [["1.1", "ΕΝ ΑΡΧΗ ἐποίησεν ὁ θεὸς"]])
      reindex!(registry)

      result = align("GEN 1.1", work: "ot", registry: registry)
      assert_equal "ot", result.work
      lxx = result.witnesses.first
      assert_equal :ok, lxx.status
      assert_includes lxx.sentences.first.text, "ΕΝ ΑΡΧΗ"
      # And the ref does not bleed into nt.
      error = assert_raises(Nabu::Query::Align::Error) do
        align("urn:cts:greekLit:tlg0527.tlg001.1st1K-grc1:1.1", work: "nt", registry: registry)
      end
      assert_match(/not aligned/, error.message)
    end

    # -- work resolution -------------------------------------------------------------

    def test_sole_work_is_the_default
      seed_five_witnesses
      reindex!
      assert_equal "nt", align("MARK 2.3").work
    end

    def test_unknown_work_raises_a_loud_error
      seed_five_witnesses
      reindex!
      error = assert_raises(Nabu::Query::Align::Error) { align("MARK 2.3", work: "iliad") }
      assert_match(/iliad/, error.message)
      assert_match(/nt/, error.message, "the error must name the registered works")
    end

    # With several works registered, a bare ref auto-resolves through the
    # index (P11-5 review fix): unique attesting work → picked; several →
    # ambiguity error naming ONLY the attesters; none → honest not-found
    # with the --work hint. Explicit --work keeps precedence.

    def test_bare_ref_auto_resolves_to_the_only_attesting_work
      yaml = REGISTRY_YAML + <<~YAML
        psalter:
          witnesses:
            - document: urn:nabu:proiel:some-psalter
      YAML
      registry = load_registry(yaml)
      seed_five_witnesses
      reindex!(registry)

      result = align("MARK 2.3", registry: registry)
      assert_equal "nt", result.work, "the sole attesting work resolves without --work"
      assert_equal(5, result.witnesses.count { |witness| witness.status == :ok })
      # A passage urn pivots through the same resolution.
      assert_equal "nt", align("urn:nabu:proiel:marianus:1", registry: registry).work
      # Explicit --work keeps precedence.
      assert_equal "nt", align("MARK 2.3", work: "nt", registry: registry).work
    end

    def test_bare_ref_attested_in_several_works_names_only_the_attesters
      yaml = REGISTRY_YAML + <<~YAML
        harmony:
          witnesses:
            - label: verses
              extractor: cts-verse
              documents:
                MARK: urn:nabu:sblgnt:mark
        psalter:
          witnesses:
            - document: urn:nabu:proiel:some-psalter
      YAML
      registry = load_registry(yaml)
      seed_five_witnesses
      seed_verse_document("urn:nabu:sblgnt:mark", language: "grc", title: "ΚΑΤΑ ΜΑΡΚΟΝ",
                                                  verses: [["2.3", "καὶ ἔρχονται"]])
      reindex!(registry)

      error = assert_raises(Nabu::Query::Align::Error) { align("MARK 2.3", registry: registry) }
      assert_match(/--work/, error.message)
      assert_match(/nt/, error.message)
      assert_match(/harmony/, error.message)
      refute_match(/psalter/, error.message, "a work that does not attest the ref is not offered")
    end

    def test_bare_ref_attested_nowhere_reads_not_found_with_the_work_hint
      yaml = REGISTRY_YAML + <<~YAML
        psalter:
          witnesses:
            - document: urn:nabu:proiel:some-psalter
      YAML
      registry = load_registry(yaml)
      seed_five_witnesses
      reindex!(registry)

      error = assert_raises(Nabu::Query::Align::Error) { align("TOBIT 1.1", registry: registry) }
      assert_match(/not attested/i, error.message)
      assert_match(/--work/, error.message)
    end

    def test_empty_registry_raises_with_guidance
      error = assert_raises(Nabu::Query::Align::Error) { align("MARK 2.3", registry: load_registry("")) }
      assert_match(/no alignment works registered/i, error.message)
    end

    def test_missing_index_table_raises_with_rebuild_guidance
      seed_five_witnesses # no reindex! — the table does not exist
      error = assert_raises(Nabu::Query::Align::Error) { align("MARK 2.3") }
      assert_match(/nabu sync|nabu rebuild/, error.message)
    end

    # -- urn pivot ---------------------------------------------------------------------

    def test_a_passage_urn_pivots_into_its_verse
      seed_five_witnesses
      reindex!

      result = align("urn:nabu:proiel:marianus:1")
      assert_equal "MARK 2.3", result.ref
      assert_equal(5, result.witnesses.count { |witness| witness.status == :ok })
    end

    def test_a_multi_verse_passage_urn_pivots_to_its_first_ref
      seed_five_witnesses
      add_sentence(@catalog, "urn:nabu:proiel:greek-nt",
                   urn_tail: "2", sequence: 1, language: "grc",
                   text: "spanning", parts: ["MARK 2.3", "MARK 2.4"])
      reindex!

      result = align("urn:nabu:proiel:greek-nt:2")
      assert_equal "MARK 2.3", result.ref
    end

    def test_an_unaligned_urn_raises_not_found
      seed_five_witnesses
      reindex!
      error = assert_raises(Nabu::Query::Align::Error) { align("urn:nabu:proiel:cic-off:1") }
      assert_match(/not aligned|not found/i, error.message)
    end

    # -- license coalesce -----------------------------------------------------------------

    def test_document_license_override_beats_source_class
      seed_five_witnesses
      @catalog[:documents].where(urn: "urn:nabu:proiel:marianus").update(license_override: "attribution")
      reindex!

      witness = align("MARK 2.3").witnesses.find { |candidate| candidate.label == "marianus" }
      assert_equal "attribution", witness.license_class
    end

    # -- range / chapter queries (P11-8) -------------------------------------------------

    # Two cts-verse witnesses over one book: one attests every verse, the other
    # only some — so per-ref attestation honesty is exercised across the range.
    RANGE_YAML = <<~YAML
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

    def seed_jonah_chapter
      registry = load_registry(RANGE_YAML)
      # src-a: JON 1.1..1.16 (all sixteen); src-b: only 1.1 and 1.3.
      seed_verse_document("urn:nabu:src-a:jon", language: "grc", title: "ΙΩΝΑΣ",
                                                verses: (1..16).map { |v| ["1.#{v}", "greek verse #{v}"] })
      seed_verse_document("urn:nabu:src-b:jon", language: "lat", title: "Jonas",
                                                verses: [["1.1", "latin one"], ["1.3", "latin three"]])
      reindex!(registry)
      registry
    end

    def test_a_chapter_renders_every_attested_ref_in_document_order
      registry = seed_jonah_chapter
      result = align("JON 1", registry: registry)

      assert_equal "ot", result.work
      assert_equal "JON 1", result.query
      assert_equal 16, result.groups.size, "every attested verse of the chapter"
      refute result.truncated
      assert_equal((1..16).map { |v| "JON 1.#{v}" }, result.groups.map(&:ref),
                   "refs render in numeric (document) order, not lexical")
      # Per-ref attestation honesty: verse 1 is in both, verse 2 only in src-a.
      v1 = result.groups.first
      assert_equal %i[ok ok], v1.witnesses.map(&:status)
      v2 = result.groups[1]
      assert_equal %i[ok no_match], v2.witnesses.map(&:status)
    end

    def test_a_verse_range_renders_the_inclusive_slice
      registry = seed_jonah_chapter
      result = align("JON 1.3-1.10", registry: registry)
      assert_equal((3..10).map { |v| "JON 1.#{v}" }, result.groups.map(&:ref))
      assert_equal 8, result.total
    end

    def test_a_reversed_range_raises_naming_the_endpoints
      registry = seed_jonah_chapter
      error = assert_raises(Nabu::Query::Align::Error) { align("JON 1.10-1.3", registry: registry) }
      assert_match(/reversed range/, error.message)
    end

    def test_a_range_caps_at_the_ceiling_with_a_truncation_flag
      registry = load_registry(<<~YAML)
        ot:
          witnesses:
            - label: full
              extractor: cts-verse
              documents:
                PSA: urn:nabu:src-a:psa
      YAML
      seed_verse_document("urn:nabu:src-a:psa", language: "grc", title: "ΨΑΛΜΟΙ",
                                                verses: (1..205).map { |v| ["1.#{v}", "verse #{v}"] })
      reindex!(registry)

      result = align("PSA 1", registry: registry)
      assert_equal 205, result.total
      assert_equal Nabu::Query::Align::MAX_REFS, result.groups.size
      assert result.truncated, "beyond the cap the range is truncated"
    end

    def test_a_chapter_with_no_attested_refs_raises_honestly
      registry = seed_jonah_chapter
      error = assert_raises(Nabu::Query::Align::Error) { align("JON 9", registry: registry) }
      assert_match(/no attested refs/i, error.message)
    end

    def test_a_range_auto_resolves_the_only_attesting_work
      # Two works; JON is attested only under ot — a bare range resolves it.
      registry = seed_jonah_chapter
      # (RANGE_YAML registers only ot; assert the resolution names it.)
      assert_equal "ot", align("JON 1.1-1.2", registry: registry).work
    end

    # -- range absent-witness summarization (P11-9) ------------------------------
    # The owner's readability fix: a witness absent from EVERY ref of a range is
    # lifted to a header summary and dropped from the per-ref groups; a witness
    # that attests SOME refs stays per-ref (honest "no_match" and all).

    # full: JON 1.1..1.4 (every ref). partial: only 1.1 (present, stays per-ref).
    # empty: a LIVE document whose only verse is JON 2.1 — no JON 1 attestation
    # (not_attested). ghost: its document is never seeded (not_synced).
    ABSENT_RANGE_YAML = <<~YAML
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
          - label: empty
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-c:jon
          - label: ghost
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-z:jon
    YAML

    def seed_absent_range
      registry = load_registry(ABSENT_RANGE_YAML)
      seed_verse_document("urn:nabu:src-a:jon", language: "grc", title: "full",
                                                verses: (1..4).map { |v| ["1.#{v}", "greek #{v}"] })
      seed_verse_document("urn:nabu:src-b:jon", language: "lat", title: "partial",
                                                verses: [["1.1", "latin one"]])
      # live, but its only verse sits in chapter 2 — absent from JON 1.
      seed_verse_document("urn:nabu:src-c:jon", language: "eng", title: "empty",
                                                verses: [["2.1", "english two-one"]])
      # src-z:jon is never created → the ghost witness is not_synced.
      reindex!(registry)
      registry
    end

    def test_a_range_lifts_all_absent_witnesses_to_a_header_summary
      registry = seed_absent_range
      result = align("JON 1", registry: registry)

      # Only witnesses present somewhere in the range appear per ref.
      result.groups.each do |group|
        assert_equal %w[full partial], group.witnesses.map(&:label)
      end
      # The two never-attesting witnesses are summarized once, with honest reasons.
      assert_equal({ "empty" => :not_attested, "ghost" => :not_synced },
                   result.absent.to_h { |witness| [witness.label, witness.reason] })
    end

    def test_a_partially_attesting_witness_is_never_lifted
      registry = seed_absent_range
      result = align("JON 1", registry: registry)
      refute_includes result.absent.map(&:label), "partial"
      # It still reads no_match per ref where it lacks the verse (JON 1.2).
      partial_v2 = result.groups[1].witnesses.find { |witness| witness.label == "partial" }
      assert_equal :no_match, partial_v2.status
    end

    def test_a_range_where_every_witness_attests_carries_no_absent_summary
      registry = seed_jonah_chapter # full + partial, both attest ≥1 ref
      assert_empty align("JON 1", registry: registry).absent
    end

    def test_the_single_ref_path_carries_no_absent_field
      # Byte-unchanged: the single-ref Result has no :absent member at all.
      seed_five_witnesses
      reindex!
      result = align("MARK 2.3")
      refute_respond_to result, :absent
    end

    # -- rebuild safety (the packet's acceptance test) -----------------------------------

    def test_alignment_survives_a_rebuild_with_reminted_ids
      seed_five_witnesses
      reindex!
      before = align("MARK 2.3")

      # A rebuild drops the catalog and re-derives it: fresh db, re-minted ids
      # (offset the id sequence so they provably differ), fresh index build.
      rebuilt = store_test_db
      source = Nabu::Store::Source.create(
        slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter", license_class: "nc"
      )
      rebuilt[:documents].insert(
        source_id: source.id, urn: "urn:nabu:proiel:id-offset", title: "x", language: "grc",
        content_sha256: "x", revision: 1, withdrawn: true
      )
      seed_five_witnesses(rebuilt, source: source)
      reindex!(@registry, catalog: rebuilt)

      after = align("MARK 2.3", catalog: rebuilt)
      assert_equal before.witnesses.map(&:label), after.witnesses.map(&:label)
      assert_equal(before.witnesses.map { |witness| witness.sentences.map(&:text) },
                   after.witnesses.map { |witness| witness.sentences.map(&:text) })
    end
  end
end
