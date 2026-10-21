# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # cy-wikisource (P140): the early-modern Welsh cone. Fixture envelopes are
  # real api.php captures (2026-10-21): Obadiah from the 1620 Bible and a
  # proverb section of Salesbury's Oll synnwyr pen Kembero ygyd (1547) —
  # both prints inside the ≤ 1800 band, original spelling — and Dafydd ap
  # Gwilym's Y Niwl from the 1901 Cyfres y Fil volume (a censused EXTRA,
  # modernized spelling); the same volume's Rhagymadrodd (apparatus) and
  # the Beirdd y Berwyn "(testun cyfansawdd)" composite (aggregate) skip.
  class CyWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("cy-wikisource")

    def conformance_adapter = Nabu::Adapters::CyWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "cy-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def test_discovery_census
      assert_equal %w[urn:nabu:cy-wikisource:12427 urn:nabu:cy-wikisource:14699 urn:nabu:cy-wikisource:2097],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      notes = conformance_adapter.discovery_skips(FIXTURES).notes
      assert(notes.any? { |note| note.start_with?("1 whole-work aggregate page(s)") })
      assert(notes.any? { |note| note.start_with?("1 editorial apparatus page(s)") })
    end

    def test_every_composite_spelling_is_an_aggregate
      adapter = conformance_adapter
      ["Beirdd y Berwyn 1700-1750 (testun cyfansawdd)", "Brut y Tywysogion (Ab Owen testun cyfansawdd)",
       "Barddoniaeth Goronwy Owen (gol Llyfrbryf, testun cyfansawdd)"].each do |title|
        assert_equal :aggregate, adapter.wikitext_class(title, "<pages />"), title
      end
      assert_nil adapter.wikitext_class("Beibl (1620)/Obadeia", "<pages />")
    end

    def test_the_orthography_is_declared_per_page
      assert_equal "original", doc(2097).metadata["orthography"]
      assert_equal "original", doc(14_699).metadata["orthography"]
      assert_equal "modernized (Cyfres y Fil)", doc(12_427).metadata["orthography"]
    end

    def test_the_1620_bible_rides_its_print
      obadiah = doc(2097)
      assert_equal "cym", obadiah.language
      assert_equal "Llyfr Obadiah.", obadiah.passages.first.text
      assert_equal "Year: 1620 (Y bibl cyssegr-lan.djvu)", obadiah.metadata["source_date"]
      assert obadiah.metadata["base_edition"].start_with?(
        "index: Y bibl cyssegr-lan.djvu (Title: Y bibl cyssegr-lan; Author: William Morgan; Year: 1620)"
      )
    end

    def test_the_print_year_feeds_the_edition_date_lane
      assert_equal :edition_year_text, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["cy-wikisource"]
      years = Nabu::Store::TimelineBuilder::MetadataDates.edition_year_text(doc(14_699).metadata)
      assert_equal [1547, 1547, "edition"], years.values_at(0, 1, 4)
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "cy-wikisource", name: "Welsh Wikisource",
                                          adapter_class: "Nabu::Adapters::CyWikisource", license_class: "attribution")
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
