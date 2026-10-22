# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::TranslationSearch — the read side of the translations
  # lane: a query over the annotation-held translations
  # (Store::TranslationIndex) answered from the precompiled index only,
  # each hit naming the ORIGINAL passage plus the matched layer.
  class TranslationSearchTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @coptic = Nabu::Store::Source.create(slug: "coptic-scriptorium", name: "Coptic SCRIPTORIUM",
                                           adapter_class: "Nabu::Adapters::CopticScriptorium",
                                           license_class: "attribution")
      Nabu::Store::Loader.new(db: @catalog, source: @coptic)
                         .load_from(Nabu::Adapters::CopticScriptorium.new,
                                    workdir: Nabu::TestSupport.fixtures("coptic-scriptorium"), full: true)
      @cdli = Nabu::Store::Source.create(slug: "cdli", name: "CDLI", adapter_class: "Nabu::Adapters::Cdli",
                                         license_class: "open")
      Nabu::Store::Loader.new(db: @catalog, source: @cdli)
                         .load_from(Nabu::Adapters::Cdli.new, workdir: Nabu::TestSupport.fixtures("cdli"), full: true)
    end

    def teardown
      @fulltext.disconnect
    end

    def build! = Nabu::Store::TranslationIndex.rebuild!(catalog: @catalog, fulltext: @fulltext)

    def search = Nabu::Query::TranslationSearch.new(catalog: @catalog, fulltext: @fulltext)

    def test_a_translation_phrase_finds_the_original_passage_with_its_layer
      build!
      results = search.run('"brothers according to the flesh"')

      assert_equal ["urn:nabu:coptic-scriptorium:ap.100.monbeg:1.1"], results.map(&:urn)
      hit = results.first
      assert_equal "cop", hit.language
      assert_equal "translation", hit.layer
      assert_match(/\[brothers\] according to the flesh/, hit.snippet)
      refute_empty hit.text, "the original passage text rides along for the reader"
      assert_equal "attribution", hit.license_class
    end

    def test_words_are_implicitly_anded_fold_aware_and_prefixable
      build!
      assert_includes search.run("Merodach baladan").map(&:urn), "urn:nabu:cdli:p519727:a:2'"
      assert_includes search.run("merod*").map(&:urn), "urn:nabu:cdli:p519727:a:2'"
      assert_includes search.run("MARDUK").map(&:urn), "urn:nabu:cdli:p519727:a:3'"
      assert_empty search.run("merodach brothers")
    end

    def test_atf_hits_name_their_language_layer
      build!
      hit = search.run("merodach").find { |r| r.urn == "urn:nabu:cdli:p519727:a:2'" }
      assert_equal "tr.en", hit.layer
    end

    def test_lang_and_source_filter_inside_the_index
      build!
      refute_empty search.run("one", source: "cdli")
      assert_empty search.run("merodach", source: "coptic-scriptorium")
      assert_empty search.run("brothers", lang: "akk")
      refute_empty search.run("brothers", lang: "cop")
      refute_empty search.run("merodach", sources: %w[cdli ebl])
    end

    def test_license_filters_catalog_side
      build!
      assert_empty search.run("brothers", license: "open")
      refute_empty search.run("brothers", license: "attribution")
    end

    def test_limit_caps_the_page
      build!
      assert_equal 2, search.run("the", limit: 2).size
    end

    def test_operator_shaped_input_is_matched_literally_never_an_fts_error
      build!
      assert_kind_of Array, search.run("brothers NOT")
      assert_kind_of Array, search.run('flesh" OR "x')
      assert_empty search.run("(:)"), "a query folding to no word matches nothing"
    end

    def test_scope_reports_what_the_build_indexed
      build!
      scope = search.scope
      assert_equal %w[cdli coptic-scriptorium], scope.map(&:first)
      assert_operator scope.to_h.fetch("coptic-scriptorium"), :>, 100
    end

    # Desk rule: an absent index is an honest hint, never a catalog scan.
    def test_an_absent_index_raises_the_build_hint
      refute search.available?
      assert_nil search.scope
      error = assert_raises(Nabu::Query::TranslationSearch::IndexMissing) { search.run("brothers") }
      assert_match(/rake index:translations/, error.message)
    end
  end
end
