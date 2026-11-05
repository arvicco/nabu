# frozen_string_literal: true

require "test_helper"

# Query::GlossSearch — the read side of Store::GlossIndex: "every word
# glossed king", across lemmas and sources, each hit a WORD (lemma +
# upstream gloss + token count) with its first attestation's passage.
module Query
  class GlossSearchTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      { "bhsa" => Nabu::Adapters::Bhsa, "achemenet" => Nabu::Adapters::Achemenet,
        "tlhdig" => Nabu::Adapters::Tlhdig }.each do |slug, adapter|
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: adapter.name,
                                            license_class: slug == "tlhdig" ? "nc" : "open")
        Nabu::Store::Loader.new(db: @catalog, source: source)
                           .load_from(adapter.new, workdir: Nabu::TestSupport.fixtures(slug), full: true)
      end
      Nabu::Store::GlossIndex.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def teardown
      @fulltext.disconnect
    end

    def searcher = Nabu::Query::GlossSearch.new(catalog: @catalog, fulltext: @fulltext)

    def test_king_finds_words_across_lemmas_and_sources
      results = searcher.run("king")
      pairs = results.map { |r| [r.source, r.lemma, r.gloss] }

      assert_includes pairs, %w[bhsa מלך king]
      assert_includes pairs, %w[achemenet šarru king]
      sarru = results.find { |r| r.lemma == "šarru" }
      assert_operator sarru.tokens, :>=, 1
      assert_match(/\Aurn:nabu:achemenet:/, sarru.urn, "the first attestation's passage")
      refute_empty sarru.form
      assert_equal "akk", sarru.language
      assert_equal "open", sarru.license_class
    end

    def test_a_miss_is_empty
      assert_empty searcher.run("zzyzx")
      assert_empty searcher.run("...")
    end

    def test_german_folds_and_prefix_widens
      assert(searcher.run("konig").any? { |r| r.lemma == "LUGAL" && r.gloss == "König" })
      assert(searcher.run("KÖNIG").any? { |r| r.lemma == "LUGAL" })
    end

    def test_filters_ride_inside_the_match
      assert(searcher.run("king", source: "bhsa").all? { |r| r.source == "bhsa" })
      assert(searcher.run("king", sources: %w[achemenet]).all? { |r| r.source == "achemenet" })
      assert_equal %w[arc], searcher.run("king", source: "bhsa", lang: "arc").map(&:language)
      assert_empty searcher.run("könig", license: "open")
      refute_empty searcher.run("könig", license: "nc")
    end

    def test_scope_names_each_source_with_its_words_and_tokens
      scope = searcher.scope
      assert_equal %w[achemenet bhsa tlhdig], scope.map(&:first)
      assert(scope.all? { |_slug, words, tokens| words.positive? && tokens >= words })
    end

    def test_an_absent_lane_raises_the_build_hint
      @fulltext.drop_table(Nabu::Store::GlossIndex::TABLE)
      error = assert_raises(Nabu::Query::GlossSearch::IndexMissing) { searcher.run("king") }
      assert_match(/rake index:glosses/, error.message)
    end
  end
end
