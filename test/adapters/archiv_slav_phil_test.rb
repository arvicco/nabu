# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "support/adapter_conformance"

module Adapters
  # archiv-slav-phil (Q105) — Jagić's Archiv für slavische Philologie as the
  # archive.org scan run, one document per volume, page grain over the hOCR
  # derivative pair (the IaScanShelf mechanics, tested in full by
  # slavistics_pd_test.rb). Fixture: the first hOCR pages of Bd. 1 (1876,
  # a 1964-reprint scan, user upload) and Bd. 16 (1894, Toronto).
  class ArchivSlavPhilTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("archiv-slav-phil")
    URN = "urn:nabu:archiv-slav-phil"
    KLASS = Nabu::Adapters::ArchivSlavPhil

    def conformance_adapter = KLASS.new(delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "archiv-slav-phil"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(key) = documents.find { |d| d.urn == "#{URN}:#{key}" } || flunk("#{key} missing")

    def test_discovers_volumes_keyed_by_number_and_year
      assert_equal %W[#{URN}:bd01-1876 #{URN}:bd16-1894], conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_volume_pages_become_passages
      bd16 = doc("bd16-1894")
      assert_equal([1, 8, 9, 10, 11, 12, 14], bd16.passages.map { |p| p.annotations["hocr_page"] })
      title_page = bd16.passages.find { |p| p.urn == "#{URN}:bd16-1894:8" }
      assert_includes title_page.text, "ARCHIV\nFÜR\nSLAVISCHE PHILOLOGIE."
      assert_equal "deu", bd16.language
      assert_equal 10, doc("bd01-1876").passages.size
    end

    def test_volume_metadata_names_the_journal_and_declares_the_ocr
      meta = doc("bd16-1894").metadata
      assert_equal "Archiv für slavische Philologie, Bd. 16", meta["title"]
      assert_equal "Vatroslav Jagić (ed.)", meta["author"]
      assert_equal({ "not_before" => 1894, "not_after" => 1894, "raw" => "1894" }, meta["date"])
      assert_equal "journal volume", meta["genre"]
      assert_equal "Berlin: Weidmannsche Buchhandlung", meta["imprint"]
      assert_equal "archivfrslavis16berluoft", meta["ia_identifier"]
      assert_equal "uncorrected-ocr", meta["text_nature"]
      assert_nil meta["note"]
    end

    def test_a_reprint_scan_keeps_the_original_date_and_says_so
      meta = doc("bd01-1876").metadata
      assert_equal 1876, meta.dig("date", "not_before")
      assert_includes meta["note"], "1964 facsimile reprint"
      reprint_page = doc("bd01-1876").passages.find { |p| p.urn == "#{URN}:bd01-1876:2" }
      assert_includes reprint_page.text, "Reprint edition 1964"
    end

    def test_the_census_holds_the_identified_run
      volumes = KLASS::ITEMS.map { |item| item.title[/Bd\. (\d+)\z/, 1].to_i }
      assert_equal [1, *3..12, *14..35], volumes.sort
      assert_equal 33, KLASS::ITEMS.size
      assert_equal KLASS::ITEMS.size, KLASS::ITEMS.map(&:identifier).uniq.size
      assert(KLASS::ITEMS.all? { |item| item.date["not_before"] < 1931 })
      reprints = KLASS::ITEMS.select(&:note).map(&:key)
      assert_equal %w[bd01-1876 bd03-1879 bd08-1885 bd09-1886 bd11-1888], reprints
    end

    def test_the_metadata_dates_lane_reads_the_structured_shape
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["archiv-slav-phil"]
    end

    def test_manifest_declares_the_per_article_eu_caveat
      manifest = KLASS.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "not audited article by article"
      assert_equal "ia-hocr-text", manifest.parser_family
    end

    def test_registry_row_is_registered_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["archiv-slav-phil"]
      refute_nil entry
      refute entry.wired, "wired: false until the first real sync is verified"
      assert_equal "manual", entry.sync_policy
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "archiv-slav-phil", name: "Archiv",
                                          adapter_class: KLASS.name, license_class: "open")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 2, first.added
      passages = db[:passages].count
      assert_equal 17, passages
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 2, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end
  end
end
