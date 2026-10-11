# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # vuk-danicic — the Vuk (NT 1847) / Daničić (OT 1865) Serbian Bible,
  # ijekavian, from the Rs1Bible USFM conversion (P117-2). One document per
  # book (urn …:<code>), passages <chapter>.<verse>.
  class VukDanicicTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("vuk-danicic")
    URN = "urn:nabu:vuk-danicic"

    def conformance_adapter = Nabu::Adapters::VukDanicic.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "vuk-danicic"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(code) = documents.find { |d| d.urn == "#{URN}:#{code}" } || flunk("#{code} missing")

    def test_discovers_one_document_per_book_in_file_order
      assert_equal %W[#{URN}:oba #{URN}:jhn #{URN}:2jn], conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_verses_are_cited_chapter_dot_verse_in_ijekavian_text
      jhn = doc("jhn")
      assert_equal "srp", jhn.language
      assert_equal "John", jhn.title
      assert_equal "#{URN}:jhn:1.1", jhn.passages.first.urn
      assert_equal "U početku bješe riječ, i riječ bješe u Boga, i Bog bješe riječ.", jhn.passages.first.text
      assert_equal 51, jhn.size
    end

    def test_testament_translator_and_attributed_era_ride_metadata
      nt = doc("2jn").metadata
      assert_equal "nt", nt["testament"]
      assert_equal "Vuk Stefanović Karadžić", nt["translator"]
      assert_equal 1847, nt["date"]["not_before"]
      ot = doc("oba").metadata
      assert_equal "ot", ot["testament"]
      assert_equal "Đura Daničić", ot["translator"]
      assert_equal [1865, 1868], [ot["date"]["not_before"], ot["date"]["not_after"]]
      assert_equal "ijekavian", ot["orthography"]
      assert_equal "Latn", ot["script"]
    end

    def test_the_era_rides_the_structured_lane_as_composition_class
      dates = Nabu::Store::TimelineBuilder::MetadataDates
      assert_equal :structured, dates::SHAPES["vuk-danicic"]
      assert_includes dates::COMPOSITION, "vuk-danicic"
    end

    def test_a_mismatched_id_line_quarantines
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "64-2JN.usfm"),
                   File.read(File.join(FIXTURES, "64-2JN.usfm")).sub("\\id 2JN", "\\id 3JN"))
        ref = conformance_adapter.discover(dir).first
        assert_raises(Nabu::ParseError) { conformance_adapter.parse(ref) }
      end
    end

    def test_unrecognized_usfm_names_are_censused
      Dir.mktmpdir do |dir|
        FileUtils.cp(File.join(FIXTURES, "64-2JN.usfm"), dir)
        File.write(File.join(dir, "extra.usfm"), "\\id XXX\n")
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        assert_equal ["#{URN}:2jn"], conformance_adapter.discover(dir).map(&:id)
      end
    end

    def test_scripture_is_the_whole_source_kind
      kind_map = YAML.safe_load_file(File.expand_path("../../config/kind_map.yml", __dir__))
      assert_equal "scripture", kind_map.dig("sources", "vuk-danicic", "source_kind")
    end

    def test_manifest_records_the_provenance_and_open_class
      manifest = Nabu::Adapters::VukDanicic.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "THE UNBOUND BIBLE"
      assert_equal "usfm", manifest.parser_family
    end

    def test_registry_row_is_ready_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["vuk-danicic"]
      refute_nil entry
      refute entry.wired
      assert_equal "manual", entry.sync_policy
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "vuk-danicic", name: "Vuk–Daničić Bible",
                                          adapter_class: "Nabu::Adapters::VukDanicic", license_class: "open")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, first.added
      passages = db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end

    def test_fetch_clones_the_repo_and_discover_finds_the_books
      Dir.mktmpdir("nabu-vuk-danicic-fetch") do |root|
        upstream = File.join(root, "upstream")
        FileUtils.mkdir_p(upstream)
        Nabu::Shell.run("git", "init", "-q", upstream)
        FileUtils.cp(Dir.glob(File.join(FIXTURES, "*.usfm")), upstream)
        Nabu::Shell.run("git", "-C", upstream, "add", ".")
        Nabu::Shell.run("git", "-C", upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m",
                        "seed")
        work = File.join(root, "canonical")
        adapter = conformance_adapter
        adapter.define_singleton_method(:repo_url) { upstream }
        report = adapter.fetch(work)
        assert_match(/\A[0-9a-f]{40}\z/, report.sha)
        assert_equal 3, adapter.discover(work).count
      end
    end
  end
end
