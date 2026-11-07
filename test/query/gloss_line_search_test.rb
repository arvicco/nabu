# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::GlossLineSearch — the read side of the gloss-lines lane:
  # a content query over the passages' upstream token glosses
  # (Store::GlossLineIndex) answered from the precompiled index only, each
  # hit naming the passage, its gloss line snippet and the matching words.
  class GlossLineSearchTest < Minitest::Test
    include StoreTestDB

    DAN_2_4 = "urn:nabu:bhsa:dan:2.4"
    LEASE = "urn:nabu:achemenet:p261571:1"
    KBO_24 = "urn:nabu:tlhdig:626:hfr:kbo.52.195+:24"

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      Nabu::TestSupport.load_gloss_corpus(@catalog)
    end

    def teardown
      @fulltext.disconnect
    end

    def build! = Nabu::Store::GlossLineIndex.rebuild!(catalog: @catalog, fulltext: @fulltext)

    def search = Nabu::Query::GlossLineSearch.new(catalog: @catalog, fulltext: @fulltext)

    # The use case: "king" reaches passages in Aramaic, Hebrew and
    # Akkadian whose words are glossed king, each hit naming the word.
    def test_king_reaches_passages_glossed_king_in_other_languages
      build!
      results = search.run("king", limit: 50)

      assert_includes results.map(&:urn), DAN_2_4
      assert_includes results.map(&:urn), LEASE
      assert_equal %w[akk arc hbo], results.map(&:language).uniq.sort
      lease = results.find { |hit| hit.urn == LEASE }
      assert_equal "achemenet", lease.source
      assert(lease.words.any? { |_form, gloss| gloss == "king" }, "the matching token is named")
      assert(lease.words.all? { |_form, gloss| gloss.match?(/\bking\b/i) })
      assert_match(/\[king\]/, lease.snippet)
      refute_includes lease.text, "king", "the passage text is the Akkadian, not the gloss"
    end

    def test_co_occurrence_and_cross_token_phrases
      build!
      assert_equal [DAN_2_4], search.run("king eternity").map(&:urn)
      hit = search.run('"to the king"', limit: 50).find { |result| result.urn == DAN_2_4 }
      refute_nil hit
      assert_equal %w[arc], [hit.language]
      assert_match(/\[to the king\]/, hit.snippet)
      assert_equal %w[to the king], hit.words.map(&:last), "the phrase names the token run that realizes it"
    end

    # The fold law at the query: a German gloss answers an accentless query.
    def test_german_glosses_fold_both_sides
      build!
      assert_includes search.run("konig", limit: 50).map(&:urn), KBO_24
      assert_includes search.run("König", limit: 50).map(&:urn), KBO_24
      hit = search.run("könig*", limit: 50).find { |result| result.source == "aes" }
      refute_nil hit, "Königs (aes) reaches a prefix query"
      assert_equal "egy", hit.language
      assert(hit.words.all? { |_form, gloss| gloss.match?(/könig/i) })
    end

    def test_lang_and_source_filter_inside_the_index
      build!
      assert_equal %w[arc], search.run("king", lang: "arc").map(&:language).uniq
      assert_equal %w[achemenet], search.run("king", source: "achemenet").map(&:source).uniq
      assert_empty search.run("king", source: "tlhdig")
      refute_empty search.run("king", sources: %w[tlhdig achemenet])
    end

    def test_operator_shaped_input_is_matched_literally_never_an_fts_error
      build!
      assert_kind_of Array, search.run("king NOT")
      assert_kind_of Array, search.run('king" OR "x')
      assert_empty search.run("(:)")
    end

    def test_limit_caps_the_page
      build!
      assert_equal 2, search.run("and", limit: 2).size
    end

    def test_scope_reports_what_the_build_indexed
      build!
      assert_equal %w[achemenet aes bhsa ceipom tlhdig], search.scope.map(&:first)
      assert_equal 5, search.scope.to_h.fetch("achemenet")
    end

    def test_an_absent_index_raises_the_build_hint
      refute search.available?
      assert_nil search.scope
      error = assert_raises(Nabu::Query::GlossLineSearch::IndexMissing) { search.run("king") }
      assert_match(/rake index:gloss_lines/, error.message)
    end
  end
end
