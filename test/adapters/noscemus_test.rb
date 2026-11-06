# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "digest"
require "fileutils"
require "tmpdir"

module Adapters
  # noscemus: the NOSCEMUS Digital Sourcebook (Zenodo 15040256) — the
  # uncorrected Transkribus HTR of 1,050 early-modern scientific Latin
  # prints, one plain-text file per Transkribus document, joined on the
  # Transkribus id to the Noscemus Wiki backup (Zenodo 7855322: works +
  # authors XML). Fixtures (README): four trimmed works + the one
  # empty-text work (the skipped-by-rule specimen), the wiki slices for
  # their joins, a wiki work with no copy and one with no Transkribus id,
  # and one never-fetched literature page.
  class NoscemusTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("noscemus")
    Adapter = Nabu::Adapters::Noscemus
    BACON = "urn:nabu:noscemus:1031760"
    HIPPOCRATES = "urn:nabu:noscemus:1285855"
    OUDIN = "urn:nabu:noscemus:643448"
    PALINGENIO = "urn:nabu:noscemus:5314216"
    CRUGER = "urn:nabu:noscemus:736346"

    def conformance_adapter = Adapter.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "noscemus"

    def adapter = conformance_adapter

    def refs = @refs ||= adapter.discover(FIXTURES).to_a

    def document(urn)
      ref = refs.find { |r| r.id == urn } || flunk("no ref #{urn}")
      adapter.parse(ref)
    end

    def passage(urn, citation)
      document(urn).find { |p| p.urn == "#{urn}:#{citation}" } || flunk("no #{urn}:#{citation}")
    end

    # -- manifest ---------------------------------------------------------------

    def test_manifest_is_attribution_under_cc_by
      manifest = adapter.manifest
      assert_equal "noscemus", manifest.id
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC BY 4.0"
      assert_includes manifest.license, "15040256"
      assert_includes manifest.license, "7855322"
      assert_equal "https://zenodo.org/records/15040256", manifest.upstream_url
    end

    # -- discover / skips ---------------------------------------------------------

    def test_discover_yields_one_document_per_transkribus_directory_in_id_order
      assert_equal [OUDIN, CRUGER, BACON, HIPPOCRATES, PALINGENIO], refs.map(&:id)
    end

    def test_the_wiki_tree_and_dotfiles_are_not_documents
      skips = adapter.discovery_skips(FIXTURES)
      assert_equal 0, skips.unrecognized
      refute(refs.any? { |ref| ref.path.include?("/wiki/") })
    end

    def test_an_unexpected_top_level_entry_is_unrecognized_and_counted
      Dir.mktmpdir("nabu-noscemus-stray") do |root|
        FileUtils.cp_r(File.join(FIXTURES, "1285855"), root)
        FileUtils.mkdir_p(File.join(root, "stray"))
        FileUtils.mkdir_p(File.join(root, "999"))
        skips = adapter.discovery_skips(root)
        assert_equal 2, skips.unrecognized, "a non-id directory and an id directory without a text file"
        assert_match(/stray/, skips.notes.join)
        assert_equal ["urn:nabu:noscemus:1285855"], adapter.discover(root).map(&:id)
      end
    end

    def test_an_empty_text_work_is_skipped_by_rule
      ref = refs.find { |r| r.id == CRUGER }
      error = assert_raises(Nabu::DocumentSkipped) { adapter.parse(ref) }
      assert_match(/no transcribed text/, error.reason)
    end

    def test_discover_yields_nothing_before_the_fetch
      Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
    end

    # -- the passage grain ----------------------------------------------------------

    def test_one_passage_per_transkribus_text_region_cited_by_region_ordinal
      doc = document(BACON)
      assert_equal "lat", doc.language
      assert_equal(%w[1 2 3 4 6 7 8 10 11 12 13 15 16 19 20], doc.map { |p| p.urn.delete_prefix("#{BACON}:") })
      assert_equal "FRANCISCJ\nDE VERULAMIO /\nSummi Angliae\nCANCELLARIJ /\nInstauratio\nmagna.",
                   passage(BACON, 1).text
      first_page = passage(BACON, 6).text
      assert first_page.start_with?("FRIMNCISOVS\nDE VERVLAMIO,"), first_page[0, 40]
      assert_includes first_page, "Vm Illi pro comperto esset, In¬\ntellectum", "HTR lines and ¬ ride verbatim"
    end

    def test_letterless_regions_ride_the_next_passage_as_marks
      assert_equal ["1620."], passage(BACON, 6).annotations["marks"]
      assert_equal %W[2\n9 4], passage(BACON, 19).annotations["marks"], "consecutive marks keep their order"
      assert_nil passage(BACON, 7).annotations["marks"]
      assert_equal %w[5 6], passage(BACON, 20).annotations["trailing_marks"], "marks after the last region"
      assert_equal ["7"], passage(OUDIN, 8).annotations["marks"]
    end

    def test_every_document_declares_the_uncorrected_htr
      %w[1031760 1285855 643448 5314216].each do |id|
        meta = document("urn:nabu:noscemus:#{id}").metadata
        assert_equal "machine-htr", meta["text_nature"]
        assert_includes meta["text_note"], "have not undergone manual editing or correction"
      end
    end

    # -- the Transkribus header -------------------------------------------------------

    def test_the_header_is_metadata_never_text
      doc = document(BACON)
      refute(doc.any? { |p| p.text.include?("Metadata section") })
      meta = doc.metadata
      assert_equal "Bacon, Francis - Instauratio magna. London 1620", doc.title
      assert_equal "1031760", meta["transkribus_id"]
      assert_equal 412, meta["page_count"]
      assert_equal "Wed Jan 01 01:00:00 CET 1620", meta["transkribus_created_from"]
      assert_nil meta["transkribus_script_type"], "Bacon's header carries no Sripttype line"
      assert_equal "NORMAL_LONG_S", document(HIPPOCRATES).metadata["transkribus_script_type"]
      assert_equal "Latin", document(PALINGENIO).metadata["transkribus_language"]
      assert_nil meta["transkribus_language"], "upstream's literal null rides as absence"
    end

    # -- dating / places -----------------------------------------------------------------

    def test_the_imprint_year_and_place_come_from_the_copys_own_title
      meta = document(BACON).metadata
      assert_equal({ "not_before" => 1620, "not_after" => 1620, "raw" => "London 1620" }, meta["date"])
      assert_equal "imprint", meta["date_basis"]
      assert_equal "London", meta["place"]
      assert_equal "Basel", document(PALINGENIO).metadata["place"]
      assert_equal 1543, document(PALINGENIO).metadata.dig("date", "not_before")
    end

    def test_imprint_reading_of_upstreams_title_shapes
      {
        "Bacon, Francis - Instauratio magna. London 1620.pdf" => ["London", 1620, 1620],
        "Malpighi, Marcello - Anatome plantarum. London 1675-79" => ["London", 1675, 1679],
        "Acta literaria Sueciae. Vol. 1. Uppsala [1723–1725] " => ["Uppsala", 1723, 1725],
        "Cermisonus, Antonius – Recollectae de urinis, Venice 1479" => ["Venice", 1479, 1479],
        "Tazewell, William - Vade-mecum medicum. Paris et al. 1798.pdf" => ["Paris", 1798, 1798],
        "Leibniz, Gottfried Wilhelm - Tentamen de motuum coelestium causis.Leipzig 1689.pdf" => ["Leipzig", 1689, 1689],
        "Nova Acta Regiae Societatis Scientiarum Upsaliensis. Vol. 3 Uppsala 1861.pdf" => ["Uppsala", 1861, 1861],
        "Abhandlungen der Churfürstlich-baierischen Akademie der Wissenschaften. Bd. 4. 1767 Munich.pdf" =>
          ["Munich", 1767, 1767],
        "Acta eruditorum 1729. Leipzig 1729.pdf" => ["Leipzig", 1729, 1729],
        "Falloppio, Gabriele - Observationes anatomicae. Paris. 1562.pdf" => ["Paris", 1562, 1562],
        "Taruffi, Giuseppe Antonio - Montgolferii machina volans. s. l. 1784.pdf" => [nil, 1784, 1784],
        "Philosophiae Naturalis Principia Mathematica 1726.pdf" => [nil, 1726, 1726],
        "Müller, Otto - Vermium terrestrium et fluviatilium historia. Leipzig & Copenhagen 1773. Vol. 1.pdf" =>
          ["Leipzig & Copenhagen", 1773, 1773],
        "Pio, Giovanni Battista - In Carum Lucretium poetam Commentarii - Bologna 1514.pdf" => ["Bologna", 1514, 1514],
        "Quillet, Claude - Callipaedia - Paris. 1656.pdf" => ["Paris", 1656, 1656],
        "Rumpf, Georg Eberhard - Herbarium Amboinense. Vol. 6.,1 Amsterdam 1750.pdf" => ["Amsterdam", 1750, 1750],
        "Oevres complètes de Christian Hugens. Vol 17. Amsterdam 1932.pdf" => ["Amsterdam", 1932, 1932],
        "Lloyd, Philipp - De partium septentrionalium quibusdam affectibus et remediis. 1699.pdf" => [nil, 1699, 1699],
        "Descartes, René et al. - Geometria a Renato des Cartes edita Amsterdam 1659–1661.pdf" => [nil, 1659, 1661],
        "Goldbach, Christian - Letter to Euler 20-31 Juliy 1730.pdf" => [nil, 1730, 1730]
      }.each do |title, (place, from, to)|
        imprint = Adapter.imprint(title)
        assert_equal [place, from, to], [imprint[:place], imprint[:not_before], imprint[:not_after]], title
      end
      assert_nil Adapter.imprint("Gregorius, de Tipherno - De astrologia oratio (Reden und Briefe italienischer " \
                                 "Humanisten).pdf")
    end

    def test_an_imprint_without_a_town_places_by_the_whole_copy_wiki_work
      Dir.mktmpdir("nabu-noscemus-place") do |root|
        FileUtils.cp_r(File.join(FIXTURES, "wiki"), root)
        FileUtils.cp_r(File.join(FIXTURES, "1285855"), root)
        path = Dir.glob(File.join(root, "1285855", "*.txt")).first
        File.write(path, File.read(path).sub("expositi. Paris 1634.pdf", "expositi 1634.pdf"))
        meta = adapter.parse(adapter.discover(root).first).metadata
        assert_equal %w[Paris wiki_place], meta.values_at("place", "place_basis")
        assert_equal "imprint", meta["date_basis"], "the year still comes from the label"
      end
      assert_equal "imprint", document(BACON).metadata["place_basis"]
    end

    def test_a_joint_imprint_places_at_its_first_town_and_lists_all
      assert_equal %w[Leipzig Copenhagen], Adapter.places("Leipzig & Copenhagen")
      assert_equal %w[Lyon Zurich], Adapter.places("Lyon; Zurich")
    end

    # -- the wiki join ------------------------------------------------------------------

    def test_a_whole_document_wiki_work_is_primary_and_contained_works_list_their_start_page
      meta = document(OUDIN).metadata
      works = meta["wiki_works"]
      assert_equal(["Poemata didascalica", "Aurora borealis", "Iris"], works.map { |w| w["title"] })
      primary = works.first
      assert primary["primary"]
      assert_nil primary["start_page"]
      assert_equal "(Vol. 2)", primary["note"]
      assert_equal "Oudin, François", primary["author"]
      assert_equal "1749", primary["year"]
      aurora = works[1]
      assert_equal 231, aurora["start_page"]
      assert_equal "Noceti, Carlo", aurora["author"]
      assert_equal "(in: Oudin, François: Poemata didascalica, vol. 2, Paris 1749, 224-271)", aurora["note"],
                   "wiki markup stripped"
      refute aurora["primary"]
    end

    def test_genre_and_discipline_facets_are_the_union_over_the_joined_works
      facets = document(OUDIN).metadata["facets"]
      assert_equal ["Didactic poem"], facets.dig("genre", "values")
      assert_equal ["Other (see description)", "Physics", "Astronomy/Astrology/Cosmography"],
                   facets.dig("discipline", "values")
      hippo = document(HIPPOCRATES).metadata["facets"]
      assert_equal ["Translation", "Didactic poem", "Other (see description)"], hippo.dig("genre", "values")
      assert_equal "Translation, Didactic poem, Other (see description)", hippo.dig("genre", "raw")
    end

    def test_authors_carry_the_wiki_life_dates_and_gnd
      authors = document(HIPPOCRATES).metadata["authors"]
      assert_equal(["Hippocrates", "Denisot, Gérard"], authors.map { |a| a["name"] })
      assert_equal({ "name" => "Denisot, Gérard", "born" => "1520", "died" => "1595", "gnd" => "1032658983" },
                   authors.last)
      assert_equal "c. 460 BC", authors.first["born"], "life dates ride raw"
    end

    def test_an_unjoined_work_takes_its_authors_from_the_header_and_carries_no_facets
      meta = document(PALINGENIO).metadata
      assert_nil meta["wiki_works"]
      assert_nil meta["facets"]
      assert_equal [{ "name" => "Palingènio Stellato, Marcello" }], meta["authors"]
    end

    def test_a_contained_only_join_keeps_the_copys_own_dating
      meta = document(BACON).metadata
      assert_equal(["Novum Organum"], meta["wiki_works"].map { |w| w["title"] })
      assert_equal 51, meta["wiki_works"].first["start_page"]
      assert_equal "imprint", meta["date_basis"]
    end

    def test_the_wiki_tables_census_works_without_a_copy
      census = Adapter.wiki_census(FIXTURES)
      assert_equal 7, census[:works]
      assert_equal 1, census[:without_transkribus_id], "Archimedis De incidentibus in humidis"
      assert_equal 1, census[:without_a_copy], "Epistola invitatoria (71583 — no such directory)"
    end

    def test_the_literature_table_is_never_read
      assert File.file?(File.join(FIXTURES, "wiki/literature/2023-03-31_noscemus_literature.xml"))
      refute(Adapter::WIKI_FILES.values.any? { |file| file[:filename].include?("literature") })
    end

    # -- fetch (WebMock only) --------------------------------------------------------------

    def stub_zip_body
      Dir.mktmpdir do |dir|
        top = File.join(dir, "staging", "Noscemus_Digital_Sourcebook")
        FileUtils.mkdir_p(top)
        FileUtils.cp_r(File.join(FIXTURES, "1285855"), top)
        zip = File.join(dir, "nds.zip")
        Nabu::Shell.run("zip", "-q", "-r", zip, "Noscemus_Digital_Sourcebook", chdir: File.join(dir, "staging"))
        return File.binread(zip)
      end
    end

    def wiki_bodies
      Adapter::WIKI_FILES.to_h do |key, file|
        [key, File.binread(File.join(FIXTURES, "wiki", key.to_s, file[:filename]))]
      end
    end

    def pinned_adapter(zip, wiki)
      Adapter.new(pins: { zip: Digest::MD5.hexdigest(zip) }.merge(wiki.transform_values { Digest::MD5.hexdigest(_1) }))
    end

    def stub_all(zip, wiki)
      stub_request(:get, Adapter::ZIP_URL).to_return(status: 200, body: zip)
      Adapter::WIKI_FILES.each { |key, file| stub_request(:get, file[:url]).to_return(status: 200, body: wiki[key]) }
    end

    def test_fetch_lands_the_works_and_the_wiki_tables_under_their_pins
      zip = stub_zip_body
      wiki = wiki_bodies
      stub_all(zip, wiki)
      Dir.mktmpdir do |workdir|
        fetcher = pinned_adapter(zip, wiki)
        report = fetcher.fetch(workdir)
        assert_equal Digest::SHA256.hexdigest(zip), report.sha
        assert_equal ["urn:nabu:noscemus:1285855"], fetcher.discover(workdir).map(&:id)
        assert_equal wiki[:works], File.binread(File.join(workdir, "wiki/works/2023-03-31_noscemus_works.xml"))
        fetcher.fetch(workdir)
        assert File.file?(File.join(workdir, "wiki/authors/2023-03-31_noscemus_authors.xml")),
               "a re-fetch never dooms the wiki tables"
      end
    end

    def test_fetch_aborts_on_a_zip_pin_mismatch_with_the_tree_untouched
      zip = stub_zip_body
      wiki = wiki_bodies
      stub_all(zip, wiki)
      Dir.mktmpdir do |workdir|
        error = assert_raises(Nabu::FetchError) { Adapter.new.fetch(workdir) }
        assert_match(/Noscemus_Digital_Sourcebook\.zip.*pin/, error.message)
        assert_empty(Dir.children(workdir).reject { |name| name.start_with?(".") })
      end
    end

    def test_fetch_aborts_on_a_wiki_pin_mismatch_with_the_tree_untouched
      zip = stub_zip_body
      wiki = wiki_bodies
      stub_all(zip, wiki.merge(works: "#{wiki[:works]} "))
      Dir.mktmpdir do |workdir|
        error = assert_raises(Nabu::FetchError) { pinned_adapter(zip, wiki).fetch(workdir) }
        assert_match(/works.*pin/, error.message)
        assert_empty(Dir.children(workdir).reject { |name| name.start_with?(".") })
      end
    end

    def test_the_live_pins_are_the_records_md5_checksums
      assert_equal "ccd475d900ee5123d41d281b7234b285", Adapter::PINS[:zip]
      assert_equal "983b5bfdd22d7c3a9f064dd81b8e0e0a", Adapter::PINS[:works]
      assert_equal "c68af30807dda50d86367eb2a1c1f3da", Adapter::PINS[:authors]
    end

    def test_fetch_wraps_http_failure
      stub_request(:get, Adapter::ZIP_URL).to_return(status: 500)
      Dir.mktmpdir do |workdir|
        assert_raises(Nabu::FetchError) { Adapter.new.fetch(workdir) }
      end
    end

    # -- idempotency -------------------------------------------------------------------------

    def test_loading_the_fixture_set_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "noscemus", name: "NOSCEMUS", adapter_class: Adapter.name,
                                          license_class: "attribution")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
      assert_equal 4, first.added
      assert_equal 1, first.skipped_by_rule, "the empty-text Crüger"
      assert_equal 0, first.errored
      assert_equal 15 + 24 + 10 + 11, db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
      assert_equal 4, second.skipped
      assert_equal 60, db[:passages].count
      assert_equal [1], db[:passages].distinct.select_map(:revision)
    end
  end
end
