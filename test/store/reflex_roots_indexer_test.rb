# frozen_string_literal: true

require "test_helper"
require "json"

module Store
  # Nabu::Store::ReflexRootsIndexer (P15-3, design §6 + the fable closure
  # review): the derived root-closure table behind `nabu cognates`. Same rig
  # as AlignmentIndexerTest — fresh in-memory catalog, separate in-memory
  # fulltext connection. The happy-path chains load from the REAL
  # wiktionary-recon fixtures (the etym test rig); the adversarial shapes the
  # review demanded (cycle, homograph, withdrawn, same-language ascent
  # edges) are constructed store rows, since no trimmed real extract can
  # exhibit a cycle on demand.
  class ReflexRootsIndexerTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @texts = Nabu::Store::Source.create(
        slug: "texts", name: "Texts", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- rigs ---------------------------------------------------------------

    def load_recon_fixtures!
      recon = Nabu::Store::Source.create(
        slug: "wiktionary-recon", name: "Wiktionary reconstructions (kaikki.org)",
        adapter_class: "Nabu::Adapters::WiktionaryRecon",
        license: "CC-BY-SA + GFDL", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: recon)
                                   .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                              workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
    end

    def make_gold_passage(language:, lemma:, form: lemma, urn_stem: "urn:nabu:test:#{language}")
      document = Nabu::Store::Document[urn: urn_stem] || Nabu::Store::Document.create(
        source_id: @texts.id, urn: urn_stem, title: "T", language: language,
        content_sha256: "x", revision: 1, withdrawn: false
      )
      seq = @catalog[:passages].where(document_id: document.id).count
      Nabu::Store::Passage.create(
        document_id: document.id, urn: "#{urn_stem}:#{seq + 1}", sequence: seq,
        language: language, text: form, text_normalized: form,
        annotations_json: JSON.generate({ "tokens" => [{ "lemma" => lemma, "form" => form }] }),
        content_sha256: "x", revision: 1
      )
    end

    # A reconstruction shelf entry built as stored rows (for the constructed
    # adversarial shapes). Returns the entry row id.
    def make_proto_entry(dictionary:, headword:, headword_folded: headword, withdrawn: false,
                         reflexes: [])
      entry = Nabu::Store::DictionaryEntry.create(
        dictionary_id: dictionary.id, entry_id: "#{headword}:test:#{dictionary.id}",
        urn: "urn:nabu:dict:#{dictionary.slug}:#{headword}:test", key_raw: headword,
        headword: headword, headword_folded: headword_folded, body: "b",
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
      reflexes.each_with_index do |reflex, seq|
        @catalog[:dictionary_reflexes].insert(
          dictionary_entry_id: entry.id, seq: seq,
          lang_code: reflex.fetch(:language, "xx"), language: reflex[:language],
          word: reflex.fetch(:word), roman: reflex[:roman],
          word_folded: reflex.fetch(:word_folded, reflex.fetch(:word)),
          roman_folded: reflex[:roman_folded]
        )
      end
      entry
    end

    def make_dictionary(slug:, language:)
      source = Nabu::Store::Source[slug: "recon-test"] || Nabu::Store::Source.create(
        slug: "recon-test", name: "R", adapter_class: "TestAdapter", license_class: "attribution"
      )
      Nabu::Store::Dictionary.create(
        source_id: source.id, slug: slug, title: slug, language: language
      )
    end

    def rebuild!
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def roots = @fulltext[Nabu::Store::ReflexRootsIndexer::TABLE]

    def roots_for(language, lemma_folded)
      roots.where(language: language, lemma_folded: lemma_folded).select_map(:root_urn).sort
    end

    # -- the closure over the real fixtures ----------------------------------

    def test_direct_edge_maps_an_attested_lemma_to_its_owning_proto_entry
      load_recon_fixtures!
      make_gold_passage(language: "chu", lemma: "богъ")
      rebuild!
      assert_includes roots_for("chu", "богъ"), "urn:nabu:dict:wiktionary-sla-pro:bogъ:noun:2"
    end

    def test_ascent_adds_the_pie_root_one_hop_up
      load_recon_fixtures!
      make_gold_passage(language: "chu", lemma: "богъ")
      rebuild!
      assert_includes roots_for("chu", "богъ"), "urn:nabu:dict:wiktionary-ine-pro:bʰeh₂g-:root",
                      "chu богъ must reach PIE *bʰeh₂g- through sla-pro *bogъ (the design chain)"
    end

    def test_two_gold_languages_meet_at_the_shared_pie_root
      load_recon_fixtures!
      make_gold_passage(language: "chu", lemma: "богъ")
      make_gold_passage(language: "grc", lemma: "ἔφᾰγον")
      rebuild!
      meet = roots_for("chu", "богъ") &
             roots_for("grc", Nabu::Normalize.search_form("ἔφᾰγον", language: "grc"))
      assert_equal ["urn:nabu:dict:wiktionary-ine-pro:bʰeh₂g-:root"], meet,
                   "grc ἔφᾰγον and chu богъ are both PIE *bʰeh₂g- descendants — the cognate meet"
    end

    def test_the_roman_fold_bridges_gothic_script
      load_recon_fixtures!
      make_gold_passage(language: "got", lemma: "guþ")
      rebuild!
      # got guþ (roman of 𐌲𐌿𐌸) → gem-pro *gudą (direct) → ine-pro *ǵʰutós (ascent).
      assert_includes roots_for("got", "guþ"), "urn:nabu:dict:wiktionary-gem-pro:gudą:noun"
      assert_includes roots_for("got", "guþ"), "urn:nabu:dict:wiktionary-ine-pro:ǵʰutós:adj"
    end

    def test_a_loan_chain_meets_at_the_lending_shelf
      load_recon_fixtures!
      make_gold_passage(language: "chu", lemma: "цѣсар҄ь")
      make_gold_passage(language: "ang", lemma: "cāsere")
      rebuild!
      # gem-pro *kaisaraz names BOTH ang cāsere and (as a proto-to-proto edge)
      # sla-pro *cěsařь, whence cu цѣсар҄ь — so the meet is at the GERMANIC
      # shelf: a borrowing, not common descent. The root_urn's dictionary
      # language is what lets renderers say so (the fable review's rider).
      meet = roots_for("chu", Nabu::Normalize.search_form("цѣсар҄ь", language: "chu")) &
             roots_for("ang", Nabu::Normalize.search_form("cāsere", language: "ang"))
      assert_includes meet, "urn:nabu:dict:wiktionary-gem-pro:kaisaraz:noun"
    end

    # -- scoping, honesty, lifecycle -----------------------------------------

    def test_rows_are_scoped_to_gold_languages
      load_recon_fixtures!
      make_gold_passage(language: "chu", lemma: "богъ")
      rebuild!
      languages = roots.distinct.select_map(:language)
      assert_equal ["chu"], languages,
                   "modern descendant languages (ru, pl, en …) never join passage_lemmas — " \
                   "emitting rows for them is pure waste"
    end

    def test_no_gold_lemmas_means_an_empty_table_not_a_missing_one
      load_recon_fixtures!
      rebuild!
      assert @fulltext.table_exists?(Nabu::Store::ReflexRootsIndexer::TABLE)
      assert_equal 0, roots.count
    end

    def test_a_catalog_without_the_reflex_table_still_creates_the_empty_table
      # A pre-007 catalog: the build must not crash and queries must degrade
      # to "no rows", never "index missing".
      Nabu::Store::ReflexRootsIndexer.rebuild!(catalog: Sequel.sqlite, fulltext: @fulltext)
      assert @fulltext.table_exists?(Nabu::Store::ReflexRootsIndexer::TABLE)
      assert_equal 0, roots.count
    end

    def test_withdrawn_entries_contribute_no_edges_and_no_roots
      dict = make_dictionary(slug: "t-sla-pro", language: "sla-pro")
      make_proto_entry(dictionary: dict, headword: "bogъ", withdrawn: true,
                       reflexes: [{ language: "chu", word: "богъ" }])
      make_gold_passage(language: "chu", lemma: "богъ")
      rebuild!
      assert_empty roots_for("chu", "богъ"),
                   "a withdrawn entry is not on the shelf — the fable review's staleness rider"
    end

    def test_stats_table_carries_per_language_gold_passage_counts
      make_gold_passage(language: "chu", lemma: "богъ")
      make_gold_passage(language: "chu", lemma: "соль")
      make_gold_passage(language: "got", lemma: "salt")
      rebuild!
      stats = @fulltext[Nabu::Store::ReflexRootsIndexer::STATS_TABLE]
              .as_hash(:language, :gold_passages)
      assert_equal({ "chu" => 2, "got" => 1 }, stats)
    end

    def test_rebuild_is_drop_and_recreate_idempotent_and_deterministic
      load_recon_fixtures!
      make_gold_passage(language: "chu", lemma: "богъ")
      rebuild!
      first = roots.order(:language, :lemma_folded, :root_urn).all
      rebuild!
      assert_equal first, roots.order(:language, :lemma_folded, :root_urn).all
    end

    def test_indexer_rebuild_builds_reflex_roots_alongside_fts
      load_recon_fixtures!
      make_gold_passage(language: "chu", lemma: "богъ")
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      assert @fulltext.table_exists?(Nabu::Store::ReflexRootsIndexer::TABLE)
      refute_equal 0, roots.count
    end

    # -- the adversarial shapes from the fable review -------------------------

    def test_a_proto_to_proto_cycle_terminates_with_a_finite_root_set
      sla = make_dictionary(slug: "t-sla-pro", language: "sla-pro")
      gem = make_dictionary(slug: "t-gem-pro", language: "gem-pro")
      # A 2-cycle: the sla-pro entry names the gem-pro headword as a
      # descendant and vice versa (bad upstream data, but the build must not
      # blow up — the walk is depth-bounded, not visited-set-pruned).
      make_proto_entry(dictionary: sla, headword: "cyka",
                       reflexes: [{ language: "chu", word: "цыка" },
                                  { language: "gem-pro", word: "kukan" }])
      make_proto_entry(dictionary: gem, headword: "kukan",
                       reflexes: [{ language: "got", word: "kuka" },
                                  { language: "sla-pro", word: "cyka" }])
      make_gold_passage(language: "chu", lemma: "цыка")
      make_gold_passage(language: "got", lemma: "kuka")
      rebuild!
      assert_equal ["urn:nabu:dict:t-gem-pro:kukan:test", "urn:nabu:dict:t-sla-pro:cyka:test"],
                   roots_for("chu", "цыка")
      assert_equal ["urn:nabu:dict:t-gem-pro:kukan:test", "urn:nabu:dict:t-sla-pro:cyka:test"],
                   roots_for("got", "kuka")
    end

    def test_intra_shelf_derivational_edges_do_not_ascend
      # The live PIE extract holds 6,068 ine-pro→ine-pro reflex rows
      # (derivational sub-trees). Ascent must exclude same-language parents —
      # mirroring Etym#ancestors_of — or every direct PIE landing sprouts
      # phantom sibling roots (the review's required item 2).
      ine = make_dictionary(slug: "t-ine-pro", language: "ine-pro")
      make_proto_entry(dictionary: ine, headword: "der-",
                       reflexes: [{ language: "ine-pro", word: "dertos" }])
      make_proto_entry(dictionary: ine, headword: "dertos",
                       reflexes: [{ language: "grc", word: "δερτος", word_folded: "δερτοσ" }])
      make_gold_passage(language: "grc", lemma: "δερτος")
      rebuild!
      assert_equal ["urn:nabu:dict:t-ine-pro:dertos:test"], roots_for("grc", "δερτοσ"),
                   "the grc lemma lands on *dertos; *der- is an intra-shelf parent, not an ascent"
    end

    def test_homograph_proto_entries_stay_distinct_roots
      sla = make_dictionary(slug: "t-sla-pro", language: "sla-pro")
      ine = make_dictionary(slug: "t-ine-pro", language: "ine-pro")
      make_proto_entry(dictionary: sla, headword: "milъ",
                       reflexes: [{ language: "chu", word: "милъ" }])
      # TWO PIE homographs (folded-equal headwords) both naming sla-pro milъ:
      # the ascent attaches BOTH — reach inflates, roots never merge (the
      # review's restated claim b).
      two = %w[mey- mey-2].map do |hw|
        make_proto_entry(dictionary: ine, headword: hw, headword_folded: "mey-",
                         reflexes: [{ language: "sla-pro", word: "milъ" }])
      end
      make_gold_passage(language: "chu", lemma: "милъ")
      rebuild!
      expected = (["urn:nabu:dict:t-sla-pro:milъ:test"] + two.map(&:urn)).sort
      assert_equal expected, roots_for("chu", "милъ")
    end

    def test_word_and_roman_folds_deduplicate_into_one_row_set
      gem = make_dictionary(slug: "t-gem-pro", language: "gem-pro")
      make_proto_entry(dictionary: gem, headword: "saltą",
                       reflexes: [{ language: "got", word: "𐍃𐌰𐌻𐍄", word_folded: "𐍃𐌰𐌻𐍄",
                                    roman: "salt", roman_folded: "salt" }])
      make_gold_passage(language: "got", lemma: "salt")
      rebuild!
      assert_equal 1, roots.where(language: "got", lemma_folded: "salt").count,
                   "word_folded and roman_folded map through one Set — no double rows"
    end
  end
end
