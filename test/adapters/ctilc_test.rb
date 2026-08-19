# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Ctilc (P80-8) — the CTILC public-domain works slice
  # (IEC): document = one downloadable work (urn from the OBRA id, never
  # the mojibake-prone title), passage = one blank-line paragraph of
  # <TEXT>; the pseudo-XML header (AUTOR/TÍTOL/ANY/CLASSIFICACIÓ_TEXTUAL)
  # parses by line rules, never an XML parser (non-ASCII tag names,
  # unescaped & in body text). Files are UTF-8 WITH BOM — the encoding
  # regression rides the real fixture bytes. The listing page supplies
  # each work's bibliographic citation + section (the only home of
  # publisher/place metadata).
  class CtilcTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("ctilc")

    LISTING_URL = Nabu::Adapters::Ctilc::LISTING_URL

    def conformance_adapter
      Nabu::Adapters::Ctilc.new(crawl_delay: 0)
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "ctilc"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_ctilc_unwired_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["ctilc"]
      refute_nil entry, "ctilc must be registered in config/sources.yml"
      refute entry.wired, "wired flips only after the owner verifies the first real sync"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "romance"
    end

    def test_manifest_records_the_pd_terms_and_the_unnamed_cc_caveat
      manifest = Nabu::Adapters::Ctilc.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "domini públic"
      assert_includes manifest.license, "Llei 21/2014"
      assert_includes manifest.license, "Aquest text ha estat digitalitzat i processat per " \
                                        "l'Institut d'Estudis Catalans",
                      "the mandatory citation sentence is recorded verbatim"
      assert_includes manifest.license, "CC variant", "the unnamed-CC caveat is recorded honestly"
      assert_equal "ctilc-txt", manifest.parser_family
    end

    def test_the_probe_heads_the_listing_against_its_file_fetch_state
      assert_equal :http_zip, Nabu::Adapters::Ctilc.remote_probe_strategy
      targets = Nabu::Adapters::Ctilc.http_probe_targets
      assert_equal 1, targets.size
      assert_equal LISTING_URL, targets.first.zip_url
      assert_equal Nabu::Adapters::Ctilc::LISTING_DIRNAME, targets.first.state_subdir
      assert_equal Nabu::FileFetch::STATE_FILE, targets.first.state_file
    end

    def test_ctilc_is_registered_for_the_structured_metadata_dates_shape
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["ctilc"],
                   "the ANY publication year rides the :structured one-year envelope (the sillok mold)"
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_work_in_id_order
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[urn:nabu:ctilc:41 urn:nabu:ctilc:1607 urn:nabu:ctilc:3392], refs.map(&:id),
                   "urns mint from the filename's zero-padded OBRA id, sorted numerically"
    end

    def test_discovery_skips_census_strays_that_are_not_the_out_txt_shape
      Dir.mktmpdir do |dir|
        works = File.join(dir, "works")
        FileUtils.mkdir_p(works)
        FileUtils.cp(File.join(FIXTURES, "works", "000041_Poemes_biblics.out.txt"), works)
        File.write(File.join(works, "stray.html"), "<html></html>")
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        assert_match(/stray\.html/, skips.notes.first)
      end
    end

    # -- parse ----------------------------------------------------------------

    def parse(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      refute_nil ref, "#{urn} must be discovered"
      adapter.parse(ref)
    end

    def test_parse_mints_paragraph_passages_with_header_metadata
      document = parse("urn:nabu:ctilc:41")
      assert_equal "Poemes bíblics", document.title
      assert_equal "cat", document.language
      assert_equal "Alcover, Joan", document.metadata["autor"]
      assert_equal 6, document.size, "one passage per blank-line paragraph of the trimmed fixture"
      assert_equal "urn:nabu:ctilc:41:1", document.first.urn
      assert_includes document.first.text, "Henoc és la ciutat mare"
      assert_includes document.first.text, "/An En Miquel d'Unamuno\\",
                      "upstream's own markers stay verbatim — canonical means canonical"
    end

    def test_the_bom_never_reaches_text_or_metadata
      raw = File.binread(File.join(FIXTURES, "works", "000041_Poemes_biblics.out.txt"))
      assert raw.start_with?("\xEF\xBB\xBF".b), "the fixture must keep the real upstream BOM"
      document = parse("urn:nabu:ctilc:41")
      refute_includes document.title, "﻿"
      document.each { |passage| refute_includes passage.text, "﻿" }
      assert(document.map(&:text).all? { |text| text.unicode_normalized?(:nfc) })
    end

    def test_the_any_year_rides_the_structured_date_envelope
      document = parse("urn:nabu:ctilc:41")
      assert_equal({ "not_before" => 1918, "not_after" => 1918, "raw" => "1918" },
                   document.metadata["date"])
    end

    def test_the_classificacio_attrs_ride_metadata_verbatim_with_the_variant_facet
      document = parse("urn:nabu:ctilc:41")
      classificacio = document.metadata["classificacio"]
      assert_equal "LIT", classificacio["llengua"]
      assert_equal "P", classificacio["gènere"]
      assert_equal "no", classificacio["traducció"]
      assert_equal "baleàric", classificacio["variant"]
      assert_equal({ "value" => "baleàric" }, document.metadata.dig("facets", "variant"),
                   "the dialect variant rides as a facet — the future lect seam, no rules yet")
    end

    def test_an_empty_variant_mints_no_facet
      document = parse("urn:nabu:ctilc:3392")
      assert_equal "sí", document.metadata["classificacio"]["traducció"]
      assert_equal "baleàric", document.metadata["classificacio"]["variant"]
      document = parse("urn:nabu:ctilc:41")
      assert_equal "", document.metadata["classificacio"]["tema"], "empty attrs stay empty, never nil"
    end

    def test_the_listing_citation_and_section_join_by_filename
      document = parse("urn:nabu:ctilc:41")
      assert_equal "LITERARI", document.metadata["section"]
      assert_equal "Alcover, Joan: Poemes bíblics. Barcelona: \"La Revista\", 1918.",
                   document.metadata["citation"], "the listing entry is the only home of imprint metadata"
      nolit = parse("urn:nabu:ctilc:1607")
      assert_equal "NO LITERARI", nolit.metadata["section"]
      assert_includes nolit.metadata["citation"], "Fills de Jaume Jepús"
      assert_equal "NLIT", nolit.metadata["classificacio"]["llengua"]
    end

    def test_a_translation_work_keeps_its_own_snippet
      document = parse("urn:nabu:ctilc:3392")
      assert_equal "Els sálms de David", document.title
      assert_equal({ "not_before" => 1840, "not_after" => 1840, "raw" => "1840" },
                   document.metadata["date"])
      assert_includes document.passages.map(&:text).join("\n"), "Son tánts els qui me tormèntan"
    end

    def test_a_filename_id_disagreeing_with_the_obra_id_quarantines
      Dir.mktmpdir do |dir|
        works = File.join(dir, "works")
        FileUtils.mkdir_p(works)
        body = File.binread(File.join(FIXTURES, "works", "000041_Poemes_biblics.out.txt"))
        File.binwrite(File.join(works, "000999_Poemes_biblics.out.txt"), body)
        adapter = conformance_adapter
        ref = adapter.discover(dir).first
        error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
        assert_match(/OBRA id/, error.message)
      end
    end

    # -- fetch (WebMock; listing via FileFetch + polite resumable crawl) ------

    WORK_FILES = %w[
      000041_Poemes_biblics.out.txt
      001607_La_llibertat_en_la_lley_civil.out.txt
      003392_Els_salms_de_David.out.txt
    ].freeze

    def stub_crawl(listing_body:)
      stub_request(:get, LISTING_URL)
        .to_return(status: 200, body: listing_body,
                   headers: { "Last-Modified" => "Tue, 19 Aug 2026 00:00:00 GMT" })
      WORK_FILES.each do |name|
        stub_request(:get, "#{Nabu::Adapters::Ctilc::WORK_URL}?fitxer=#{name}")
          .to_return(status: 200, body: File.binread(File.join(FIXTURES, "works", name)))
      end
    end

    def test_fetch_snapshots_the_listing_and_crawls_every_work
      listing_body = File.binread(File.join(FIXTURES, "listing", "CTILCCorpus_Descarr.html"))
      stub_crawl(listing_body: listing_body)
      Dir.mktmpdir do |dir|
        report = Nabu::Adapters::Ctilc.new(crawl_delay: 0).fetch(dir)
        assert File.file?(File.join(dir, "listing", "CTILCCorpus_Descarr.html"))
        WORK_FILES.each { |name| assert File.file?(File.join(dir, "works", name)), "#{name} crawled" }
        assert_match(/works: 3 fetched, 0 cached \(3 listed\)/, report.notes)
        assert_equal [LISTING_URL], report.repos.keys
      end
    end

    def test_fetch_is_resumable_valid_files_are_never_refetched
      listing_body = File.binread(File.join(FIXTURES, "listing", "CTILCCorpus_Descarr.html"))
      stub_crawl(listing_body: listing_body)
      Dir.mktmpdir do |dir|
        adapter = Nabu::Adapters::Ctilc.new(crawl_delay: 0)
        adapter.fetch(dir)
        stub_request(:get, LISTING_URL).to_return(status: 304)
        report = adapter.fetch(dir)
        assert_match(/works: 0 fetched, 3 cached/, report.notes)
      end
    end

    def test_fetch_replaces_a_truncated_file_and_attics_the_old_bytes
      listing_body = File.binread(File.join(FIXTURES, "listing", "CTILCCorpus_Descarr.html"))
      stub_crawl(listing_body: listing_body)
      Dir.mktmpdir do |dir|
        works = File.join(dir, "works")
        FileUtils.mkdir_p(works)
        truncated = "\xEF\xBB\xBF<DOCUMENT>\n<OBRA id=\"41\">\ncut off mid-transfer".b
        File.binwrite(File.join(works, "000041_Poemes_biblics.out.txt"), truncated)
        report = Nabu::Adapters::Ctilc.new(crawl_delay: 0).fetch(dir)
        assert_match(/works: 3 fetched, 0 cached/, report.notes)
        replaced = File.binread(File.join(works, "000041_Poemes_biblics.out.txt"))
        assert replaced.end_with?("</DOCUMENT>\n"), "the valid body replaced the truncated file"
        attic = File.join(dir, ".attic", "works", "000041_Poemes_biblics.out.txt")
        assert File.file?(attic), "replacement is non-destructive — the old bytes are atticked"
        assert_equal truncated, File.binread(attic)
      end
    end

    def test_fetch_with_an_entryless_listing_aborts_loudly
      stub_request(:get, LISTING_URL)
        .to_return(status: 200, body: "<html><body>nothing here</body></html>")
      Dir.mktmpdir do |dir|
        error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Ctilc.new(crawl_delay: 0).fetch(dir) }
        assert_match(/no work entries/, error.message)
      end
    end

    def test_fetch_aborts_on_a_body_that_is_not_a_complete_document
      listing_body = File.binread(File.join(FIXTURES, "listing", "CTILCCorpus_Descarr.html"))
      stub_crawl(listing_body: listing_body)
      stub_request(:get, "#{Nabu::Adapters::Ctilc::WORK_URL}?fitxer=000041_Poemes_biblics.out.txt")
        .to_return(status: 200, body: "<html>session expired</html>")
      Dir.mktmpdir do |dir|
        error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Ctilc.new(crawl_delay: 0).fetch(dir) }
        assert_match(%r{</DOCUMENT>}, error.message, "an error page is never persisted as a work")
      end
    end
  end
end
