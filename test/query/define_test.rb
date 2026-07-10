# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Define (P11-4): folded-headword dictionary lookup over the
  # catalog's dictionary shelf, with query-time citation resolution against
  # the in-catalog documents. The shelf is loaded end-to-end from the real
  # lexica fixtures (adapter → DictionaryLoader); resolution targets are
  # store-level document/passage rows (the loader's own tests cover the
  # passage pipeline).
  class DefineTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "lexica", name: "Perseus Lexica", adapter_class: "Nabu::Adapters::Lexica",
        license: "CC BY-SA 4.0", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: @source)
                                   .load_from(Nabu::Adapters::Lexica.new,
                                              workdir: Nabu::TestSupport.fixtures("lexica"))
      @texts = Nabu::Store::Source.create(
        slug: "texts", name: "Texts", adapter_class: "TestAdapter", license_class: "attribution"
      )
    end

    def make_document(urn:, language:, title: "T")
      Nabu::Store::Document.create(
        source_id: @texts.id, urn: urn, title: title, language: language,
        content_sha256: "x", revision: 1, withdrawn: false
      )
    end

    def make_passage(document, urn:)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: 0, language: document.language,
        text: "τ", text_normalized: "τ", content_sha256: "x", revision: 1
      )
    end

    def define(lemma, **)
      Nabu::Query::Define.new(catalog: @catalog).run(lemma, **)
    end

    # -- lookup ---------------------------------------------------------------

    def test_defines_a_greek_lemma_with_license_label_and_gloss
      results = define("μῆνις")
      assert_equal 1, results.size
      menis = results.first
      assert_equal "μῆνις", menis.headword
      assert_equal "lsj", menis.dictionary_slug
      assert_equal "grc", menis.language
      assert_equal "attribution", menis.license_class
      assert_equal "wrath", menis.gloss
      assert_equal "urn:nabu:dict:lsj:n67485", menis.urn
      assert_includes menis.body, "wrath"
    end

    def test_lookup_is_accent_insensitive_and_folds_final_sigma_both_sides
      assert_equal ["μῆνις"], define("μηνις").map(&:headword)
      assert_equal ["λόγος"], define("λόγος").map(&:headword)
      assert_equal ["λόγος"], define("λογοσ").map(&:headword)
    end

    def test_defines_a_latin_lemma
      results = define("officium")
      assert_equal ["offĭcĭum"], results.map(&:headword)
      assert_equal "a service", results.first.gloss
      assert_equal "lewis-short", results.first.dictionary_slug
    end

    def test_lang_filters_by_dictionary_language
      assert_empty define("officium", lang: "grc")
      assert_equal 1, define("officium", lang: "lat").size
    end

    def test_withdrawn_entries_are_excluded
      @catalog[:dictionary_entries].where(entry_id: "n67485").update(withdrawn: true)
      assert_empty define("μῆνις")
    end

    def test_missing_shelf_degrades_to_no_results
      bare = Nabu::Store.connect("sqlite::memory:") # no migrations: no shelf tables
      assert_empty Nabu::Query::Define.new(catalog: bare).run("μῆνις")
    ensure
      bare&.disconnect
    end

    # -- citation resolution ----------------------------------------------------

    def test_resolves_a_citation_to_the_in_catalog_edition_of_the_work
      # LSJ cites Il. 1.1 with an urn anchored at perseus-grc1; the catalog
      # holds grc2 — resolution matches the WORK and re-anchors.
      iliad = make_document(urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2", language: "grc")
      make_passage(iliad, urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1")

      citation = define("μῆνις").first.citations.find { |c| c.label == "Il. 1.1" }
      assert_equal "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1", citation.resolved_urn
    end

    def test_resolution_prefers_the_original_language_edition_over_a_translation
      eng = make_document(urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-eng4", language: "eng")
      make_passage(eng, urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-eng4:1.1")
      grc = make_document(urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2", language: "grc")
      make_passage(grc, urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1")

      citation = define("μῆνις").first.citations.find { |c| c.label == "Il. 1.1" }
      assert_equal "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1", citation.resolved_urn
    end

    def test_resolves_the_latin_anchor_cic_off
      off = make_document(urn: "urn:cts:latinLit:phi0474.phi055.perseus-lat1", language: "lat")
      make_passage(off, urn: "urn:cts:latinLit:phi0474.phi055.perseus-lat1:1.2.4")

      citations = define("officium").first.citations
      resolved = citations.find { |c| c.urn_raw == "urn:cts:latinLit:phi0474.phi055.perseus-lat1:1:2:4" }
      assert_equal "urn:cts:latinLit:phi0474.phi055.perseus-lat1:1.2.4", resolved.resolved_urn
    end

    def test_resolution_falls_back_to_the_chapter_section_double_citation
      # The real shape mismatch: L&S cites Cic. Off. "1, 2, 4" (book, chapter,
      # continuous section) but the Perseus edition cites book.section — the
      # last number IS the section, so 1:2:4 must resolve to :1.4 when no
      # 3-level passage exists.
      off = make_document(urn: "urn:cts:latinLit:phi0474.phi055.perseus-lat1", language: "lat")
      make_passage(off, urn: "urn:cts:latinLit:phi0474.phi055.perseus-lat1:1.4")

      citations = define("officium").first.citations
      cite = citations.find { |c| c.urn_raw == "urn:cts:latinLit:phi0474.phi055.perseus-lat1:1:2:4" }
      assert_equal "urn:cts:latinLit:phi0474.phi055.perseus-lat1:1.4", cite.resolved_urn
    end

    def test_citations_of_works_not_in_catalog_stay_unresolved_text
      citations = define("μῆνις").first.citations
      plato = citations.find { |c| c.label.start_with?("Pl. R.") }
      refute_nil plato
      assert_nil plato.resolved_urn
      assert_nil citations.find { |c| c.label == "Il. 1.1" }.resolved_urn, "no Iliad in catalog here"
    end

    def test_malformed_upstream_urns_resolve_to_nothing_without_crashing
      bad = define("virtus").first.citations.find { |c| c.urn_raw.include?("Orat::") }
      assert_nil bad.resolved_urn
    end
  end
end
