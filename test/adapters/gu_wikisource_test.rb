# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # gu-wikisource (P120-3): the Gujarati bhakti cone. Fixture envelopes are
  # real api.php captures (2026-10-12): a Narsinh Mehta pada and an Akho
  # chhappa from Bruhad Kavyadohan Granth 1 (1908, admitted), a Mirabai
  # pada from the year-less Meerabai Lekhan scan (edition_unstated), and
  # Premanand's Mameru (the 1683 composition-year Index — excluded).
  class GuWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("gu-wikisource")

    def conformance_adapter = Nabu::Adapters::GuWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "gu-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def envelope(pageid) = JSON.parse(File.read(File.join(FIXTURES, "pages", "#{pageid}.json")))

    def test_discovery_census
      assert_equal %w[urn:nabu:gu-wikisource:64 urn:nabu:gu-wikisource:8229],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      notes = conformance_adapter.discovery_skips(FIXTURES).notes
      assert(notes.any? { |note| note.start_with?("1 page(s) whose edition states no year") })
      assert(notes.any? { |note| note.start_with?("1 page(s) transcluding a censused excluded Index") })
    end

    def test_a_yearless_index_cannot_pass_the_post_1930_filter
      mira = envelope(12_209)
      assert_equal :edition_unstated, conformance_adapter.page_class(mira)
      assert_empty conformance_adapter.envelope_edition_years(mira)
    end

    def test_the_composition_year_index_is_a_censused_exclusion
      mameru = envelope(7415)
      assert_equal :excluded_index, conformance_adapter.page_class(mameru)
      assert_includes Nabu::Adapters::GuWikisource::EXCLUDED_INDEXES.fetch("Mameru.pdf"), "composition year"
    end

    def test_the_index_edition_rides_verbatim
      pada = doc(8229)
      assert_equal "guj", pada.language
      assert pada.passages.first.text.start_with?("ટળતો ટળતો હીંડીશ મારે, આલિંગન દીધા વિના ક્યમ સરેરે;\n")
      assert_equal "index: Bruhad Kavyadohan Granth 1.pdf (શીર્ષક: બૃહત્ કાવ્યદોહન - ગ્રંથ ૧; " \
                   "સંપાદક: ઈચ્છારામ સૂર્યરામ દેસાઈ; વર્ષ: 1908)", pada.metadata["base_edition"]
      edition = pada.metadata["index_editions"].first
      assert_equal ["1908", "ઈચ્છારામ સૂર્યરામ દેસાઈ"], edition.values_at("year", "editor")
      assert_equal({ "author" => "નરસિંહ મહેતા" }, pada.metadata["header"])
    end

    def test_the_proofread_level_is_recorded_never_filtered
      assert_equal({ "levels" => { "3" => 1 }, "lowest_text_level" => 3 }, doc(8229).metadata["proofread"])
      assert_equal({ "levels" => { "1" => 1 }, "lowest_text_level" => 1 }, doc(64).metadata["proofread"])
    end

    def test_the_index_year_feeds_the_edition_date_lane
      shapes = Nabu::Store::TimelineBuilder::MetadataDates::SHAPES
      assert_equal :edition_year_text, shapes["gu-wikisource"]
      years = Nabu::Store::TimelineBuilder::MetadataDates.edition_year_text(doc(64).metadata)
      assert_equal [1908, 1908], years.first(2)
      assert_equal "edition", years.last
    end

    def test_an_uncensused_index_language_quarantines
      adapter = conformance_adapter
      foreign = envelope(8229)
      foreign["indexes"].first["fields"]["ભાષા"] = "hi"
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "pages"))
        File.write(File.join(dir, "pages", "8229.json"), JSON.generate(foreign))
        ref = adapter.discover(dir).first
        error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
        assert_match(/not censused/, error.message)
      end
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "gu-wikisource", name: "Gujarati Wikisource",
                                          adapter_class: "Nabu::Adapters::GuWikisource", license_class: "attribution")
      load = -> { Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true) }
      assert_equal 2, load.call.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      load.call
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end
  end
end
