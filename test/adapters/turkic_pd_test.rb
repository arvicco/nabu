# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "support/adapter_conformance"

module Adapters
  # turkic-pd — the PD Turkic reference shelf as archive.org scans (the
  # mongolic-pd mold over IaScanShelf: page grain over the hOCR derivative
  # pair, UNCORRECTED OCR declared). Fixture: three census items laid out
  # as canonical/ holds them, each a documented prefix trim: Kuun's Codex
  # Cumanicus (qwm; first 14 pages, blank leaves included), Thomsen's
  # Inscriptions de l'Orkhon (otk; first 11, Google's guideline pages
  # included) and Vámbéry's Kudatku Bilik (xqa; first 12).
  class TurkicPdTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("turkic-pd")
    URN = "urn:nabu:turkic-pd"
    KLASS = Nabu::Adapters::TurkicPd

    def conformance_adapter = KLASS.new(delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "turkic-pd"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(key) = documents.find { |d| d.urn == "#{URN}:#{key}" } || flunk("#{key} missing")

    def test_discovers_the_census_items_on_disk_by_their_work_keys
      assert_equal %W[#{URN}:kuun-codex-cumanicus-1880 #{URN}:thomsen-inscriptions-orkhon-1896
                      #{URN}:vambery-kudatku-bilik-1870],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_one_passage_per_non_blank_hocr_page
      kuun = doc("kuun-codex-cumanicus-1880")
      assert_equal(%w[3 8 10 11 12 13 14], kuun.passages.map { |p| p.urn.split(":").last },
                   "14 hOCR pages, 7 blank leaves (1, 2, 4, 5, 6, 7, 9)")
      assert_includes kuun.passages.find { |p| p.urn.end_with?(":8") }.text, "CODEX CUMANICUS"
      assert_includes kuun.passages.find { |p| p.urn.end_with?(":12") }.text, "PR/EFATIO."
      assert_includes kuun.passages.last.text, "PROLEGOMENA."
      assert_equal 10, doc("thomsen-inscriptions-orkhon-1896").passages.size, "11 pages, page 3 blank"
      assert_equal 8, doc("vambery-kudatku-bilik-1870").passages.size, "12 pages, pages 1–4 blank"
    end

    def test_documents_claim_their_prose_language_and_name_the_object_language
      kuun = doc("kuun-codex-cumanicus-1880")
      assert_equal "lat", kuun.language
      assert_equal "qwm", kuun.metadata["object_language"]
      thomsen = doc("thomsen-inscriptions-orkhon-1896")
      assert_equal "fra", thomsen.language
      assert_equal "otk", thomsen.metadata["object_language"]
      vambery = doc("vambery-kudatku-bilik-1870")
      assert_equal "deu", vambery.language
      assert_equal "xqa", vambery.metadata["object_language"]
      assert(vambery.passages.all? { |p| p.language == "deu" })
      assert_includes vambery.passages.map(&:text).join("\n"), "KUDATKU BILIK"
    end

    def test_uncorrected_ocr_and_script_loss_are_declared
      documents.each do |d|
        assert_equal "uncorrected-ocr", d.metadata["text_nature"]
        assert_includes d.metadata["ocr_note"], "the runiform script"
        assert_includes d.metadata["ocr_note"], "the Uyghur script are garbled"
        assert_kind_of Float, d.metadata["ocr_wordlike"]
      end
    end

    def test_dates_series_and_genre_ride_the_metadata
      thomsen = doc("thomsen-inscriptions-orkhon-1896").metadata
      assert_equal({ "not_before" => 1896, "not_after" => 1896, "raw" => "1896" }, thomsen["date"])
      assert_equal "Mémoires de la Société Finno-Ougrienne V", thomsen["series"]
      assert_equal({ "genre" => { "value" => "inscription study" } }, thomsen["facets"])
      assert_equal "inscriptionsdel00thomgoog", thomsen["ia_identifier"]
      assert_includes doc("thomsen-inscriptions-orkhon-1896").passages.map(&:text).join("\n"),
                      "IMPRIMERIE DE lA SOCIÉTÉ DE LITTÉRATURE FINNOISE"
    end

    def test_radloff_binds_the_whole_series_and_is_dated_across_it
      radloff = KLASS::ITEMS.find { |i| i.key == "radloff-alttuerkische-inschriften-1895-99" }
      assert_equal({ "not_before" => 1895, "not_after" => 1899, "raw" => "1895–1899" }, radloff.date)
      assert_equal "deu", radloff.language
      assert_includes radloff.note, "Zweite Folge"
    end

    def test_the_census_is_unique_and_every_item_is_well_formed
      items = KLASS::ITEMS
      assert_equal 4, items.size, "Kuun, Thomsen, Radloff, Vámbéry — the held-back items never enter"
      assert_equal items.size, items.map(&:key).uniq.size
      assert_equal items.size, items.map(&:identifier).uniq.size
      refute(items.any? { |i| i.identifier == "kamusitrki00emse" }, "Kamus-i Türki is held back")
      items.each do |item|
        assert_match(/\A[a-z0-9-]+\z/, item.key)
        assert_includes %w[lat fra deu], item.language
        assert_operator item.date["not_after"], :<, 1931, "every print predates 1931 (PD)"
        assert_includes ["glossary edition", "inscription study", "text edition"], item.genre
      end
    end

    def test_object_languages_cover_every_item
      assert_equal KLASS::ITEMS.map(&:key).sort, KLASS::OBJECT_LANGUAGES.keys.sort
      assert_equal({ "qwm" => 1, "otk" => 2, "xqa" => 1 }, KLASS::OBJECT_LANGUAGES.values.tally)
    end

    def test_the_metadata_dates_lane_reads_the_structured_shape
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["turkic-pd"]
    end

    def test_manifest_is_open_public_domain_and_declares_the_ocr
      manifest = KLASS.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "uncorrected machine OCR"
      assert_equal "ia-hocr-text", manifest.parser_family
    end

    def test_registry_row_is_registered_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
      entry = registry["turkic-pd"]
      refute_nil entry
      refute entry.wired, "wired: false until the first real sync is verified"
      assert_equal "manual", entry.sync_policy
      assert_equal ["turkic"], entry.axes
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "turkic-pd", name: "PD Turkic", adapter_class: KLASS.name,
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

    KUUN = KLASS::ITEMS.find { |i| i.key == "kuun-codex-cumanicus-1880" }
    THOMSEN = KLASS::ITEMS.find { |i| i.key == "thomsen-inscriptions-orkhon-1896" }

    def stub_item(item)
      Nabu::Adapters::IaHocrText.paths(File.join(FIXTURES, item.identifier), item.file).each_value do |path|
        stub_request(:get, KLASS.download_url(item.identifier, File.basename(path)))
          .to_return(status: 200, body: File.binread(path))
      end
    end

    def test_fetch_lands_each_item_pair_under_upstream_file_names
      stub_item(KUUN)
      stub_item(THOMSEN)
      Dir.mktmpdir do |workdir|
        report = KLASS.new(delay: 0, items: [KUUN, THOMSEN]).fetch(workdir)
        assert_includes report.notes, "2/2 item(s) held (+2 this sync)"
        assert File.file?(File.join(workdir, "codexcumanicusbi00kuunuoft",
                                    "codexcumanicusbi00kuunuoft_hocr_searchtext.txt.gz"))
        assert File.file?(File.join(workdir, "inscriptionsdel00thomgoog",
                                    "inscriptionsdel00thomgoog_hocr_pageindex.json.gz"))
      end
    end
  end
end
