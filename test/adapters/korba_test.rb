# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # korba — the KorBa manually annotated subcorpus 2.0 (Electronic Corpus
  # of 17th- and 18th-century Polish Texts, IJP PAN; P116-1): ONE zip of
  # NKJP-format TEI text directories, split by project stage into
  # TEI_korba1/ and TEI_korba2/. Grain: document = one text directory,
  # passage = one <ab> block (nkjp-tei family), the manual morphosyntax as
  # gold token annotations. Fixture: six real texts from the v2.0 tree,
  # trimmed consistently across their four layers (README).
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

    def text_dir(name) = Dir.glob(File.join(FIXTURES, "TEI_korba*", name)).first || flunk("#{name} missing")

    def test_discovers_one_document_per_text_directory_across_both_stage_folders
      assert_equal ["#{URN}:AkDziec", "#{URN}:AkZbrojGęb", "#{URN}:AndPiekBoh", "#{URN}:AugustKopia",
                    "#{URN}:HumListRzecz", "#{URN}:LubJMan"],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_the_urn_is_the_text_id_alone_never_the_stage_folder
      # The v1.2 (2021) archive held the stage-1 texts flat; v2.0 nests them
      # under TEI_korba1/. Dirnames are unique across both stage folders
      # (censused on the live tree), so the URN stays the bare text id and
      # the stage-1 URNs are the 2021 build's URNs unchanged.
      ref = conformance_adapter.discover(FIXTURES).find { |r| r.id == "#{URN}:AkDziec" }
      assert_equal File.expand_path(File.join(FIXTURES, "TEI_korba1", "AkDziec")), ref.path
    end

    def test_a_flat_text_directory_outside_the_stage_folders_is_not_discovered
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(text_dir("AkDziec"), File.join(dir, "AkDziec"))
        assert_empty conformance_adapter.discover(dir).to_a, "only the v2.0 TEI_korba<n>/<text>/ layout is the asset"
      end
    end

    def test_the_project_stage_rides_as_metadata
      assert_equal 1, doc("AkDziec").metadata["project_stage"]
      assert_equal 2, doc("AugustKopia").metadata["project_stage"]
    end

    def test_stage_two_samples_carry_the_annotator_plus_tagger_regime
      assert_equal "annotator + tagger + adjudicator", doc("AugustKopia").metadata["annotation"],
                   "the corpus header: in the second stage the two passes were an annotator and the tagger"
    end

    def test_stage_two_unknown_sentinels_mint_nothing
      meta = doc("AugustKopia").metadata
      assert_nil meta["place"], "\"nieznane\" (unknown)"
      assert_nil meta["region"], "\"nieznany\" — the stage-2 headers' masculine spelling of the region sentinel"
      assert_equal({ "not_before" => 1704, "not_after" => 1704, "raw" => "1704" }, meta["date"])
      assert_equal "August II Mocny", meta["author"]
    end

    def test_urns_are_nfc_even_when_the_filesystem_hands_back_nfd
      Dir.mktmpdir do |dir|
        nfd = "AkZbrojGęb".unicode_normalize(:nfd)
        FileUtils.mkdir_p(File.join(dir, "TEI_korba1"))
        FileUtils.cp_r(text_dir("AkZbrojGęb"), File.join(dir, "TEI_korba1", nfd))
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

    # <editor role="translator"> in the original bibl names the translator
    # of a translated work (322 headers) — verbatim, the translator facet.
    def test_the_translator_rides_metadata
      meta = doc("AndPiekBoh").metadata
      assert_equal "Krzysztof Piekarski", meta["translator"]
      assert_equal "Francesco Andreini", meta["author"], "the original's author stays the author"
      assert_nil doc("AkZbrojGęb").metadata["translator"], "an untranslated text claims no translator"
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
        FileUtils.mkdir_p(File.join(dir, "TEI_korba1"))
        FileUtils.cp_r(text_dir("LubJMan"), File.join(dir, "TEI_korba1", "LubJMan_s"))
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

    def test_registry_row_is_wired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["korba"]
      refute_nil entry
      assert entry.wired, "first full parse verified 2026-10-14 (2,091 docs / 10,281 passages)"
      assert_equal "manual", entry.sync_policy
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "korba", name: "KorBa", adapter_class: "Nabu::Adapters::Korba",
                                          license_class: "attribution")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 6, first.added
      assert_equal 9, db[:passages].count, "3 + 1 + 1 + 1 + 1 + 2 blocks across the six trimmed texts"
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 6, second.skipped
      assert_equal 9, db[:passages].count
      assert_equal [1], db[:passages].distinct.select_map(:revision)
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only) -------------------------------------------------
    # The v2.0 tree lands as canonical/korba/{KorBa_manual_header.xml,
    # TEI_korba1/, TEI_korba2/} (a single wrapping top dir, if any, is
    # stripped by ZipFetch).

    def zip_body
      @zip_body ||= Dir.mktmpdir do |tmp|
        stage = File.join(tmp, "stage", "korba_corpus")
        FileUtils.mkdir_p(File.join(stage, "TEI_korba1"))
        FileUtils.cp(File.join(FIXTURES, "KorBa_manual_header.xml"), stage)
        FileUtils.cp_r(text_dir("AkDziec"), File.join(stage, "TEI_korba1"))
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
        assert File.file?(File.join(workdir, "TEI_korba1", "AkDziec", "text.xml"))
        assert_equal ["#{URN}:AkDziec"], Nabu::Adapters::Korba.new.discover(workdir).map(&:id)
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      stub_request(:get, Nabu::Adapters::Korba::ZIP_URL).to_return(status: 502)
      Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { Nabu::Adapters::Korba.new.fetch(workdir) } }
    end
  end
end
