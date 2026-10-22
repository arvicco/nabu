# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Senses (`nabu sense TERM`): passages — and the tokens in
  # them — by the sense their gold tokens cite. Runs on the REAL dcs
  # fixtures end to end: the chapters through the Dcs adapter + Loader,
  # the dcs-senses shelf through the lookup lane + DictionaryLoader, the
  # sense facet pairs through PassageFacetBuilder under the SHIPPED
  # facet_map rule. Fixture census: 215 WordSem tokens on 5 passages, 121
  # distinct ids; Su. 35 sentence 2612 carries 25 aṅgula tokens citing
  # 59344 "finger" and sthaulyāni's two ids 25248,25258.
  class SensesTest < Minitest::Test
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("dcs")
    ANGULA = "urn:nabu:dcs:5:3363:2612"

    def setup
      @catalog = class_template_db do |db|
        source = Nabu::Store::Source.create(slug: "dcs", name: "DCS", adapter_class: "Nabu::Adapters::Dcs",
                                            license_class: "attribution")
        Nabu::Store::Loader.new(db: db, source: source, ledger: nil)
                           .load_from(Nabu::Adapters::Dcs.new, workdir: FIXTURES)
        Nabu::Store::DictionaryLoader.new(db: db, source: source)
                                     .load_from(Nabu::Adapters::DcsLexiconLane.new, workdir: FIXTURES)
        Nabu::Store::PassageFacetBuilder.rebuild!(catalog: db, facet_map: self.class.facet_map)
      end
    end

    def self.facet_map
      @facet_map ||= Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
    end

    def senses = Nabu::Query::Senses.new(catalog: @catalog, facet_map: self.class.facet_map)

    # A known WordSem id resolves to its dcs-senses entry: name, gloss, urn.
    def test_a_sense_id_resolves_against_the_shelf
      result = senses.run("59344")
      assert_equal 1, result.sense_total
      finger = result.senses.first
      assert_equal %w[59344 finger dcs-senses], [finger.id, finger.headword, finger.shelf]
      assert_equal "the length of breadth of a finger used as a linear measure", finger.gloss
      assert_equal "urn:nabu:dict:dcs-senses:59344", finger.urn
      assert_equal 1, finger.passages
      assert_equal 1, result.passage_total
    end

    # The hit names the TOKENS citing the sense — read back off the stored
    # tokens, every one of them (the pair itself is passage grain).
    def test_hits_carry_the_tokens_that_cite_the_sense
      hit = only(senses.run("59344").hits)
      assert_equal ANGULA, hit.urn
      assert_equal 25, hit.tokens.size
      assert_equal %w[aṅgula], hit.tokens.map(&:lemma).uniq
      assert_includes hit.tokens.map(&:form), "aṅgulāni"
      assert(hit.tokens.all? { |token| token.ids == %w[59344] })
    end

    def test_a_sense_name_finds_the_same_passages_as_its_id
      by_name = senses.run("finger")
      assert_equal %w[59344], by_name.senses.map(&:id)
      assert_equal [ANGULA], by_name.hits.map(&:urn)
      assert_equal %w[128218], senses.run("dhanvantari").senses.map(&:id), "case-insensitive name match"
    end

    def test_gloss_mode_matches_inside_the_gloss
      assert_empty senses.run("linear measure").senses, "plain mode matches the sense NAME only"
      assert_equal %w[59344], senses.run("linear measure", gloss: true).senses.map(&:id)
      assert_equal %w[128218], senses.run("physician of the gods", gloss: true).senses.map(&:id)
    end

    # Multi-id tokens are kept: sthaulyāni cites circumference AND
    # thickness, and either sense finds it.
    def test_a_multi_id_token_answers_for_each_of_its_senses
      %w[25258 thickness].each do |term|
        hit = only(senses.run(term).hits)
        assert_equal ANGULA, hit.urn, term
        assert_equal [%w[sthaulyāni 25248 25258]], hit.tokens.map { |token| [token.form, *token.ids] }, term
      end
      circumference = only(senses.run("circumference").hits)
      assert_equal %w[pariṇāhāni sthaulyāni pariṇāha pariṇāhau pariṇāham pariṇāhā], circumference.tokens.map(&:form),
                   "every citing token, in sentence order"
    end

    def test_several_ids_and_a_name_pattern_widen_the_match
      result = senses.run("25248,25258")
      assert_equal %w[25248 25258], result.senses.map(&:id).sort
      assert_equal 1, result.passage_total
      assert_equal %w[circumference], senses.run("circum%").senses.map(&:headword)
    end

    # An id the shelf does not hold still finds its passages; the sense is
    # labelled unresolved, never dropped (the fixture shelf is a trim).
    def test_an_unheld_id_is_found_and_labelled_unresolved
      result = senses.run("88425")
      sense = only(result.senses)
      assert_nil sense.headword
      assert_equal "dcs-senses", sense.shelf
      assert_equal ["urn:nabu:dcs:5:3363:2588"], result.hits.map(&:urn)
      assert_equal %w[vyākhyā], result.hits.first.tokens.map(&:lemma)
    end

    def test_no_match_is_an_empty_result
      result = senses.run("zzzz-no-such-sense")
      assert_equal [0, 0], [result.sense_total, result.passage_total]
      assert_empty result.hits
    end

    def test_limit_caps_the_hits_not_the_totals
      result = senses.run("%", limit: 2)
      assert_equal 2, result.hits.size
      assert_equal 3, result.passage_total, "the Su. 35 passages citing a sense the trimmed shelf holds"
    end

    def test_census_counts_senses_passages_and_pairs_per_source
      row = only(senses.census)
      assert_equal ["dcs", 121, 5, 121], [row.source, row.senses, row.passages, row.pairs]
    end

    def test_entries_for_resolves_ids_against_the_shelves
      entries = senses.entries_for(%w[30125 128793 88425])
      assert_equal "chapter", entries.fetch("30125").headword
      assert_equal "Āturopakramaṇīya", entries.fetch("128793").headword
      refute entries.key?("88425")
    end

    # The facet surface's generic filter reaches the same pairs: a sense id
    # composes with search/browse as `--facet sense=ID`.
    def test_the_sense_facet_composes_with_the_shared_facet_filter
      search = Nabu::Query::Search.new(catalog: @catalog, fulltext: nil, lects: nil)
      assert_equal [ANGULA], search.browse(facets: { "sense" => "59344" }).map(&:urn)
      assert_equal [ANGULA], search.browse(facets: { "sense" => "urn:nabu:dict:dcs-senses:25258" }).map(&:urn)
    end

    def test_an_unbuilt_index_is_an_honest_error
      @catalog[:passage_facets].delete
      @catalog[:passage_facet_values].delete
      error = assert_raises(Nabu::Query::Senses::Error) { senses.run("finger") }
      assert_match(/sense index is not built yet — run `bundle exec rake builders:refresh`/, error.message)
    end

    # A catalog whose dcs-senses shelf is absent (the slug no longer names
    # a loaded dictionary).
    def test_a_name_lookup_without_the_shelf_says_so
      @catalog[:dictionaries].where(slug: "dcs-senses").update(slug: "not-the-shelf")
      error = assert_raises(Nabu::Query::Senses::Error) { senses.run("finger") }
      assert_match(/no sense shelf is loaded \(dcs-senses\)/, error.message)
      assert_equal [ANGULA], senses.run("59344").hits.map(&:urn), "an id still answers from the facet pairs"
    end

    private

    def only(items)
      assert_equal 1, items.size, items.inspect
      items.first
    end
  end
end
