# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "support/adapter_conformance"

module Adapters
  # elektire — the Croatian school canon of lektire.skole.hr (P117-2). The
  # fixture is the fetch layout: index/ (real WP-JSON listing pages,
  # trimmed to the fixture works and their terms) and epub/ (five real
  # books re-packed without fonts and images). Three are admitted (Kaboga,
  # Pelegrinović, Šimunović); Car Emin (d. 1963) and Vitez (no PD
  # statement) are excluded by rule.
  class ElektireTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("elektire")
    URN = "urn:nabu:elektire"

    def conformance_adapter = Nabu::Adapters::Elektire.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "elektire"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(slug) = documents.find { |d| d.urn == "#{URN}:#{slug}" } || flunk("#{slug} missing")

    def test_discovers_only_the_admitted_books
      assert_equal %W[#{URN}:duga #{URN}:jedupka #{URN}:pjesme-8],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_exclusions_are_skips_by_rule_with_their_reasons
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 2, skips.skipped_by_rule
      assert skips.clean?
      notes = skips.notes.join("\n")
      assert_match(/mali-od-foguna: author d\. 1963 — in copyright/, notes)
      assert_match(/izabrane-pjesme-16: no public-domain statement/, notes)
    end

    def test_an_epub_the_listing_does_not_know_is_unrecognized
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "index"), dir)
        FileUtils.mkdir_p(File.join(dir, "epub"))
        FileUtils.cp(File.join(FIXTURES, "epub", "duga.epub"), File.join(dir, "epub", "stray-book.epub"))
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        assert_empty conformance_adapter.discover(dir).to_a
      end
    end

    def test_passages_are_lines_cited_by_spine_position
      d = doc("pjesme-8")
      assert_equal "hrv", d.language
      assert_equal "Pjesme", d.title
      assert_equal "#{URN}:pjesme-8:4.1", d.passages.first.urn
      assert_equal({ "kind" => "head" }, d.passages.first.annotations)
      assert_equal "Čuj me svak što ću rit, od mlada do stara,", d.passages[1].text
      assert_empty d.passages[1].annotations
    end

    def test_metadata_carries_rights_edition_century_and_facets
      meta = doc("jedupka").metadata
      assert_equal "Mikša Pelegrinović", meta["author"]
      assert_equal 1562, meta["author_death"]
      assert_match(/\AAutorska prava na djela Mikše Pelegrinovića su istekla/, meta["rights_statement"])
      assert_equal({ "not_before" => 1501, "not_after" => 1600,
                     "raw" => "16. stoljeće (the portal's century of origin)" }, meta["date"])
      assert_equal "Bulaja naklada", meta["edition"]["publisher"]
      assert_equal "978-953-328-088-2", meta["edition"]["isbn"]
      assert_equal "not stated in the asset", meta["edition"]["base_edition"]
      assert_equal "https://lektire.skole.hr/djela/jedupka/", meta["url"]
      assert meta["facets"].key?("genre")
    end

    def test_the_century_rides_the_structured_lane_as_composition_class
      dates = Nabu::Store::TimelineBuilder::MetadataDates
      assert_equal :structured, dates::SHAPES["elektire"]
      assert_includes dates::COMPOSITION, "elektire"
    end

    def test_manifest_quotes_the_per_work_statement_and_the_rule
      manifest = Nabu::Adapters::Elektire.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "javno dobro koje se nesmetano može kopirati"
      assert_includes manifest.license, "opremu knjige"
      assert_equal 1955, Nabu::Adapters::Elektire::AUTHOR_DEATH_CUTOFF
    end

    def test_registry_row_is_ready_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["elektire"]
      refute_nil entry
      assert entry.wired, "wired: true — first sync verified 2026-10-11 (205 docs / 375,300 passages)"
      assert_equal "manual", entry.sync_policy
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "elektire", name: "eLektire",
                                          adapter_class: "Nabu::Adapters::Elektire", license_class: "open")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, first.added
      passages = db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only) ------------------------------------------------

    def stub_api!
      index = File.join(FIXTURES, "index")
      stub_request(:get, %r{\Ahttps://lektire\.skole\.hr/wp-json/wp/v2/}).to_return do |request|
        name = request.uri.path.split("/").last
        if name == "media"
          parent = request.uri.query[/parent=(\d+)/, 1]
          { status: 200, body: File.read(File.join(index, "media-#{parent}.json")) }
        else
          page = request.uri.query[/page=(\d+)/, 1]
          { status: 200, body: File.read(File.join(index, "#{name}-#{page}.json")),
            headers: { "X-WP-TotalPages" => Dir.glob(File.join(index, "#{name}-*.json")).size.to_s } }
        end
      end
      stub_request(:get, %r{\Ahttps://lektire\.skole\.hr/wp-content/uploads/.*\.epub\z}).to_return do |request|
        slug = epub_slugs.fetch(request.uri.path)
        { status: 200, body: File.binread(File.join(FIXTURES, "epub", "#{slug}.epub")) }
      end
    end

    # The fixture's media lists name the real upload URLs; map each back
    # to its book's slug via the works listing.
    def epub_slugs
      @epub_slugs ||= begin
        works = JSON.parse(File.read(File.join(FIXTURES, "index", "djela-1.json")))
        works.each_with_object({}) do |work, map|
          media_path = File.join(FIXTURES, "index", "media-#{work['id']}.json")
          next unless File.file?(media_path)

          JSON.parse(File.read(media_path)).each do |m|
            map[URI(m["source_url"]).path] = work["slug"] if m["source_url"].end_with?(".epub")
          end
        end
      end
    end

    def fetcher(workdir)
      Nabu::ElektireFetch.new(base_url: Nabu::Adapters::Elektire::BASE_URL, dir: workdir,
                              attic_dir: File.join(workdir, ".attic"), delay: 0)
    end

    def test_fetch_lands_the_listings_and_the_croatian_books
      stub_api!
      Dir.mktmpdir do |workdir|
        fetch = fetcher(workdir)
        fetch.prepare!
        fetch.complete!
        assert_equal epub_slugs.values.uniq.sort,
                     Dir.children(File.join(workdir, "epub")).map { |n| n.delete_suffix(".epub") }.sort
        assert File.file?(File.join(workdir, "index", "djela-1.json"))
        assert_match(/\A\h{64}\z/, fetch.sha)
        assert_equal %W[#{URN}:duga #{URN}:jedupka #{URN}:pjesme-8],
                     conformance_adapter.discover(workdir).map(&:id).sort
      end
    end

    def test_a_second_fetch_reuses_the_books_on_disk
      stub_api!
      Dir.mktmpdir do |workdir|
        first = fetcher(workdir)
        first.prepare!
        first.complete!
        again = fetcher(workdir)
        again.prepare!
        again.complete!
        assert_equal 0, again.fetched
        assert_equal epub_slugs.values.uniq.size, again.cached
        assert_equal first.sha, again.sha
      end
    end

    def test_a_failing_api_raises_after_retries
      stub_request(:get, %r{\Ahttps://lektire\.skole\.hr/}).to_return(status: 503)
      Dir.mktmpdir do |workdir|
        error = assert_raises(Nabu::ElektireFetch::Error) { fetcher(workdir).prepare! }
        assert_match(/HTTP 503/, error.message)
      end
    end
  end
end
