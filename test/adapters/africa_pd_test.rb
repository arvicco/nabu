# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "support/adapter_conformance"

module Adapters
  # africa-pd — the PD African-languages reference shelf as archive.org
  # scans (the slavistics-pd mold over IaScanShelf: page grain over the
  # hOCR derivative pair, UNCORRECTED OCR declared). Fixture: three census
  # items laid out as canonical/ holds them, each a documented prefix trim:
  # Velten's Prosa und Poesie der Suaheli (the one sw claim; first 22
  # pages), Taylor's African Aphorisms (the identifier ≠ file-stem case;
  # first 9) and Hanoteau's Tamachek' grammar (a stem with spaces and a
  # comma; first 10).
  class AfricaPdTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("africa-pd")
    URN = "urn:nabu:africa-pd"
    KLASS = Nabu::Adapters::AfricaPd

    def conformance_adapter = KLASS.new(delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "africa-pd"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(key) = documents.find { |d| d.urn == "#{URN}:#{key}" } || flunk("#{key} missing")

    def test_discovers_the_census_items_on_disk_by_their_work_keys
      assert_equal %W[#{URN}:hanoteau-grammaire-tamachek-1860 #{URN}:taylor-african-aphorisms-1891
                      #{URN}:velten-prosa-poesie-suaheli-1907],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_one_passage_per_non_blank_hocr_page
      velten = doc("velten-prosa-poesie-suaheli-1907")
      assert_equal 17, velten.passages.size, "22 hOCR pages, 5 blank leaves"
      assert_equal "#{URN}:velten-prosa-poesie-suaheli-1907:2", velten.passages.first.urn
      first_text = velten.passages.find { |p| p.urn.end_with?(":22") }
      assert_includes first_text.text, "hadisi ya mwanamke zaifu"
    end

    def test_documents_claim_their_prose_language_and_name_the_object_language
      assert_equal "sw", doc("velten-prosa-poesie-suaheli-1907").language
      taylor = doc("taylor-african-aphorisms-1891")
      assert_equal "eng", taylor.language
      assert_equal "sw", taylor.metadata["object_language"]
      hanoteau = doc("hanoteau-grammaire-tamachek-1860")
      assert_equal "fra", hanoteau.language
      assert_equal "tmh", hanoteau.metadata["object_language"]
      assert(hanoteau.passages.all? { |p| p.language == "fra" })
    end

    def test_uncorrected_ocr_is_declared_with_the_shelf_note
      documents.each do |d|
        assert_equal "uncorrected-ocr", d.metadata["text_nature"]
        assert_includes d.metadata["ocr_note"], "Old Nubian, Arabic-script (Ajami)"
        assert_kind_of Float, d.metadata["ocr_wordlike"]
      end
    end

    def test_work_metadata_carries_the_census_facts
      meta = doc("taylor-african-aphorisms-1891").metadata
      assert_equal "W. E. Taylor", meta["author"]
      assert_equal({ "not_before" => 1891, "not_after" => 1891, "raw" => "1891" }, meta["date"])
      assert_equal "London: Society for Promoting Christian Knowledge", meta["imprint"]
      assert_equal({ "genre" => { "value" => "proverb collection" } }, meta["facets"])
      assert_equal "AfricanAphorisms", meta["ia_identifier"]
      assert_equal "African_aphorisms", meta["ia_file"]
      assert_includes meta["note"], "title page"
      assert_nil meta["place"], "the imprint is the printing place, never a place claim"
    end

    def test_the_census_is_unique_and_every_item_is_well_formed
      items = KLASS::ITEMS
      assert_equal 10, items.size, "the survey's ten cleared works"
      assert_equal items.size, items.map(&:key).uniq.size
      assert_equal items.size, items.map { |i| [i.identifier, i.file] }.uniq.size
      assert_equal items.map(&:key).sort, KLASS::OBJECT_LANGUAGES.keys.sort
      items.each do |item|
        assert_match(/\A[a-z0-9-]+\z/, item.key)
        assert_includes %w[eng deu fra sw], item.language
        assert_operator item.date["not_before"], :<, 1931, "every print predates 1931 (PD)"
      end
      assert_equal ["velten-prosa-poesie-suaheli-1907"], items.select { |i| i.language == "sw" }.map(&:key)
    end

    def test_the_metadata_dates_lane_reads_the_structured_shape
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["africa-pd"]
    end

    def test_manifest_is_open_public_domain_and_declares_the_ocr
      manifest = KLASS.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "uncorrected machine OCR"
      assert_equal "ia-hocr-text", manifest.parser_family
    end

    def test_registry_row_is_registered_wired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["africa-pd"]
      refute_nil entry
      assert entry.wired, "flipped after the verified 2026-10-13 first sync (counts in sources.yml)"
      assert_equal "manual", entry.sync_policy
      assert_equal ["africa"], entry.axes
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "africa-pd", name: "PD Africa", adapter_class: KLASS.name,
                                          license_class: "open")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, first.added
      passages = db[:passages].count
      assert_equal documents.sum { |d| d.passages.size }, passages
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only) ------------------------------------------------

    TAYLOR = KLASS::ITEMS.find { |i| i.key == "taylor-african-aphorisms-1891" }
    HANOTEAU = KLASS::ITEMS.find { |i| i.key == "hanoteau-grammaire-tamachek-1860" }

    def stub_item(item)
      Nabu::Adapters::IaHocrText.paths(File.join(FIXTURES, item.identifier), item.file).each_value do |path|
        stub_request(:get, KLASS.download_url(item.identifier, File.basename(path)))
          .to_return(status: 200, body: File.binread(path))
      end
    end

    def test_fetch_lands_each_item_pair_under_upstream_file_names
      stub_item(TAYLOR)
      stub_item(HANOTEAU)
      Dir.mktmpdir do |workdir|
        report = KLASS.new(delay: 0, items: [TAYLOR, HANOTEAU]).fetch(workdir)
        assert_includes report.notes, "2/2 item(s) held (+2 this sync)"
        assert File.file?(File.join(workdir, "AfricanAphorisms", "African_aphorisms_hocr_searchtext.txt.gz"))
        assert File.file?(File.join(workdir, HANOTEAU.identifier,
                                    "#{HANOTEAU.file}_hocr_pageindex.json.gz"))
      end
    end
  end
end
