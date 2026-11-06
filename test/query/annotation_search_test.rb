# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::AnnotationSearch — the read side of the annotations lane:
  # a query over the declared searchable annotation layers
  # (Store::AnnotationIndex) answered from the precompiled index only,
  # each hit naming the passage plus the matched layer.
  class AnnotationSearchTest < Minitest::Test
    include StoreTestDB

    PRESUL = "urn:nabu:cantus:455843:1"
    BIBLE_PAGE = "urn:nabu:korpus16:58:200"

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      Nabu::TestSupport.load_annotation_corpus(@catalog)
    end

    def teardown
      @fulltext.disconnect
    end

    def build! = Nabu::Store::AnnotationIndex.rebuild!(catalog: @catalog, fulltext: @fulltext)

    def search = Nabu::Query::AnnotationSearch.new(catalog: @catalog, fulltext: @fulltext)

    # The use case: a standardized-spelling query reaches the manuscript
    # passage, whose own text spells the word otherwise.
    def test_a_standardized_spelling_finds_the_manuscript_passage
      build!
      results = search.run("praesul")

      assert_equal [PRESUL], results.map(&:urn)
      hit = results.first
      assert_equal "lat", hit.language
      assert_equal "standardized", hit.layer
      assert_match(/\[praesul\]/, hit.snippet)
      assert_includes hit.text, "presul", "the manuscript's own spelling rides along"
    end

    # Fold-both-sides through the main search's per-language union: a
    # query typed with j finds the Latin-folded "iam" layer, and the
    # long s of the Slovene notes needs no typing.
    def test_queries_fold_the_main_search_way
      build!
      assert_includes search.run("jam").map(&:urn), "urn:nabu:cantus:455850:1"
      assert_includes search.run("Iam").map(&:urn), "urn:nabu:cantus:455850:1"
      assert_equal [BIBLE_PAGE], search.run('"sobbota ali prasnik"').map(&:urn)
    end

    def test_korpus16_notes_hit_with_the_matched_note
      build!
      hit = search.run("prasnik").first

      assert_equal BIBLE_PAGE, hit.urn
      assert_equal "sl", hit.language
      assert_equal "notes", hit.layer
      assert_match(/Sobbota ali \[prasnik\]/, hit.snippet, "the matching note, not the page's first one")
    end

    def test_words_are_anded_and_prefixable
      build!
      assert_includes search.run("praesul cathedr*").map(&:urn), PRESUL
      assert_empty search.run("praesul prasnik")
    end

    def test_lang_and_source_filter_inside_the_index
      build!
      assert_empty search.run("praesul", source: "korpus16")
      refute_empty search.run("praesul", source: "cantus")
      assert_empty search.run("prasnik", lang: "lat")
      refute_empty search.run("prasnik", lang: "sl")
      refute_empty search.run("prasnik", sources: %w[korpus16 cantus])
    end

    def test_operator_shaped_input_is_matched_literally_never_an_fts_error
      build!
      assert_kind_of Array, search.run("praesul NOT")
      assert_kind_of Array, search.run('flesh" OR "x')
      assert_empty search.run("(:)")
    end

    def test_limit_caps_the_page
      build!
      assert_equal 2, search.run("gloria", limit: 2).size
    end

    def test_scope_reports_what_the_build_indexed
      build!
      assert_equal %w[cantus korpus16], search.scope.map(&:first)
      assert_equal 1, search.scope.to_h.fetch("korpus16")
    end

    def test_an_absent_index_raises_the_build_hint
      refute search.available?
      assert_nil search.scope
      error = assert_raises(Nabu::Query::AnnotationSearch::IndexMissing) { search.run("praesul") }
      assert_match(/rake index:annotations/, error.message)
    end
  end
end
