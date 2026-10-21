# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::EtymonAscent: the READING surface of migration 047's typed
  # etymon rows (inherited / derived / borrowed / learned-borrowing — the
  # UP edges that name an entry's own ancestor or donor). The shelves load
  # end-to-end from the real wiktionary-recon fixtures, whose kaikki
  # etymology templates mint those rows.
  class EtymonAscentTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = class_template_db do |db|
        recon = Nabu::Store::Source.create(
          slug: "wiktionary-recon", name: "Wiktionary reconstructions (kaikki.org)",
          adapter_class: "Nabu::Adapters::WiktionaryRecon",
          license: "CC-BY-SA + GFDL", license_class: "attribution"
        )
        Nabu::Store::DictionaryLoader.new(db: db, source: recon)
                                     .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                                workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
      end
    end

    def entry_id(urn)
      @catalog[:dictionary_entries].where(urn: urn).get(:id) || flunk("#{urn} not loaded")
    end

    def ascent(urn)
      Nabu::Query::EtymonAscent.new(catalog: @catalog).for_entry(entry_id(urn))
    end

    def add_etymon(urn:, language:, word:, folded:, relation:, seq: 999)
      @catalog[:dictionary_reflexes].insert(
        dictionary_entry_id: entry_id(urn), seq: seq, lang_code: language, language: language,
        word: word, word_folded: folded, borrowed: false, uncertain: false, relation: relation
      )
    end

    # The entry's own etymology, in the order upstream states it (nearest
    # ancestor first): Proto-Slavic *suka inherits from Proto-Balto-Slavic
    # *śaukāˀ, then PIE *ḱowk-eh₂; two derived roots follow.
    def test_lists_the_entry_s_own_etymons_in_stated_order
      steps = ascent("urn:nabu:dict:wiktionary-sla-pro:suka:noun")
      assert_equal([%w[inherited ine-bsl-pro *śaukāˀ], %w[inherited ine-pro *ḱowk-eh₂],
                    %w[derived ine-pro *ḱewk-], %w[derived ine-pro *sewH-]],
                   steps.map { |s| [s.relation, s.language, s.word] })
      assert(steps.all? { |s| s.hop.zero? }, "all four are the entry's own statement")
    end

    def test_descendant_rows_never_read_as_etymons
      steps = ascent("urn:nabu:dict:wiktionary-sla-pro:bogъ:noun:1")
      assert_equal [%w[derived ine-pro *bʰeh₂g-]], steps.map { |s| [s.relation, s.language, s.word] },
                   "the descendants tree of *bogъ stays out of its ascent"
    end

    # An etymon the shelf holds as a UNIQUE entry carries that entry's urn
    # (one `nabu show` away); a homograph-ambiguous or unheld one is nil.
    def test_resolves_an_etymon_held_on_the_shelf_to_its_entry_urn
      bog = ascent("urn:nabu:dict:wiktionary-sla-pro:bogъ:noun:1").first
      assert_equal "urn:nabu:dict:wiktionary-ine-pro:bʰeh₂g-:root", bog.urn
      suka = ascent("urn:nabu:dict:wiktionary-sla-pro:suka:noun")
      assert_nil suka.first.urn, "*śaukāˀ is not on the fixture shelf — an honest nil"
    end

    # The ASCENT: a resolved etymon's own entry states ITS etymology, which
    # continues the chain (hop 1); rows already on the chain never repeat.
    def test_climbs_through_a_resolved_etymon_s_own_etymology
      add_etymon(urn: "urn:nabu:dict:wiktionary-gem-pro:hlaibaz:noun",
                 language: "ine-pro", word: "*klóyb-os", folded: "kloyb-os", relation: "inherited")
      steps = ascent("urn:nabu:dict:wiktionary-gmw-pro:hlaib:noun")
      assert_equal([["inherited", "gem-pro", "*hlaibaz", 0], ["inherited", "ine-pro", "*klóyb-os", 1]],
                   steps.map { |s| [s.relation, s.language, s.word, s.hop] })
      assert_equal "urn:nabu:dict:wiktionary-gem-pro:hlaibaz:noun", steps.first.urn
    end

    def test_a_restated_etymon_is_not_repeated_by_the_climb
      # Middle Irish rí names Old Irish rí, whose own statement repeats the
      # Celtic and PIE etymons mga already lists.
      steps = ascent("urn:nabu:dict:wiktionary-mga:rí:noun")
      assert_equal %w[rí *rīxs *h₃rḗǵs], steps.map(&:word)
      assert_equal "urn:nabu:dict:wiktionary-sga:rí:noun", steps.first.urn
    end

    def test_a_cycle_terminates
      add_etymon(urn: "urn:nabu:dict:wiktionary-gem-pro:hlaibaz:noun",
                 language: "gmw-pro", word: "*hlaib", folded: "hlaib", relation: "borrowed")
      steps = ascent("urn:nabu:dict:wiktionary-gmw-pro:hlaib:noun")
      assert_equal ["*hlaibaz"], steps.map(&:word), "the climb never re-enters the entry it started from"
    end

    def test_an_entry_without_etymons_has_an_empty_ascent
      assert_empty ascent("urn:nabu:dict:wiktionary-ine-pro:bʰeh₂g-:root")
    end

    # -- the consumers: define and etym carry the ascent on every entry ----------

    def test_define_results_carry_the_etymon_ascent
      result = Nabu::Query::Define.new(catalog: @catalog, lects: nil).run("*suka").first ||
               flunk("*suka is on the fixture shelf")
      assert_equal %w[*śaukāˀ *ḱowk-eh₂ *ḱewk- *sewH-], result.etymons.map(&:word)
    end

    def test_etym_results_and_their_ancestors_carry_the_etymon_ascent
      results = Nabu::Query::Etym.new(catalog: @catalog, lects: nil).run("*bogъ", limit: 5)
      bog = results.find { |r| r.urn == "urn:nabu:dict:wiktionary-sla-pro:bogъ:noun:1" } ||
            flunk("the *bogъ entry with a stated etymology")
      assert_equal([%w[derived ine-pro *bʰeh₂g-]], bog.etymons.map { |s| [s.relation, s.language, s.word] })
      assert(bog.ancestors.all? { |a| a.etymons.is_a?(Array) }, "every entry on the walk answers")
    end

    def test_a_catalog_predating_the_relation_column_reads_empty
      db = Nabu::Store.connect("sqlite::memory:")
      db.create_table(:dictionary_reflexes) do
        primary_key :id
        Integer :dictionary_entry_id
      end
      assert_empty Nabu::Query::EtymonAscent.new(catalog: db).for_entry(1)
    end
  end
end
