# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # korba — the KorBa manually annotated subcorpus 2.0 (Electronic Corpus
  # of 17th- and 18th-century Polish Texts, IJP PAN; P116-1): ONE zip of
  # NKJP-format TEI text directories. Grain: document = one text directory,
  # passage = one <ab> block (nkjp-tei family), the manual morphosyntax as
  # gold token annotations. Fixture: three real texts trimmed consistently
  # across their four layers (AkZbrojGęb, AkDziec, AndPiekBoh).
  class KorbaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("korba")
    URN = "urn:nabu:korba"

    def conformance_adapter = Nabu::Adapters::Korba.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "korba"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(slug) = documents.find { |d| d.urn == "#{URN}:#{slug}" } || flunk("#{slug} missing")

    def test_discovers_one_document_per_text_directory
      assert_equal ["#{URN}:AkDziec", "#{URN}:AkZbrojGęb", "#{URN}:AndPiekBoh", "#{URN}:HumListRzecz",
                    "#{URN}:LubJMan"],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_urns_are_nfc_even_when_the_filesystem_hands_back_nfd
      Dir.mktmpdir do |dir|
        nfd = "AkZbrojGęb".unicode_normalize(:nfd)
        FileUtils.cp_r(File.join(FIXTURES, "AkZbrojGęb"), File.join(dir, nfd))
        ids = conformance_adapter.discover(dir).map(&:id)
        assert_equal ["#{URN}:AkZbrojGęb".unicode_normalize(:nfc)], ids
      end
    end

    def test_blocks_become_passages_cited_by_the_ab_number
      d = doc("AkZbrojGęb")
      assert_equal "pl", d.language
      first = d.passages.first
      assert_equal "#{URN}:AkZbrojGęb:1.1", first.urn
      assert_match(/\A1692, d\. 24 Januarii accessit z Jaworowa działo spiżowe/, first.text)
      assert_equal ["132"], first.annotations["pages"]
      assert_equal "txt_2.1.22.4-p", first.annotations["n"]
      assert_equal 3, d.passages.size
    end

    def test_tokens_ride_as_gold_annotations_with_lemma_and_tag
      tokens = doc("AkDziec").passages.first.annotations["tokens"]
      jezeli = tokens.find { |t| t["form"] == "Ieżeli" }
      assert_equal({ "form" => "Ieżeli", "orth" => "Jeżeli", "lemma" => "jeżeli" },
                   jezeli.slice("form", "orth", "lemma"))
      refute(tokens.any? { |t| t["form"] == "uczyni" }, "rejected segmentation alternatives are not tokens")
    end

    def test_foreign_spans_and_their_tokens_carry_the_language
      passage = doc("AndPiekBoh").passages.first
      assert_equal "la", passage.annotations["foreign"].first["lang"]
      assert_equal [{ "reason" => "unreadable", "text" => "subiscit" }], passage.annotations["uncertain"]
      assert_equal "la", passage.annotations["tokens"].find { |t| t["form"] == "Quod" }["lang"]
    end

    def test_header_axes_are_mined
      meta = doc("AkZbrojGęb").metadata
      assert_equal "Inwentarz akcesyjny zbrojowni zamku Żółkiewskiego", doc("AkZbrojGęb").title
      assert_equal({ "not_before" => 1690, "not_after" => 1693, "raw" => "między 1690 a 1693" }, meta["date"])
      assert_equal "Żółkiew", meta["place"]
      assert_equal "Ziemie Ruskie", meta["region"]
      assert_equal "Anonim", meta["author"]
      assert_equal({ "value" => "kanc", "raw" => "kanc" }, meta.dig("facets", "genre"))
      assert_equal({ "value" => "inwentarze", "raw" => "inwentarze" }, meta.dig("facets", "kind"))
      assert_equal({ "value" => "wojskowość", "raw" => "wojskowość" }, meta.dig("facets", "subject"))
      assert_equal({ "value" => "proza", "raw" => "proza" }, meta.dig("facets", "text_form"))
      assert_equal "Mieczysław Gębarowicz", meta.dig("modernized_edition", "editor"),
                   "a text keyed from a modernized edition says so"
    end

    def test_a_printed_text_carries_its_print_year_and_publisher
      meta = doc("AkDziec").metadata
      assert_equal({ "not_before" => 1761, "not_after" => 1761, "raw" => "1761" }, meta["date"])
      assert_equal "Wilno", meta["place"]
      assert_equal "Drukarnia JKM i Rzeczypospolitej Scholarum Piarum", meta["publisher"]
    end

    def test_the_annotation_regime_and_header_availability_ride_as_metadata
      assert_equal "two annotators + adjudicator", doc("AkDziec").metadata["annotation"]
      assert_equal "free", doc("AkDziec").metadata["availability"]
      assert_equal "restricted", doc("AkZbrojGęb").metadata["availability"],
                   "the per-text header flag is recorded verbatim (the download page is the grant)"
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "LubJMan"), File.join(dir, "LubJMan_s"))
        ref = conformance_adapter.discover(dir).first
        assert_equal "single annotator", conformance_adapter.parse(ref).metadata["annotation"],
                     "the corpus header: an \"_s\" id marks a single-annotator sample"
      end
    end

    def test_unknown_place_and_region_mint_nothing
      meta = doc("HumListRzecz").metadata
      assert_nil meta["place"], "\"nieznane\" (unknown) is the corpus's absent-place sentinel"
      assert_nil meta["region"]
      assert_equal({ "not_before" => 1734, "not_after" => 1734, "raw" => "1734" }, meta["date"])
    end

    def test_multi_code_categories_become_multi_value_facets
      assert_equal({ "values" => %w[historia wojskowość], "raw" => "historia wojskowość" },
                   doc("HumListRzecz").metadata.dig("facets", "subject"))
    end

    def test_the_date_rides_the_structured_metadata_dates_lane
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["korba"]
    end

    def test_manifest_records_the_download_page_license
      manifest = Nabu::Adapters::Korba.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC BY-SA 4.0"
      assert_includes manifest.license, "Creative Commons Attribution Share Alike"
    end

    def test_registry_row_is_ready_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["korba"]
      refute_nil entry
      refute entry.wired
      assert_equal "manual", entry.sync_policy
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "korba", name: "KorBa", adapter_class: "Nabu::Adapters::Korba",
                                          license_class: "attribution")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 5, first.added
      assert_equal 7, db[:passages].count, "3 + 1 + 1 + 1 + 1 blocks across the five trimmed texts"
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 5, second.skipped
      assert_equal 7, db[:passages].count
      assert_equal [1], db[:passages].distinct.select_map(:revision)
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only) -------------------------------------------------
    # The real zip carries ONE top-level directory (korba_corpus/), stripped
    # by ZipFetch so the text directories land at canonical/korba/<text>/.

    def zip_body
      @zip_body ||= Dir.mktmpdir do |tmp|
        stage = File.join(tmp, "stage", "korba_corpus")
        FileUtils.mkdir_p(stage)
        FileUtils.cp_r(File.join(FIXTURES, "AkDziec"), stage)
        zip = File.join(tmp, "korba_xml.zip")
        Dir.chdir(File.join(tmp, "stage")) { Nabu::Shell.run("zip", "-qr", zip, "korba_corpus") }
        File.binread(zip)
      end
    end

    def test_fetch_unpacks_the_text_tree_and_discover_finds_it
      stub_request(:get, Nabu::Adapters::Korba::ZIP_URL)
        .to_return(status: 200, body: zip_body, headers: { "Last-Modified" => "Mon, 07 Jun 2021 14:18:27 GMT" })
      Dir.mktmpdir do |workdir|
        report = Nabu::Adapters::Korba.new.fetch(workdir)
        assert_match(/\A\h{64}\z/, report.sha)
        assert File.file?(File.join(workdir, "AkDziec", "text.xml"))
        assert_equal ["#{URN}:AkDziec"], Nabu::Adapters::Korba.new.discover(workdir).map(&:id)
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      stub_request(:get, Nabu::Adapters::Korba::ZIP_URL).to_return(status: 502)
      Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { Nabu::Adapters::Korba.new.fetch(workdir) } }
    end
  end
end
