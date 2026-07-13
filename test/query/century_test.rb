# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Century (P15-2, `vocab --by-century`): the diachronic histogram
  # over the date/place axis. Catalog is a fresh in-memory store; the fulltext
  # index is rebuilt with the real Indexer so the "plot this word" path is
  # exercised end to end.
  class CenturyTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @source = Nabu::Store::Source.create(
        slug: "p", name: "P", adapter_class: "T", license_class: "open"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    def seed(urn, text, not_before, not_after, place: nil, language: "grc")
      doc = Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: urn, language: language,
        content_sha256: urn, revision: 1, withdrawn: false
      )
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "#{urn}:1", sequence: 1, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        content_sha256: "#{urn}p", revision: 1, withdrawn: false
      )
      @catalog[:document_axes].insert(
        document_id: doc.id, not_before: not_before, not_after: not_after,
        precision: "x", place_name: place, axis_source: "hgv"
      )
    end

    def run_century(**)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      Nabu::Query::Century.new(catalog: @catalog, fulltext: @fulltext).run(**)
    end

    def test_buckets_the_dated_corpus_in_chronological_order
      seed("urn:a", "στρατηγος", -113, -113)
      seed("urn:b", "στρατηγος", 591, 602) # spans 6th–7th c.
      seed("urn:c", "στρατηγος", -30, 14)  # spans 1c BCE–1c CE
      result = run_century
      assert_equal ["2nd c. BCE", "1st c. BCE", "6th c. CE"], result.buckets.map(&:label)
      assert_equal [1, 1, 1], result.buckets.map(&:documents)
      assert_equal 3, result.total_documents
      assert_equal 2, result.multi_century # b (591–602) and c (-30–14) each span two centuries
    end

    def test_text_query_plots_a_word_across_centuries
      seed("urn:a", "στρατηγος αγαθος", -113, -113)
      seed("urn:b", "νομαρχης", 591, 602)
      result = run_century(query: "στρατηγος")
      assert_equal ["2nd c. BCE"], result.buckets.map(&:label)
      assert_equal "στρατηγος", result.query
    end

    def test_from_to_filter_scopes_the_histogram
      seed("urn:a", "x", -113, -113)
      seed("urn:b", "x", 591, 602)
      result = run_century(from: 500)
      assert_equal ["6th c. CE"], result.buckets.map(&:label)
    end

    def test_place_filter_scopes_the_histogram
      seed("urn:a", "x", -113, -113, place: "Oxyrhynchus")
      seed("urn:b", "x", 591, 602, place: "Arsinoites")
      result = run_century(place: "oxyrhynch%")
      assert_equal ["2nd c. BCE"], result.buckets.map(&:label)
      assert_equal 1, result.total_documents
    end

    def test_open_ended_row_buckets_by_its_known_bound
      seed("urn:a", "x", nil, -257) # notAfter-only → buckets by not_after
      result = run_century
      assert_equal ["3rd c. BCE"], result.buckets.map(&:label)
    end

    def test_undated_documents_are_absent
      Nabu::Store::Document.create(
        source_id: @source.id, urn: "urn:undated", title: "u", language: "grc",
        content_sha256: "u", revision: 1, withdrawn: false
      )
      seed("urn:a", "x", -113, -113)
      result = run_century
      assert_equal 1, result.total_documents # only the dated one
    end
  end
end
