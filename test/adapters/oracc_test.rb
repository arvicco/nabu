# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::Oracc (P10-1): discover walks <workdir>/<project>/
  # corpusjson/*.json (skipping the catalog-only EMPTY files — an upstream
  # norm, not damage), parse delegates to OraccJsonParser, fetch downloads and
  # unpacks the per-project HTTP zips via Nabu::ZipFetch. No network: fetch is
  # exercised against WebMock-stubbed zip responses ASSEMBLED IN THE TEST from
  # the real checked-in fixture files (the corpusjson/metadata/catalogue
  # payloads are genuine upstream data; only the zip envelope is built here —
  # ORACC serves `application/zip` with a `Last-Modified` header, the shape
  # recorded by the P9-5a scout and honestly reproduced below).
  class OraccTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("oracc")

    def conformance_adapter
      Nabu::Adapters::Oracc.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "oracc"
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_the_four_non_empty_texts_sorted_by_urn
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[
        urn:nabu:oracc:etcsri:Q001299
        urn:nabu:oracc:etcsri:Q004151
        urn:nabu:oracc:rimanum:P405134
        urn:nabu:oracc:rimanum:P405432
      ], refs.map(&:id)
    end

    def test_discover_skips_catalog_only_empty_corpusjson_files
      ids = conformance_adapter.discover(FIXTURES).map(&:id)
      refute_includes ids, "urn:nabu:oracc:rimanum:P405254",
                      "the 0-byte catalog-only file must be skipped, not yielded"
    end

    def test_discover_resolves_titles_from_the_catalogue_designation
      refs = conformance_adapter.discover(FIXTURES).to_h { |ref| [ref.id, ref] }
      assert_equal "UF 10, 152 26", refs["urn:nabu:oracc:rimanum:P405432"].metadata["title"]
      assert_equal "Amar-Suena 2049add / CDLI Seals 000423",
                   refs["urn:nabu:oracc:etcsri:Q004151"].metadata["title"]
      assert_equal "rimanum", refs["urn:nabu:oracc:rimanum:P405432"].metadata["project"]
    end

    # -- license (read per project, never hardcoded) --------------------------

    def test_discover_accepts_the_machine_read_cc0_license
      refute_empty conformance_adapter.discover(FIXTURES).to_a
    end

    def test_discover_stops_on_a_license_that_does_not_map_to_the_declared_class
      with_doctored_license("released under the CC BY-SA 3.0 license") do |workdir|
        error = assert_raises(Nabu::FetchError) { conformance_adapter.discover(workdir).to_a }
        assert_match(/license/i, error.message)
        assert_match(/attribution/, error.message,
                     "the mapped class must be named so the mismatch is actionable")
      end
    end

    def test_discover_stops_on_an_unknown_license
      with_doctored_license("some novel license nobody vetted") do |workdir|
        error = assert_raises(Nabu::FetchError) { conformance_adapter.discover(workdir).to_a }
        assert_match(/unrecognized license/i, error.message)
      end
    end

    # -- parse ----------------------------------------------------------------

    def test_parse_delegates_to_the_oracc_json_parser_with_title
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id.end_with?("P405432") }
      document = adapter.parse(ref)
      assert_equal "UF 10, 152 26", document.title
      assert_equal "akk", document.language
      assert_equal "2(BARIG) ZI₃ US₂ a-na GEŠBUN", document.first.text
    end

    # -- lemma plumbing (cf → passage_lemmas via the shared Indexer) ----------

    def test_fixture_load_produces_lemma_rows_for_citation_forms
      catalog = store_test_db
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      source = Nabu::Store::Source.create(
        slug: "oracc", name: "ORACC", adapter_class: "Nabu::Adapters::Oracc", license_class: "open"
      )
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

      lemmas = fulltext[:passage_lemmas]
      assert_operator lemmas.where(language: "akk").count, :>, 0
      assert_operator lemmas.where(language: "sux").count, :>, 0

      # qēmu "flour" (P405432 o 1) folds diacritic-insensitively; the pristine
      # surface form rides along for readable hits.
      row = lemmas.where(lemma_folded: Nabu::Normalize.search_form("qēmu", language: "akk")).first
      refute_nil row, "expected a passage_lemmas row for cf qēmu"
      assert_equal "qēmu", row[:lemma_raw]
      assert_equal "urn:nabu:oracc:rimanum:P405432:o.1", row[:urn]
      assert_includes row[:surface_forms], "ZI₃"

      # end to end: lemma search finds the Akkadian citation form
      hits = Nabu::Query::LemmaSearch.new(catalog: catalog, fulltext: fulltext).run("qemu")
      assert_equal ["urn:nabu:oracc:rimanum:P405432:o.1"], hits.map(&:urn)
    ensure
      fulltext&.disconnect
    end

    # -- fetch (HTTP zip, no network: WebMock-stubbed) ------------------------

    RIMANUM_URL = "https://oracc.museum.upenn.edu/json/rimanum.zip"
    ETCSRI_URL = "https://oracc.museum.upenn.edu/json/etcsri.zip"

    # The two projects with checked-in corpus fixtures; the remaining in-scope
    # projects (P11-6 expansion — saao/saa01, rinap/rinap1, dcclt) are stubbed
    # with a metadata-only envelope (no cdl fixtures invented, 0 ingestible
    # texts) so fetch's per-project plumbing is exercised across the full list.
    FIXTURED_PROJECTS = %w[rimanum etcsri].freeze

    def test_fetch_downloads_and_unpacks_both_project_zips
      Dir.mktmpdir do |root|
        stub_project_zips(root)
        workdir = File.join(root, "work")

        report = conformance_adapter.fetch(workdir)

        assert File.file?(File.join(workdir, "rimanum", "metadata.json"))
        assert File.file?(File.join(workdir, "rimanum", "corpusjson", "P405432.json"))
        assert File.file?(File.join(workdir, "etcsri", "corpusjson", "Q004151.json"))
        assert_match(/\A\h{64}\z/, report.sha, "sha pins the (last) zip's sha256")
        assert_match(/rimanum=\h{12}/, report.notes)
        assert_match(/etcsri=\h{12}/, report.notes)
        assert_match(/1 catalog-only \(empty\)/, report.notes,
                     "the empty-corpusjson count is the honest sync note")
        # repos pins every in-scope project by its zip URL, subproject
        # slash-paths hyphen-flattened (saao/saa01 → saao-saa01.zip).
        assert_equal Nabu::Adapters::Oracc::PROJECTS.map { |project|
          "https://oracc.museum.upenn.edu/json/#{project.tr('/', '-')}.zip"
        }, report.repos.keys
      end
    end

    def test_fetch_is_a_no_op_on_304_not_modified
      Dir.mktmpdir do |root|
        stub_project_zips(root)
        workdir = File.join(root, "work")
        first = conformance_adapter.fetch(workdir)

        stub_request(:get, RIMANUM_URL)
          .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
          .to_return(status: 304)
        stub_request(:get, ETCSRI_URL)
          .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
          .to_return(status: 304)

        second = conformance_adapter.fetch(workdir)
        assert_equal first.sha, second.sha, "an unchanged upstream keeps the pinned sha"
        assert File.file?(File.join(workdir, "rimanum", "corpusjson", "P405432.json"))
      end
    end

    def test_fetch_attics_files_dropped_from_a_fresh_zip
      Dir.mktmpdir do |root|
        stub_project_zips(root)
        workdir = File.join(root, "work")
        adapter = conformance_adapter
        adapter.fetch(workdir)

        # Upstream drops a NON-ingestible file (metadata stays, catalogue
        # vanishes): no breaker (discover does not ingest catalogues), but the
        # retention contract still attics it.
        stub_project_zips(root, drop: "rimanum/catalogue.json")
        adapter.fetch(workdir)

        attic = File.join(workdir, ".attic", "rimanum", "catalogue.json")
        assert File.file?(attic), "the dropped file must be preserved in the attic"
        refute File.file?(File.join(workdir, "rimanum", "catalogue.json"))
        manifest = JSON.parse(File.read(File.join(workdir, ".attic", "rimanum", ".attic.json")))
        assert_match(/\A\h{64}\z/, manifest.fetch("catalogue.json"))
      end
    end

    def test_fetch_trips_the_mass_deletion_breaker_before_any_tree_change
      Dir.mktmpdir do |root|
        stub_project_zips(root)
        workdir = File.join(root, "work")
        adapter = conformance_adapter
        adapter.fetch(workdir)

        # Dropping 1 of 4 ingestible texts = 25% > the 20% threshold.
        stub_project_zips(root, drop: "rimanum/corpusjson/P405432.json")
        assert_raises(Nabu::SyncAborted) { adapter.fetch(workdir) }
        assert File.file?(File.join(workdir, "rimanum", "corpusjson", "P405432.json")),
               "a tripped breaker must leave the tree byte-unchanged"

        # --force proceeds: the text is atticked and rediscovered as retained.
        report = adapter.fetch(workdir, force: true)
        assert_match(/atticked/, report.notes)
        attic_ref = adapter.discover_with_attic(workdir)
                           .find { |ref| ref.id == "urn:nabu:oracc:rimanum:P405432" }
        refute_nil attic_ref, "the atticked text must be rediscovered"
        assert attic_ref.metadata["retained"]
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      Dir.mktmpdir do |root|
        stub_request(:get, RIMANUM_URL).to_return(status: 500)
        assert_raises(Nabu::FetchError) { conformance_adapter.fetch(File.join(root, "work")) }
      end
    end

    # -- helpers ---------------------------------------------------------------

    LAST_MODIFIED = "Fri, 28 Jun 2024 12:46:36 GMT"

    # Zip the checked-in fixture projects (real upstream payloads) into
    # <root>/zips and stub both project URLs with the recorded response shape
    # (200, application/zip, Last-Modified). +drop+ omits one entry, simulating
    # an upstream deletion in the next build.
    def stub_project_zips(root, drop: nil)
      zips = File.join(root, "zips-#{drop ? 'dropped' : 'full'}")
      Nabu::Adapters::Oracc::PROJECTS.each do |project|
        slug = project.tr("/", "-")
        url = "#{Nabu::Adapters::Oracc::ZIP_BASE_URL}/#{slug}.zip"
        staging = File.join(zips, slug)
        FileUtils.mkdir_p(File.dirname(staging))
        if FIXTURED_PROJECTS.include?(project)
          FileUtils.cp_r(File.join(FIXTURES, project), staging)
        else
          # No corpus fixture: ship only a real CC0 metadata.json (the license
          # gate the adapter reads) — a valid, empty project envelope, not
          # invented cdl data.
          FileUtils.mkdir_p(staging)
          FileUtils.cp(File.join(FIXTURES, "rimanum", "metadata.json"), staging)
        end
        FileUtils.rm_f(File.join(zips, drop)) if drop&.start_with?("#{slug}/")
        zip_path = File.join(zips, "#{slug}.zip")
        Nabu::Shell.run("zip", "-q", "-r", zip_path, slug, chdir: zips)
        stub_request(:get, url).to_return(
          status: 200, body: File.binread(zip_path),
          headers: { "Content-Type" => "application/zip", "Last-Modified" => LAST_MODIFIED }
        )
      end
    end

    # A workdir whose rimanum metadata.json declares +license+ instead of CC0.
    def with_doctored_license(license)
      Dir.mktmpdir do |root|
        workdir = File.join(root, "work")
        FileUtils.mkdir_p(workdir)
        FileUtils.cp_r(File.join(FIXTURES, "rimanum"), File.join(workdir, "rimanum"))
        FileUtils.cp_r(File.join(FIXTURES, "etcsri"), File.join(workdir, "etcsri"))
        metadata_path = File.join(workdir, "rimanum", "metadata.json")
        metadata = JSON.parse(File.read(metadata_path))
        metadata["license"] = license
        File.write(metadata_path, JSON.generate(metadata))
        yield workdir
      end
    end
  end
end
