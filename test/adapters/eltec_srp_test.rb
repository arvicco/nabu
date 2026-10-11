# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # eltec-srp — the Serbian novel collection of ELTeC (P117-2): one
  # document per novel, passages = the eltec-tei family's blocks. The
  # fixture holds four trimmed real level-1 files, one of them (Секулић,
  # d. 1958) excluded by the life+70 rule.
  class EltecSrpTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("eltec-srp")
    URN = "urn:nabu:eltec-srp"

    def conformance_adapter = Nabu::Adapters::EltecSrp.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "eltec-srp"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(id) = documents.find { |d| d.urn == "#{URN}:#{id}" } || flunk("#{id} missing")

    def test_discovers_one_document_per_novel_keyed_by_the_eltec_id
      assert_equal %W[#{URN}:srp18520 #{URN}:srp18590 #{URN}:srp19180],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_a_work_whose_author_died_after_the_cutoff_is_skipped_by_rule
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      assert skips.clean?
      assert_match(/SRP19190_IsidoraS_Djakon\.xml: Секулић, Исидора d\. 1958/, skips.notes.first)
      assert_equal 1955, Nabu::Adapters::EltecSrp::AUTHOR_DEATH_CUTOFF
    end

    def test_an_unrecorded_death_year_is_admitted_on_the_collection_statement
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "level1"))
        source = File.read(File.join(FIXTURES, "level1", "SRP19190_IsidoraS_Djakon.xml"))
        File.write(File.join(dir, "level1", "SRP19190_IsidoraS_Djakon.xml"), source.sub("(1877-1958)", "(????-????)"))
        assert_equal ["#{URN}:srp19190"], conformance_adapter.discover(dir).map(&:id)
      end
    end

    def test_passages_carry_div_path_citations_kinds_and_pages
      d = doc("srp18520")
      assert_equal "srp", d.language
      assert_equal "Два идола", d.title
      first = d.passages.first
      assert_equal "#{URN}:srp18520:1.1", first.urn
      assert_equal "Родољубац и издајица", first.text
      assert_equal({ "kind" => "head", "page" => "3" }, first.annotations)
      verse = d.passages.find { |p| p.urn == "#{URN}:srp18520:1.3" }
      assert_equal "l", verse.annotations["kind"]
    end

    def test_metadata_mines_dates_places_and_the_named_edition
      meta = doc("srp18590").metadata
      assert_equal({ "not_before" => 1859, "not_after" => 1859, "raw" => "1859" }, meta["date"])
      assert_equal "Пешта", meta["place"]
      assert_equal "1987", meta["print_source"]["date"]
      assert_equal "Матица српска ; Јединство", meta["print_source"]["publisher"]
      assert_equal "Игњатовић, Јаков", meta["author"]
      assert_equal 1889, meta["author_death"]
      assert_equal "Cyrl", meta["script"]
      assert_equal "SRP18590", meta["eltec_id"]
      assert_includes meta["responsibility"], { "resp" => "Кодирање за ELTeC", "name" => "Цветана Крстев" }
    end

    def test_latin_script_text_is_marked
      assert_equal "Latn", doc("srp19180").metadata["script"]
      assert_equal "Zagreb", doc("srp19180").metadata["place"]
    end

    def test_a_missing_first_edition_date_falls_back_to_the_reference_year
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "level1"))
        source = File.read(File.join(FIXTURES, "level1", "SRP18520_BogobojA_DvaIdola.xml"))
        File.write(File.join(dir, "level1", "a.xml"), source.sub("<date>1852</date>", ""))
        adapter = conformance_adapter
        meta = adapter.parse(adapter.discover(dir).first).metadata
        assert_equal({ "not_before" => 1852, "not_after" => 1852,
                       "raw" => "1852 (ELTeC reference year, from the id)" }, meta["date"])
      end
    end

    def test_the_edition_date_rides_the_structured_metadata_dates_lane
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["eltec-srp"]
    end

    def test_manifest_quotes_the_readme_licence
      manifest = Nabu::Adapters::EltecSrp.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "All texts included in this collection are in the public domain"
      assert_includes manifest.license, "CC BY"
      assert_equal "eltec-tei", manifest.parser_family
    end

    def test_registry_row_is_ready_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["eltec-srp"]
      refute_nil entry
      refute entry.wired, "ready, not wired — the first sync waits for the owner"
      assert_equal "manual", entry.sync_policy
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "eltec-srp", name: "ELTeC-srp",
                                          adapter_class: "Nabu::Adapters::EltecSrp",
                                          license_class: "attribution")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, first.added
      passages = db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, second.skipped
      assert_equal passages, db[:passages].count
      assert_equal [1], db[:passages].distinct.select_map(:revision)
    ensure
      db&.disconnect
    end

    # --- fetch (local git only, no network) ----------------------------------

    def test_fetch_sparse_clones_only_the_level1_cone
      Dir.mktmpdir("nabu-eltec-srp-fetch") do |root|
        upstream = File.join(root, "upstream")
        build_upstream_repo(upstream)
        work = File.join(root, "canonical")
        adapter = conformance_adapter
        adapter.define_singleton_method(:repo_url) { upstream }
        report = adapter.fetch(work)
        assert_match(/\A[0-9a-f]{40}\z/, report.sha)
        assert File.file?(File.join(work, "level1", "SRP18520_BogobojA_DvaIdola.xml"))
        assert File.file?(File.join(work, "README.md"))
        refute File.exist?(File.join(work, "level2")), "the annotated level2 twin stays out of the cone"
        assert_equal 3, adapter.discover(work).count
      end
    end

    private

    def build_upstream_repo(upstream)
      FileUtils.mkdir_p(upstream)
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      Nabu::Shell.run("git", "init", "-q", upstream)
      FileUtils.cp_r(File.join(FIXTURES, "level1"), upstream)
      File.write(File.join(upstream, "README.md"), "# ELTeC-srp\n")
      FileUtils.mkdir_p(File.join(upstream, "level2"))
      File.write(File.join(upstream, "level2", "SRP18520-L2.xml"), "<TEI/>")
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
    end
  end
end
