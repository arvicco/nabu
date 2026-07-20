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

    def define(lemma, **)
      Nabu::Query::Define.new(catalog: @catalog).run(lemma, **)
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
  end
end
