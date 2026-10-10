# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "support/store_test_db"

module Adapters
  # bg-wikisource (P116-2): the medieval charters' original-script lane +
  # Paisiy's history (hosted as a modern rendering — declared). Fixture
  # envelopes are real api.php captures (2026-10-10) — see the README.
  class BgWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("bg-wikisource")

    def conformance_adapter = Nabu::Adapters::BgWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "bg-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn == "urn:nabu:bg-wikisource:#{pageid}" } || flunk("#{pageid} missing")

    def test_rendering_only_medieval_pages_skip_by_rule
      ids = conformance_adapter.discover(FIXTURES).map(&:id)
      refute_includes ids, "urn:nabu:bg-wikisource:5459", "Bobchev's translation of the ЗСЛ hosts no original"
      assert_match(/modern-language rendering only/, conformance_adapter.discovery_skips(FIXTURES).notes.join)
    end

    def test_charter_reads_only_the_original_script
      d = doc(6326)
      assert_equal "chu", d.language
      assert d.passages.first.text.start_with?("Бл҃гочъ́стивно чт҆о"), "titlos and superscripts verbatim"
      assert_equal "line", d.metadata["grain"]
      assert_equal "bulgarian", d.metadata["recension"]
      assert_equal [1378, 1378], d.metadata["date"].values_at("not_before", "not_after")
    end

    def test_caption_original_and_issuance_range
      d = doc(6045)
      assert d.passages.first.text.start_with?("† Ѿ гнⷣа • цр҃ѣ • Ср҃ацимира")
      refute(d.passages.any? { |p| p.text.match?(/[а-я]+ния\b.*съвременен/) })
      assert_equal [1369, 1380], d.metadata["date"].values_at("not_before", "not_after"),
                   "\"Издадена между 1369 г. и 1380 г.\" spans the envelope"
      assert_includes d.metadata["apparatus"].keys, "На съвременен български език",
                      "the modern rendering rides as apparatus, never as the text"
    end

    def test_serbian_charter_carries_its_edition_footnote
      d = doc(6194)
      assert_equal "serbian", d.metadata["recension"]
      assert d.metadata["base_edition"].start_with?("По редакция и издание на Татјана Суботин Голубовић")
      assert_equal 1348, d.metadata.dig("date", "not_before")
    end

    def test_paisiy_is_a_declared_modern_rendering
      d = doc(2142)
      assert_equal "bul", d.language
      assert_equal "modern literary Bulgarian", d.metadata["rendering"]
      assert_match(/предаден на съвременен книжовен език/, d.metadata["base_edition"])
      assert_equal "Паисий Хилендарски", d.metadata["author"]
      assert_nil d.metadata["date"], "the rendering carries no typed date"
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "bg-wikisource", name: "bg", license_class: "attribution",
                                          adapter_class: "Nabu::Adapters::BgWikisource")
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
