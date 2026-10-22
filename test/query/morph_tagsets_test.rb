# frozen_string_literal: true

require "test_helper"
require "nabu/query/morph_facets"

module Query
  # The morph façade's later tagsets, END TO END: each source's REAL fixture
  # bytes go through its adapter → Store::Loader → Indexer, under the real
  # source slug (the façade's source-scoped rows key on it), and
  # LemmaSearch#run(lemma, morph:) — the `search --lemma X --morph …` surface
  # — must reach the decoded token, with the decoded evidence on the hit.
  # One test per tagset; the token named in each is the fixture's own.
  class MorphTagsetsTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    end

    def teardown
      @fulltext.disconnect
    end

    # Load +slug+'s fixture through its adapter and rebuild the index.
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

    def search(lemma, morph:)
      Nabu::Query::LemmaSearch.new(catalog: @catalog, fulltext: @fulltext).run(lemma, morph: morph, limit: 50)
    end

    # Thucydides 1.1 ξυνέγραψε (συγγράφω): "aor ind act 3rd sg".
    def test_diorisis_analyses_reach_the_morph_surface
      load_source("diorisis", "Diorisis", tier: "silver")
      hits = search("συγγράφω", morph: "tense=aor,mood=ind,person=3")
      assert_includes hits.map(&:urn), "urn:nabu:diorisis:0003:001:1"
      hit = hits.find { |result| result.urn == "urn:nabu:diorisis:0003:001:1" }
      assert_equal "person=3|number=sing|tense=aor|mood=ind|voice=act", hit.morph
      assert_empty search("συγγράφω", morph: "tense=pres")
    end

    # Dan 2:4 יְדַבְּרוּ — lex_utf8 דבר, piel wayq 3mp. The bhsa lexeme key
    # (LemmaKeys) must anchor the morph path too, not only the index.
    def test_bhsa_etcbc_features_reach_the_morph_surface
      load_source("bhsa", "Bhsa")
      hits = search("דבר", morph: "stem=piel,conjugation=wayq,number=pl")
      assert_includes hits.map(&:urn), "urn:nabu:bhsa:dan:2.4"
      hit = hits.find { |result| result.urn == "urn:nabu:bhsa:dan:2.4" }
      assert_equal "דבר", hit.lemma
      assert_match "stem=piel", hit.morph
      assert_includes search("מלך", morph: "state=emph").map(&:urn), "urn:nabu:bhsa:dan:2.4",
                      "Aramaic מַלְכָּא is emphatic"
    end

    # 4Q483 f2.1 יהי — Abegg qal wayy + juss → ETCBC wayq, mood jus.
    def test_dss_abegg_features_reach_the_morph_surface
      load_source("dss", "Dss")
      hits = search("היה", morph: "conjugation=wayq,mood=jus")
      assert_includes hits.map(&:urn), "urn:nabu:dss:4q483:f2.1"
      assert_includes search("עלל", morph: "stem=afel").map(&:urn), "urn:nabu:dss:4q156:f1.3",
                      "Abegg aphel answers the ETCBC spelling"
    end

    # Gen 1:1 בָּרָא — HVqp3ms; the augmented-Strong's lemma "1254 a".
    def test_oshb_morph_codes_reach_the_morph_surface
      load_source("oshb", "Oshb")
      hits = search("1254 a", morph: "stem=qal,conjugation=perf,person=3,gender=masc")
      assert_includes hits.map(&:urn), "urn:nabu:oshb:gen:1.1"
      assert_empty search("1254 a", morph: "stem=niphal")
    end

    # ReM m058 100v.5 ſtet (stân): Ind.Pres.Sg.3.
    def test_rem_cora_msd_reaches_the_morph_surface
      load_source("rem", "Rem")
      hits = search("stân", morph: "mood=ind,tense=pres,person=3")
      assert_includes hits.map(&:urn), "urn:nabu:rem:m058:100v.5"
    end

    # ReN Hamburg UK 1.01 se (wēsen²): Irr.3.Sg.Pres.Konj → mood sub.
    def test_ren_cora_msd_reaches_the_morph_surface
      load_source("ren", "Ren")
      hits = search("wēsen²", morph: "mood=sub,number=sg")
      assert_includes hits.map(&:urn), "urn:nabu:ren:hamb-uk-1301-1350:1.01"
    end

    # Dalmatin 1584 ab.2 isganjali (izganjati): Vmp → aspect imp.
    def test_goo300k_imp_msd_reaches_the_morph_surface
      load_source("goo300k", "Goo300k")
      hits = search("izganjati", morph: "aspect=imp")
      assert_includes hits.map(&:urn), "urn:nabu:goo300k:zrc_00001-1584:ab.2"
      assert_empty search("izganjati", morph: "aspect=perf")
    end

    # Besa, On Lack of Food: ⲙⲡⲉ tagged ANEGPST (gold) → polarity neg;
    # ⲁⲛⲟⲛ tagged PPERS → a personal pronoun.
    def test_coptic_scriptorium_tags_reach_the_morph_surface
      load_source("coptic-scriptorium", "CopticScriptorium")
      hits = search("ⲙⲡⲉ", morph: "polarity=neg")
      assert(hits.any? { |hit| hit.urn.start_with?("urn:nabu:coptic-scriptorium:besa.food.monbbb:") },
             "the besa ⲙⲡⲉ is among the gold hits")
      assert_equal ["polarity=neg"], hits.map(&:morph).uniq
      refute_empty search("ⲁⲛⲟⲛ", morph: "prontype=prs")
      assert_empty search("ⲁⲛⲟⲛ", morph: "prontype=dem")
    end

    # The CoNLL-U FEATS join: Besa's ⲧⲉⲧⲛ (lemma ⲛⲧⲱⲧⲛ, tag PPERS) carries
    # its twin's Person=2|Number=Plur — features no TT tag states.
    def test_coptic_scriptorium_joined_ud_feats_reach_the_morph_surface
      load_source("coptic-scriptorium", "CopticScriptorium")
      hits = search("ⲛⲧⲱⲧⲛ", morph: "person=2,number=pl")
      assert_includes hits.map(&:urn), "urn:nabu:coptic-scriptorium:besa.food.monbbb:1.1"
      assert_empty search("ⲛⲧⲱⲧⲛ", morph: "person=3")
    end

    # AM 1056 IX 4to 2vB.7 þarnast (þarfna): xVB fI tPS vR → inf, middle.
    def test_menota_msa_reaches_the_morph_surface
      load_source("menota", "Menota")
      hits = search("þarfna", morph: "mood=inf,voice=mid")
      assert_includes hits.map(&:urn), "urn:nabu:menota:am-1056-ix-4to:2vB.7"
    end
  end
end
