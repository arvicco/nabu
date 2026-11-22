# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"
require "support/adapter_conformance"

module Adapters
  # syriac-htr-gt — the Syriac ground truth of the Vienna HTR Winter
  # Schools over two New Testament manuscripts: ÖNB Cod. Syr. 1 (Zenodo
  # 14714089, Serto, the Gospels, 1554) and St Mark's Monastery MS 36
  # (Zenodo 18157525, Estrangelo, 12th–14th c.). One adapter over both
  # records' page.zip (the page-xml family); document = page image,
  # passage = TextLine cited r<region>.l<line>. Fixture: five real pages
  # verbatim from the zips + the .DS_Store specimen (the rejected grain).
  class SyriacHtrGtTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("syriac-htr-gt")
    URN = "urn:nabu:syriac-htr-gt"
    ADAPTER = Nabu::Adapters::SyriacHtrGt

    def conformance_adapter = ADAPTER.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "syriac-htr-gt"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(id) = documents.find { |d| d.urn == "#{URN}:#{id}" } || flunk("#{id} missing")

    def passage(id, citation) = doc(id).find { |p| p.urn == "#{URN}:#{id}:#{citation}" } || flunk(citation)

    # --- discover + the rejected grain ----------------------------------------

    def test_discovers_one_document_per_page_image_keyed_by_manuscript_and_sequence
      assert_equal %W[#{URN}:onb-cod-syr-1:p0001 #{URN}:onb-cod-syr-1:p0159 #{URN}:onb-cod-syr-1:p0179
                      #{URN}:onb-cod-syr-1:p0319 #{URN}:smmj-36:p0071],
                   conformance_adapter.discover(FIXTURES).map(&:id)
      assert_empty(Dir.mktmpdir { |empty| conformance_adapter.discover(empty).to_a })
    end

    def test_the_finder_file_is_skipped_by_rule_and_strays_are_unrecognized
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
      assert_match(%r{onb-cod-syr-1/\.DS_Store: macOS Finder metadata}, skips.notes.join("\n"))

      Dir.mktmpdir do |work|
        FileUtils.cp_r(File.join(FIXTURES, "smmj-36"), work)
        File.write(File.join(work, "smmj-36", "mets.xml"), "<mets/>")
        FileUtils.mkdir_p(File.join(work, "images"))
        stray = conformance_adapter.discovery_skips(work)
        assert_equal 2, stray.unrecognized
        assert_match(%r{smmj-36/mets\.xml}, stray.notes.join("\n"))
        assert_match(/images: not a PAGE file/, stray.notes.join("\n"))
        assert_equal ["#{URN}:smmj-36:p0071"], conformance_adapter.discover(work).map(&:id)
      end
    end

    # --- passages -------------------------------------------------------------

    def test_lines_become_passages_cited_by_region_and_line_reading_order
      d = doc("onb-cod-syr-1:p0001")
      assert_equal "syc", d.language
      assert_equal 12, d.size
      gold = passage("onb-cod-syr-1:p0001", "r2.l1")
      assert_equal "ܥܠ ܚܝܠܗ\u00A0ܕܡܪܢ", gold.text, "upstream's own no-break space, verbatim"
      assert_equal "MainZone-gold", gold.annotations["region_type"], "the incipit in gold block letters"
      matthew = passage("onb-cod-syr-1:p0001", "r3.l1")
      assert_equal "ܟܬܒܐ ܕܝܠܝܕܘܬܗ ܕܝܫܘܥ ܡܫܝܚܐ ܒܪܗ ܕܕܘܝܕ ܒܪܗ ܕܐܒܪܗܡ.", matthew.text
      assert_equal "MainZone", matthew.annotations["region_type"]
      folio = passage("onb-cod-syr-1:p0001", "r4.l1")
      assert_equal %w[1v NumberingZone], [folio.text, folio.annotations["region_type"]]
      assert_equal [12, 22, 21, 5, 134], documents.map(&:size)
    end

    def test_empty_lines_mint_nothing_and_keep_the_following_citations
      d = doc("onb-cod-syr-1:p0159")
      assert_equal "#{URN}:onb-cod-syr-1:p0159:r3.l1", d.passages.first.urn,
                   "the two empty margin lines (r1.l1, r2.l1) mint nothing; r3 keeps its ordinal"
      refute d.passages.first.annotations.key?("region_type"), "a structure-less Transkribus region types nothing"
    end

    def test_non_canonical_mark_order_is_normalized_at_the_boundary
      line = doc("onb-cod-syr-1:p0179").find { |p| p.annotations["line_id"] == "eSc_line_6952d7b5" }
      assert line.text.end_with?("ܘܝ̣̇ܬܝܪ"), "dot below (ccc 220) before dot above (ccc 230)"
      assert line.text.unicode_normalized?(:nfc)
    end

    def test_transkribus_tags_ride_offset_addressed_with_their_values
      unclear = passage("smmj-36:p0071", "r1.l1")
      assert_equal [{ "offset" => 1, "length" => 6, "form" => "ܡܪܣܟܝܢ", "alternative" => "ܡܬܘܟܝܢ" }],
                   unclear.annotations["unclear"]
      sic = passage("smmj-36:p0071", "r1.l30")
      assert_equal "ܘܗܝ ܐܝܬ", sic.annotations["sic"].first["form"]
      assert_equal "ܐܝܬܘܗܝ", sic.annotations["sic"].first["correction"]
      person = passage("smmj-36:p0071", "r1.l25")
      assert_equal [{ "offset" => 8, "length" => 10, "form" => "ܫܡܥܘܢ ܟܐܦܐ" }], person.annotations["person"]
    end

    def test_transkribus_value_escapes_are_decoded
      span = Nabu::Adapters::PageXmlParser::Span.new(tag: "unclear", offset: 0, length: 1, form: "ܐ",
                                                     attributes: { "reason" => "no\\u0020erasure" })
      assert_equal "no erasure", conformance_adapter.send(:span_annotation, span)["reason"]
    end

    # --- metadata and axes ----------------------------------------------------

    def test_the_onb_pages_carry_the_colophon_date_and_vienna
      meta = doc("onb-cod-syr-1:p0319").metadata
      assert_equal 1554, meta["date"]["not_before"]
      assert_equal 1554, meta["date"]["not_after"]
      assert_equal "1545", meta["record_date"], "the record's own claim rides verbatim beside the colophon's"
      assert_equal "Vienna", meta["place"]
      assert_equal "Moses of Mardin", meta["scribe"]
      assert_equal "Serto", meta["script_style"]
      assert_equal "00000334", meta["image_id"]
      colophon = passage("onb-cod-syr-1:p0319", "r1.l1")
      assert_equal "ܫܢܬ ܐܠܦ ܘܚܡܫܡܐ ܘ ܚܡܫܝܢ ܘܐܪܒܥܐ ܡܫܝܚ̈ܝܬܐ: ܒܐܝܪܚ", colophon.text,
                   "the year 1554 of the Messiah — the date the metadata carries"
    end

    def test_the_st_marks_pages_carry_the_century_band_and_no_place
      meta = doc("smmj-36:p0071").metadata
      assert_equal({ "not_before" => 1100, "not_after" => 1399, "raw" => "approximately 12th - 14th century" },
                   meta["date"])
      refute meta.key?("place"), "Jerusalem is where it is kept, never its claimed origin"
      assert_equal "Estrangelo", meta["script_style"]
      assert_equal 71, meta["transkribus_page_nr"]
      assert_equal "DONE", meta["transkribus_status"]
      assert_equal "11622279", meta["transkribus_doc_id"]
      assert_equal "SMMJ_00036__076", meta["image_id"]
      assert_match(/St Mark's Monastery MS 36/, doc("smmj-36:p0071").title)
    end

    def test_the_artifact_dates_ride_the_structured_metadata_dates_lane
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["syriac-htr-gt"]
    end

    # --- manifest + registry --------------------------------------------------

    def test_manifest_records_both_license_statements_honestly
      manifest = ADAPTER.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC BY 4.0"
      assert_includes manifest.license, "CC-BY-SA-4.0"
      assert_includes manifest.license, "10.5281/zenodo.18157525"
      assert_equal "page-xml", manifest.parser_family
    end

    def test_registry_row_is_wired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
      entry = registry["syriac-htr-gt"]
      refute_nil entry
      assert entry.wired, "wired after the verified first sync (273 pages / 20,706 lines, 2026-11-22)"
      assert_equal "manual", entry.sync_policy
      assert_equal ADAPTER, entry.adapter_class
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "syriac-htr-gt", name: "Syriac HTR ground truth",
                                          adapter_class: "Nabu::Adapters::SyriacHtrGt",
                                          license_class: "attribution")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 5, first.added
      assert_equal 194, db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 5, second.skipped
      assert_equal 194, db[:passages].count
      assert_equal [1], db[:passages].distinct.select_map(:revision)
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only) -------------------------------------------------
    # 14714089's zip carries one top directory (page/, stripped by
    # ZipFetch); 18157525's carries its pages at the root.

    def zip_bodies
      @zip_bodies ||= Dir.mktmpdir do |tmp|
        onb = File.join(tmp, "onb", "page")
        FileUtils.mkdir_p(onb)
        FileUtils.cp(File.join(FIXTURES, "onb-cod-syr-1", "0319_00000334.xml"), onb)
        smmj = File.join(tmp, "smmj")
        FileUtils.mkdir_p(smmj)
        FileUtils.cp(File.join(FIXTURES, "smmj-36", "0071_SMMJ_00036__076.xml"), smmj)
        Dir.chdir(File.join(tmp, "onb")) { Nabu::Shell.run("zip", "-qr", File.join(tmp, "onb.zip"), "page") }
        Dir.chdir(smmj) { Nabu::Shell.run("zip", "-q", File.join(tmp, "smmj.zip"), "0071_SMMJ_00036__076.xml") }
        { "onb-cod-syr-1" => File.binread(File.join(tmp, "onb.zip")),
          "smmj-36" => File.binread(File.join(tmp, "smmj.zip")) }
      end
    end

    def stub_zips(bodies = zip_bodies)
      ADAPTER::MANUSCRIPTS.each do |manuscript|
        stub_request(:get, ADAPTER.zip_url(manuscript))
          .to_return(status: 200, body: bodies.fetch(manuscript.key),
                     headers: { "Last-Modified" => "Mon, 05 Jan 2026 20:42:00 GMT" })
      end
    end

    def pins = zip_bodies.transform_values { |body| Digest::MD5.hexdigest(body) }

    def test_fetch_unpacks_both_page_trees_md5_verified
      stub_zips
      Dir.mktmpdir do |workdir|
        report = ADAPTER.new(pins: pins).fetch(workdir)
        assert_match(/\A\h{64}\z/, report.sha)
        assert_match(/onb-cod-syr-1: md5 pin verified/, report.notes)
        assert File.file?(File.join(workdir, "onb-cod-syr-1", "0319_00000334.xml")), "page/ stripped"
        assert File.file?(File.join(workdir, "smmj-36", "0071_SMMJ_00036__076.xml"))
        assert_equal ["#{URN}:onb-cod-syr-1:p0319", "#{URN}:smmj-36:p0071"],
                     ADAPTER.new.discover(workdir).map(&:id)
      end
    end

    def test_an_md5_mismatch_aborts_before_either_tree_mutates
      stub_zips
      Dir.mktmpdir do |workdir|
        wrong = pins.merge("smmj-36" => "0" * 32)
        error = assert_raises(Nabu::FetchError) { ADAPTER.new(pins: wrong).fetch(workdir) }
        assert_match(/smmj-36 page\.zip misses the record's published md5/, error.message)
        refute File.exist?(File.join(workdir, "onb-cod-syr-1", "0319_00000334.xml")),
               "nothing lands until every pin verifies"
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      ADAPTER::MANUSCRIPTS.each { |m| stub_request(:get, ADAPTER.zip_url(m)).to_return(status: 500) }
      Dir.mktmpdir do |workdir|
        assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(workdir) }
      end
    end
  end
end
