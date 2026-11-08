# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # dbnl — the DBNL public-domain collection (KB): one offered zip of TEI.2
  # titles + the titels_pd.csv register. Document = title, passage = printed
  # page. Fixture: six real titles (two trimmed) + a trimmed register
  # (README.md).
  class DbnlTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("dbnl")
    URN = "urn:nabu:dbnl"
    ADAPTER = Nabu::Adapters::Dbnl
    TITLES = %w[_cor008cort01_01 _ges002gesc01_01 _rub001rubb01_01 dous003adia01_01 vaen001embl01_01
                will028lala01_01].freeze

    def conformance_adapter = ADAPTER.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "dbnl"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(stem) = documents.find { |d| d.urn == "#{URN}:#{stem}" } || flunk("#{stem} missing")

    # The fixture as it lands in canonical/dbnl/ (README/manifest are the
    # fixture's own furniture, not upstream's).
    def landed_tree
      Dir.mktmpdir do |dir|
        TITLES.each { |stem| FileUtils.cp(File.join(FIXTURES, "#{stem}.xml"), dir) }
        FileUtils.cp_r(File.join(FIXTURES, "metadata"), dir)
        yield dir
      end
    end

    # -- discovery -------------------------------------------------------------

    def test_discovers_one_document_per_zip_member
      assert_equal(TITLES.map { |stem| "#{URN}:#{stem}" }, conformance_adapter.discover(FIXTURES).map(&:id))
    end

    def test_the_register_and_the_fetch_pins_skip_by_rule_and_strangers_are_unrecognized
      landed_tree do |dir|
        skips = conformance_adapter.discovery_skips(dir)
        assert skips.clean?, skips.notes.inspect
        assert_equal 1, skips.skipped_by_rule
        assert_includes skips.notes.first, "7 titles listed, 1 with no file in xml_pd.zip"
        File.write(File.join(dir, Nabu::ZipFetch::STATE_FILE), "{}")
        File.write(File.join(dir, "metadata", Nabu::FileFetch::STATE_FILE), "{}")
        assert_equal 3, conformance_adapter.discovery_skips(dir).skipped_by_rule
        File.write(File.join(dir, "index.html"), "?")
        refute conformance_adapter.discovery_skips(dir).clean?
      end
    end

    # -- passages ----------------------------------------------------------------

    def test_passages_are_pages
      rubben = doc("_rub001rubb01_01")
      assert_equal "#{URN}:_rub001rubb01_01:f239vb", rubben.passages.first.urn
      assert rubben.passages.first.text.start_with?("Rubben. Hier beghint die sotternie. Rubben. Ay boy")
      assert_equal 9, rubben.passages.size
      assert_equal(%w[d1 d2], doc("dous003adia01_01").passages.map { |p| p.urn.split(":").last })
    end

    # -- language ------------------------------------------------------------------

    def test_language_comes_from_lang_usage_and_dutch_before_1500_is_middle_dutch
      assert_equal "dum", doc("_rub001rubb01_01").language
      assert_equal "no langUsage (Dutch); dated by 1500 → Middle Dutch",
                   doc("_rub001rubb01_01").metadata["language_basis"]
      assert_equal "nld", doc("_cor008cort01_01").language
      assert_equal "nld", doc("vaen001embl01_01").language, "no langUsage, 1618: Dutch"
      assert_equal "lat", doc("dous003adia01_01").language, "langUsage la (first of la/nl)"
      assert_equal "fra", doc("will028lala01_01").language
      assert(documents.all? { |d| d.passages.all? { |p| p.language == d.language } })
    end

    # -- dating ------------------------------------------------------------------------

    def test_a_manuscript_or_first_print_is_the_witness_own_date
      assert_equal({ "not_before" => 1400, "not_after" => 1420, "raw" => "ca. 1400-1420",
                     "basis" => "witness (handschrift)" }, doc("_rub001rubb01_01").metadata["date"])
      assert_equal({ "not_before" => 1566, "not_after" => 1566, "raw" => "1566",
                     "basis" => "witness (1ste druk)" }, doc("_cor008cort01_01").metadata["date"])
    end

    def test_a_later_printing_is_never_the_text_date
      date = doc("_ges002gesc01_01").metadata["date"]
      assert_equal "composition", date["class"], "the header states the first print's year"
      assert_equal [1838, 1838], date.values_at("not_before", "not_after")
      assert_includes date["raw"], "this witness 1840, 4de druk"
    end

    def test_the_jaar_shapes
      bounds = ->(raw) { ADAPTER::DbnlDate.bounds(raw) }
      assert_equal [1834, 1834], bounds["1834"]
      assert_equal [1880, 1880], bounds["ca. 1880"]
      assert_equal [1880, 1890], bounds["ca. 1880-1890"]
      assert_equal [1487, 1488], bounds["[1487-1488]"]
      assert_equal [1882, 1882], bounds["1882?"]
      assert_equal [1201, 1300], bounds["13de eeuw"]
      assert_equal [1601, 1700], bounds["begin 17de eeuw"]
      assert_equal [nil, 1343], bounds["voor 1343"]
      assert_equal [1870, nil], bounds["Na 1870"]
      assert_equal [1837, nil], bounds["1837-"]
      assert_nil bounds["?"]
    end

    def test_an_edition_year_without_a_first_print_statement_is_class_edition
      landed_tree do |dir|
        path = File.join(dir, "_ges002gesc01_01.xml")
        File.write(path, File.read(path).sub("De eerste druk dateert uit 1838.", ""))
        adapter = conformance_adapter
        meta = adapter.parse(adapter.discover(dir).find { |r| r.id.end_with?("_ges002gesc01_01") }).metadata
        assert_equal({ "not_before" => 1840, "not_after" => 1840, "raw" => "1840", "class" => "edition",
                       "basis" => "edition (4de druk)" }, meta["date"])
      end
    end

    # -- the register ------------------------------------------------------------------

    def test_register_fields_ride_the_metadata
      meta = doc("will028lala01_01").metadata
      assert_equal ["sec - taalkunde"], meta["genres"]
      assert_equal "1ste druk", meta["printing"]
      assert_equal "421571594", meta["ppn"]
      assert_equal "https://dbnl.org/tekst/will028lala01_01", meta["dbnl_url"]
      assert_equal ["J.F. Willems"], meta["author"]
      assert_equal [{ "id" => "will028", "name" => "J.F. Willems", "born" => "1793", "died" => "1846",
                      "birth_place" => "Boechout", "death_place" => "Gent" }], meta["authors"]
      assert_equal %w[poëzie jeugdliteratuur], doc("_ges002gesc01_01").metadata["genres"]
    end

    def test_an_anonymous_title_names_no_author
      meta = doc("_rub001rubb01_01").metadata
      assert meta["anonymous"]
      refute meta.key?("author")
      assert_equal({ "editeur" => ["leen006"], "primair" => %w[_abe001 _abe001abel01 _rub001rubb01] },
                   meta["dbnl_interp"])
    end

    def test_header_fields_ride_the_metadata
      meta = doc("_ges002gesc01_01").metadata
      assert_equal "_ges002gesc01_01", meta["dbnl_id"]
      assert_equal "_ges002gesc01", meta["ti_id"]
      assert_equal "page", meta["grain"]
      assert_equal "De geschiedenis van een goed en van een kwaad kind. J. Zender, Dordrecht 1840 (4de druk)",
                   meta["source_edition"]
      assert_equal 1, meta["editorial_interventions"].size
      assert_equal "De geschiedenis van een goed en van een kwaad kind", doc("_ges002gesc01_01").title
    end

    def test_a_member_without_a_register_row_parses_from_its_header
      Dir.mktmpdir do |dir|
        FileUtils.cp(File.join(FIXTURES, "_cor008cort01_01.xml"), dir)
        adapter = conformance_adapter
        document = adapter.parse(adapter.discover(dir).first)
        assert_equal "absent", document.metadata["register"]
        refute document.metadata.key?("date")
        assert_equal "nld", document.language
      end
    end

    # -- load + timeline ------------------------------------------------------------------

    def test_loading_twice_is_idempotent
      catalog = loaded_catalog
      first = [catalog[:documents].count, catalog[:passages].count]
      assert_equal [6, documents.sum { |d| d.passages.size }], first
      Nabu::Store::Loader.new(db: catalog, source: Nabu::Store::Source.first(slug: "dbnl"))
                         .load_from(ADAPTER.new, workdir: FIXTURES, full: true)
      assert_equal first, [catalog[:documents].count, catalog[:passages].count]
    end

    def test_the_timeline_rows_carry_the_date_classes
      catalog = loaded_catalog
      Nabu::Store::TimelineBuilder::MetadataDates.refresh_source!(catalog: catalog, slug: "dbnl")
      rows = catalog[:document_axes].join(:documents, id: :document_id)
                                    .select(Sequel[:documents][:urn], Sequel[:document_axes][:date_class])
                                    .to_hash(:urn, :date_class)
      assert_equal 6, rows.size
      assert_equal "composition", rows["#{URN}:_ges002gesc01_01"]
      assert_nil rows["#{URN}:_rub001rubb01_01"]
    end

    # -- registry --------------------------------------------------------------------------

    def test_registry_row_is_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["dbnl"]
      refute_nil entry
      assert_equal ADAPTER, entry.adapter_class
      refute entry.wired, "wired: false until the first real sync is verified"
      assert_equal "manual", entry.sync_policy
    end

    def test_the_lects_resolve_through_the_registry
      lects = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"))
      assert_equal "nl", lects.resolve("nld", source: "dbnl")
      refute_nil lects.resolve("dum", source: "dbnl")
    end

    # -- fetch: ZipFetch + FileFetch (WebMock only) ------------------------------------------

    def test_fetch_unpacks_the_zip_flat_and_lands_the_register
      stub_request(:get, ADAPTER::ZIP_URL).to_return(status: 200, body: zip_body)
      stub_request(:get, ADAPTER::METADATA_URL)
        .to_return(status: 200, body: File.read(File.join(FIXTURES, "metadata", "titels_pd.csv")))
      Dir.mktmpdir do |workdir|
        report = conformance_adapter.fetch(workdir)
        assert_instance_of Nabu::FetchReport, report
        assert_equal(TITLES.map { |stem| "#{URN}:#{stem}" }, conformance_adapter.discover(workdir).map(&:id))
        assert File.file?(File.join(workdir, "metadata", "titels_pd.csv"))
        skips = conformance_adapter.discovery_skips(workdir)
        assert skips.clean?, skips.notes.inspect
        assert_equal 3, skips.skipped_by_rule, "the register + the two state pins"
      end
    end

    def test_fetch_wraps_http_failure
      stub_request(:get, ADAPTER::ZIP_URL).to_return(status: 500)
      stub_request(:get, ADAPTER::METADATA_URL).to_return(status: 200, body: "sep=|\nti_id|\n")
      Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { conformance_adapter.fetch(workdir) } }
    end

    def test_the_probe_heads_both_artifacts_and_only_those
      assert_equal :http_zip, ADAPTER.remote_probe_strategy
      assert_equal [ADAPTER::ZIP_URL, ADAPTER::METADATA_URL], ADAPTER.http_probe_targets.map(&:zip_url)
      assert_equal [ADAPTER::METADATA_DIR, Nabu::ZipFetch::STATE_FILE], ADAPTER.materialized_paths
    end

    private

    def loaded_catalog
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "dbnl", name: "DBNL", adapter_class: ADAPTER.name,
                                          license_class: "attribution")
      Nabu::Store::Loader.new(db: catalog, source: source).load_from(ADAPTER.new, workdir: FIXTURES, full: true)
      catalog
    end

    # xml_pd.zip's shape: flat members at the zip root.
    def zip_body
      Dir.mktmpdir do |dir|
        TITLES.each { |stem| FileUtils.cp(File.join(FIXTURES, "#{stem}.xml"), dir) }
        zip_path = File.join(dir, "xml_pd.zip")
        Nabu::Shell.run("zip", "-q", zip_path, *TITLES.map { |stem| "#{stem}.xml" }, chdir: dir)
        return File.binread(zip_path)
      end
    end
  end
end
