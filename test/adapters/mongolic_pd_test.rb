# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "support/adapter_conformance"

module Adapters
  # mongolic-pd — the PD Manchu–Mongolic–Oirat reference shelf as
  # archive.org scans (the africa-pd mold over IaScanShelf: page grain over
  # the hOCR derivative pair, UNCORRECTED OCR declared). Fixture: three
  # census items laid out as canonical/ holds them, each a documented
  # prefix trim: Zakharov's Manchu-Russian dictionary (the mnc flagship;
  # first 10 pages, blank leaves included), Kowalewski's dictionary volume
  # 1 (cmg; the identifier ≠ file-stem case, the stem carrying a comma and
  # a combining cedilla; first 11) and Jülg's Siddhi-Kür (xwo; first 9).
  class MongolicPdTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("mongolic-pd")
    URN = "urn:nabu:mongolic-pd"
    KLASS = Nabu::Adapters::MongolicPd

    def conformance_adapter = KLASS.new(delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "mongolic-pd"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(key) = documents.find { |d| d.urn == "#{URN}:#{key}" } || flunk("#{key} missing")

    def test_discovers_the_census_items_on_disk_by_their_work_keys
      assert_equal %W[#{URN}:julg-siddhi-kur-1866 #{URN}:kowalewski-dictionnaire-mongol-1-1844
                      #{URN}:zakharov-manchu-russian-dictionary-1875],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_one_passage_per_non_blank_hocr_page
      zakharov = doc("zakharov-manchu-russian-dictionary-1875")
      assert_equal 5, zakharov.passages.size, "10 hOCR pages, 5 blank leaves (1, 3, 4, 5, 7)"
      assert_equal(%w[2 6 8 9 10], zakharov.passages.map { |p| p.urn.split(":").last })
      imprimatur = zakharov.passages.find { |p| p.urn.end_with?(":9") }
      assert_includes imprimatur.text, "Факультета восточныхъ языковъ"
      assert_includes zakharov.passages.last.text, "ПРВДИСЛОВІЕ."
    end

    def test_documents_claim_their_prose_language_and_name_the_object_language
      assert_equal "rus", doc("zakharov-manchu-russian-dictionary-1875").language
      assert_equal "mnc", doc("zakharov-manchu-russian-dictionary-1875").metadata["object_language"]
      kowalewski = doc("kowalewski-dictionnaire-mongol-1-1844")
      assert_equal "rus", kowalewski.language
      assert_equal "cmg", kowalewski.metadata["object_language"]
      julg = doc("julg-siddhi-kur-1866")
      assert_equal "deu", julg.language
      assert_equal "xwo", julg.metadata["object_language"]
      assert(julg.passages.all? { |p| p.language == "deu" })
    end

    def test_uncorrected_ocr_and_native_script_loss_are_declared
      documents.each do |d|
        assert_equal "uncorrected-ocr", d.metadata["text_nature"]
        assert_includes d.metadata["ocr_note"], "Oirat Clear Script — are garbled"
        assert_kind_of Float, d.metadata["ocr_wordlike"]
      end
    end

    def test_the_identifier_and_the_cedilla_stem_ride_the_metadata
      meta = doc("kowalewski-dictionnaire-mongol-1-1844").metadata
      assert_equal KLASS::KOWALEWSKI, meta["ia_identifier"]
      assert_equal "Kovalevskij, Dictionnaire Mongol-Russe-Franca̧is (1844-49) - Volume 1", meta["ia_file"]
      assert_equal({ "not_before" => 1844, "not_after" => 1844, "raw" => "1844" }, meta["date"])
      assert_equal({ "genre" => { "value" => "dictionary" } }, meta["facets"])
      assert_includes doc("kowalewski-dictionnaire-mongol-1-1844").passages.map(&:text).join("\n"),
                      "DICTIONNAIRE MONGOL-RUSSE-FRANÇAIS"
    end

    def test_the_census_is_unique_and_every_item_is_well_formed
      items = KLASS::ITEMS
      assert_equal 15, items.size, "13 works, Kowalewski's dictionary in its three volumes"
      assert_equal items.size, items.map(&:key).uniq.size
      assert_equal items.size, items.map { |i| [i.identifier, i.file] }.uniq.size
      items.each do |item|
        assert_match(/\A[a-z0-9-]+\z/, item.key)
        assert_includes %w[rus eng fra deu], item.language
        assert_operator item.date["not_before"], :<, 1931, "every print predates 1931 (PD)"
        assert_includes %w[dictionary grammar chrestomathy tales], item.genre
      end
    end

    def test_object_languages_partition_the_shelf
      counts = KLASS::OBJECT_LANGUAGES.values.tally
      assert_equal({ "mnc" => 7, "cmg" => 5, "xwo" => 3 }, counts)
      assert_equal "cmg", KLASS::OBJECT_LANGUAGES["schmidt-grammatik-mongolisch-1831"]
      assert_equal "xwo", KLASS::OBJECT_LANGUAGES["popov-kalmyk-grammar-1847"]
    end

    def test_the_metadata_dates_lane_reads_the_structured_shape
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["mongolic-pd"]
    end

    def test_manifest_is_open_public_domain_and_declares_the_ocr
      manifest = KLASS.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "uncorrected machine OCR"
      assert_equal "ia-hocr-text", manifest.parser_family
    end

    def test_registry_row_is_registered_wired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["mongolic-pd"]
      refute_nil entry
      assert entry.wired, "flipped live after the verified first sync (P164)"
      assert_equal "manual", entry.sync_policy
      assert_equal ["mongolic"], entry.axes
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "mongolic-pd", name: "PD Mongolic", adapter_class: KLASS.name,
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

    ZAKHAROV = KLASS::ITEMS.find { |i| i.key == "zakharov-manchu-russian-dictionary-1875" }
    KOWALEWSKI_1 = KLASS::ITEMS.find { |i| i.key == "kowalewski-dictionnaire-mongol-1-1844" }

    def stub_item(item)
      Nabu::Adapters::IaHocrText.paths(File.join(FIXTURES, item.identifier), item.file).each_value do |path|
        stub_request(:get, KLASS.download_url(item.identifier, File.basename(path)))
          .to_return(status: 200, body: File.binread(path))
      end
    end

    def test_fetch_lands_each_item_pair_under_upstream_file_names
      stub_item(ZAKHAROV)
      stub_item(KOWALEWSKI_1)
      Dir.mktmpdir do |workdir|
        report = KLASS.new(delay: 0, items: [ZAKHAROV, KOWALEWSKI_1]).fetch(workdir)
        assert_includes report.notes, "2/2 item(s) held (+2 this sync)"
        assert File.file?(File.join(workdir, "polnyimanchzhurs00zakh",
                                    "polnyimanchzhurs00zakh_hocr_searchtext.txt.gz"))
        assert File.file?(File.join(workdir, KLASS::KOWALEWSKI, "#{KOWALEWSKI_1.file}_hocr_pageindex.json.gz"))
      end
    end
  end
end
