# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # ebible-pacific — eBible.org's public-domain Pacific Bibles as USFM
  # (P154): the Hawaiian Baibala Hemolele (1868 revision), the Chamorro
  # Gospels, Acts and Psalms (ABS, 1908) and the Pohnpeian New Testament
  # and Psalms in the old alphabet (1922). One document per (translation,
  # book), passages <chapter>.<verse>.
  class EbiblePacificTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("ebible-pacific")
    URN = "urn:nabu:ebible-pacific"
    ZIP_URLS = %w[haw1868 cha pon].to_h { |id| [id, "https://ebible.org/Scriptures/#{id}_usfm.zip"] }

    def conformance_adapter = Nabu::Adapters::EbiblePacific.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "ebible-pacific"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(tail) = documents.find { |d| d.urn == "#{URN}:#{tail}" } || flunk("#{tail} missing")

    def test_discovers_one_document_per_translation_book
      assert_equal %W[#{URN}:haw1868-oba #{URN}:haw1868-jhn #{URN}:haw1868-3jn #{URN}:cha-psa #{URN}:cha-jhn
                      #{URN}:pon-jhn #{URN}:pon-2jn],
                   conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_hawaiian_1868_text_in_its_period_spelling
      jhn = doc("haw1868-jhn")
      assert_equal "haw", jhn.language
      assert_equal "Ioane", jhn.title
      assert_equal "#{URN}:haw1868-jhn:1.1", jhn.passages.first.urn
      assert_equal "I KINOHI ka Logou, me ke Akua ka Logou, a o ke Akua no ka Logou.", jhn.passages.first.text
      assert_equal 51, jhn.size
      assert_equal 21, doc("haw1868-oba").size
    end

    def test_chamorro_and_pohnpeian_ride_their_own_codes
      cha = doc("cha-jhn")
      assert_equal "cha", cha.language
      assert_equal "San Juan", cha.title
      assert_equal "Y tutujonña gaegue y Finijo, ya y Finijo güiya yan si Yuus; ya y Finijo güiya si Yuus.",
                   cha.passages.first.text
      assert_equal 50, cha.size, "the 1908 text bridges 1:43-44 into one verse"
      assert_includes cha.passages.map(&:urn), "#{URN}:cha-jhn:1.43-44"
      pon = doc("pon-jhn")
      assert_equal "pon", pon.language
      assert_equal "MAJAN kotier ni tapi o, a majan kotier ren Kot, a majan me udan Kot.", pon.passages.first.text
      assert_equal 13, doc("pon-2jn").size
    end

    def test_psalms_keep_the_cha_psalm_citation
      psa = doc("cha-psa")
      assert_equal "#{URN}:cha-psa:1.1", psa.passages.first.urn
      assert_equal "#{URN}:cha-psa:2.12", psa.passages.last.urn
    end

    def test_edition_year_translation_and_testament_ride_metadata
      haw = doc("haw1868-oba").metadata
      assert_equal "haw1868", haw["translation"]
      assert_equal "ot", haw["testament"]
      assert_equal({ "not_before" => 1868, "not_after" => 1868, "class" => "edition" },
                   haw["date"].slice("not_before", "not_after", "class"))
      assert_equal "na na misionari i pai", haw["translator"]
      assert_equal 1908, doc("cha-jhn").metadata.dig("date", "not_before")
      assert_equal "American Bible Society", doc("cha-jhn").metadata["translator"]
      pon = doc("pon-2jn").metadata
      assert_equal 1922, pon.dig("date", "not_before")
      assert_equal "nt", pon["testament"]
      assert_equal "old alphabet", pon["orthography"]
    end

    def test_the_edition_year_rides_the_structured_lane
      dates = Nabu::Store::TimelineBuilder::MetadataDates
      assert_equal :structured, dates::SHAPES["ebible-pacific"]
      refute_includes dates::COMPOSITION, "ebible-pacific", "the edition year is an edition-class date"
    end

    def test_rights_pages_stylesheets_and_signing_material_skip_by_rule
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 6, skips.skipped_by_rule, "3 copr.htm + latin.css + keys.asc + signature.txt.asc"
      assert_equal 0, skips.unrecognized
      assert(skips.notes.any? { |n| n.include?("haw1868/keys.asc") })
    end

    def test_the_fetchers_own_state_pin_skips_by_rule
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "pon"))
        FileUtils.cp(File.join(FIXTURES, "pon", "69-2JNpon.usfm"), File.join(dir, "pon"))
        File.write(File.join(dir, "pon", Nabu::ZipFetch::STATE_FILE), "{}")
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.skipped_by_rule
        assert_equal 0, skips.unrecognized
        assert(skips.notes.any? { |n| n.include?(Nabu::ZipFetch::STATE_FILE) })
      end
    end

    def test_an_unknown_usfm_name_is_unrecognized_never_a_document
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "pon"))
        FileUtils.cp(File.join(FIXTURES, "pon", "69-2JNpon.usfm"), File.join(dir, "pon"))
        File.write(File.join(dir, "pon", "stray.usfm"), "\\id XXX\n")
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        assert_equal ["#{URN}:pon-2jn"], conformance_adapter.discover(dir).map(&:id)
      end
    end

    def test_a_mismatched_id_line_quarantines
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "pon"))
        File.write(File.join(dir, "pon", "69-2JNpon.usfm"),
                   File.read(File.join(FIXTURES, "pon", "69-2JNpon.usfm")).sub("\\id 2JN", "\\id 3JN"))
        ref = conformance_adapter.discover(dir).first
        assert_raises(Nabu::ParseError) { conformance_adapter.parse(ref) }
      end
    end

    def test_scripture_is_the_whole_source_kind
      kind_map = YAML.safe_load_file(File.expand_path("../../config/kind_map.yml", __dir__))
      assert_equal "scripture", kind_map.dig("sources", "ebible-pacific", "source_kind")
    end

    def test_manifest_records_the_public_domain_statements
      manifest = Nabu::Adapters::EbiblePacific.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "na na misionari i pai"
      assert_equal "usfm", manifest.parser_family
    end

    def test_registry_row_is_ready_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["ebible-pacific"]
      refute_nil entry
      assert_equal Nabu::Adapters::EbiblePacific, entry.adapter_class
      refute entry.wired, "wired: false until the first real sync is verified"
      assert_equal "manual", entry.sync_policy
    end

    def test_the_lects_resolve_onto_the_minted_pacific_anchors
      lects = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"))
      assert_equal "ch", lects.resolve("cha", source: "ebible-pacific"), "the codemap's cha → ch alias"
      %w[haw pon].each { |code| refute_nil lects.lect(code), "#{code} is a registry anchor" }
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "ebible-pacific", name: "eBible Pacific Bibles",
                                          adapter_class: "Nabu::Adapters::EbiblePacific", license_class: "open")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 7, first.added
      passages = db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 7, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end

    def test_fetch_downloads_and_unpacks_the_three_zips
      stub_zips
      Dir.mktmpdir do |workdir|
        report = conformance_adapter.fetch(workdir)
        assert_instance_of Nabu::FetchReport, report
        assert_match(/\A\h{64}\z/, report.sha)
        assert_equal ZIP_URLS.values.sort, report.repos.keys.sort
        assert_equal 7, conformance_adapter.discover(workdir).count
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      ZIP_URLS.each_value { |url| stub_request(:get, url).to_return(status: 500) }
      Dir.mktmpdir do |workdir|
        assert_raises(Nabu::FetchError) { conformance_adapter.fetch(workdir) }
      end
    end

    def test_probe_heads_each_zip
      targets = Nabu::Adapters::EbiblePacific.http_probe_targets
      assert_equal :http_zip, Nabu::Adapters::EbiblePacific.remote_probe_strategy
      assert_equal ZIP_URLS.values, targets.map(&:zip_url)
      assert_equal ZIP_URLS.keys, targets.map(&:state_subdir)
    end

    private

    # Zip each fixture subtree FLAT (eBible's zips carry no top-level dir).
    def stub_zips
      Dir.mktmpdir do |dir|
        ZIP_URLS.each do |id, url|
          zip_path = File.join(dir, "#{id}.zip")
          Nabu::Shell.run("zip", "-q", "-r", zip_path, ".", chdir: File.join(FIXTURES, id))
          stub_request(:get, url).to_return(
            status: 200, body: File.binread(zip_path),
            headers: { "Content-Type" => "application/zip", "Last-Modified" => "Fri, 30 Oct 2026 04:44:16 GMT" }
          )
        end
      end
    end
  end
end
