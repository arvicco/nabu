# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "support/store_test_db"

module Adapters
  # sr-wikisource (P116-2): the Serbian oral-tradition cone. Fixture
  # envelopes are real api.php captures (2026-10-10, prop=revisions|
  # categories) in the adapter's own envelope shape — see the fixture
  # README for the per-page classes.
  class SrWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("sr-wikisource")

    def conformance_adapter = Nabu::Adapters::SrWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "sr-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn == "urn:nabu:sr-wikisource:#{pageid}" } || flunk("#{pageid} missing")

    def test_skip_rules_name_their_reasons
      ids = conformance_adapter.discover(FIXTURES).map(&:id).sort
      assert_equal %w[urn:nabu:sr-wikisource:15002 urn:nabu:sr-wikisource:22093
                      urn:nabu:sr-wikisource:28813 urn:nabu:sr-wikisource:45771], ids
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 3, skips.skipped_by_rule
      notes = skips.notes.join("\n")
      assert_match(/Bulgarian-source collection/, notes, "the Bulgarian-source songs are out by rule")
      assert_match(/Vuk volume index page/, notes)
      assert_match(/index page \(navigation list/, notes, "the Erlangen table of contents is navigation")
    end

    def test_vuk_song_is_serbian_verse_with_its_source_line
      d = doc(22_093)
      assert_equal "srp", d.language
      assert_equal 66, d.passages.size
      assert_equal "urn:nabu:sr-wikisource:22093:1", d.passages.first.urn
      assert_equal "Фала Богу лијепе љепоте,", d.passages.first.text
      meta = d.metadata
      assert_includes meta["base_edition"], "Пјесме јуначке средњијех времена, књига трећа 1846",
                      "the base-edition rule: the page's own Избор source line, verbatim"
      assert_equal ["Српске епске народне песме", "Збирке Вука Стефановића Караџића"], meta["cone"]
      assert_includes meta["categories"], "Збирка народних песама Вук књига трећа"
      assert_equal "verse", meta["grain"]
    end

    def test_erlangen_page_declares_its_edition_and_interventions
      d = doc(28_813)
      assert_equal "srp", d.language
      assert_match(/Приредиле Мирјана Детелић/, d.metadata["base_edition"],
                   "no Извор line: the header's edition statement is the base edition")
      assert_includes d.metadata.dig("apparatus", "Интервенције"), "јат = е",
                      "the editors' orthographic normalizations ride declared, never hidden"
      refute(d.passages.any? { |p| p.text.include?("Геземан") }, "the bibliography is apparatus")
    end

    def test_latin_script_pages_claim_croatian
      d = doc(45_771)
      assert_equal "hrv", d.language, "the Latin-script transcriptions are the Croatian-collected songs"
      assert_equal "Latn", d.metadata["script"]
      assert_equal "Lov lovio Kraljeviću Marko,", d.passages.first.text
      assert_equal "Cyrl", doc(15_002).metadata["script"]
    end

    def test_quality_stamp_and_unstated_edition
      meta = doc(15_002).metadata
      assert_equal "100%", meta["textquality"]
      assert_equal "unstated", meta["base_edition"], "absence is recorded, never guessed"
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "sr-wikisource", name: "sr", license_class: "attribution",
                                          adapter_class: "Nabu::Adapters::SrWikisource")
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
