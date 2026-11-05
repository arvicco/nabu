# frozen_string_literal: true

require "test_helper"

# The token-gloss lane of the fulltext index (Store::GlossIndex): one FTS5
# row per distinct (source, language, lemma, gloss) WORD among the live
# tokens of the sources that store upstream's own lexical gloss
# (Query::TokenGlosses), pointing back at its first attestation. Built
# from real fixtures loaded through the real Loader — the gloss and lemma
# keys are exercised against actual adapter output.
module Store
  class GlossIndexTest < Minitest::Test
    include StoreTestDB

    Index = Nabu::Store::GlossIndex
    Indexer = Nabu::Store::Indexer

    SOURCES = {
      "bhsa" => Nabu::Adapters::Bhsa,
      "achemenet" => Nabu::Adapters::Achemenet,
      "tlhdig" => Nabu::Adapters::Tlhdig
    }.freeze

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      SOURCES.each do |slug, adapter|
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: adapter.name,
                                            license_class: "open")
        Nabu::Store::Loader.new(db: @catalog, source: source)
                           .load_from(adapter.new, workdir: Nabu::TestSupport.fixtures(slug), full: true)
      end
      # An unregistered source whose tokens carry a "gloss"-shaped key
      # (tla-hf's grammatical labels are the live case): never indexed.
      other = Nabu::Store::Source.create(slug: "perseus", name: "P", adapter_class: "TestAdapter",
                                         license_class: "open")
      doc = Nabu::Store::Document.create(source_id: other.id, urn: "urn:x:1", title: "t", language: "grc",
                                         content_sha256: "x", revision: 1)
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:x:1:1", sequence: 0, language: "grc",
                                  text: "βασιλεύς", text_normalized: "βασιλευσ", content_sha256: "x", revision: 1,
                                  annotations_json: '{"tokens":[{"form":"βασιλεύς","lemma":"βασιλεύς",' \
                                                    '"gloss":"king"}]}')
    end

    def teardown
      @fulltext.disconnect
    end

    def rows = @fulltext[Index::TABLE].order(:rowid).all

    # Row identity without the rowid (a slice refresh re-inserts, so rowids
    # move; the CONTENT is the contract).
    def content = rows.map { |row| row.except(:rowid) }.sort_by(&:to_s)

    def scope = @fulltext[Index::SCOPE_TABLE].order(:slug).select_map(%i[slug words tokens])

    def match(expression)
      @fulltext[Index::TABLE].where(Sequel.lit("token_glosses MATCH ?", expression))
                             .select(:source, :lemma, :display).all
    end

    def words_for(expression) = match(expression).map { |row| [row.fetch(:lemma), row.fetch(:display)] }

    # Every glossed live token of +slug+, straight from the catalog — the
    # expected token population.
    def glossed_tokens(slug)
      @catalog[:passages].join(:documents, id: :document_id).join(:sources, id: :source_id)
                         .where(Sequel[:sources][:slug] => slug, Sequel[:passages][:withdrawn] => false)
                         .select_map(Sequel[:passages][:annotations_json])
                         .sum do |json|
                           Array(JSON.parse(json || "{}")["tokens"]).count do |token|
                             Nabu::Query::TokenGlosses.gloss(token, source: slug)
                           end
                         end
    end

    def test_king_finds_the_words_glossed_king_across_sources
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      kings = words_for('"king"')
      assert_includes kings, %w[מלך king], "bhsa's consonantal lexeme, English gloss"
      assert_includes kings, %w[šarru king], "achemenet's BabyLemmatizer English"
      refute(kings.any? { |lemma, _| lemma == "βασιλεύς" }, "an unregistered source never enters the lane")
      assert_empty match('"basileus"')
    end

    def test_german_glosses_fold_both_sides
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_includes words_for(%("#{Index.fold('König')}")), %w[LUGAL König]
      assert_includes words_for('"konig"'), %w[LUGAL König], "diacritic-insensitive"
    end

    def test_one_row_per_word_counting_its_tokens_and_pointing_at_its_first_attestation
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      keys = rows.map { |row| row.values_at(:source, :language, :lemma, :display, :form) }
      assert_equal keys.uniq.size, keys.size, "one row per distinct word"
      bhsa_rows = rows.select { |row| row[:source] == Indexer.source_token("bhsa") }
      bhsa_tokens = bhsa_rows.sum { |row| row.fetch(:tokens) }
      assert_equal glossed_tokens("bhsa"), bhsa_tokens
      king = rows.find { |row| row[:lemma] == "מלך" && row[:display] == "king" }
      passage = @catalog[:passages].where(id: king.fetch(:passage_id)).get(:annotations_json)
      token = JSON.parse(passage).fetch("tokens").fetch(king.fetch(:token))
      assert_equal "king", token.fetch("gloss"), "the pointer names the attesting token"
      assert_equal token.fetch("form"), king.fetch(:form)
      assert_operator king.fetch(:passages), :<=, king.fetch(:tokens)
    end

    def test_the_scope_records_words_and_tokens_per_source
      result = Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal SOURCES.keys.sort, scope.map(&:first)
      bhsa = scope.find { |slug, _, _| slug == "bhsa" }
      assert_equal glossed_tokens("bhsa"), bhsa.last
      assert_equal rows.size, result.fetch(:words)
      assert_equal SOURCES.size, result.fetch(:sources)
    end

    def test_language_and_source_sentinels_filter_inside_the_match
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      bhsa = Indexer.source_token("bhsa")
      # Two rows: Hebrew and Aramaic (Daniel) מלך are distinct BHSA lexemes.
      assert_equal [%w[מלך king]] * 2, words_for(%("king" AND source : ("#{bhsa}")))
      assert_equal [%w[מלך king]], words_for(%("king" AND language : ("#{Indexer.language_token('arc')}")))
      assert_empty match(%("king" AND language : ("#{Indexer.language_token('egy')}")))
      refute_empty match(%("king" AND language : ("#{Indexer.language_token('akk')}")))
    end

    def test_withdrawn_passages_stay_out
      ids = @catalog[:passages].join(:documents, id: :document_id).join(:sources, id: :source_id)
                               .where(Sequel[:sources][:slug] => "achemenet").select_map(Sequel[:passages][:id])
      @catalog[:passages].where(id: ids).update(withdrawn: true)
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      refute_includes words_for('"king"'), %w[šarru king]
      refute_includes scope.map(&:first), "achemenet"
    end

    def test_rebuild_is_idempotent
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      first = [rows, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal first, [rows, scope]
    end

    def test_a_source_refresh_reaches_the_rebuild_state_and_is_idempotent
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      bhsa = @catalog[:sources].where(slug: "bhsa").get(:id)
      @catalog[:passages].where(document_id: @catalog[:documents].where(source_id: bhsa).select(:id))
                         .update(withdrawn: true)

      2.times { Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "bhsa") }
      refreshed = [content, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal [content, scope], refreshed, "row identity: refresh == from-scratch rebuild"
      refute_includes words_for('"king"'), %w[מלך king]
    end

    def test_refresh_never_bootstraps_an_absent_lane
      assert_nil Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "bhsa")
      refute @fulltext.table_exists?(Index::TABLE)
    end

    def test_refresh_of_an_unregistered_source_is_a_no_op
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      before = [rows, scope]

      assert_nil Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "perseus")
      assert_equal before, [rows, scope]
    end

    # -- the Indexer seams: reference rebuild, sync refresh, stage reconcile --

    def test_the_reference_rebuild_builds_and_stamps_the_lane
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

      refute_empty words_for('"king"')
      assert_equal Indexer::STAGE_VERSIONS.fetch(Index::STAGE),
                   @fulltext[:stage_stamps].where(stage: Index::STAGE).get(:version)
    end

    def test_the_sync_refresh_carries_the_lane_slice
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      ids = @catalog[:passages].join(:documents, id: :document_id).join(:sources, id: :source_id)
                               .where(Sequel[:sources][:slug] => "achemenet").select_map(Sequel[:passages][:id])
      @catalog[:passages].where(id: ids).update(withdrawn: true)

      Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "achemenet")

      refute_includes words_for('"king"'), %w[šarru king]
    end

    def test_a_stale_stage_is_rederived_standalone_by_the_reconcile
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      @fulltext.drop_table(Index::TABLE)
      @fulltext[:stage_stamps].where(stage: Index::STAGE).update(version: "v0")

      redone, refusal, = Indexer.reconcile_stages!(catalog: @catalog, fulltext: @fulltext)

      assert_nil refusal
      assert_includes redone, Index::STAGE
      refute_empty words_for('"king"')
    end
  end
end
