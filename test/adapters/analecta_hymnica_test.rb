# frozen_string_literal: true

require "json"
require "test_helper"
require "tmpdir"
require "support/adapter_conformance"

module Adapters
  # analecta-hymnica — the Analecta Hymnica Medii Aevi as the archive.org
  # scan run, one document per volume, page grain over the hOCR derivative
  # pair (the IaScanShelf mechanics, tested in full by slavistics_pd_test.rb).
  # Fixture: the first hOCR pages of Bd. 1 (1886) and Bd. 55 (1922) laid
  # out as canonical/ holds them, plus census/ — trimmed archive.org
  # metadata responses pinning one specimen per REJECTED grain.
  class AnalectaHymnicaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("analecta-hymnica")
    URN = "urn:nabu:analecta-hymnica"
    KLASS = Nabu::Adapters::AnalectaHymnica

    def conformance_adapter = KLASS.new(delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "analecta-hymnica"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(key) = documents.find { |d| d.urn == "#{URN}:#{key}" } || flunk("#{key} missing")

    def specimen(identifier) = JSON.parse(File.read(File.join(FIXTURES, "census", "#{identifier}.json")))

    def test_discovers_volumes_keyed_by_number_and_print_year
      assert_equal %W[#{URN}:ah01-1886 #{URN}:ah55-1922], conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_volume_pages_become_passages
      bd1 = doc("ah01-1886")
      assert_equal([2, 3, 7, 8, 9, 10], bd1.passages.map { |p| p.annotations["hocr_page"] })
      title_page = bd1.passages.find { |p| p.urn == "#{URN}:ah01-1886:7" }
      assert_includes title_page.text, "Leiche, Lieder und Rufe\ndes 13., 14. und 15. Jahrhunderts"
      bd55 = doc("ah55-1922")
      assert_equal 15, bd55.passages.size, "22 hOCR pages, 7 blank"
      sequence = bd55.passages.find { |p| p.urn == "#{URN}:ah55-1922:22" }
      assert_includes sequence.text, "Ascribitur Adamo de S. Victore"
      assert(documents.all? { |d| d.language == "lat" && d.passages.all? { |p| p.language == "lat" } })
    end

    def test_volume_metadata_carries_the_title_page_facts
      meta = doc("ah55-1922").metadata
      assert_equal "Analecta Hymnica Medii Aevi, Bd. 55: Thesauri hymnologici prosarium. Die Sequenzen des " \
                   "Thesaurus hymnologicus H. A. Daniels und anderer Sequenzenausgaben. Des 2. Teiles zweiter " \
                   "Band: Liturgische Prosen zweiter Epoche auf Feste der Heiligen", meta["title"]
      assert_equal "Clemens Blume (ed.)", meta["author"]
      assert_equal 55, meta["volume"]
      assert_equal "Leipzig: O. R. Reisland", meta["imprint"]
      assert_equal "sequences", meta["genre"]
      assert_equal "hymniineditilitu55drev", meta["ia_identifier"]
      assert_equal "uncorrected-ocr", meta["text_nature"]
      assert_includes meta["ocr_note"], "Latin hymn texts"
      assert_nil meta["place"], "the imprint is the printing place, never a place claim"
      assert_equal "Leipzig: Fues's Verlag (R. Reisland)", doc("ah01-1886").metadata["imprint"]
    end

    def test_the_date_is_the_print_year_labeled_edition
      assert_equal({ "not_before" => 1922, "not_after" => 1922, "raw" => "1922", "class" => "edition" },
                   doc("ah55-1922").metadata["date"])
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["analecta-hymnica"]
    end

    def test_the_census_holds_one_item_per_volume
      items = KLASS::ITEMS
      assert_equal((1..55).to_a, items.map { |item| item.title[/Bd\. (\d+):/, 1].to_i })
      assert_equal 55, items.map(&:identifier).uniq.size
      years = items.map { |item| item.date["not_before"] }
      assert_equal [1886, 1922], years.minmax
      assert_equal years.sort, years, "the volumes appeared in number order"
      assert(items.all? { |item| item.date["not_before"] < 1931 }, "every print predates 1931 (PD)")
      assert_equal "analectahymnicam41drev", items[40].identifier
      assert_equal "hymniineditilitu42drev", items[41].identifier
      assert_equal "analectahymnicam50drevuoft", items[49].identifier
    end

    def test_census_reconciles_the_169_series_items
      rejected = KLASS::REJECTED.values.flatten
      assert_equal({ "no_hocr" => 72, "bundle" => 20, "other_copy" => 20, "folder_upload" => 1, "duplicate" => 1 },
                   KLASS::REJECTED.transform_values(&:size))
      assert_equal rejected.size, rejected.uniq.size
      adopted = KLASS::ITEMS.map(&:identifier)
      assert_empty adopted & rejected
      assert_empty KLASS::NOT_THE_SERIES & (adopted + rejected)
      assert_equal 169, adopted.size + rejected.size
    end

    # One pinned specimen per rejected grain, each skipped by the rule.
    def test_the_census_rule_rejects_each_pinned_grain
      {
        "analectahymnicam13drev_0" => "bundle", "analectahymnica01drevuoft" => "no_hocr",
        "analecta-hymnica-medii-aevi" => "folder_upload", "11338315bsb" => "not_the_series"
      }.each do |identifier, verdict|
        assert_equal verdict, KLASS.census_verdict(specimen(identifier)), identifier
        listed = KLASS::REJECTED.fetch(verdict, KLASS::NOT_THE_SERIES)
        assert_includes listed, identifier, "#{identifier} is reconciled under #{verdict}"
      end
    end

    def test_the_adopted_specimen_is_eligible_and_held
      assert_equal "eligible", KLASS.census_verdict(specimen("analectahymnicam01drev"))
      assert_includes KLASS::ITEMS.map(&:identifier), "analectahymnicam01drev"
    end

    def test_manifest_is_open_public_domain_and_declares_the_ocr
      manifest = KLASS.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "uncorrected machine OCR"
      assert_includes manifest.license, "1886–1922"
      assert_equal "ia-hocr-text", manifest.parser_family
    end

    def test_registry_row_is_registered_wired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["analecta-hymnica"]
      refute_nil entry
      assert entry.wired, "wired after the verified first sync of 2026-11-04 (55 docs / 17,211 passages, exactly the census)"
      assert_equal "manual", entry.sync_policy
      assert_equal %w[classical romance], entry.axes
    end

    def test_the_lect_override_stages_the_series_medieval
      overrides = YAML.safe_load_file(File.expand_path("../../config/lect_overrides.yml", __dir__))
      assert_equal({ "lect" => "lat:med", "tier" => "approximation" },
                   overrides.dig("sources", "analecta-hymnica", "lat"))
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "analecta-hymnica", name: "AH", adapter_class: KLASS.name,
                                          license_class: "open")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 2, first.added
      passages = db[:passages].count
      assert_equal 21, passages
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 2, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only) ------------------------------------------------

    BD55 = KLASS::ITEMS.last

    def test_fetch_lands_the_pair_under_upstream_file_names
      Nabu::Adapters::IaHocrText.paths(File.join(FIXTURES, BD55.identifier), BD55.file).each_value do |path|
        stub_request(:get, KLASS.download_url(BD55.identifier, File.basename(path)))
          .to_return(status: 200, body: File.binread(path))
      end
      Dir.mktmpdir do |workdir|
        report = KLASS.new(delay: 0, items: [BD55]).fetch(workdir)
        assert_includes report.notes, "1/1 item(s) held (+1 this sync)"
        assert File.file?(File.join(workdir, BD55.identifier, "hymniineditilitu55drev_hocr_searchtext.txt.gz"))
      end
    end

    # The shared walk keeps an item folder in the download path: a stem
    # "<folder>/<name>" fetches <identifier>/<folder>/<name>…, the "/" literal.
    def test_a_stem_inside_an_item_folder_keeps_its_folder
      item = BD55.with(identifier: "some-upload", file: "Some Folder/Vol. 55")
      base = "https://archive.org/download/some-upload/Some%20Folder/Vol.%2055"
      assert_equal "#{base}_hocr_searchtext.txt.gz",
                   KLASS.download_url("some-upload", "Some Folder/Vol. 55_hocr_searchtext.txt.gz")
      stub_request(:get, "#{base}_hocr_searchtext.txt.gz").to_return(status: 200, body: "t")
      stub_request(:get, "#{base}_hocr_pageindex.json.gz").to_return(status: 200, body: "i")
      Dir.mktmpdir do |workdir|
        KLASS.new(delay: 0, items: [item]).fetch(workdir)
        assert File.file?(File.join(workdir, "some-upload", "Some Folder", "Vol. 55_hocr_pageindex.json.gz"))
      end
    end
  end
end
