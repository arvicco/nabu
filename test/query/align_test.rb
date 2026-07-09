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

    def test_multiple_works_require_an_explicit_work
      yaml = REGISTRY_YAML + <<~YAML
        psalter:
          witnesses:
            - document: urn:nabu:proiel:some-psalter
      YAML
      registry = load_registry(yaml)
      seed_five_witnesses
      reindex!(registry)

      error = assert_raises(Nabu::Query::Align::Error) { align("MARK 2.3", registry: registry) }
      assert_match(/--work/, error.message)
      assert_equal "nt", align("MARK 2.3", work: "nt", registry: registry).work
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
