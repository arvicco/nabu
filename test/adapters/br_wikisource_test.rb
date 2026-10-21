# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # br-wikisource (P140): the dated 19th-century Breton cone. Fixture
  # envelopes are real api.php captures (2026-10-21): Odilon from Marigo's
  # Buez ar Saent (1837), Ann eostik from the 1846 Barzaz Breiz and Santes
  # Henori from Luzel's Gwerziou Breiz-Izel (1868) — admitted; the 1846
  # "/a-bezh" whole-book page (aggregate), Jezegou's 1906 Ar Vro story
  # (after_cone) and the Quellien song-book root, French prose (measured
  # foreign_language; its rendering TRIMMED at a paragraph boundary — see
  # the fixture README) skip.
  class BrWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("br-wikisource")

    def conformance_adapter = Nabu::Adapters::BrWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "br-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def envelope(pageid) = JSON.parse(File.read(File.join(FIXTURES, "pages", "#{pageid}.json")))

    def test_discovery_census
      assert_equal %w[urn:nabu:br-wikisource:123 urn:nabu:br-wikisource:16516 urn:nabu:br-wikisource:24543],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      notes = conformance_adapter.discovery_skips(FIXTURES).notes
      ["1 whole-work aggregate page(s)", "1 page(s) whose print year falls after LAST_PRINT_YEAR",
       "1 page(s) MEASURED as foreign-language"].each do |prefix|
        assert(notes.any? { |note| note.start_with?(prefix) }, "missing skip note: #{prefix}")
      end
    end

    def test_the_french_song_book_is_measured_out
      adapter = conformance_adapter
      assert_equal :foreign_language, adapter.page_class(envelope(27_457))
      breton = adapter.send(:passages_for, envelope(123)).map(&:text).join(" ")
      assert_operator adapter.foreign_share(breton), :<, 0.05, "a gwerz scores near zero"
    end

    def test_the_saints_lives_ride_their_1837_print
      odilon = doc(24_543)
      assert_equal "bre", odilon.language
      assert_equal "Eil devez a viz Guenver.", odilon.passages.first.text
      assert_equal "Year: 1837 (Marigo - Buez ar Saent.djvu)", odilon.metadata["source_date"]
      edition = odilon.metadata["index_editions"].first
      assert_equal ["Glaoda Marigo", "E. Blot", "Kemper"], edition.values_at("author", "publisher", "place")
    end

    def test_a_song_split_over_two_indexes_keeps_both
      eostik = doc(16_516)
      assert_equal 2, eostik.metadata["index_editions"].size
      assert_match(/\AYear: 1846 \(Barzaz Breiz 4e edition 1846 vol 1\.djvu\)/, eostik.metadata["source_date"])
    end

    def test_the_print_year_feeds_the_edition_date_lane
      assert_equal :edition_year_text, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["br-wikisource"]
      years = Nabu::Store::TimelineBuilder::MetadataDates.edition_year_text(doc(123).metadata)
      assert_equal [1868, 1868, "edition"], years.values_at(0, 1, 4)
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "br-wikisource", name: "Breton Wikisource",
                                          adapter_class: "Nabu::Adapters::BrWikisource", license_class: "attribution")
      load = -> { Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true) }
      assert_equal 3, load.call.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      load.call
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end
  end
end
