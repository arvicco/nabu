# frozen_string_literal: true

require "test_helper"
require "json"

module Query
  # Nabu::Query::Etym (P14-1): the reconstruction crosswalk walk — attested
  # lemma → proto entry (reflex fold match) → cognate reflexes with corpus
  # attestation counts → proto-to-proto ascent (bounded, one hop up). The
  # shelves load end-to-end from the real wiktionary-recon fixtures; the
  # attested side is the real Indexer over store-level passages with gold
  # token annotations (the LemmaSearch rig).
  class EtymTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @recon = Nabu::Store::Source.create(
        slug: "wiktionary-recon", name: "Wiktionary reconstructions (kaikki.org)",
        adapter_class: "Nabu::Adapters::WiktionaryRecon",
        license: "CC-BY-SA + GFDL", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: @recon)
                                   .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                              workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
      @texts = Nabu::Store::Source.create(
        slug: "texts", name: "Texts", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    def make_gold_passages(language:, lemma:, form:, count: 1, urn_stem: nil)
      urn_stem ||= "urn:nabu:test:#{language}"
      document = Nabu::Store::Document.create(
        source_id: @texts.id, urn: urn_stem, title: "T", language: language,
        content_sha256: "x", revision: 1, withdrawn: false
      )
      count.times do |i|
        Nabu::Store::Passage.create(
          document_id: document.id, urn: "#{urn_stem}:#{i + 1}", sequence: i,
          language: language, text: form, text_normalized: form,
          annotations_json: JSON.generate({ "tokens" => [{ "lemma" => lemma, "form" => form }] }),
          content_sha256: "x", revision: 1
        )
      end
    end

    def rebuild!
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def etym(lemma, **)
      Nabu::Query::Etym.new(catalog: @catalog, fulltext: @fulltext).run(lemma, **)
    end

    # -- the walk: attested → proto ------------------------------------------------

    def test_walks_an_attested_ocs_lemma_to_its_proto_slavic_entry
      make_gold_passages(language: "chu", lemma: "богъ", form: "ба", count: 2)
      rebuild!
      results = etym("богъ", lang: "chu")
      assert_equal 1, results.size
      bog = results.first
      assert_equal "urn:nabu:dict:wiktionary-sla-pro:bogъ:noun:2", bog.urn
      assert_equal "*bogъ", bog.headword, "display prefixes the reconstruction asterisk"
      assert_equal "god", bog.gloss
      assert_equal "sla-pro", bog.language
      assert_equal "attribution", bog.license_class
      assert_equal "chu", bog.matched_reflex.language
      assert_equal "богъ", bog.matched_reflex.word
    end

    def test_cognates_carry_attestation_counts_for_in_catalog_lemmas
      make_gold_passages(language: "chu", lemma: "богъ", form: "ба", count: 2)
      make_gold_passages(language: "orv", lemma: "богъ", form: "богъ", count: 3)
      rebuild!
      bog = etym("богъ", lang: "chu").first
      chu = bog.cognates.find { |c| c.language == "chu" && c.word == "богъ" }
      assert_equal 2, chu.attested_count
      orv = bog.cognates.find { |c| c.language == "orv" && c.word == "богъ" }
      assert_equal 3, orv.attested_count
      ru = bog.cognates.find { |c| c.language == "ru" }
      assert_nil ru.attested_count, "not in the catalog — an honest nil, not a zero claim"
    end

    def test_duplicate_reflex_rows_render_one_view_with_merged_loan_flag
      # One word can descend from a root through several subtrees of the
      # upstream descendants data — each mints its own crosswalk row
      # (honest provenance), but the DISPLAY groups them (owner defect
      # 2026-07-13: prīmus ×3 under *per-). The loan flag merges by the
      # closure's own rule: true > false > nil.
      make_gold_passages(language: "chu", lemma: "богъ", form: "ба", count: 2)
      rebuild!
      chu_row = @catalog[:dictionary_reflexes].where(language: "chu", word: "богъ").first
      refute_nil chu_row, "fixture must hold a chu богъ reflex row"
      dupe = chu_row.dup
      dupe.delete(:id)
      dupe[:seq] = 9_999
      dupe[:borrowed] = true if @catalog[:dictionary_reflexes].columns.include?(:borrowed)
      @catalog[:dictionary_reflexes].insert(dupe)

      bog = etym("богъ", lang: "chu").first
      chu_views = bog.cognates.select { |c| c.language == "chu" && c.word == chu_row[:word] }
      assert_equal 1, chu_views.size, "duplicate crosswalk rows must render as one view"
      assert_equal true, chu_views.first.borrowed, "loan flag merges true > false > nil"
    end

    def test_gothic_walks_via_the_roman_fold_the_script_bridge
      make_gold_passages(language: "got", lemma: "guþ", form: "guþ")
      rebuild!
      results = etym("guþ", lang: "got")
      gud = results.find { |r| r.urn == "urn:nabu:dict:wiktionary-gem-pro:gudą:noun" } ||
            flunk("guþ must reach *gudą through the 𐌲𐌿𐌸 roman")
      assert_equal "*gudą", gud.headword
      got = gud.cognates.find { |c| c.language == "got" }
      assert_equal "𐌲𐌿𐌸", got.word
      assert_equal "guþ", got.roman
      assert_equal 1, got.attested_count, "counted via the roman fold"
    end

    # -- the ascent: the shelf-visited chain (P17-3) -----------------------------------

    def test_ascends_to_the_pie_ancestor_with_its_own_cognates
      make_gold_passages(language: "chu", lemma: "богъ", form: "ба")
      rebuild!
      bog = etym("богъ", lang: "chu").first
      pie = bog.ancestors.find { |a| a.headword == "*bʰeh₂g-" } ||
            flunk("PIE *bʰeh₂g- names sla-pro *bogъ in its descendants — the fixture demo chain")
      assert_equal "ine-pro", pie.language
      assert(pie.cognates.any? { |c| c.language == "grc" && c.word == "ἔφᾰγον" },
             "the PIE ancestor brings the cross-family cognates")
      assert_empty pie.ancestors,
                   "no shelf names a PIE headword — the chain ends exactly where one-hop did"
    end

    # THE multi-hop golden (P17-3): прьстъ → *pьrstъ ← *pírštan ← *per- —
    # the Proto-Balto-Slavic intermediate shelf carries the chain the old
    # one-hop cut could not render.
    def test_ascends_the_multi_hop_chain_through_proto_balto_slavic
      make_gold_passages(language: "chu", lemma: "прьстъ", form: "прьстъ")
      rebuild!
      results = etym("прьстъ", lang: "chu")
      pers = results.find { |r| r.headword == "*pьrstъ" } || flunk("*pьrstъ missing")
      pbs = pers.ancestors.find { |a| a.headword == "*pírštan" } ||
            flunk("ine-bsl-pro *pírštan names sla-pro *pь̃rstъ — the accented fold must join")
      assert_equal "ine-bsl-pro", pbs.language
      assert_equal false, pbs.edge_borrowed, "an inherited edge parsed unflagged"
      pie = pbs.ancestors.find { |a| a.headword == "*per-" } ||
            flunk("PIE *per- names ine-bsl-pro *pírštan — the chain's top")
      assert_equal "ine-pro", pie.language
      assert_empty pie.ancestors
    end

    # The loan edge (P17-3): the *hlaibaz ancestor is reached over the
    # borrowed-flagged gem→sla proto edge — edge_borrowed labels it; the
    # direct chu → *xlěbъ edge is honestly false on the matched reflex.
    def test_ancestor_reached_over_a_flagged_edge_carries_edge_borrowed
      make_gold_passages(language: "chu", lemma: "хлѣбъ", form: "хлѣбъ")
      rebuild!
      xleb = etym("хлѣбъ", lang: "chu").find { |r| r.headword == "*xlěbъ" } ||
             flunk("*xlěbъ missing")
      assert_equal false, xleb.matched_reflex.borrowed
      hlaibaz = xleb.ancestors.find { |a| a.headword == "*hlaibaz" } ||
                flunk("gem-pro *hlaibaz names sla-pro *xlěbъ (flagged) — the ascent must find it")
      assert_equal true, hlaibaz.edge_borrowed, "the loan flag rides the connecting edge"
      assert_nil xleb.edge_borrowed, "a top-level result has no connecting edge"
    end

    # P18-3: the class doc claims duplicate naming edges from ONE ancestor
    # collapse with flags merged — verify. Two reflex rows of the same
    # ancestor naming the same (language, word_folded) child (a repeated
    # node across descendant subtrees) must render ONE ancestor whose
    # edge_borrowed merges true > false > nil.
    def test_duplicate_ancestor_naming_edges_collapse_with_merged_edge_borrowed
      make_gold_passages(language: "chu", lemma: "богъ", form: "ба")
      rebuild!
      pie_id = @catalog[:dictionary_entries]
               .where(urn: "urn:nabu:dict:wiktionary-ine-pro:bʰeh₂g-:root").get(:id)
      edge = @catalog[:dictionary_reflexes]
             .where(dictionary_entry_id: pie_id, language: "sla-pro", word_folded: "bogъ").first
      refute_nil edge, "the PIE fixture entry must name sla-pro *bogъ as a descendant"
      dupe = edge.dup
      dupe.delete(:id)
      dupe[:seq] = 9_999
      dupe[:borrowed] = true if @catalog[:dictionary_reflexes].columns.include?(:borrowed)
      @catalog[:dictionary_reflexes].insert(dupe)

      ancestors = etym("богъ", lang: "chu").first.ancestors
      pies = ancestors.select { |a| a.headword == "*bʰeh₂g-" }
      assert_equal 1, pies.size, "duplicate naming edges from one ancestor collapse"
      assert_equal true, pies.first.edge_borrowed, "edge flags merge true > false > nil"
    end

    def test_gothic_ascends_to_the_pie_ancestors_of_guda
      make_gold_passages(language: "got", lemma: "guþ", form: "guþ")
      rebuild!
      gud = etym("guþ", lang: "got").find { |r| r.headword == "*gudą" }
      assert_includes gud.ancestors.map(&:headword), "*ǵʰutós"
    end

    # -- direct reconstruction lookup -------------------------------------------------

    def test_an_asterisk_query_looks_the_proto_headword_up_directly
      rebuild!
      results = etym("*bogъ")
      # (dictionary, entry_id) order: the adjective homograph sorts first
      assert_equal(%w[bogъ:adj:3 bogъ:noun:1 bogъ:noun:2],
                   results.map { |r| r.urn.split(":").last(3).join(":") })
      assert_nil results.first.matched_reflex, "no attested starting point — a direct lookup"
      assert(results.all? { |r| r.headword.start_with?("*") })
    end

    # -- bare-form fallback: the proto form typed directly (P14-10) --------------------

    def test_bare_proto_form_falls_back_to_headword_lookup_when_the_reflex_path_misses
      rebuild!
      # *gʷʰew- names no attested reflex in the catalog, so the reflex path
      # misses; unstarred input then falls back to the reconstruction shelves'
      # own headwords (the asterisk is optional — zsh globs a bare *).
      results = etym("gʷʰew-")
      assert_equal 1, results.size
      root = results.first
      assert_equal "urn:nabu:dict:wiktionary-ine-pro:gʷʰew-:root", root.urn
      assert_equal "*gʷʰew-", root.headword
      assert_nil root.matched_reflex, "a direct headword hit, not a reflex walk"
    end

    def test_bare_fallback_is_trailing_hyphen_tolerant
      rebuild!
      # Root entries store a trailing hyphen (*gʷʰew-); a bare form typed
      # without it must still reach the entry.
      assert_equal "*gʷʰew-", etym("gʷʰew").first.headword
    end

    def test_bare_fallback_resolves_a_pure_ascii_proto_form_via_the_modifier_letter_fold
      rebuild!
      # P14-10 fold: ʷ→w, ʰ→h — an ASCII typist reaches *gʷʰew- by "gwhew".
      root = etym("gwhew").first
      assert_equal "*gʷʰew-", root.headword
      assert_equal "ine-pro", root.language
    end

    def test_the_reflex_path_is_preferred_over_the_bare_fallback
      make_gold_passages(language: "chu", lemma: "богъ", form: "ба")
      rebuild!
      # богъ is an attested reflex, so the walk enters via the reflex and the
      # matched_via is preserved — the fallback fires only when reflexes miss.
      assert_equal "богъ", etym("богъ", lang: "chu").first.matched_reflex.word
    end

    def test_a_starred_query_is_still_hyphen_and_fold_tolerant
      rebuild!
      # define/etym `*` parity: the direct path folds ASCII and tolerates the
      # missing root hyphen just like the bare fallback.
      assert_equal "*gʷʰew-", etym("*gwhew").first.headword
    end

    # -- filters, bounds, graceful states ---------------------------------------------

    def test_lang_filter_scopes_the_reflex_match
      make_gold_passages(language: "chu", lemma: "богъ", form: "ба")
      rebuild!
      assert_empty etym("богъ", lang: "got")
    end

    def test_without_a_fulltext_db_counts_are_nil_but_the_walk_works
      results = Nabu::Query::Etym.new(catalog: @catalog).run("богъ", lang: "chu")
      refute_empty results
      assert(results.first.cognates.all? { |c| c.attested_count.nil? })
    end

    def test_limit_caps_the_proto_entries
      rebuild!
      assert_equal 1, etym("богъ", limit: 1).size
    end

    def test_a_catalog_without_the_reflex_table_returns_empty
      bare = Sequel.sqlite
      assert_empty Nabu::Query::Etym.new(catalog: bare).run("богъ")
    end

    def test_blank_and_unknown_lemmas_return_empty
      rebuild!
      assert_empty etym("   ")
      assert_empty etym("зззз")
    end

    # -- P24-2: the crosswalk shelf census (define/etym coordination) --------------

    # The miss message's shelf enumeration is DB-DRIVEN (the P11/P18
    # hardcoded-list lesson): distinct dictionary languages actually
    # holding reflex rows. A shelf added to the catalog appears with zero
    # code change; a prose-only dictionary (vasmer: no reflex rows) never
    # claims crosswalk membership.
    def test_crosswalk_shelves_are_db_derived_and_pick_up_a_new_shelf_without_code_change
      query = Nabu::Query::Etym.new(catalog: @catalog)
      shelves = query.crosswalk_shelves
      assert_includes shelves, "sla-pro"
      assert_includes shelves, "ine-pro"
      assert_includes shelves, "ine-bsl-pro"
      assert_equal shelves.sort, shelves, "deterministic order"

      dict_id = @catalog[:dictionaries].insert(source_id: @recon.id, slug: "new-shelf",
                                               title: "New shelf", language: "xx-pro")
      entry_id = @catalog[:dictionary_entries].insert(
        dictionary_id: dict_id, urn: "urn:nabu:dict:new-shelf:1", entry_id: "1",
        key_raw: "x", headword: "x", headword_folded: "x", body: "b",
        content_sha256: "x", revision: 1, withdrawn: false
      )
      @catalog[:dictionary_reflexes].insert(dictionary_entry_id: entry_id, seq: 0,
                                            lang_code: "yy", language: "yy",
                                            word: "y", word_folded: "y")
      assert_includes query.crosswalk_shelves, "xx-pro",
                      "a new shelf with reflex rows enumerates itself — no code change"
    end

    def test_crosswalk_shelves_are_empty_without_the_reflex_table
      assert_empty Nabu::Query::Etym.new(catalog: Sequel.sqlite).crosswalk_shelves
    end

    # -- P16-5 (a): attested wiktionary-cu entries enter the walk ------------------

    # The descendants backfill lets an sl lemma reach its ATTESTED OCS
    # ancestor entry (стопа carries no recon-fixture chain, so the cu entry
    # is the only hit) — rendered WITHOUT the reconstruction asterisk, which
    # only the -pro shelves earn.
    def test_walks_an_sl_lemma_to_its_attested_ocs_entry_without_an_asterisk
      cu = Nabu::Store::Source.create(
        slug: "wiktionary-cu", name: "Wiktionary OCS (kaikki.org)",
        adapter_class: "Nabu::Adapters::WiktionaryCu",
        license: "CC-BY-SA + GFDL", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: cu)
                                   .load_from(Nabu::Adapters::WiktionaryCu.new,
                                              workdir: Nabu::TestSupport.fixtures("wiktionary-cu"))
      make_gold_passages(language: "sl", lemma: "stopa", form: "stopa")
      rebuild!
      results = etym("stopa", lang: "sl")
      assert_equal 1, results.size
      stopa = results.first
      assert_equal "urn:nabu:dict:wiktionary-cu:стопа:noun", stopa.urn
      assert_equal "стопа", stopa.headword, "attested OCS is not a reconstruction — no asterisk"
      assert_equal "chu", stopa.language
      assert_equal "sl", stopa.matched_reflex.language
    end

    # -- P17-4: MW's own cognate notes enter the walk as a SECOND witness ----------

    # The dictionary-native comparanda (mw-survey §4): a Greek lemma cited
    # by MW s.v. aṃsa reaches the MW entry through the same reflex fold the
    # kaikki crosswalk uses — a 19th-century comparativist witness with MW
    # provenance (the owning entry's dictionary is mw), no asterisk (san is
    # attested), zero schema change.
    def test_walks_a_greek_lemma_to_the_mw_entry_that_names_it_as_comparandum
      mw = Nabu::Store::Source.create(
        slug: "mw", name: "Monier-Williams", adapter_class: "Nabu::Adapters::Mw",
        license: "CC BY-NC-SA 3.0", license_class: "nc"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: mw)
                                   .load_from(Nabu::Adapters::Mw.new,
                                              workdir: Nabu::TestSupport.fixtures("mw"))
      results = etym("ὦμος", lang: "grc")
      assert_equal 1, results.size
      amsa = results.first
      assert_equal "urn:nabu:dict:mw:88", amsa.urn
      assert_equal "mw", amsa.dictionary_slug, "MW provenance — distinct from the kaikki shelves"
      assert_equal "aṃsa", amsa.headword, "attested Sanskrit — no reconstruction asterisk"
      assert_equal "nc", amsa.license_class
      assert_equal "ὦμος", amsa.matched_reflex.word
      cognates = amsa.cognates.map { |view| [view.lang_code, view.word] }
      assert_includes cognates, %w[Goth. amsa]
      assert_includes cognates, %w[Lat. humerus]
    end

    # P18-3: MW comparanda duplicated WITHIN one entry (a 19th-century
    # entry can cite the same comparandum in several senses) ride the same
    # ReflexViews grouped render as the kaikki subtree duplicates — one
    # entry (the matched-reflex uniq), one cognate view. (MW and kaikki
    # naming the same (language, word) under DIFFERENT entries stays two
    # honest witnesses — two entries, never merged.)
    def test_duplicated_mw_comparanda_render_one_entry_with_one_cognate_view
      mw = Nabu::Store::Source.create(
        slug: "mw", name: "Monier-Williams", adapter_class: "Nabu::Adapters::Mw",
        license: "CC BY-NC-SA 3.0", license_class: "nc"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: mw)
                                   .load_from(Nabu::Adapters::Mw.new,
                                              workdir: Nabu::TestSupport.fixtures("mw"))
      amsa_id = @catalog[:dictionary_entries].where(urn: "urn:nabu:dict:mw:88").get(:id)
      omos = @catalog[:dictionary_reflexes]
             .where(dictionary_entry_id: amsa_id, word: "ὦμος").first
      refute_nil omos, "the MW fixture entry must carry the ὦμος comparandum"
      dupe = omos.dup
      dupe.delete(:id)
      dupe[:seq] = 9_999
      @catalog[:dictionary_reflexes].insert(dupe)

      results = etym("ὦμος", lang: "grc")
      assert_equal 1, results.size, "the doubled matched comparandum resolves to ONE entry"
      views = results.first.cognates.select { |view| view.word == "ὦμος" }
      assert_equal 1, views.size, "duplicated comparanda render as one view"
    end
  end
end
