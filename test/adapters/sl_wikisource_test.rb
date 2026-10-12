# frozen_string_literal: true

require "json"
require "tmpdir"
require "test_helper"
require "support/adapter_conformance"
require "support/store_test_db"

module Adapters
  # sl-wikisource (P116-2): Wikivir's year-category cone to 1899. Fixture
  # envelopes are real api.php captures (2026-10-10) — see the README.
  class SlWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("sl-wikisource")
    API = "https://sl.wikisource.org/w/api.php"

    def conformance_adapter = Nabu::Adapters::SlWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "sl-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn == "urn:nabu:sl-wikisource:#{pageid}" } || flunk("#{pageid} missing")

    def test_translations_skip_by_rule
      ids = conformance_adapter.discover(FIXTURES).map(&:id)
      refute_includes ids, "urn:nabu:sl-wikisource:37864", "Afričanka (Scribe, tr. Gangl) is a translation"
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      assert_match(/translation \(Kategorija:Prevodi\)/, skips.notes.join)
    end

    def test_year_category_is_a_typed_date
      date = doc(18_712).metadata["date"]
      assert_equal({ "not_before" => 1855, "not_after" => 1855, "raw" => "Dela leta 1855" }, date)
      assert_equal "sl", doc(18_712).language
    end

    def test_base_edition_prefers_the_publication_line
      assert_equal "Amerikanski Slovenec 11. marec 1892 (1/12), 3", doc(22_746).metadata["base_edition"],
                   "the base-edition rule: izdano verbatim (templates flattened to their display text)"
      assert_equal "Vaje 1855", doc(18_712).metadata["base_edition"], "no izdano: the spisano line"
      assert_match(/Jenko_Vaje_2|60, 61/, doc(18_712).metadata["source"])
    end

    def test_bohoricica_is_declared_never_normalized
      d = doc(35_136)
      assert_equal "bohoričica", d.metadata["orthography"]
      assert(d.passages.any? { |p| p.text.include?("Naſha domovina imá") }, "long s and zh ride verbatim")
      assert_equal "PREDGOVOR.", d.passages.find { |p| p.text.start_with?("Naſha") }.annotations["section"]
    end

    def test_dalmatin_1584_and_verse_couplets
      assert_equal 1584, doc(36_499).metadata.dig("date", "not_before")
      assert_equal "Jurij Dalmatin", doc(36_499).metadata["author"]
      poem = doc(22_746)
      assert_equal "verse", poem.metadata["grain"]
      assert_equal "Živel je nekdaj mož z ženo,", poem.passages[1].text, "the ':' indent is layout, not text"
    end

    def test_fetch_reads_the_year_cone_from_allcategories
      stub_request(:get, /#{Regexp.escape(API)}.*list=allcategories/).to_return(
        body: JSON.generate("query" => { "allcategories" => ["Dela leta 1584", "Dela leta 1899", "Dela leta 1900",
                                                             "Dela leta 1855"].map { |name| { "*" => name } } })
      )
      adapter = Nabu::Adapters::SlWikisource.new(delay: 0)
      assert_equal ["Dela leta 1584", "Dela leta 1855", "Dela leta 1899"], adapter.cone.map(&:label),
                   "the cone stops at 1899, in year order"
      assert_equal "Kategorija:Dela leta 1584", adapter.cone.first.category
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "sl-wikisource", name: "sl", license_class: "attribution",
                                          adapter_class: "Nabu::Adapters::SlWikisource")
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 4, first.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end
  end
end
