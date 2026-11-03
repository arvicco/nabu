# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # emmo — Early Modern Manuscripts Online (Folger): one public zip of 100
  # word-tokenized TEI manuscripts; document = file, passage = page.
  # Fixture: three whole files + the rejected stylesheet (README.md).
  class EmmoTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("emmo")
    URN = "urn:nabu:emmo"
    ZIP_URL = Nabu::Adapters::Emmo::ZIP_URL

    def conformance_adapter = Nabu::Adapters::Emmo.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "emmo"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(stem) = documents.find { |d| d.urn == "#{URN}:#{stem}" } || flunk("#{stem} missing")

    # The fixture dir minus its own README/manifest — the tree as it lands.
    def landed_tree
      Dir.mktmpdir do |dir|
        %w[La13.xml Lb543.xml Xd451-187.xml emmo.xsl].each { |name| FileUtils.cp(File.join(FIXTURES, name), dir) }
        yield dir
      end
    end

    def test_discovers_the_three_manuscripts
      assert_equal %w[La13 Lb543 Xd451-187].map { |s| "#{URN}:#{s}" }, conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_the_stylesheet_and_the_state_pin_skip_by_rule
      landed_tree do |dir|
        File.write(File.join(dir, Nabu::ZipFetch::STATE_FILE), "{}")
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 2, skips.skipped_by_rule
        assert skips.clean?
        assert(skips.notes.any? { |n| n.start_with?("emmo.xsl:") })
      end
    end

    def test_an_unknown_member_is_unrecognized
      landed_tree do |dir|
        File.write(File.join(dir, "notes.txt"), "?")
        refute conformance_adapter.discovery_skips(dir).clean?
      end
    end

    def test_passages_are_pages_cited_by_leaf
      assert_equal ["#{URN}:La13:1r", "#{URN}:La13:2v"], doc("La13").passages.map(&:urn)
      assert_equal ["#{URN}:Xd451-187:2v-1r", "#{URN}:Xd451-187:s2", "#{URN}:Xd451-187:1v-2r"],
                   doc("Xd451-187").passages.map(&:urn), "an n-less page is cited by its sequence"
      assert_equal(7, documents.sum { |d| d.passages.size })
    end

    def test_the_citation_rule
      assert_equal "1r", Nabu::Adapters::Emmo.citation("leaf 1 recto")
      assert_equal "1v-2r", Nabu::Adapters::Emmo.citation("leaf 1 verso || leaf 2 recto")
      assert_equal "1v-2r", Nabu::Adapters::Emmo.citation("leaf 1v || leaf 2 recto")
      assert_nil Nabu::Adapters::Emmo.citation(nil)
      assert_nil Nabu::Adapters::Emmo.citation("cover")
    end

    def test_a_known_snippet_and_the_regularized_annotation
      page = doc("Lb543").passages.first
      assert_equal "en", page.language
      assert_includes page.text, "Received the Day and year abouewritten"
      assert_includes page.annotations["regularized"], "Received the Day and year above-written"
      assert_equal "https://digitalcollections.folger.edu/img5936", page.annotations["image_url"]
      assert_equal [{ "lang" => "la", "text" => "9o Iulii 1602" }], page.annotations["foreign"]
    end

    def test_documents_are_dated_by_the_catalogue_origin
      assert_equal({ "not_before" => 1620, "not_after" => 1620, "raw" => "1620 March 27", "class" => "composition" },
                   doc("La13").metadata["date"])
      assert_equal 1697, doc("Xd451-187").metadata.dig("date", "not_before")
    end

    def test_the_dateline_place_is_the_document_place
      meta = doc("La13").metadata
      assert_equal "Oxford", meta["place"]
      assert_equal "dateline", meta["place_role"]
      assert_equal %w[Oxford Blithfield], meta["places_mentioned"]
      assert_nil doc("Lb543").metadata["place"], "no dateline place — never inferred from the title"
      assert_equal ["Clapham"], doc("Xd451-187").metadata["places_mentioned"]
    end

    def test_header_fields_ride_the_metadata
      meta = doc("Lb543").metadata
      assert_equal "Receipt", meta["document_type"]
      assert_equal ["Receipt"], meta["genre"]
      assert_equal "Donne, John", meta["author"]
      assert_equal "L.b.543", meta["shelfmark"]
      assert_equal "Papers of the More family of Loseley Park, Surrey", meta["collection"]
      assert_equal "eng", meta["language_raw"]
      assert_includes meta["persons_mentioned"], "Sir Thomas Egerton"
      assert_equal "Letter", doc("La13").metadata["document_type"]
      assert_equal 1, doc("La13").metadata["blank_pages"]
    end

    def test_the_title_head_noun_is_the_document_type
      assert_equal "Copy of an order",
                   Nabu::Adapters::Emmo.document_type("Copy of an order from the Privy Council to Sir William Ellis")
      assert_equal "Certificate of recusancy", Nabu::Adapters::Emmo.document_type("Certificate of recusancy from J")
      assert_equal "Legal opinion", Nabu::Adapters::Emmo.document_type("Legal opinion of Sir Humphrey Davenport")
      assert_nil Nabu::Adapters::Emmo.document_type("Commonplace book")
    end

    def test_a_file_under_another_licence_quarantines
      Dir.mktmpdir do |dir|
        xml = File.read(File.join(FIXTURES, "La13.xml")).sub("licenses/by-sa/4.0/", "licenses/by-nc/4.0/")
        File.write(File.join(dir, "La13.xml"), xml)
        ref = conformance_adapter.discover(dir).first
        assert_raises(Nabu::ParseError) { conformance_adapter.parse(ref) }
      end
    end

    def test_the_lect_resolves_to_early_modern_english
      lects = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"),
                               overrides_path: File.expand_path("../../config/lect_overrides.yml", __dir__))
      assert_equal "en:early", lects.resolve("en", source: "emmo"), "every catalogue date sits in [1500, 1700]"
    end

    def test_registry_row_is_wired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["emmo"]
      refute_nil entry
      assert_equal Nabu::Adapters::Emmo, entry.adapter_class
      assert entry.wired, "first sync verified 2026-11-03 (100 docs / 196 passages)"
      assert_equal "manual", entry.sync_policy
    end

    # -- fetch: ZipFetch (WebMock only) ----------------------------------------

    def test_fetch_unpacks_the_zip_and_strips_its_top_directory
      stub_request(:get, ZIP_URL).to_return(status: 200, body: zip_body,
                                            headers: { "Last-Modified" => "Sun, 31 May 2026 23:13:48 GMT" })
      Dir.mktmpdir do |workdir|
        report = conformance_adapter.fetch(workdir)
        assert_instance_of Nabu::FetchReport, report
        assert_equal %w[La13 Lb543 Xd451-187].map { |s| "#{URN}:#{s}" }, conformance_adapter.discover(workdir).map(&:id)
        assert conformance_adapter.discovery_skips(workdir).clean?
      end
    end

    def test_fetch_wraps_http_failure
      stub_request(:get, ZIP_URL).to_return(status: 500)
      Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { conformance_adapter.fetch(workdir) } }
    end

    def test_the_probe_heads_the_zip
      assert_equal :http_zip, Nabu::Adapters::Emmo.remote_probe_strategy
      assert_equal [ZIP_URL], Nabu::Adapters::Emmo.http_probe_targets.map(&:zip_url)
    end

    private

    def zip_body
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "emmo"))
        %w[La13.xml Lb543.xml Xd451-187.xml emmo.xsl].each do |n|
          FileUtils.cp(File.join(FIXTURES, n), File.join(dir, "emmo"))
        end
        zip_path = File.join(dir, "emmo.zip")
        Nabu::Shell.run("zip", "-q", "-r", zip_path, "emmo", chdir: dir)
        return File.binread(zip_path)
      end
    end
  end
end
