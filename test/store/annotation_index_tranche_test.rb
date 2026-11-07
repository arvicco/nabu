# frozen_string_literal: true

require "test_helper"

# The annotations lane over the declaration tranche's new shapes, loaded
# from REAL fixtures through the real Loader: suttacentral's comments (an
# HTML fragment, declared English) beside its Pali variant readings, and
# the Socinian letters' German commentary on a Latin letter. The index
# holds the layers' TEXT (never their tags), folds each by its declared
# language, and rebuilds idempotently; the read side snippets the same
# clean text.
module Store
  class AnnotationIndexTrancheTest < Minitest::Test
    include StoreTestDB

    Index = Nabu::Store::AnnotationIndex

    COMMENT = "urn:nabu:suttacentral:sn46.70:1.1"
    LETTER = "urn:nabu:socinian-letters:MAIN_dq3_2dc_b2b:7"

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      { "suttacentral" => Nabu::Adapters::Suttacentral,
        "socinian-letters" => Nabu::Adapters::SocinianLetters }.each do |slug, klass|
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: klass.name, license_class: "open")
        Nabu::Store::Loader.new(db: @catalog, source: source)
                           .load_from(klass.new, workdir: Nabu::TestSupport.fixtures(slug), full: true)
      end
    end

    def teardown
      @fulltext.disconnect
    end

    def match_ids(expression)
      @fulltext[Index::TABLE].where(Sequel.lit("passages_annotations MATCH ?", expression)).select_order_map(:rowid)
    end

    def passage_id(urn) = @catalog[:passages].where(urn: urn).get(:id)

    def scope = @fulltext[Index::SCOPE_TABLE].order(:slug).select_map(%i[slug passages])

    def test_html_comments_index_their_text_never_their_tags
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal [passage_id(COMMENT)], match_ids('"non attachment"')
      assert_empty match_ids('"href"'), "the <a href> markup is stripped before indexing"
      assert_empty match_ids('"sujato"'), "so is the link target"
      refute_empty match_ids('"amatapadam"'), "the variant readings index beside the comments"
    end

    def test_german_commentary_folds_as_german_on_a_latin_letter
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal "lat", @catalog[:passages].where(urn: LETTER).get(:language)
      assert_equal [passage_id(LETTER)], match_ids('"jener"')
      assert_empty match_ids('"iener"'), "the Latin j→i rule never reaches the German note"
    end

    def test_rebuild_and_targeted_build_are_idempotent
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      first = [@fulltext[Index::TABLE].select_order_map(:rowid), scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      assert_equal first, [@fulltext[Index::TABLE].select_order_map(:rowid), scope]

      Index.build_source!(catalog: @catalog, fulltext: @fulltext, slug: "suttacentral")
      assert_equal first, [@fulltext[Index::TABLE].select_order_map(:rowid), scope]
      assert_equal %w[socinian-letters suttacentral], scope.map(&:first)
    end

    def test_the_read_side_snippets_the_clean_comment
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      hit = Nabu::Query::AnnotationSearch.new(catalog: @catalog, fulltext: @fulltext).run("non-attachment").first

      assert_equal COMMENT, hit.urn
      assert_equal %w[pli comments], [hit.language, hit.layer]
      assert_equal "Defined at AN 10.60:11.1 as [non]-attachment.", hit.snippet,
                   "the stripped comment, earliest term bracketed — no tag soup"
    end
  end
end
