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

    def make_passage(document, urn:, sequence: 0)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: document.language,
        text: "τ", text_normalized: "τ", content_sha256: "x", revision: 1
      )
    end

    # lects: nil — the hermeticity doctrine (P57-4): the suite never rides
    # the :auto default (box-state-dependent); the seam lane passes an
    # explicit fixture registry.
    def define(lemma, **)
      Nabu::Query::Define.new(catalog: @catalog, lects: nil).run(lemma, **)
    end

    # -- by_urn (P22-2: `show` resolves the urns `define` prints) -------------

    def test_by_urn_resolves_one_entry_with_the_define_result_shape
      row = @catalog[:dictionary_entries]
            .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
            .where(Sequel[:dictionaries][:slug] => "lsj")
            .select(Sequel[:dictionary_entries][:urn]).first
      result = Nabu::Query::Define.new(catalog: @catalog).by_urn(row[:urn])
      assert_equal row[:urn], result.urn
      assert_equal "lsj", result.dictionary_slug
      refute result.withdrawn
    end

    def test_by_urn_resolves_withdrawn_entries_honestly
      row = @catalog[:dictionary_entries].first
      @catalog[:dictionary_entries].where(id: row[:id]).update(withdrawn: true)
      result = Nabu::Query::Define.new(catalog: @catalog).by_urn(row[:urn])
      assert result, "show hides nothing — a withdrawn entry still resolves"
      assert result.withdrawn
    end

    def test_by_urn_returns_nil_on_a_miss
      assert_nil Nabu::Query::Define.new(catalog: @catalog).by_urn("urn:nabu:dict:lsj:nope")
    end

    # -- lookup ---------------------------------------------------------------

    # P37-2: och headwords (Baxter-Sagart/TLS shape) store the traditional
    # skeleton — a lookup typed in simplified (or the 説 z-glyph) reaches the
    # entry through the query_forms union, fold-both-sides.
    def test_han_variant_spellings_reach_the_och_headword
      dict = @catalog[:dictionaries].insert(source_id: @source.id, slug: "baxter-sagart",
                                            title: "Baxter-Sagart", language: "och")
      @catalog[:dictionary_entries].insert(
        dictionary_id: dict, urn: "urn:nabu:dict:baxter-sagart:shuo", entry_id: "shuo", key_raw: "說",
        headword: "說", headword_folded: Nabu::Normalize.search_form("說", language: "och"),
        gloss: "speak, explain", body: "說 body", content_sha256: "x", revision: 1, withdrawn: false
      )

      %w[說 説 说].each do |spelling|
        results = define(spelling).select { |r| r.dictionary_slug == "baxter-sagart" }
        assert_equal ["說"], results.map(&:headword),
                     "#{spelling} must reach the traditional och headword"
      end
    end

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

    # -- the Old English shelf (P12-3) ----------------------------------------

    def seed_oe_shelf
      bt = Nabu::Store::Source.create(
        slug: "bosworth-toller", name: "Bosworth-Toller",
        adapter_class: "Nabu::Adapters::BosworthToller",
        license: "CC BY 4.0", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: bt)
                                   .load_from(Nabu::Adapters::BosworthToller.new,
                                              workdir: Nabu::TestSupport.fixtures("bosworth-toller"))
    end

    # THE folding payoff: a user with an ASCII keyboard reaches æðele — and
    # the native spelling reaches it too, via the query_forms union.
    def test_defines_an_old_english_headword_typed_in_ascii
      seed_oe_shelf
      results = define("aethele", lang: "ang")
      assert_equal 1, results.size
      aethele = results.first
      assert_equal "æðele", aethele.headword
      assert_equal "noble", aethele.gloss
      assert_equal "urn:nabu:dict:bosworth-toller:940", aethele.urn
      assert_equal "bosworth-toller", aethele.dictionary_slug
      assert_equal "attribution", aethele.license_class
      assert_empty aethele.citations, "no OE crosswalk yet — citations start empty"

      assert_equal ["æðele"], define("æðele").map(&:headword), "native spelling folds the same"
    end

    def test_old_english_homographs_are_separate_entries
      seed_oe_shelf
      urns = define("ae", lang: "ang").map(&:urn)
      assert_equal %w[308 309 310], urns.map { |urn| urn.split(":").last },
                   "the three ǽ homographs all print, in entry order"
    end

    # The lemma-gloss bridge, verbatim for OE: a treebank lemma in ang carries
    # its Bosworth-Toller gloss through the same batched lookup LSJ/L&S use.
    def test_glosses_covers_old_english_lemmas
      seed_oe_shelf
      out = Nabu::Query::Define.new(catalog: @catalog).glosses([%w[æðele ang], %w[þing ang]])
      assert_equal "noble", out[%w[æðele ang]]
      assert_equal "a thing", out[%w[þing ang]]
    end

    # -- the Sanskrit shelf (P17-4): MW → GRETIL resolution ----------------------

    def seed_mw_shelf
      mw = Nabu::Store::Source.create(
        slug: "mw", name: "Monier-Williams", adapter_class: "Nabu::Adapters::Mw",
        license: "CC BY-NC-SA 3.0", license_class: "nc"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: mw)
                                   .load_from(Nabu::Adapters::Mw.new,
                                              workdir: Nabu::TestSupport.fixtures("mw"))
    end

    def seed_mvp_shelf
      mvp = Nabu::Store::Source.create(
        slug: "mvp", name: "Mahāvyutpatti", adapter_class: "Nabu::Adapters::Mvp",
        license: "PD (believed)", license_class: "open"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: mvp)
                                   .load_from(Nabu::Adapters::Mvp.new,
                                              workdir: Nabu::TestSupport.fixtures("mvp"))
    end

    # P48-r1 (D48-a, owner-ruled 2026-07-28): the curated Sanskrit
    # query-variant rule — MVP's inflected-nominative headwords
    # (bodhisattvaḥ) and MW's stems (bodhisattva) reach each other from
    # either spelling. Candidates are generated per stem class and
    # VALIDATED BY EXISTENCE (the lookup only returns real shelf entries),
    # so tapaḥ can propose both tapa and tapas without corrupting either.
    # Tier 2 (the general form→lemma table derived from DCS gold) is
    # nabu-data material, deliberately NOT built here.
    def test_sanskrit_stem_query_reaches_the_nominative_headword
      seed_mvp_shelf
      results = define("bodhisattva", lang: "san")
      assert results.any? { |r| r.urn == "urn:nabu:dict:mvp:625" },
             "the stem spelling must reach MVP's nominative entry (bodhisattvaḥ)"
    end

    def test_sanskrit_nominative_query_still_finds_its_own_entry
      seed_mvp_shelf
      results = define("bodhisattvaḥ", lang: "san")
      assert(results.any? { |r| r.urn == "urn:nabu:dict:mvp:625" })
    end

    def test_sanskrit_variant_generator_covers_the_stem_classes
      v = Nabu::Query::Define.sanskrit_stem_variants("tapaḥ")
      assert_includes v, "tapa", "a-stem candidate"
      assert_includes v, "tapas", "s-stem candidate — never blanket-stripped"
      assert_includes Nabu::Query::Define.sanskrit_stem_variants("manas"), "manaḥ"
      assert_includes Nabu::Query::Define.sanskrit_stem_variants("karman"), "karma"
      assert_includes Nabu::Query::Define.sanskrit_stem_variants("rājā"), "rājan"
      assert_includes Nabu::Query::Define.sanskrit_stem_variants("haviḥ"), "havis"
      assert_empty Nabu::Query::Define.sanskrit_stem_variants("λόγος"),
                   "non-Latin scripts generate nothing — the rule is IAST/ASCII-scoped"
    end

    # -- the nabu-data form→lemma expansion (P51-W6, D48-a tier 2) --------------

    # A minimal san shelf whose headwords are STEMS (the MW citation
    # practice): tapas and tap — the entries only the published table can
    # route an oblique form to.
    def seed_san_stem_shelf
      dict = @catalog[:dictionaries].insert(source_id: @source.id, slug: "san-stems",
                                            title: "San Stems", language: "san")
      { "tapas" => "religious austerity", "tap" => "to heat" }.each do |headword, gloss|
        @catalog[:dictionary_entries].insert(
          dictionary_id: dict, urn: "urn:nabu:dict:san-stems:#{headword}", entry_id: headword,
          key_raw: headword, headword: headword,
          headword_folded: Nabu::Normalize.search_form(headword, language: "san"),
          gloss: gloss, body: "#{headword} body", content_sha256: "x", revision: 1, withdrawn: false
        )
      end
    end

    def form_lemma_table
      @form_lemma_table ||= Nabu::FormLemma.load(Nabu::TestSupport.fixtures("nabu-data"))
    end

    def define_with_table(lemma, **)
      Nabu::Query::Define.new(catalog: @catalog, form_lemma: form_lemma_table).run(lemma, **)
    end

    # THE tier-2 payoff: tapasā (s-stem instrumental) is invisible to the
    # P48-r1 rule — with the published table live, the same query reaches
    # the tapas entry; without it, behavior is byte-identical to before.
    def test_an_oblique_form_reaches_its_stem_entry_only_through_the_table
      seed_san_stem_shelf
      rule_only = Nabu::Query::Define.new(catalog: @catalog, form_lemma: nil, lila: nil)
      assert_empty rule_only.run("tapasā", lang: "san"),
                   "the curated stem rule alone cannot map an instrumental — the honest pre-table miss"

      results = define_with_table("tapasā", lang: "san")
      assert_equal ["urn:nabu:dict:san-stems:tapas"], results.map(&:urn),
                   "the table knows tapasā → tapas; the entry is found, not invented"
    end

    def test_table_hits_are_ordinary_results_labeled_nothing_new
      seed_san_stem_shelf
      hit = define_with_table("tapasā", lang: "san").first
      assert_equal "tapas", hit.headword, "the entry's own headword — no via_ rewrite"
      assert_nil hit.via_lila, "the table feeds lookup, not attestation — nothing is labeled"
    end

    def test_a_multi_lemma_form_widens_to_every_held_candidate
      seed_san_stem_shelf
      urns = define_with_table("tapa", lang: "san").map(&:urn)
      assert_includes urns, "urn:nabu:dict:san-stems:tapas", "tapa → tapas (sandhi) candidate"
      assert_includes urns, "urn:nabu:dict:san-stems:tap", "tapa → tap (verb) candidate"
    end

    def test_the_ascii_fold_reaches_the_table_too
      seed_san_stem_shelf
      assert_equal ["urn:nabu:dict:san-stems:tapas"],
                   define_with_table("tapasa", lang: "san").map(&:urn),
                   "an ASCII keyboard reaches the table the same way it reaches the shelf"
    end

    # The language gate is a LOAD gate (the lila lat_eligible? shape): an
    # explicit non-Sanskrit --lang must never consult (or load) the table.
    def test_a_non_sanskrit_lang_never_consults_the_table
      never = Object.new
      def never.lookup(_form) = raise "the table must not be consulted for a non-Sanskrit lang"
      results = Nabu::Query::Define.new(catalog: @catalog, form_lemma: never)
                                   .run("tapasā", lang: "grc")
      assert_empty results
    end

    # -- the nabu-data verb-lemma expansion (P54-3, the Tibetan lane) -----------

    # A minimal bod shelf whose headwords are the LEMMA (present-stem)
    # citation forms — the tibetan-verbs/wiktionary-bo practice: entries
    # only the published table can route a tense stem to.
    def seed_bod_verb_shelf
      dict = @catalog[:dictionaries].insert(source_id: @source.id, slug: "bod-verbs",
                                            title: "Bod Verbs", language: "bod")
      { "འགྲོ" => "to go", "སྐྱེལ" => "to carry", "འཆོར" => "to escape" }.each do |headword, gloss|
        @catalog[:dictionary_entries].insert(
          dictionary_id: dict, urn: "urn:nabu:dict:bod-verbs:#{headword}", entry_id: headword,
          key_raw: headword, headword: headword,
          headword_folded: Nabu::Normalize.search_form(headword, language: "bod"),
          gloss: gloss, body: "#{headword} body", content_sha256: "x", revision: 1, withdrawn: false
        )
      end
    end

    def verb_lemma_table
      @verb_lemma_table ||= Nabu::VerbLemma.load(Nabu::TestSupport.fixtures("nabu-data"))
    end

    def define_with_verb_table(lemma, **)
      Nabu::Query::Define.new(catalog: @catalog, verb_lemma: verb_lemma_table).run(lemma, **)
    end

    # THE lane payoff: ཕྱིན (the suppletive past of འགྲོ) matches no
    # headword — with the published table live, the same query reaches the
    # lemma's dictionary entry; injected as nil (the absent-tree state),
    # behavior is byte-identical to before.
    def test_a_tense_stem_reaches_its_lemma_entry_only_through_the_table
      seed_bod_verb_shelf
      lane_off = Nabu::Query::Define.new(catalog: @catalog, verb_lemma: nil, lila: nil)
      assert_empty lane_off.run("ཕྱིན", lang: "bod"),
                   "no headword is the past stem — the honest pre-table miss"

      results = define_with_verb_table("ཕྱིན", lang: "bod")
      assert_equal ["urn:nabu:dict:bod-verbs:འགྲོ"], results.map(&:urn),
                   "the table knows ཕྱིན → འགྲོ; the entry is found, not invented"
      assert_equal "འགྲོ", results.first.headword, "an ordinary Result — labeled nothing new"
      assert_nil results.first.via_lila
    end

    def test_a_wylie_query_reaches_the_table_the_same_way
      seed_bod_verb_shelf
      assert_equal ["urn:nabu:dict:bod-verbs:འགྲོ"],
                   define_with_verb_table("phyin", lang: "bod").map(&:urn),
                   "Wylie and script fold to the same EWTS key (both sides)"
    end

    # A bracket-variant stem (སྐྱོལད rides GT's སྐྱོལ༼ད༽༼སྐྱོལ༽) and a
    # BRACKETED published lemma (ཤོརད → Lemma འཆོར༼ཤོར༽) both land on
    # real entries: expansion strips the notation before the shelf lookup.
    def test_bracket_variants_and_bracketed_lemmas_reach_real_entries
      seed_bod_verb_shelf
      assert_equal ["urn:nabu:dict:bod-verbs:སྐྱེལ"],
                   define_with_verb_table("སྐྱོལད", lang: "bod").map(&:urn)
      assert_equal ["urn:nabu:dict:bod-verbs:འཆོར"],
                   define_with_verb_table("ཤོརད", lang: "bod").map(&:urn),
                   "the ༼༽ notation never leaks into the folded shelf query"
    end

    # The language gate is a LOAD gate (the form_lemma san_eligible? shape):
    # a Sanskrit query must never consult (or load) the verb table.
    def test_a_sanskrit_query_never_consults_the_verb_table
      never = Object.new
      def never.lookup(_form) = raise "the verb table must not be consulted for a Sanskrit lang"
      results = Nabu::Query::Define.new(catalog: @catalog, verb_lemma: never)
                                   .run("tapasā", lang: "san")
      assert_empty results
    end

    # THE transcode payoff: ASCII "amsa" reaches both aṃśa and aṃsa — the
    # same folded shape GRETIL's IAST produces (survey §2, no fold-rule
    # change).
    def test_defines_a_sanskrit_headword_typed_in_ascii
      seed_mw_shelf
      results = define("amsa", lang: "san")
      assert_equal %w[aṃśa aṃsa], results.map(&:headword), "homographs at the fold, both print"
      assert_equal "urn:nabu:dict:mw:10", results.first.urn
      assert_equal "nc", results.first.license_class
      assert_equal "a share, portion, part, party", results.first.gloss
      assert_equal %w[aṃśa aṃsa], define("aṃśa").map(&:headword),
                   "the native IAST spelling folds the same — diacritic-insensitive BOTH sides (§9)"
    end

    # The survey's end-to-end verified citation: "RV. v, 86, 5" → the GRETIL
    # document urn + normalized citation, pada suffix probed at query time.
    def test_resolves_an_rv_citation_into_the_gretil_shelf_via_pada_probing
      seed_mw_shelf
      rgveda = make_document(urn: "urn:nabu:gretil:sa_Rgveda-edAufrecht", language: "san-Latn")
      make_passage(rgveda, urn: "urn:nabu:gretil:sa_Rgveda-edAufrecht:5.086.05a")

      citation = define("aṃśa").first.citations.find { |c| c.label == "RV. v, 86, 5" }
      assert_equal "urn:nabu:gretil:sa_Rgveda-edAufrecht:5.086.05a", citation.resolved_urn,
                   "5.086.05 has no exact passage; the pada probe finds 05a"
    end

    def test_an_exact_verse_passage_wins_over_the_pada_probe
      seed_mw_shelf
      rgveda = make_document(urn: "urn:nabu:gretil:sa_Rgveda-edAufrecht", language: "san-Latn")
      make_passage(rgveda, urn: "urn:nabu:gretil:sa_Rgveda-edAufrecht:5.086.05")
      make_passage(rgveda, urn: "urn:nabu:gretil:sa_Rgveda-edAufrecht:5.086.05a", sequence: 1)

      citation = define("aṃśa").first.citations.find { |c| c.label == "RV. v, 86, 5" }
      assert_equal "urn:nabu:gretil:sa_Rgveda-edAufrecht:5.086.05", citation.resolved_urn
    end

    # Document-grain honesty: a held single-blob work resolves to the
    # DOCUMENT urn; a bare CTS work reference keeps the old nil.
    def test_document_grain_citations_resolve_to_the_document_urn
      seed_mw_shelf
      make_document(urn: "urn:nabu:gretil:sa_pANini-aSTAdhyAyI", language: "san-Latn")

      citations = define("bhāṣ").first.citations
      pan = citations.find { |c| c.label == "Pāṇ. vii, 4, 3" }
      assert_equal "urn:nabu:gretil:sa_pANini-aSTAdhyAyI", pan.resolved_urn
      mn = citations.find { |c| c.label == "Mn." }
      assert_nil mn.resolved_urn, "Manusmṛti is not in this catalog — an honest miss"
    end

    # P34-4 (the TLS attestation crosswalk): a document-urn work that IS held
    # still resolves — to the DOCUMENT — when the cited passage is not a held
    # passage urn. TLS cites kanripo texts by (juan, page) whose pagination
    # only sometimes matches the held edition's anchors; the text-grain claim
    # stays honest when the page probe misses. Unheld works keep nil.
    def test_a_missed_passage_probe_on_a_held_document_falls_back_to_the_document_urn
      seed_mw_shelf
      make_document(urn: "urn:nabu:gretil:sa_Rgveda-edAufrecht", language: "san-Latn")

      citation = define("aṃśa").first.citations.find { |c| c.label == "RV. v, 86, 5" }
      assert_equal "urn:nabu:gretil:sa_Rgveda-edAufrecht", citation.resolved_urn,
                   "no held passage matches 5.086.05 — the held text itself is the honest resolution"
    end

    def test_mw_citations_of_unheld_works_and_authority_labels_stay_unresolved
      seed_mw_shelf
      citations = define("bhāṣ").first.citations
      assert_nil citations.find { |c| c.label == "MBh." }.resolved_urn
      assert_nil citations.find { |c| c.label == "ib." }.resolved_urn
    end

    # -- the reconstruction shelf (P14-1): the `*` convention ---------------------

    def seed_recon_shelf
      recon = Nabu::Store::Source.create(
        slug: "wiktionary-recon", name: "Wiktionary reconstructions",
        adapter_class: "Nabu::Adapters::WiktionaryRecon",
        license: "CC-BY-SA + GFDL", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: recon)
                                   .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                              workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
    end

    def test_an_asterisk_strips_and_scopes_to_the_reconstruction_shelves
      seed_recon_shelf
      results = define("*bogъ")
      assert_equal 3, results.size, "the three bogъ homographs, all sla-pro"
      assert_equal ["wiktionary-sla-pro"], results.map(&:dictionary_slug).uniq
      assert_equal "*bogъ", results.map(&:headword).uniq.first,
                   "display prefixes the asterisk back onto reconstruction headwords"
    end

    def test_an_asterisk_query_never_reaches_attested_shelves
      seed_recon_shelf
      assert_empty define("*μῆνις"), "LSJ is not a reconstruction shelf"
      assert_equal 1, define("μῆνις").size, "the plain query still is LSJ's"
    end

    # P58-6: with the Lects seam present, the recon scope is the registry's
    # mode field — a derom la-vul shelf IS a reconstruction shelf (the
    # ratified roa:pro override), which the "-pro" string test cannot see.
    # Without the seam, the string test stands byte-identically (above).
    def seed_derom_shelf
      derom = Nabu::Store::Source.create(slug: "derom", name: "DÉRom",
                                         adapter_class: "TestAdapter", license_class: "nc")
      dict = @catalog[:dictionaries].insert(source_id: derom.id, slug: "derom-etyms",
                                            title: "DÉRom", language: "la-vul")
      @catalog[:dictionary_entries].insert(
        dictionary_id: dict, urn: "urn:nabu:dict:derom-etyms:lacte", entry_id: "lacte", key_raw: "lacte",
        headword: "lacte", headword_folded: Nabu::Normalize.search_form("lacte", language: "la"),
        gloss: "milk", body: "lacte body", content_sha256: "x", revision: 1, withdrawn: false
      )
    end

    def test_recon_scope_reads_the_lects_mode_when_the_seam_is_present
      seed_derom_shelf
      registry = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"),
                                  overrides_path: File.join(Nabu::Config::PROJECT_ROOT, "config",
                                                            "lect_overrides.yml"))
      with_seam = Nabu::Query::Define.new(catalog: @catalog, lects: registry)
      assert_equal ["derom-etyms"], with_seam.run("*lacte").map(&:dictionary_slug),
                   "derom's la-vul resolves to roa:pro — mode reconstructed"
      without = Nabu::Query::Define.new(catalog: @catalog, lects: nil)
      assert_empty without.run("*lacte"),
                   "no seam -> the '-pro' string test stands, and la-vul is not '-pro'"
    end

    # P59-3: `lect:` scopes shelves at DICTIONARY grain — the (language,
    # source) resolution under the search filter's prefix semantics,
    # per-source overrides included (derom's la-vul sits under roa, never
    # lat). Module absent: loud error, never a silent no-filter.
    def test_lect_scopes_shelves_at_dictionary_grain
      seed_derom_shelf
      registry = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"),
                                  overrides_path: File.join(Nabu::Config::PROJECT_ROOT, "config",
                                                            "lect_overrides.yml"))
      scoped = Nabu::Query::Define.new(catalog: @catalog, lects: registry)
      assert_equal ["derom-etyms"], scoped.run("lacte", lect: "roa").map(&:dictionary_slug),
                   "derom's la-vul resolves to roa:pro — under the roa anchor"
      assert_empty scoped.run("lacte", lect: "lat"),
                   "the override moves the shelf OUT from under lat — no silent bare-code match"
      assert_equal ["lsj"], scoped.run("μῆνις", lect: "grc").map(&:dictionary_slug).uniq,
                   "an identity-resolving shelf scopes under its own anchor"

      error = assert_raises(Nabu::Error) do
        Nabu::Query::Define.new(catalog: @catalog, lects: nil).run("lacte", lect: "roa")
      end
      assert_match(/nabu-lects module not synced/, error.message)
    end

    def test_recon_entries_carry_reflex_views
      seed_recon_shelf
      bog = define("*bogъ").find { |r| r.urn.end_with?("bogъ:noun:2") }
      refute_empty bog.reflexes
      chu = bog.reflexes.find { |r| r.language == "chu" && r.word == "богъ" }
      refute_nil chu
      assert_nil chu.attested_count, "no fulltext handle given — honest nil"
      assert_empty define("μῆνις").first.reflexes, "attested shelves have none"
    end

    # P18-3: duplicate crosswalk rows on one entry (multi-subtree descent —
    # the prīmus ×3 defect) render ONE reflex view on the define surface
    # too — it rides the same ReflexViews grouped render as etym.
    def test_duplicate_reflex_rows_render_one_view_on_the_define_surface
      seed_recon_shelf
      entry_id = @catalog[:dictionary_entries]
                 .where(urn: "urn:nabu:dict:wiktionary-sla-pro:bogъ:noun:2").get(:id)
      chu_row = @catalog[:dictionary_reflexes]
                .where(dictionary_entry_id: entry_id, language: "chu", word: "богъ").first
      refute_nil chu_row
      dupe = chu_row.dup
      dupe.delete(:id)
      dupe[:seq] = 9_999
      @catalog[:dictionary_reflexes].insert(dupe)

      bog = define("*bogъ").find { |r| r.urn.end_with?("bogъ:noun:2") }
      views = bog.reflexes.select { |r| r.language == "chu" && r.word == "богъ" }
      assert_equal 1, views.size, "duplicate crosswalk rows must render as one reflex view"
    end

    def test_reconstruction_lang_filter_works_unstarred
      seed_recon_shelf
      assert_equal 3, define("bogъ", lang: "sla-pro").size
      assert_empty define("bogъ", lang: "grc")
    end

    def test_ascii_reconstruction_query_folds_modifier_letters
      # P14-10: the -pro shelves fold ʰ→h, ʷ→w, so an ASCII typist reaches
      # *gʷʰew- by "*gwhew-" — parity with `nabu etym gwhew` (quote the star
      # in the shell; zsh globs a bare *).
      seed_recon_shelf
      root = define("*gwhew-").first
      refute_nil root, "the ASCII fold must reach the ʷ/ʰ-bearing root"
      assert_equal "*gʷʰew-", root.headword
      assert_equal "ine-pro", root.language
    end

    # -- the LiLa variant-form fallback (P44-8) --------------------------------

    def lila_resolver
      Nabu::Lila.load(File.join(Nabu::TestSupport.fixtures("lila"), "rdf", "lemmaBank.ttl"))
    end

    # A minimal Latin dictionary entry keyed by the house lat fold, owned by
    # the lexica source (so license/class resolve).
    def make_lat_entry(headword, slug: "test-lat", gloss: "the gloss", body: "the body")
      dict = Nabu::Store::Dictionary.find(slug: slug) ||
             Nabu::Store::Dictionary.create(source_id: @source.id, slug: slug,
                                            title: "Test Latin Dictionary", language: "lat")
      Nabu::Store::DictionaryEntry.create(
        dictionary_id: dict.id, urn: "urn:nabu:dict:#{slug}:#{headword}", entry_id: headword,
        key_raw: headword, headword: headword,
        headword_folded: Nabu::Normalize.search_form(headword, language: "lat"),
        gloss: gloss, body: body, content_sha256: "x", revision: 1, withdrawn: false
      )
    end

    def define_lila(lemma, **)
      Nabu::Query::Define.new(catalog: @catalog, lila: lila_resolver).run(lemma, **)
    end

    def test_a_latin_miss_is_retried_via_the_lila_canonical_mapping
      entry = make_lat_entry("eclipsans")            # the LiLa canonical form
      results = define_lila("eclypsans")             # queried as a LiLa variant
      assert_equal 1, results.size, "the variant reaches its canonical entry via LiLa"
      hit = results.first
      assert_equal entry.urn, hit.urn
      assert_equal "eclypsans → eclipsans", hit.via_lila
      assert_equal "via LiLa: eclypsans → eclipsans", hit.headword,
                   "the provenance rides the displayed headword (the fenced CLI prints it as-is)"
    end

    def test_the_ae_oe_orthographic_variant_also_resolves
      make_lat_entry("proeliaris")
      hit = define_lila("praeliaris").first
      refute_nil hit, "praeliaris is a LiLa writtenRep of canonical proeliaris"
      assert_equal "praeliaris → proeliaris", hit.via_lila
    end

    def test_a_direct_hit_never_triggers_the_fallback
      make_lat_entry("eclipsans")
      hit = define_lila("eclipsans").first           # already the canonical form
      assert_nil hit.via_lila, "a direct dictionary hit is not a LiLa detour"
      assert_equal "eclipsans", hit.headword
    end

    def test_a_form_lila_cannot_map_stays_an_honest_miss
      make_lat_entry("eclipsans")
      assert_empty define_lila("thisisnotalatinlemma"),
                   "LiLa knows no such form — the miss stays honest"
    end

    def test_a_lila_variant_whose_canonical_is_absent_stays_an_honest_miss
      # LiLa maps amiger → hamiger, but no dictionary holds hamiger.
      make_lat_entry("eclipsans")
      assert_empty define_lila("amiger"), "no shelf entry for the canonical → honest miss"
    end

    def test_the_fallback_is_skipped_for_a_non_latin_language
      make_lat_entry("eclipsans")
      assert_empty define_lila("eclypsans", lang: "grc"),
                   "LiLa is Latin-only — a --lang grc query never detours through it"
    end

    def test_absent_lila_tree_is_byte_identical_no_fallback
      make_lat_entry("eclipsans")
      # lila: nil is exactly the no-canonical-tree state (load_default → nil).
      absent = Nabu::Query::Define.new(catalog: @catalog, lila: nil)
      assert_empty absent.run("eclypsans"), "without LiLa a variant miss is just a miss"
      assert_equal "eclipsans", absent.run("eclipsans").first.headword,
                   "and direct lookups are entirely unchanged"
    end
  end
end
