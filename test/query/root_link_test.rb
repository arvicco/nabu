# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::RootLink: a Quranic token's root (Buckwalter or DMG) steps
  # to Lane's entries filed under it, through the entry facet surface's
  # derived root keys. End to end on the REAL fixtures: Lane's sample
  # through the adapter + DictionaryLoader + EntryFacetBuilder under the
  # SHIPPED facet_map keyed rule (fixture headings: ذمر 16 entries, ذمل 5,
  # ذمى 7, يتم 1, قبس 2, قبع 4, قبن 1, قبو 1, قو 1, ق 1), the Quranic
  # Arabic Corpus sample through its adapter + Loader.
  class RootLinkTest < Minitest::Test
    include StoreTestDB

    LANE = Nabu::TestSupport.fixtures("lane-lexicon")
    QAC = Nabu::TestSupport.fixtures("quranic-corpus")

    def self.facet_map
      @facet_map ||= Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
    end

    def setup
      @catalog = class_template_db do |db|
        lane = Nabu::Store::Source.create(slug: "lane-lexicon", name: "Lane", adapter_class: "Nabu::Adapters::LaneLexicon",
                                          license_class: "attribution")
        Nabu::Store::DictionaryLoader.new(db: db, source: lane)
                                     .load_from(Nabu::Adapters::LaneLexicon.new, workdir: LANE)
        qac = Nabu::Store::Source.create(slug: "quranic-corpus", name: "QAC", adapter_class: "Nabu::Adapters::QuranicCorpus",
                                         license_class: "attribution")
        Nabu::Store::Loader.new(db: db, source: qac, ledger: nil)
                           .load_from(Nabu::Adapters::QuranicCorpus.new, workdir: QAC)
        Nabu::Store::EntryFacetBuilder.rebuild!(catalog: db, facet_map: self.class.facet_map)
      end
    end

    def link = Nabu::Query::RootLink.new(catalog: @catalog)

    def test_a_buckwalter_root_reaches_its_lane_article
      result = link.lookup("*mr", scheme: :buckwalter)
      assert_equal :strict, result.tier
      assert_equal "ذمر", result.arabic
      assert_equal ["ذمر"], result.headings
      assert_equal 16, result.total
      entries = link.entries(result, limit: 3)
      assert_equal 3, entries.size
      assert(entries.all? { |entry| entry.dictionary == "lane" && entry.heading == "ذمر" })
      assert(entries.all? { |entry| entry.urn.start_with?("urn:nabu:dict:lane:") })
    end

    def test_dmg_and_buckwalter_and_arabic_reach_the_same_entries
      bw = link.lookup("*mr", scheme: :buckwalter)
      assert_equal bw.entry_ids, link.lookup("ḏmr", scheme: :dmg).entry_ids
      assert_equal bw.entry_ids, link.lookup("ذمر", scheme: :arabic).entry_ids
      assert_equal bw.entry_ids, link.lookup("ḏmr").entry_ids, "scheme detected from the characters"
      assert_equal bw.entry_ids, link.lookup("*mr").entry_ids
    end

    # Rule 1: Lane's alif-maqsura heading ذمى is QAC's y-final dmy.
    def test_rule_one_joins_alif_maqsura_strictly
      result = link.lookup("*my", scheme: :buckwalter)
      assert_equal [:strict, ["ذمى"], 7], [result.tier, result.headings, result.total]
    end

    # Rule 3 answers only a strict miss, and says so.
    def test_a_weak_radical_disagreement_joins_on_the_loose_tier
      result = link.lookup("wtm", scheme: :buckwalter)
      assert_equal [:loose, ["يتم"]], [result.tier, result.headings]
      assert_equal :strict, link.lookup("ytm", scheme: :buckwalter).tier
    end

    def test_misses_are_honest
      absent = link.lookup("ktb", scheme: :buckwalter)
      assert_nil absent.tier
      assert_equal "كتب", absent.arabic
      assert_empty link.entries(absent)

      unmapped = link.lookup("ʾūl", scheme: :dmg)
      assert_nil unmapped.tier
      assert_nil unmapped.arabic, "an unmapped character never guesses a letter"
    end

    def test_an_unbuilt_surface_reads_as_a_miss_not_a_scan
      @catalog[:entry_facets].delete
      @catalog[:entry_facet_values].delete
      refute link.built?
      assert_nil link.lookup("*mr", scheme: :buckwalter).tier
    end

    # The stored QAC tokens: every root-bearing token gets its Link, read
    # in the source's scheme; another source's tokens get none.
    def test_token_links_read_the_stored_tokens_in_the_source_scheme
      annotations = JSON.parse(@catalog[:passages].where(urn: "urn:nabu:quranic-corpus:1:1").get(:annotations_json))
      pairs = link.token_links(annotations, source: "quranic-corpus")
      assert_equal(%w[smw Alh rHm rHm], pairs.map { |token, _link| token["root"] })
      assert(pairs.all? { |_token, found| found.scheme == :buckwalter })
      assert_equal "رحم", pairs.last.last.arabic
      assert_empty link.token_links(annotations, source: "lane-lexicon")
      assert_equal :dmg, Nabu::Query::RootLink.scheme_for("corpus-coranicum")
    end

    # define --root: the Define Results of the reached entries, in order,
    # capped by limit; the define card shows the verbatim root facet only.
    def test_define_by_root_returns_full_results
      found, results = Nabu::Query::Define.new(catalog: @catalog, lila: nil).by_root("*mr", limit: 2)
      assert_equal 16, found.total
      assert_equal 2, results.size
      assert_equal link.entries(found, limit: 2).map(&:urn), results.map(&:urn)
      assert(results.all? { |result| result.facets.map(&:facet).uniq == ["root"] })

      missed, none = Nabu::Query::Define.new(catalog: @catalog, lila: nil).by_root("ktb")
      assert_nil missed.tier
      assert_empty none
    end

    def test_a_dmg_token_resolves
      annotations = { "tokens" => [{ "form" => "ذَمَرَ", "root" => "ḏmr" }, { "form" => "و" }] }
      pairs = link.token_links(annotations, source: "corpus-coranicum")
      assert_equal 1, pairs.size
      assert_equal :strict, pairs.first.last.tier
    end
  end
end
