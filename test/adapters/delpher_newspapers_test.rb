# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"
require "support/adapter_conformance"

module Adapters
  # delpher-newspapers — the Delpher open newspaper archive (KB): period
  # zips of issue folders (DIDL + articletext + ALTO). Document = issue,
  # passage = article. Fixture: four real 16xx issues + the zip-root
  # furniture + two trimmed ALTO pages (README.md).
  class DelpherNewspapersTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("delpher-newspapers")
    URN = "urn:nabu:delpher-newspapers"
    ADAPTER = Nabu::Adapters::DelpherNewspapers
    ISSUES = %w[ddd:010500649 MMKB08:000213603 ddd:010899278 ddd:011225333 ddd:011005283].freeze

    def conformance_adapter = ADAPTER.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "delpher-newspapers"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(id) = documents.find { |d| d.urn == "#{URN}:#{id}" } || flunk("#{id} missing")

    # The fixture as it lands in canonical/delpher-newspapers/ (README.md
    # is the fixture's own furniture, not upstream's).
    def landed_tree
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "kranten_pd_16xx"), dir)
        yield dir
      end
    end

    # -- upstream packaging gaps (the first retrieval's 4 quarantines) -----------

    # Four 16xx issues name articles the zip never carried text for: a0001
    # of the 1650 Courante has no articletext resource in its own DIDL, and
    # a named file can be absent from the folder. Both ride the
    # missing_articles metadata (the empty-OCR pattern) — the issue keeps
    # its present articles instead of quarantining away real news text.
    def test_an_article_without_text_rides_missing_articles
      document = documents.find { |d| d.urn.end_with?("ddd:010899278") }
      assert_equal 2, document.passages.size, "a2 and a3 are the fixture's present articles"
      assert_equal %w[a0001 a0004 a0005 a0006 a0007 a0008 a0009], document.metadata["missing_articles"]
      assert_equal 9, document.metadata["article_count"]
    end

    # -- discovery ---------------------------------------------------------------

    def test_discovers_one_document_per_issue_folder
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal(ISSUES.map { |id| "#{URN}:#{id}" }, refs.map(&:id))
      assert(refs.all? { |ref| ref.path.end_with?("/didl.xml") && ref.metadata["zip"] == "kranten_pd_16xx" })
    end

    def test_issue_ids_come_from_both_folder_schemes
      assert_equal "ddd:010500649", ADAPTER.issue_id("DDD_ddd_010500649_mpeg21")
      assert_equal "MMKB08:000213603", ADAPTER.issue_id("KRANTEN_MMKB08_MMKB08_000213603_mpeg21")
      assert_nil ADAPTER.issue_id("KRANTEN_MMKB08_MMKB09_000213603_mpeg21")
      assert_nil ADAPTER.issue_id("README_newspapers_pd_16xx.txt")
    end

    def test_alto_pages_and_zip_root_furniture_skip_by_rule_and_strangers_are_unrecognized
      landed_tree do |dir|
        skips = conformance_adapter.discovery_skips(dir)
        assert skips.clean?, skips.notes.inspect
        assert_equal 5, skips.skipped_by_rule, "3 zip-root files + 2 ALTO pages"
        assert(skips.notes.any? { |note| note.include?("kranten_pd_16xx: 2 ALTO page file(s)") })
        assert(skips.notes.any? { |note| note.start_with?("kranten_pd_16xx/index_kranten_pd_16xx.tsv") })
        File.write(File.join(dir, "kranten_pd_16xx", Nabu::ZipFetch::STATE_FILE), "{}")
        assert_equal 6, conformance_adapter.discovery_skips(dir).skipped_by_rule
        File.write(File.join(dir, "kranten_pd_16xx", "1618", "06", "14", "DDD_ddd_010500649_mpeg21", "x.jp2"), "?")
        File.write(File.join(dir, "index.html"), "?")
        stray = conformance_adapter.discovery_skips(dir)
        assert_equal 2, stray.unrecognized
      end
    end

    def test_an_articletext_file_without_its_didl_is_unrecognized
      landed_tree do |dir|
        FileUtils.rm(File.join(dir, "kranten_pd_16xx", "1695", "03", "14", "DDD_ddd_011005283_mpeg21", "didl.xml"))
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 4, skips.unrecognized, "the four articletext files of a didl-less folder"
        assert_equal ISSUES.size - 1, conformance_adapter.discover(dir).count
      end
    end

    # -- passages ----------------------------------------------------------------

    def test_passages_are_articles_in_didl_order
      courante = doc("ddd:010500649")
      assert_equal 4, courante.size
      first = courante.passages.first
      assert_equal "#{URN}:ddd:010500649:a0001", first.urn
      assert first.text.start_with?("VVt Venetien den 1. Iunij, Anno 1618. DEn 25. Passato is geadviseert worden")
      assert_equal({ "article" => "ddd:010500649:mpeg21:a0001", "subject" => "artikel",
                     "title" => "VVt Venetien den 1.Iunij, Anno 1618.", "pages" => [1] }, first.annotations)
      assert_equal([4, 1, 2, 8, 4], ISSUES.map { |id| doc(id).size })
    end

    def test_an_article_over_two_pages_and_the_didl_title_fallback
      haerlem = doc("ddd:011225333")
      assert_equal [1, 2], haerlem.passages[3].annotations["pages"]
      colophon = haerlem.passages.last
      assert_equal "advertentie", colophon.annotations["subject"]
      assert_equal "Advertentie", colophon.annotations["title"], "an empty articletext title falls back to the DIDL's"
    end

    def test_an_article_with_empty_ocr_mints_no_passage
      landed_tree do |dir|
        issue = File.join(dir, "kranten_pd_16xx", "1618", "06", "14", "DDD_ddd_010500649_mpeg21")
        File.write(File.join(issue, "DDD_010500649_0003_articletext.xml"),
                   "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<text>\n  <title></title>\n  <p> </p>\n</text>\n")
        ref = conformance_adapter.discover(dir).first
        document = conformance_adapter.parse(ref)
        assert_equal(%w[a0001 a0002 a0004], document.passages.map { |p| p.urn.split(":").last })
        assert_equal ["a0003"], document.metadata["empty_articles"]
      end
    end

    def test_a_missing_articletext_file_quarantines_the_issue
      landed_tree do |dir|
        issue = File.join(dir, "kranten_pd_16xx", "1618", "06", "14", "DDD_ddd_010500649_mpeg21")
        FileUtils.rm(File.join(issue, "DDD_010500649_0002_articletext.xml"))
        ref = conformance_adapter.discover(dir).first
        document = conformance_adapter.parse(ref)
        assert_equal %w[a0002], document.metadata["missing_articles"],
                     "a named-but-absent file rides missing_articles (the 2017 zip's packaging gaps)"
        Dir.glob(File.join(issue, "*_articletext.xml")).each { |f| FileUtils.rm(f) }
        error = assert_raises(Nabu::ParseError) { conformance_adapter.parse(ref) }
        assert_match(/no article carries OCR text/, error.message)
      end
    end

    # -- metadata: the axes --------------------------------------------------------

    def test_the_issue_record_rides_the_metadata
      meta = doc("ddd:010500649").metadata
      assert_equal "Courante uyt Italien, Duytslandt, &c., 1618-06-14", doc("ddd:010500649").title
      assert_equal({ "not_before" => 1618, "not_after" => 1618, "raw" => "1618-06-14",
                     "basis" => "the issue's own date (DIDL dc:date)" }, meta["date"])
      assert_equal "Amsterdam", meta["place"]
      assert_equal "Landelijk", meta["distribution"]
      assert_equal "Caspar van Hilten", meta["publisher"]
      assert_equal "Courante uyt Italien, Duytslandt, &c.", meta["paper"]
      assert_equal "1", meta["issue_number"]
      assert_equal "National Library of Sweden KBS", meta["holding"]
      assert_equal "kranten_pd_16xx", meta["zip"]
      assert_equal "http://resolver.kb.nl/resolve?urn=ddd:010500649:mpeg21", meta["resolver_url"]
      assert_equal({ "artikel" => 4 }, meta["subjects"])
      assert_equal "Haerlem", doc("ddd:011225333").metadata["place"]
    end

    def test_language_comes_from_dc_language
      assert_equal(%w[nld nld nld nld fra], ISSUES.map { |id| doc(id).language })
      gazette = doc("ddd:011005283")
      assert_equal ["fra"], gazette.metadata["languages"]
      assert gazette.passages.first.text.start_with?("Ardi au loir le carnaval")
    end

    def test_hand_corrected_pages_are_told_from_machine_ocr
      assert_equal "hand-corrected", doc("ddd:010500649").metadata["text_nature"]
      assert_equal(%w[machine-ocr machine-ocr machine-ocr machine-ocr], ISSUES.drop(1).map do |id|
        doc(id).metadata["text_nature"]
      end)
      assert_equal [0.33], doc("MMKB08:000213603").metadata["ocr_confidence"]
    end

    def test_a_folder_whose_didl_names_another_record_quarantines
      landed_tree do |dir|
        zip = File.join(dir, "kranten_pd_16xx")
        FileUtils.mv(File.join(zip, "1618", "06", "14", "DDD_ddd_010500649_mpeg21"),
                     File.join(zip, "1618", "06", "14", "DDD_ddd_010500650_mpeg21"))
        ref = conformance_adapter.discover(dir).first
        assert_raises(Nabu::ParseError) { conformance_adapter.parse(ref) }
      end
    end

    # -- load + timeline -------------------------------------------------------------

    def test_loading_twice_is_idempotent
      catalog = loaded_catalog
      first = [catalog[:documents].count, catalog[:passages].count]
      assert_equal [5, 19], first
      Nabu::Store::Loader.new(db: catalog, source: Nabu::Store::Source.first(slug: "delpher-newspapers"))
                         .load_from(ADAPTER.new, workdir: FIXTURES, full: true)
      assert_equal first, [catalog[:documents].count, catalog[:passages].count]
    end

    def test_the_timeline_rows_carry_the_issue_year_and_place
      catalog = loaded_catalog
      Nabu::Store::TimelineBuilder::MetadataDates.refresh_source!(catalog: catalog, slug: "delpher-newspapers")
      rows = catalog[:document_axes].join(:documents, id: :document_id)
                                    .select(Sequel[:documents][:urn], :not_before, :place_name, :date_class)
                                    .to_hash(:urn, %i[not_before place_name date_class])
      assert_equal 5, rows.size
      assert_equal [1618, "Amsterdam", nil], rows["#{URN}:ddd:010500649"]
      assert_equal [1695, "Rotterdam", nil], rows["#{URN}:ddd:011005283"]
    end

    # -- registry --------------------------------------------------------------------

    def test_registry_row_is_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["delpher-newspapers"]
      refute_nil entry
      assert_equal ADAPTER, entry.adapter_class
      refute entry.wired, "wired flips true after the verified first sync"
      assert_equal "manual", entry.sync_policy
    end

    def test_the_lects_resolve_through_the_registry
      lects = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"))
      assert_equal "nl", lects.resolve("nld", source: "delpher-newspapers")
      assert_equal "fr", lects.resolve("fra", source: "delpher-newspapers")
    end

    def test_the_census_constants_match_upstream
      assert_equal 23, ADAPTER::ZIPS.size
      assert_equal 370_016, ADAPTER::ZIPS.sum(&:issues), "upstream's whole-archive index"
      assert_equal %w[kranten_pd_16xx], ADAPTER::CONE
      assert_equal 8_559, ADAPTER.zip("kranten_pd_16xx").issues
    end

    # -- fetch: ZipFetch per cone zip (WebMock only) ------------------------------------

    def test_fetch_unpacks_each_cone_zip_into_its_own_dir_and_checks_the_md5
      body = zip_body
      stub_request(:get, ADAPTER.zip_url("kranten_pd_16xx")).to_return(status: 200, body: body)
      Dir.mktmpdir do |workdir|
        report = adapter_with_md5(Digest::MD5.hexdigest(body)).fetch(workdir)
        assert_instance_of Nabu::FetchReport, report
        assert_includes report.notes, "kranten_pd_16xx.zip unpacked"
        assert_equal(ISSUES.map { |id| "#{URN}:#{id}" }, conformance_adapter.discover(workdir).map(&:id))
        skips = conformance_adapter.discovery_skips(workdir)
        assert skips.clean?, skips.notes.inspect
        assert_equal 6, skips.skipped_by_rule, "3 root files + 2 ALTO pages + the state pin"
      end
    end

    def test_an_md5_mismatch_aborts_before_the_tree_changes
      stub_request(:get, ADAPTER.zip_url("kranten_pd_16xx")).to_return(status: 200, body: zip_body)
      Dir.mktmpdir do |workdir|
        error = assert_raises(Nabu::FetchError) { adapter_with_md5("0" * 32).fetch(workdir) }
        assert_includes error.message, "md5"
        assert_empty conformance_adapter.discover(workdir).to_a
      end
    end

    def test_fetch_wraps_http_failure
      stub_request(:get, ADAPTER.zip_url("kranten_pd_16xx")).to_return(status: 500)
      Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { conformance_adapter.fetch(workdir) } }
    end

    def test_the_probe_heads_the_cone_zips_and_only_those
      assert_equal :http_zip, ADAPTER.remote_probe_strategy
      assert_equal ["https://resolver.kb.nl/resolve?urn=DATA:kranten:kranten_pd_16xx.zip"],
                   ADAPTER.http_probe_targets.map(&:zip_url)
      assert_equal ["kranten_pd_16xx/#{Nabu::ZipFetch::STATE_FILE}"], ADAPTER.materialized_paths
    end

    private

    def loaded_catalog
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "delpher-newspapers", name: "Delpher", adapter_class: ADAPTER.name,
                                          license_class: "attribution")
      Nabu::Store::Loader.new(db: catalog, source: source).load_from(ADAPTER.new, workdir: FIXTURES, full: true)
      catalog
    end

    # The adapter with the cone zip's published md5 replaced (the test zip
    # is not upstream's 1 GB body).
    def adapter_with_md5(md5)
      zip = ADAPTER.zip("kranten_pd_16xx").with(md5: md5)
      adapter = ADAPTER.new
      adapter.define_singleton_method(:cone_zips) { [zip] }
      adapter
    end

    # kranten_pd_16xx.zip's shape: the year dirs and the root files at the
    # zip root.
    def zip_body
      Dir.mktmpdir do |dir|
        src = File.join(FIXTURES, "kranten_pd_16xx")
        members = Dir.children(src).sort
        zip_path = File.join(dir, "kranten_pd_16xx.zip")
        Nabu::Shell.run("zip", "-q", "-r", zip_path, *members, chdir: src)
        return File.binread(zip_path)
      end
    end
  end
end
