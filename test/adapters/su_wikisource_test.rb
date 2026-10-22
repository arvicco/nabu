# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # su-wikisource (P140): the dated 19th-century Sundanese cone. Fixture
  # envelopes are real api.php captures (2026-10-21): a chapter of Moehamad
  # Oemar's fish-farming wawacan (1866, Latin script) and tale X of Muhamad
  # Musa's Dongeng-Dongeng nu Araneh (1866, Cacarakan — Sundanese in
  # Javanese script, measured sun-Java), the 1926 TBG Carita Parahyangan
  # (the censused EXTRA, pinned to Old Sundanese); Meijer's Dutch
  # introduction to the Badui pantun (foreign_language) and a 1922 Poesaka
  # Soenda issue (after_cone) skip.
  class SuWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("su-wikisource")

    def conformance_adapter = Nabu::Adapters::SuWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "su-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def test_discovery_census
      assert_equal %w[urn:nabu:su-wikisource:12457 urn:nabu:su-wikisource:12797 urn:nabu:su-wikisource:98],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      notes = conformance_adapter.discovery_skips(FIXTURES).notes
      assert(notes.any? { |note| note.start_with?("1 page(s) whose print year falls after LAST_PRINT_YEAR") })
      assert(notes.any? { |note| note.start_with?("1 page(s) MEASURED as foreign-language") })
    end

    def test_language_and_script_per_page
      assert_equal "sun", doc(12_457).language
      assert_equal "Latn", doc(12_457).metadata["script"]
      assert_equal "sun-Java", doc(12_797).language, "the Cacarakan subpages are Sundanese in Javanese script"
    end

    def test_the_carita_parahyangan_rides_as_old_sundanese
      parahyangan = doc(98)
      assert_equal "osn", parahyangan.language
      assert_equal "De Tjarita Parahijangan.", parahyangan.passages.first.text
      assert_match(/\AYear: 1926 \(Tijdschrift/, parahyangan.metadata["source_date"])
    end

    def test_the_print_year_feeds_the_edition_date_lane
      assert_equal :edition_year_text, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["su-wikisource"]
      years = Nabu::Store::TimelineBuilder::MetadataDates.edition_year_text(doc(12_457).metadata)
      assert_equal [1866, 1866, "edition"], years.values_at(0, 1, 4)
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "su-wikisource", name: "Sundanese Wikisource",
                                          adapter_class: "Nabu::Adapters::SuWikisource", license_class: "attribution")
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
