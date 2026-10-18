# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # cs-wikisource (P116-3, under the base-edition rule): censused premodern works.
  # Fixture envelopes are real api.php captures (2026-10-10): Dalimil
  # chapter V (Jireček 1877, verse), Bible kralická (1613)/Rut (the 1613
  # Brethren orthography, whole rendering), Hospodine, pomiluj ny! (keys to
  # the 1959 Český kancionál — EDITION_TAINT_POST_1930), Bible kralická
  # (the {{Rozcestník}} versions shell).
  class CsWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("cs-wikisource")

    def conformance_adapter = Nabu::Adapters::CsWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "cs-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def envelope(pageid) = JSON.parse(File.read(File.join(FIXTURES, "pages", "#{pageid}.json")))

    # Textinfo's AUTOR (the LAST occurrence wins, as MediaWiki renders a
    # duplicated parameter — Dalimil's header states the work's editor
    # first, then the part's full attribution) and TITUL, the parent work.
    def test_author_and_parent_work_ride_metadata
      dalimil = doc(9925).metadata
      assert_equal "neznámý, tzv. Dalimil, k vydání upravil Josef Jireček", dalimil["author"]
      assert_equal "Rýmovaná kronika česká tak řečeného Dalimila", dalimil["work"]
      assert_equal "Bible kralická (1613)", doc(68_927).metadata["work"]
      assert_equal "neznámý", conformance_adapter.header_author(envelope(41_239)["wikitext"]),
                   "a trailing editorial-note template is not part of the author"
    end

    def test_discovery_census
      assert_equal %w[urn:nabu:cs-wikisource:68927 urn:nabu:cs-wikisource:9925],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      notes = conformance_adapter.discovery_skips(FIXTURES).notes
      assert(notes.any? { |note| note.start_with?("1 versions/disambiguation shell") })
      assert(notes.any? { |note| note.start_with?("1 page(s) excluded by EDITION_TAINT_POST_1930") })
    end

    def test_the_1959_kancional_taints_the_medieval_hymn
      hymn = envelope(41_239)
      assert_equal :edition_taint, conformance_adapter.page_class(hymn)
      assert_includes conformance_adapter.edition_years(hymn["title"], hymn["wikitext"]), 1959
    end

    def test_dalimil_chapter_is_verse_with_its_edition_verbatim
      dalimil = doc(9925)
      assert_equal "ces", dalimil.language
      assert dalimil.passages.first.text.start_with?("Páni po koniu pojedú,\naž Bieliny řěky dojedú.")
      assert_includes dalimil.metadata["base_edition"], "VYDÁNO: Praha, Matice česká 1877"
      assert_includes dalimil.metadata["source_date"], "1877",
                      "the edition statement feeds the edition-year date lane"
    end

    def test_the_edition_statement_dates_the_edition_never_the_composition
      shapes = Nabu::Store::TimelineBuilder::MetadataDates::SHAPES
      assert_equal :edition_year_text, shapes["cs-wikisource"]
      assert_equal %w[pl-wikisource ru-wikisource uk-wikisource].map { :era_band_key },
                   shapes.values_at("pl-wikisource", "ru-wikisource", "uk-wikisource")
      years = Nabu::Store::TimelineBuilder::MetadataDates.edition_year_text(doc(9925).metadata)
      assert_equal [1877, 1877], years.first(2)
      assert_equal "edition", years.last
    end

    def test_kralice_1613_keeps_the_print_orthography
      rut = doc(68_927)
      assert(rut.passages.any? { |p| p.text.include?("Elimelech/ a gméno ženy geho Noémi") },
             "long s, the Brethren ľ and the slash punctuation stay verbatim")
      assert_includes rut.metadata["base_edition"], "VYDÁNO: [s. l.] M.DC.XIII"
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "cs-wikisource", name: "Czech Wikisource",
                                          adapter_class: "Nabu::Adapters::CsWikisource", license_class: "attribution")
      load = -> { Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true) }
      assert_equal 2, load.call.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      load.call
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end

    def test_apparatus_and_editions_root
      adapter = conformance_adapter
      assert_equal :apparatus, adapter.wikitext_class("Rýmovaná kronika česká tak řečeného Dalimila/Úvod", "")
      assert_equal :excluded, adapter.wikitext_class("Bible kralická (1918)", "")
      assert_nil adapter.wikitext_class("Rýmovaná kronika česká tak řečeného Dalimila/Předmluva", ""),
                 "the chronicle's OWN preface is text"
    end
  end
end
