# frozen_string_literal: true

require "test_helper"

module Query
  # Token glosses on the lemma-search surface, END TO END: each source's
  # REAL fixture bytes go through its adapter → Store::Loader → Indexer
  # under the real slug, then LemmaSearch#run(lemma, gloss:) — `search
  # --lemma X --gloss Y` — keeps only attestations whose upstream token
  # gloss matches, and every hit from a gloss-bearing source carries its
  # token gloss(es) for display, on the plain lemma path too.
  class TokenGlossSearchTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    end

    def teardown
      @fulltext.disconnect
    end

    def load_source(slug, adapter_class, tier: nil)
      require "nabu/adapters/#{slug.tr('-', '_')}"
      adapter = Nabu::Adapters.const_get(adapter_class).new
      source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "Nabu::Adapters::#{adapter_class}",
                                          license_class: adapter.class.manifest.license_class)
      Nabu::Store::Loader.new(db: @catalog, source: source)
                         .load_from(adapter, workdir: Nabu::TestSupport.fixtures(slug), full: true)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    lemma_tiers: tier ? { slug => tier } : {})
    end

    def search(lemma, **)
      Nabu::Query::LemmaSearch.new(catalog: @catalog, fulltext: @fulltext).run(lemma, limit: 50, **)
    end

    # The BHSA lemma key is the CONSONANTAL lexeme, so homographs merge:
    # דבר is both "speak" (Dan 2:4 יְדַבְּרוּ) and "word" (Hag 2:5 דָּבָר).
    # The token gloss splits them back apart.
    def test_bhsa_gloss_splits_a_consonantal_homograph
      load_source("bhsa", "Bhsa")
      word = search("דבר", gloss: "word")
      assert_includes word.map(&:urn), "urn:nabu:bhsa:hag:2.5"
      refute_includes word.map(&:urn), "urn:nabu:bhsa:dan:2.4", "Dan 2:4 attests only the verb"
      assert(word.all? { |hit| hit.token_gloss == "word" })
      speak = search("דבר", gloss: "speak")
      assert_includes speak.map(&:urn), "urn:nabu:bhsa:dan:2.4"
      refute_includes speak.map(&:urn), "urn:nabu:bhsa:hag:2.5"
    end

    def test_bhsa_gloss_composes_with_morph
      load_source("bhsa", "Bhsa")
      hits = search("דבר", gloss: "speak", morph: "stem=piel,conjugation=wayq")
      assert_equal %w[urn:nabu:bhsa:dan:2.4], hits.map(&:urn)
      assert_equal "speak", hits.first.token_gloss
      assert_match "conjugation=wayq", hits.first.morph
      assert_empty search("דבר", gloss: "word", morph: "conjugation=wayq")
    end

    # The plain lemma path shows the token gloss too (no filter).
    def test_plain_lemma_hits_carry_the_token_gloss
      load_source("bhsa", "Bhsa")
      hit = search("מלך").find { |result| result.urn == "urn:nabu:bhsa:dan:2.4" }
      refute_nil hit
      assert_equal "king", hit.token_gloss
      both = search("דבר").map(&:token_gloss).uniq.sort
      assert_equal %w[speak word], both
    end

    # Achemenet's silver English gloss: ša "that" vs "of" (BabyLemmatizer).
    def test_achemenet_eng_gloss
      load_source("achemenet", "Achemenet", tier: "silver")
      that = search("ša", gloss: "that")
      refute_empty that
      assert(that.all? { |hit| hit.token_gloss.split("; ").include?("that") })
      assert_includes search("eqlu").map(&:token_gloss), "field"
    end

    # AES's German contextual gloss (cotext_translation).
    def test_aes_german_gloss
      load_source("aes", "Aes")
      hits = search("ṯḥn.t", gloss: "glas")
      assert_equal 1, hits.size
      assert_equal "Fayence; Glas (aus Silicium)", hits.first.token_gloss
      assert_equal 2, search("ṯḥn.t", gloss: "fayence").size
    end

    # TLHdig's German gloss on the selected analysis: parā "aus-" vs
    # "außerdem" (KBo 20.119 line 95).
    def test_tlhdig_german_gloss
      load_source("tlhdig", "Tlhdig", tier: "silver")
      hits = search("parā", gloss: "außerdem")
      assert_equal %w[urn:nabu:tlhdig:786:hfr:kbo.20.119:95], hits.map(&:urn)
      refute_includes search("parā", gloss: "aus").map(&:urn), "urn:nabu:tlhdig:786:hfr:kbo.20.119:95"
    end

    # DSS tokens carry no gloss of their own, but lex_etcbc is the ETCBC
    # crosswalk into BHSA's lexeme space: the gloss resolves at read time
    # from a BHSA token with the same lex (and language). 11Q19 col. 10
    # line 9 עשיתמה is lex_etcbc <FH[ — BHSA's "make" (Hag 2:4 in the
    # bhsa fixture).
    def test_dss_gloss_resolves_through_the_bhsa_lexeme_crosswalk
      load_source("bhsa", "Bhsa")
      load_source("dss", "Dss")
      hit = search("עשה").find { |result| result.urn == "urn:nabu:dss:11q19:10.9" }
      refute_nil hit
      assert_equal "make", hit.token_gloss
      gate = search("שער").find { |result| result.urn == "urn:nabu:dss:11q19:10.9" }
      assert_equal "gate", gate.token_gloss
    end

    # The crosswalk joins on the EXACT lex, never the consonantal lemma
    # key: 3Q15 1:12 עד is lex_etcbc <D ("unto"), while the bhsa fixture
    # also carries the homograph <D=/ ("witness", Ruth 4:9).
    def test_dss_crosswalk_keeps_consonantal_homographs_apart
      load_source("bhsa", "Bhsa")
      load_source("dss", "Dss")
      hit = search("עד").find { |result| result.urn == "urn:nabu:dss:3q15:1.12" }
      refute_nil hit
      assert_equal "unto", hit.token_gloss
      witness = search("עד").find { |result| result.urn == "urn:nabu:bhsa:ruth:4.9" }
      assert_equal "witness", witness.token_gloss
    end

    # No BHSA in the catalog → nothing to cross into: honest absence.
    def test_dss_without_bhsa_has_no_token_gloss
      load_source("dss", "Dss")
      hit = search("עשה").find { |result| result.urn == "urn:nabu:dss:11q19:10.9" }
      refute_nil hit
      assert_nil hit.token_gloss
    end

    # A source with no registered gloss layer: the filter matches nothing,
    # plain hits carry no token gloss — honest absence.
    def test_unregistered_source_has_no_token_gloss
      load_source("oshb", "Oshb")
      refute_empty search("1254 a")
      assert(search("1254 a").all? { |hit| hit.token_gloss.nil? })
      assert_empty search("1254 a", gloss: "create")
    end

    # A blank gloss is no filter (the --morph convention); the CLI and MCP
    # surfaces refuse it before it gets here.
    def test_blank_gloss_is_no_filter
      load_source("bhsa", "Bhsa")
      assert_equal search("דבר").map(&:urn), search("דבר", gloss: " ").map(&:urn)
    end
  end
end
