# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Clarify — the reference normalizer behind nabu_clarify:
  # partial/misspelled work-or-passage input → is_ref, a resolved urn when
  # the input parses UNIQUELY, the citation structure one level deeper, and
  # typed CANDIDATES — never a silent guess. Rig: fresh in-memory catalog +
  # fulltext, the real Indexer (which derives the clarify lane).
  class ClarifyTest < Minitest::Test
    include StoreTestDB

    ILIAD = "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2"
    ILIAD_ENG = "urn:cts:greekLit:tlg0012.tlg001.perseus-eng4"
    ODYSSEY = "urn:cts:greekLit:tlg0012.tlg002.perseus-grc2"

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @perseus = Nabu::Store::Source.create(slug: "perseus", name: "Perseus Digital Library",
                                            adapter_class: "TestAdapter", license_class: "open")
      @private = Nabu::Store::Source.create(slug: "adhoc", name: "Ad hoc", adapter_class: "TestAdapter",
                                            license_class: "research_private")
      seed
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def teardown
      @fulltext.disconnect
    end

    def document(urn, title:, citations:, source: @perseus, language: "grc")
      doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: title, language: language,
                                         content_sha256: "x", revision: 1)
      citations.each_with_index do |citation, i|
        Nabu::Store::Passage.create(document_id: doc.id, urn: "#{urn}:#{citation}", sequence: i,
                                    language: language, text: "t", text_normalized: "t",
                                    annotations_json: "{}", content_sha256: "x", revision: 1)
      end
      doc
    end

    def seed
      document(ILIAD, title: "Iliad", citations: %w[1.1 1.2 1.3 2.1])
      document(ILIAD_ENG, title: "Iliad", citations: %w[1.1 1.2], language: "eng")
      document(ODYSSEY, title: "Ὀδύσσεια", citations: %w[1.1 1.2])
      document("urn:nabu:adhoc:iliad-notes", title: "Iliad notebook", citations: %w[1], source: @private)
      shelf = @catalog[:dictionaries].insert(source_id: @perseus.id, slug: "lsj", title: "LSJ", language: "grc")
      @catalog[:dictionary_entries].insert(dictionary_id: shelf, urn: "urn:nabu:dict:lsj:menis",
                                           entry_id: "menis", key_raw: "μῆνις", headword: "μῆνις",
                                           headword_folded: "μηνισ", body: "wrath", content_sha256: "x")
      @catalog[:place_index].insert(gazetteer: "pleiades", place_id: "462281", title: "Lilybaeum",
                                    place_types_json: "[]", time_periods_json: "[]", position: 0)
    end

    def clarify(input, **)
      Nabu::Query::Clarify.new(catalog: @catalog, fulltext: @fulltext).run(input, **)
    end

    # -- urn input ---------------------------------------------------------

    def test_an_exact_passage_urn_resolves_with_its_document_structure
      result = clarify("#{ILIAD}:1.2")
      assert result.is_ref
      assert_equal "#{ILIAD}:1.2", result.resolved_urn
      assert_equal %w[passage Iliad], [result.ref.kind, result.ref.title]
      structure = result.structure
      assert_equal [ILIAD, 4, "1.1", "2.1", 2, "1.2"],
                   [structure.document_urn, structure.passages, structure.first_citation,
                    structure.last_citation, structure.depth, structure.citation]
      assert_equal "#{ILIAD}:1.1-1.2", structure.range_example
    end

    def test_a_document_urn_resolves_and_teaches_the_deeper_citation
      result = clarify(ILIAD)
      assert result.is_ref
      assert_equal ILIAD, result.resolved_urn
      assert_equal "document", result.ref.kind
      assert_equal "#{ILIAD}:1.1", result.structure.example
      assert_nil result.structure.citation
    end

    def test_a_citation_prefix_resolves_for_term_less_browsing
      result = clarify("#{ILIAD}:1")
      assert result.is_ref
      assert_equal ["citation_prefix", "#{ILIAD}:1"], [result.ref.kind, result.resolved_urn]
    end

    def test_a_partial_urn_is_not_a_ref_and_completes_to_documents
      result = clarify("urn:cts:greekLit:tlg0012.tlg00")
      refute result.is_ref
      assert_nil result.resolved_urn
      assert_equal [ILIAD_ENG, ILIAD, ODYSSEY].sort, result.completions.map(&:key).sort
      assert(result.completions.all? { |c| c.type == "document" })
    end

    # -- name input ----------------------------------------------------------

    def test_a_title_prefix_completes_to_typed_candidates
      result = clarify("Ilia")
      refute result.is_ref, "a prefix is not a reference"
      keys = result.completions.map(&:key)
      assert_includes keys, ILIAD
      assert_includes keys, ILIAD_ENG
      iliad = result.completions.find { |c| c.key == ILIAD }
      assert_equal ["Iliad", "document", true], [iliad.title, iliad.type, iliad.is_primary]
    end

    def test_an_exact_shared_title_is_a_ref_but_ambiguous_never_a_guess
      result = clarify("iliad")
      assert result.is_ref
      assert_nil result.resolved_urn, "two editions share the title — candidates, never a silent pick"
      assert_equal [ILIAD, ILIAD_ENG].sort,
                   result.completions.select { |c| c.match == "exact" }.map(&:key).sort
    end

    def test_title_plus_citation_resolves_uniquely_or_lists_candidates
      unique = clarify("Iliad 2.1")
      assert unique.is_ref
      assert_equal "#{ILIAD}:2.1", unique.resolved_urn, "only the Greek edition holds 2.1"

      ambiguous = clarify("Iliad 1.1")
      assert ambiguous.is_ref
      assert_nil ambiguous.resolved_urn
      assert_equal ["#{ILIAD}:1.1", "#{ILIAD_ENG}:1.1"].sort,
                   ambiguous.completions.filter_map(&:ref_urn).sort
    end

    def test_diacritics_are_optional_both_ways
      result = clarify("odysseia")
      refute_includes result.completions.map(&:key), ODYSSEY, "a transliteration is not a fold"
      greek = clarify("οδυσσεια")
      assert_includes greek.completions.map(&:key), ODYSSEY, "unaccented Greek finds Ὀδύσσεια"
    end

    def test_a_misspelling_reaches_the_title_through_the_trigram_lane
      result = clarify("Illiad")
      iliad = result.completions.find { |c| c.key == ILIAD }
      refute_nil iliad, "the trigram lane recovers the doubled-l typo"
      assert_equal "fuzzy", iliad.match
      refute result.is_ref, "a fuzzy match is a candidate, never a resolution"
    end

    def test_sources_lemmas_and_places_are_typed_candidates
      assert_equal ["source", false],
                   clarify("perseus").completions.find { |c| c.key == "perseus" }.then { |c| [c.type, c.is_primary] },
                   "the slug matched as an alias"
      lemma = clarify("μηνις").completions.find { |c| c.type == "lemma" }
      assert_equal ["urn:nabu:dict:lsj:menis", "μῆνις", "LSJ"], [lemma.key, lemma.title, lemma.detail]
      place = clarify("lilyb").completions.find { |c| c.type == "place" }
      assert_equal "pleiades:462281", place.key
    end

    def test_restricted_entries_are_withheld_unless_asked
      refute_includes clarify("iliad note").completions.map(&:key), "urn:nabu:adhoc:iliad-notes"
      assert_includes clarify("iliad note", include_restricted: true).completions.map(&:key),
                      "urn:nabu:adhoc:iliad-notes"
    end

    def test_completions_are_bounded
      assert_equal 1, clarify("Ilia", limit: 1).completions.size
    end

    # -- the absent-index degrade ---------------------------------------------

    def test_without_the_lane_names_degrade_honestly_and_urns_still_resolve
      Nabu::Store::Indexer.drop_clarify!(@fulltext)
      names = clarify("Iliad")
      refute names.index_present
      assert_empty names.completions
      assert_match(/rake index:clarify/, names.note)
      urn = clarify("#{ILIAD}:1.1")
      assert_equal "#{ILIAD}:1.1", urn.resolved_urn, "urn resolution is catalog-only"
    end
  end
end
