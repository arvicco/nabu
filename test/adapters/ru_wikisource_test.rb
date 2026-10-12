# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # ru-wikisource (P116-3, under the base-edition rule): the Old East Slavic cone with
  # the PER-PAGE EDITION FILTER. Fixture envelopes are real api.php
  # captures (2026-10-10), chosen for the filter's real cases:
  #
  # - Повесть временных лет (Нестор)/1997 (ДО) — THE ruled case: ИСТОЧНИК
  #   names Творогов's text in the 1997 Библиотека литературы Древней
  #   Руси, ДАТАПУБЛИКАЦИИ 1997 (wikitext trimmed to the header + opening).
  # - Слово о погибели Русской земли/ДО — keys to "Библиотека литературы
  #   Древней Руси, т. 5" with NO year: the named-series arm of the rule.
  # - Стихотворения (Шаховской) — an az.lib.ru import: the header names
  #   only the website, the BODY opens with the 1989 «Виршевая поэзия»
  #   imprint (the body-head arm of the rule; wikitext trimmed).
  # - Слово о полку Игореве (Жуковский) — a translation (ПЕРЕВОДЧИК filled).
  # - Поучение Владимира Мономаха/Поучение детям/1893/ВТ — a modern-
  #   orthography duplicate of a held ДО page.
  # - Слово о полку Игореве/Текст — ADMITTED: the 1800 Musin-Pushkin
  #   editio princeps (wikitext + rendering trimmed).
  # - Хвала о церкве (Аввакум) — ADMITTED: a web-sourced page whose
  #   statement names no edition ("unstated"-class, verbatim).
  class RuWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("ru-wikisource")

    def conformance_adapter = Nabu::Adapters::RuWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "ru-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def envelope(pageid) = JSON.parse(File.read(File.join(FIXTURES, "pages", "#{pageid}.json")))

    def classify(pageid) = conformance_adapter.page_class(envelope(pageid))

    # -- the edition filter (EDITION_TAINT_POST_1930) ------------------------

    def test_the_pvl_1997_page_is_excluded_by_the_named_rule
      assert_equal :edition_taint, classify(433_334)
      pvl = envelope(433_334)
      years = conformance_adapter.edition_years(pvl["title"], pvl["wikitext"])
      assert_includes years, 1997, "ИСТОЧНИК + ДАТАПУБЛИКАЦИИ + the title's dated segment all say 1997"
      assert(years.all? { |year| year > Nabu::Adapters::SlavicWikisourceHtml::TAINT_AFTER_YEAR })
    end

    def test_a_yearless_named_post_1930_series_taints_too
      assert_equal :edition_taint, classify(54_545)
      statement = envelope(54_545).then { |e| conformance_adapter.edition_statement(e["title"], e["wikitext"]) }
      assert_includes statement, "Библиотека литературы Древней Руси, т. 5"
      assert_empty envelope(54_545).then { |e| conformance_adapter.edition_years(e["title"], e["wikitext"]) },
                   "no year at all — the TAINTED_SERIES arm is what catches it"
    end

    def test_a_body_head_imprint_taints_the_az_lib_ru_imports
      # Стихотворения (Шаховской): the header names only az.lib.ru, but the
      # body opens with its source book's imprint — the 1989 «Виршевая
      # поэзия» (20 such pages in the live cone).
      shakhovskoy = envelope(1_101_386)
      statement = conformance_adapter.edition_statement(shakhovskoy["title"], shakhovskoy["wikitext"])
      assert_includes statement, "body: М., \"Советская Россия\", 1989"
      assert_equal :edition_taint, classify(1_101_386)
    end

    def test_body_evidence_reads_only_the_head
      deep_footnote = "{{Отексте\n| ИСТОЧНИК = x\n}}\n#{'Текст. ' * 400}\nПрим.: М., 1999."
      assert_nil conformance_adapter.wikitext_class("Пример", deep_footnote),
                 "an imprint deep in the body is a footnote, not the page's edition"
      prep = "{{Отексте\n| ИСТОЧНИК = x\n}}\n=== Подготовка текста Е. И. Ванеевой ===\nТекст."
      assert_equal :edition_taint, conformance_adapter.wikitext_class("Пример", prep),
                   "the BLDR/PLDR text-preparation credit is a named-series marker"
    end

    def test_pre_1931_editions_pass_and_ride_verbatim
      assert_equal :text, classify(34_424)
      slovo = doc(34_424)
      assert_includes slovo.metadata["base_edition"], "Москва, въ Сенатской Типографіи, 1800"
      assert_includes slovo.metadata["base_edition"], "ДАТАПУБЛИКАЦИИ: 1800"
    end

    def test_a_url_slug_year_is_never_edition_evidence
      wikitext = "{{Отексте\n| ИСТОЧНИК = [http://az.lib.ru/p/polockij_s/text_1978_poe.shtml az.lib.ru]\n}}"
      assert_empty conformance_adapter.edition_years("Стихотворения (Полоцкий)", wikitext),
                   "az.lib.ru slugs carry years that are not editions — URLs strip before the scan"
      assert_nil conformance_adapter.wikitext_class("Стихотворения (Полоцкий)", wikitext)
    end

    def test_unstated_editions_are_admitted_with_their_statement_verbatim
      assert_equal :text, classify(293_263)
      assert_equal "ИСТОЧНИК: библиотека «Либрусек» (http://lib.rus.ec/b/158484/read)",
                   doc(293_263).metadata["base_edition"]
    end

    # -- the other rules ------------------------------------------------------

    def test_translations_and_modern_orthography_duplicates_skip
      assert_equal :translation, classify(34_445)
      assert_equal :modernized, classify(473_330)
    end

    def test_censused_exclusions_and_reference_articles
      adapter = conformance_adapter
      assert_equal :excluded, adapter.wikitext_class("Летописи", "")
      assert_equal :reference, adapter.wikitext_class("ЭСБЕ/Слово о Полку Игореве", "")
      assert_equal :apparatus, adapter.wikitext_class("Слово о полку Игореве/Историческое содержание песни", "")
    end

    def test_discovery_census
      assert_equal %w[urn:nabu:ru-wikisource:293263 urn:nabu:ru-wikisource:34424],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 5, skips.skipped_by_rule
      assert(skips.notes.any? { |note| note.start_with?("3 page(s) excluded by EDITION_TAINT_POST_1930") })
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "ru-wikisource", name: "Russian Wikisource",
                                          adapter_class: "Nabu::Adapters::RuWikisource", license_class: "attribution")
      load = -> { Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true) }
      assert_equal 2, load.call.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      load.call
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end

    # -- language + dating ----------------------------------------------------

    def test_orv_throughout_with_the_composition_band
      hvala = doc(293_263)
      assert_equal "orv", hvala.language
      assert_equal({ "not_before" => 1670, "not_after" => 1670, "raw" => "1670" }, hvala.metadata["era_band"])
      assert_nil doc(34_424).metadata["era_band"], "no ДАТАСОЗДАНИЯ on the 1800 page — no band, never a guess"
    end

    def test_composition_band_reads_centuries_and_ranges
      adapter = conformance_adapter
      band = ->(value) { adapter.composition_band("{{Отексте\n| ДАТАСОЗДАНИЯ = #{value}\n}}") }
      assert_equal [1201, 1300], band.call("XIII век").values_at("not_before", "not_after")
      assert_equal [1101, 1200], band.call("{{roman|12}} век").values_at("not_before", "not_after")
      assert_equal [1238, 1246], band.call("c 1238 по 1246 г").values_at("not_before", "not_after")
      assert_nil band.call("")
    end
  end
end
