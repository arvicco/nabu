# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "support/adapter_conformance"

module Adapters
  # bu-ajami — Boston University's NEH Ajami collection: typed romanized
  # transcriptions of Hausa, Mandinka, Fula (Pular) and Wolof Ajami
  # manuscripts, one document per item, one passage per transcription-PDF
  # page. Fixtures (test/fixtures/bu-ajami, laid out as canonical/ holds
  # them): three items with their PDFs + the RECORDED mutool text layers,
  # and one Fula item page whose PDF is absent (discover skips it).
  class BuAjamiTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("bu-ajami")
    KLASS = Nabu::Adapters::BuAjami
    URN = "urn:nabu:bu-ajami"

    # The recorded text layers (mutool 1.28 on the cutting box) — the
    # suite never depends on mutool being installed (the local-library
    # law); the guarded live test pins agreement when mutool is present.
    RECORDED = lambda do |path|
      layer = File.join(FIXTURES, "textlayers", "#{File.basename(path, '.pdf')}.txt")
      pages = File.read(layer, encoding: "UTF-8").split("\f", -1)
      pages.pop if pages.last.to_s.strip.empty?
      pages
    end

    def conformance_adapter = KLASS.new(pdf_text: RECORDED, delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "bu-ajami"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(key) = documents.find { |d| d.urn == "#{URN}:#{key}" } || flunk("#{key} missing")

    def test_discovers_items_whose_transcription_is_held
      assert_equal %W[#{URN}:hausa:falke-2729-wakar-sarkin-kano #{URN}:mandinka:mandinkakan-leetaroolu-3
                      #{URN}:wolof:bakk-wi],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort,
                   "fula/coora's page is held but its PDF is not — no document"
    end

    def test_each_item_claims_its_language_at_the_honest_grain
      assert_equal "ha", doc("hausa:falke-2729-wakar-sarkin-kano").language
      assert_equal "mnk", doc("mandinka:mandinkakan-leetaroolu-3").language
      assert_equal "wo", doc("wolof:bakk-wi").language
      assert_equal({ "fula" => "fuf", "hausa" => "ha", "mandinka" => "mnk", "wolof" => "wo" }, KLASS::LANGUAGES)
      assert(documents.all? { |d| d.passages.all? { |p| p.language == d.language } })
    end

    def test_one_passage_per_pdf_page_and_the_citation_header_moves_to_metadata
      d = doc("hausa:falke-2729-wakar-sarkin-kano")
      assert_equal ["#{URN}:hausa:falke-2729-wakar-sarkin-kano:p1"], d.passages.map(&:urn)
      text = d.passages.first.text
      assert text.start_with?("1\nWaƙar Sarkin Kano\nWa bi nastaʿīnu"), text[0, 80]
      refute_includes text, "Citation"
      assert_match(/\ACitation: Fallou Ngom \(PI\), .* 2022\. “A Poem in Honor of the Emir of Kano\.” http/,
                   d.metadata["pdf_citation"])
      assert_equal 15, doc("wolof:bakk-wi").passages.size
      assert_equal (1..15).map { |n| "#{URN}:wolof:bakk-wi:p#{n}" }, doc("wolof:bakk-wi").passages.map(&:urn)
    end

    def test_the_running_citation_header_is_cut_from_every_page
      documents.each do |d|
        d.passages.each { |p| refute_includes p.text, "Citation", p.urn }
      end
      second = doc("wolof:bakk-wi").passages[1]
      assert second.text.start_with?("2\nJokku naa jekk naa ji"), second.text[0, 40]
    end

    def test_manuscript_page_markers_ride_as_annotations_and_stay_in_the_text
      first = doc("mandinka:mandinkakan-leetaroolu-3").passages.first
      assert_equal({ "pdf_page" => 1, "ms_pages" => ["Document 1: Page 1"] }, first.annotations)
      assert_includes first.text, "[Document 1: Page 1]"
      assert_equal({ "pdf_page" => 1 }, doc("hausa:falke-2729-wakar-sarkin-kano").passages.first.annotations)
    end

    def test_item_metadata_is_mined_whole
      meta = doc("hausa:falke-2729-wakar-sarkin-kano").metadata
      assert_equal "A Poem in Honor of the Emir of Kano (Waƙar Sarkin Kano)", meta["title"]
      assert_equal "Abd al-Wahhab Adam al-Falaki (author), Umar Falke (owner)", meta["author_or_owner"]
      assert_equal "Kano, Nigeria", meta["provenance"]
      assert_equal "Kano, Nigeria", meta["place"]
      assert_equal "Poetry", meta["genre"]
      assert_equal({ "genre" => { "value" => "Poetry" } }, meta["facets"])
      assert_equal "Hausa", meta["upstream_language"]
      assert_equal "Hausa Ajami", meta["manuscript_script"]
      assert_equal "Handwritten", meta["manuscript_type"]
      assert_equal "Unpublished", meta["publisher"]
      assert_equal "Literature, Eulogy for the Emir of Kano, Abdullahi Bayero, Diplomacy, England", meta["subject"]
      assert_match(/Creative Commons Attribution-Non-Commercial 4\.0/, meta["rights"])
      assert_includes meta["contributors"], "Mustapha Hashim Kurfi"
      assert_equal "https://sites.bu.edu/nehajami/the-four-languages/hausa/hausa-manuscripts/" \
                   "falke-2729-wakar-sarkin-kano/", meta["item_url"]
      assert_equal "https://sites.bu.edu/nehajami/files/2022/02/Falke-2729_Transcription.pdf",
                   meta["transcription_url"]
      assert_equal "https://sites.bu.edu/nehajami/files/2022/02/Falke-2729_English-translation.pdf",
                   meta.dig("translation_urls", "en")
      refute_empty meta["manuscript_image_urls"]
      assert_match(/romanized/, meta["text_script"])
      assert_equal "A Poem in Honor of the Emir of Kano (Waƙar Sarkin Kano)",
                   doc("hausa:falke-2729-wakar-sarkin-kano").title
    end

    def test_stated_composition_eras_are_dated_as_their_own_class
      date = doc("hausa:falke-2729-wakar-sarkin-kano").metadata["date"]
      assert_equal [1953, 1953, "composition"], date.values_at("not_before", "not_after", "class")
      assert_includes date["basis"], "trip to London"
      bakk = doc("wolof:bakk-wi").metadata["date"]
      assert_equal [1889, 1963, "composition"], bakk.values_at("not_before", "not_after", "class")
      assert_nil doc("mandinka:mandinkakan-leetaroolu-3").metadata["date"], "nothing stated — nothing claimed"
    end

    def test_a_typed_year_in_the_source_reference_is_an_artifact_date
      date = KLASS.typed_date("Aminu na Baban, “Waƙar Aure a Ƙasar Hausa” (1968/9). Courtesy of Northwestern")
      assert_equal({ "not_before" => 1968, "not_after" => 1969, "raw" => "(1968/9)",
                     "basis" => "the source reference's typed year" }, date)
      assert_equal [1965, 1968], KLASS.typed_date("Amin Na Baban-Inda, “Mai Sana’a” (1965/1968). Courtesy")
                                      .values_at("not_before", "not_after")
      assert_nil KLASS.typed_date("Umar Falke, “Yabo ga Ahmad Tijani” (nd). Courtesy of Northwestern")
      assert_nil KLASS.typed_date("Mouhamadou L. Diallo and Fallou Ngom. 2016. African Ajami Library"),
                 "a digitization project's year is not the text's"
    end

    def test_the_curated_date_table_is_well_formed
      assert_operator KLASS::DATES.size, :>=, 25
      KLASS::DATES.each do |key, date|
        assert_match(%r{\A(fula|hausa|mandinka|wolof)/[a-z0-9-]+\z}, key)
        assert_operator date["not_before"], :<=, date["not_after"], key
        assert_includes [nil, "composition"], date["class"], key
        refute_empty date["basis"].to_s, "#{key}: every curated date quotes its basis"
      end
    end

    def test_the_metadata_dates_lane_reads_the_structured_shape_with_its_class
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["bu-ajami"]
      meta = { "date" => { "not_before" => 1889, "not_after" => 1963, "raw" => "x", "class" => "composition" } }
      assert_equal [1889, 1963, "x", nil, "composition"],
                   Nabu::Store::TimelineBuilder::MetadataDates.structured(meta)
    end

    def test_manifest_is_nc_and_credits_the_collection
      manifest = KLASS.manifest
      assert_equal "nc", manifest.license_class
      assert_includes manifest.license, "Creative Commons Attribution-Non-Commercial 4.0"
      assert_includes manifest.license, "Fallou Ngom"
      assert_equal "bu-ajami-html", manifest.parser_family
    end

    def test_registry_row_is_registered_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["bu-ajami"]
      refute_nil entry
      refute entry.wired, "wired: false until the first real sync is verified"
      assert_equal "manual", entry.sync_policy
    end

    def test_an_unreadable_pdf_is_a_parse_error
      broken = KLASS.new(pdf_text: ->(_path) { raise Nabu::PdfText::Error, "mutool exploded" }, delay: 0)
      ref = broken.discover(FIXTURES).first
      assert_raises(Nabu::ParseError) { broken.parse(ref) }
    end

    def test_fetch_failure_is_a_fetch_error
      stub_request(:get, Nabu::BuAjamiFetch.list_url(1)).to_return(status: 500)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { KLASS.new(delay: 0).fetch(File.join(dir, "bu-ajami")) }
      end
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "bu-ajami", name: "NEH Ajami", adapter_class: KLASS.name,
                                          license_class: "nc")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, first.added
      passages = db[:passages].count
      assert_equal 1 + 15 + documents.find { |d| d.urn.include?("mandinka") }.passages.size, passages
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end

    # -- live mutool (present on the owner's box, absent in CI) ------------

    def test_real_mutool_extraction_agrees_with_the_recorded_layers
      skip "mutool not on PATH — the recorded-extraction tests carry the suite" unless mutool_available?

      Dir.glob(File.join(FIXTURES, "files", "**", "*.pdf")).each do |pdf|
        live = Nabu::PdfText.pages(pdf)
        assert_equal RECORDED.call(pdf).map { |p| p.split("\n").map(&:rstrip) },
                     live.map { |p| p.split("\n").map(&:rstrip) },
                     "#{File.basename(pdf)}: the checked-in layer must stay what mutool extracts"
      end
    end

    private

    def mutool_available?
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        File.executable?(File.join(dir, "mutool"))
      end
    end
  end
end
