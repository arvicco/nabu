# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Vocab (P14-3). Same rig as LemmaSearch/Search: a fresh
  # in-memory catalog, a separate in-memory fulltext, the index rebuilt with
  # the real Indexer — so the profile runs the true annotation → fold →
  # corpus-frequency path end to end. The fixture is a small treebank-shaped
  # document (a distinctive lemma repeated, two hapax) over a background corpus,
  # so the distinctiveness metric is exercised, not just the counting.
  class VocabTest < Minitest::Test
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

    # -- helpers -------------------------------------------------------------

    def make_document(urn:, title: "Doc", language: "lat", withdrawn: false)
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: title, language: language,
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    # +lemmas+ is a flat list of lemma strings (each becomes one token; repeats
    # allowed so a passage can attest a lemma twice). No lemmas → an
    # un-annotated passage (annotations "{}"-shaped, the non-treebank majority).
    def make_passage(document, urn:, sequence:, language: "lat", lemmas: [], withdrawn: false)
      tokens = lemmas.map { |lemma| { "lemma" => lemma, "form" => lemma } }
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: lemmas.join(" "), text_normalized: Nabu::Normalize.search_form(lemmas.join(" "), language: language),
        annotations_json: JSON.generate({ "tokens" => tokens }),
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def rebuild!
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def vocab(urn, **)
      Nabu::Query::Vocab.new(catalog: @catalog, fulltext: @fulltext).run(urn, **)
    end

    # A background corpus (40 passages of "et"/"sum") plus a target document:
    # "hostis" repeated across six passages (distinctive here, attested nowhere
    # else), "et" in three (common corpus-wide), and two singletons.
    def seed_corpus
      bg = make_document(urn: "urn:d:bg", title: "Background")
      40.times { |i| make_passage(bg, urn: "urn:d:bg:#{i}", sequence: i, lemmas: %w[et sum]) }

      doc = make_document(urn: "urn:d:lat", title: "Bellum")
      make_passage(doc, urn: "urn:d:lat:1", sequence: 1, lemmas: %w[hostis et unicus])
      make_passage(doc, urn: "urn:d:lat:2", sequence: 2, lemmas: %w[hostis et rarus])
      make_passage(doc, urn: "urn:d:lat:3", sequence: 3, lemmas: %w[hostis et])
      make_passage(doc, urn: "urn:d:lat:4", sequence: 4, lemmas: %w[hostis])
      make_passage(doc, urn: "urn:d:lat:5", sequence: 5, lemmas: %w[hostis])
      make_passage(doc, urn: "urn:d:lat:6", sequence: 6, lemmas: %w[hostis])
      rebuild!
      doc
    end

    # -- counting ------------------------------------------------------------

    def test_totals_count_gold_tokens_and_distinct_lemmas
      seed_corpus
      profile = vocab("urn:d:lat")

      assert_equal :document, profile.kind
      assert_equal "Bellum", profile.title
      assert_equal 6, profile.passages
      assert_equal 6, profile.annotated_passages
      # 6 hostis + 3 et + unicus + rarus = 11 gold tokens, 4 distinct lemmas.
      assert_equal 11, profile.total_tokens
      assert_equal 4, profile.distinct_lemmas
    end

    def test_hapax_are_the_lemmas_attested_exactly_once
      seed_corpus
      profile = vocab("urn:d:lat")

      assert_equal 2, profile.hapax_count
      assert_equal %w[rarus unicus], profile.hapax, "sorted; hostis (6×) and et (3×) are not hapax"
    end

    # -- the distinctiveness metric (the reason for log-odds over simple ratio) -

    def test_distinctive_ranks_the_repeated_local_lemma_first
      seed_corpus
      profile = vocab("urn:d:lat")

      assert_equal "hostis", profile.distinctive.first.lemma,
                   "repeated-and-local beats both the corpus-common (et) and the singletons"
      top = profile.distinctive.first
      assert_equal 6, top.doc_count
      assert_equal 6, top.corpus_freq, "hostis is attested only in this document"
    end

    def test_log_odds_damps_singletons_below_the_repeated_lemma
      seed_corpus
      scored = vocab("urn:d:lat").distinctive.to_h { |e| [e.lemma, e.score] }

      # A plain frequency ratio would float unicus/rarus (doc 1, corpus 1) to the
      # top; the z-score's variance penalty keeps them under hostis.
      assert_operator scored.fetch("hostis"), :>, scored.fetch("unicus")
      assert_operator scored.fetch("hostis"), :>, scored.fetch("et"),
                      "hostis is over-represented here; et is corpus-common"
    end

    def test_limit_caps_the_distinctive_list_and_hapax
      seed_corpus
      profile = vocab("urn:d:lat", limit: 1)

      assert_equal 1, profile.distinctive.size
      assert_equal "hostis", profile.distinctive.first.lemma
      # The full hapax list is still carried (the CLI caps the print), so the
      # count stays honest regardless of the display limit.
      assert_equal 2, profile.hapax_count
    end

    # -- scopes: range and single passage ------------------------------------

    def test_range_profiles_only_the_slice
      seed_corpus
      profile = vocab("urn:d:lat:1-3")

      assert_equal :range, profile.kind
      assert_equal 3, profile.passages
      # passages 1..3: hostis×3, et×3, unicus×1, rarus×1 = 8 tokens.
      assert_equal 8, profile.total_tokens
      assert_equal %w[rarus unicus], profile.hapax
    end

    def test_single_passage_urn_profiles_that_passage
      seed_corpus
      profile = vocab("urn:d:lat:1")

      assert_equal :passage, profile.kind
      assert_equal 1, profile.passages
      assert_equal 3, profile.total_tokens, "hostis, et, unicus"
      assert_equal 3, profile.distinct_lemmas
    end

    # -- honest coverage -----------------------------------------------------

    def test_document_without_gold_lemmas_reports_plainly
      seed_corpus
      bare = make_document(urn: "urn:d:bare", title: "Unannotated Poem", language: "ang")
      3.times { |i| make_passage(bare, urn: "urn:d:bare:#{i}", sequence: i, language: "ang", lemmas: []) }
      # No rebuild needed for the target (it has no lemmas), but the index must
      # already hold the gold corpus so the honest list can name its languages.

      profile = vocab("urn:d:bare")

      assert_equal 0, profile.total_tokens
      assert_equal 0, profile.distinct_lemmas
      assert_empty profile.distinctive
      assert_empty profile.hapax
      refute_nil profile.gold_languages, "the no-gold path names the gold-bearing languages"
      assert_includes profile.gold_languages.map(&:first), "lat",
                      "the fixture corpus's gold lemmas are Latin"
    end

    # -- P26-4: the lemma tier (labeled profile, gold reference corpus) --------

    def silver_source
      @silver_source ||= Nabu::Store::Source.create(
        slug: "diorisis", name: "Diorisis", adapter_class: "TestAdapter",
        license_class: "attribution"
      )
    end

    def make_silver_document(urn:, title: "Silver")
      Nabu::Store::Document.create(
        source_id: silver_source.id, urn: urn, title: title, language: "grc",
        content_sha256: "x", revision: 1, withdrawn: false
      )
    end

    def silver_rebuild!
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    lemma_tiers: { "diorisis" => "silver" })
    end

    def test_a_gold_document_carries_the_gold_tier_label
      seed_corpus
      assert_equal "gold", vocab("urn:d:lat").lemma_tier
    end

    def test_a_silver_document_profiles_labeled_never_as_gold
      seed_corpus # gold background (built again below with tiers threaded)
      doc = make_silver_document(urn: "urn:d:silver")
      make_passage(doc, urn: "urn:d:silver:1", sequence: 1, language: "grc",
                        lemmas: %w[θεός θεός λόγος])
      silver_rebuild!
      profile = vocab("urn:d:silver")
      assert_equal "silver", profile.lemma_tier,
                   "the profile of an automatic-lemmatization document says so"
      assert_equal 3, profile.total_tokens, "silver documents DO profile — that is the value"
      assert_equal 2, profile.distinct_lemmas
    end

    def test_corpus_reference_frequencies_are_gold_scoped
      seed_corpus # gold "et" df = 43 (40 background + 3 in the document)
      doc = make_silver_document(urn: "urn:d:silver")
      make_passage(doc, urn: "urn:d:silver:1", sequence: 1, language: "grc", lemmas: %w[et])
      silver_rebuild!
      profile = vocab("urn:d:lat")
      et = profile.distinctive.find { |e| e.lemma == "et" } || flunk("et entry missing")
      assert_equal 43, et.corpus_freq,
                   "the reference corpus stays gold — the silver row must not lift et to 44"
    end

    def test_gold_languages_listing_is_gold_scoped
      seed_corpus
      doc = make_silver_document(urn: "urn:d:silver")
      make_passage(doc, urn: "urn:d:silver:1", sequence: 1, language: "grc", lemmas: %w[θεός])
      empty = make_document(urn: "urn:d:empty", title: "No lemmas")
      make_passage(empty, urn: "urn:d:empty:1", sequence: 1)
      silver_rebuild!
      profile = vocab("urn:d:empty")
      assert_equal ["lat"], profile.gold_languages.map(&:first),
                   "the listing's own label says GOLD-bearing — silver-only grc must not appear"
    end

    def test_withdrawn_passages_are_excluded_from_the_profile
      doc = make_document(urn: "urn:d:w")
      make_passage(doc, urn: "urn:d:w:1", sequence: 1, lemmas: %w[hostis])
      make_passage(doc, urn: "urn:d:w:2", sequence: 2, lemmas: %w[hostis], withdrawn: true)
      rebuild!

      profile = vocab("urn:d:w")
      assert_equal 1, profile.total_tokens, "the withdrawn passage's token is not counted"
    end

    def test_unknown_urn_raises_not_found
      seed_corpus
      error = assert_raises(Nabu::Query::Vocab::NotFound) { vocab("urn:d:nope") }
      assert_match(/urn not found/, error.message)
    end
  end
end
