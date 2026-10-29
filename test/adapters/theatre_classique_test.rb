# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # theatre-classique — Paul Fièvre's TEI plays via the DraCor mirror: one
  # document per play file, passages = the theatre-classique-tei family's
  # blocks. Four real files (three trimmed, one whole).
  class TheatreClassiqueTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("theatre-classique")
    URN = "urn:nabu:theatre-classique"
    STEMS = %w[ABEILLE_CORIOLAN BARY_BELLESMAINS MOLIERE_MISANTHROPE SAND_MOLIERE].freeze

    def conformance_adapter = Nabu::Adapters::TheatreClassique.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "theatre-classique"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(id) = documents.find { |d| d.urn == "#{URN}:#{id}" } || flunk("#{id} missing")

    def test_discovers_one_document_per_play_keyed_by_the_filename
      assert_equal STEMS.map { |s| "#{URN}:#{s.downcase}" }, conformance_adapter.discover(FIXTURES).map(&:id)
      assert_equal 0, conformance_adapter.discovery_skips(FIXTURES).skipped_by_rule
    end

    def test_identity_is_the_filename_never_the_idno
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "xml"))
        FileUtils.cp(File.join(FIXTURES, "xml", "ABEILLE_CORIOLAN.xml"), File.join(dir, "xml", "ABEILLE_CORIOLAN.XML"))
        ref = conformance_adapter.discover(dir).first
        assert_equal "#{URN}:abeille_coriolan", ref.id, "an upper-case .XML extension is a play too"
        assert_equal "ABEILLE_CORIOLAN", conformance_adapter.parse(ref).metadata["tc_id"]
      end
      assert_nil doc("sand_moliere").metadata["idno"], "SAND_MOLIERE carries no idno"
    end

    def test_a_play_whose_textual_author_died_after_the_cutoff_is_skipped_by_rule
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "xml"))
        source = File.read(File.join(FIXTURES, "xml", "SAND_MOLIERE.xml"))
        File.write(File.join(dir, "xml", "SAND_MOLIERE.xml"), source.sub("(1804-1876)", "(1890-1960)"))
        assert_empty conformance_adapter.discover(dir).to_a
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.skipped_by_rule
        assert skips.clean?
        assert_match(/SAND_MOLIERE\.xml: SAND, George d\. 1960 — in copyright/, skips.notes.first)
      end
      assert_equal 1955, Nabu::Adapters::TheatreClassique::AUTHOR_DEATH_CUTOFF
    end

    def test_a_collaborators_late_death_does_not_exclude_the_play
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "xml"))
        source = File.read(File.join(FIXTURES, "xml", "SAND_MOLIERE.xml"))
        File.write(File.join(dir, "xml", "SAND_MOLIERE.xml"),
                   source.sub("</titleStmt>",
                              "<author type=\"musique\">Henri SAUGUET (1901-1989)</author></titleStmt>"))
        assert_equal ["#{URN}:sand_moliere"], conformance_adapter.discover(dir).map(&:id)
      end
    end

    # The mirror's one Latin-1 file (CORNEILLET_LAODICE declares
    # encoding="iso-8859-1"): rebuilt here from a real fixture transcoded
    # the same way, it is discovered and quarantines at parse — never an
    # aborted discovery.
    def test_a_latin1_file_is_discovered_and_quarantines_at_parse
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "xml"))
        source = File.read(File.join(FIXTURES, "xml", "ABEILLE_CORIOLAN.xml"))
        File.binwrite(File.join(dir, "xml", "ABEILLE_CORIOLAN.xml"),
                      source.sub('encoding="UTF-8"', 'encoding="iso-8859-1"').encode("ISO-8859-1"))
        adapter = conformance_adapter
        refs = adapter.discover(dir).to_a
        assert_equal ["#{URN}:abeille_coriolan"], refs.map(&:id)
        error = assert_raises(Nabu::ParseError) { adapter.parse(refs.first) }
        assert_match(/not valid UTF-8/, error.message)
      end
    end

    def test_passages_carry_citations_kinds_and_speakers
      d = doc("moliere_misanthrope")
      assert_equal "fra", d.language
      assert_equal "LE MISANTHROPE ou L'ATRABILAIRE AMOUREUX, COMÉDIE", d.title
      assert_equal "#{URN}:moliere_misanthrope:f0.1", d.passages.first.urn
      assert_equal "LE MISANTHROPE", d.passages.first.text
      line = d.passages.find { |p| p.urn == "#{URN}:moliere_misanthrope:1.1.2" }
      assert_equal "Qu'est-ce donc ? Qu'avez-vous ?", line.text
      assert_equal({ "kind" => "l", "who" => "PHILINTE", "speaker" => "PHILINTE.", "n" => "1", "part" => "i" },
                   line.annotations)
      assert_equal({ "kind" => "head" }, d.passages.find { |p| p.urn.end_with?(":1.1") }.annotations)
    end

    def test_metadata_mines_edition_date_premiere_imprint_place_and_genre
      meta = doc("moliere_misanthrope").metadata
      assert_equal({ "not_before" => 1667, "not_after" => 1667,
                     "raw" => "M. DC. LXVII. AVEC PRIVILÈGE DU ROI.", "class" => "edition" }, meta["date"])
      assert_equal({ "date" => "1666-06-04", "location" => "Théâtre du Palais-Royal",
                     "note" => "Représenté pour la première fois le 4 juin 1666 au Théâtre du Palais Royal." },
                   meta["premiere"])
      assert_equal "Paris", meta["place"]
      assert_match(/\AÀ PARIS, chez JEAN RIBOU/, meta["imprint"])
      assert_equal({ "location" => "Paris", "country" => "France" }, meta["setting"])
      assert_equal ["Comédie", "moeurs", "Cinq actes", "vers", "1661-1670"],
                   meta.values_at("genre", "inspiration", "structure", "form", "periode")
      assert_equal "MOLIERE, Jean-Baptiste Poquelin dit", meta["author"]
      assert_equal [1622, 1673], meta.values_at("author_birth", "author_death")
      assert_equal "Creative Commons BY-NC-SA", meta["rights"]
      assert_equal "https://gallica.bnf.fr/ark:/12148/bpt6k1280468t", meta["permalink"]["url"]
    end

    def test_imprint_cities_title_case_into_one_axis_key
      assert_equal "La Haye", doc("abeille_coriolan").metadata["place"]
      assert_equal "TEI.2", doc("abeille_coriolan").metadata["tei_root"]
      assert_equal "Paris", doc("bary_bellesmains").metadata["place"], "read from the docImprint editor"
      assert_nil doc("sand_moliere").metadata["place"], "a bare printer name (BIELEFELD) names no city"
    end

    def test_a_missing_edition_year_falls_back_to_the_periode_band
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "xml"))
        source = File.read(File.join(FIXTURES, "xml", "BARY_BELLESMAINS.xml"))
        File.write(File.join(dir, "xml", "BARY_BELLESMAINS.xml"), source.sub("<docDate value='1662'>", "<docDate>"))
        adapter = conformance_adapter
        meta = adapter.parse(adapter.discover(dir).first).metadata
        assert_equal({ "not_before" => 1661, "not_after" => 1670, "raw" => "periode 1661-1670",
                       "class" => "composition" }, meta["date"])
      end
    end

    def test_the_edition_date_rides_the_structured_metadata_dates_lane
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["theatre-classique"]
    end

    def test_manifest_quotes_the_rights_statements
      manifest = Nabu::Adapters::TheatreClassique.manifest
      assert_equal "nc", manifest.license_class
      assert_includes manifest.license, "<rights>Creative Commons BY-NC-SA</rights>"
      assert_includes manifest.license, "non commerciale de ces contenus est libre et gratuite"
      assert_equal "theatre-classique-tei", manifest.parser_family
    end

    def test_registry_row_is_wired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["theatre-classique"]
      refute_nil entry
      assert entry.wired, "wired 2026-10-28: first sync verified on census (1,939 docs)"
      assert_equal "manual", entry.sync_policy
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "theatre-classique", name: "Théâtre Classique",
                                          adapter_class: "Nabu::Adapters::TheatreClassique",
                                          license_class: "nc")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 4, first.added
      passages = db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 4, second.skipped
      assert_equal passages, db[:passages].count
      assert_equal [1], db[:passages].distinct.select_map(:revision)
    ensure
      db&.disconnect
    end

    # --- fetch (local git only, no network) ----------------------------------

    def test_fetch_sparse_clones_only_the_xml_cone
      Dir.mktmpdir("nabu-theatre-classique-fetch") do |root|
        upstream = File.join(root, "upstream")
        build_upstream_repo(upstream)
        work = File.join(root, "canonical")
        adapter = conformance_adapter
        adapter.define_singleton_method(:repo_url) { upstream }
        report = adapter.fetch(work)
        assert_match(/\A[0-9a-f]{40}\z/, report.sha)
        assert File.file?(File.join(work, "xml", "MOLIERE_MISANTHROPE.xml"))
        assert File.file?(File.join(work, "README.md"))
        refute File.exist?(File.join(work, "update")), "the repo's update tooling stays out of the cone"
        assert_equal 4, adapter.discover(work).count
      end
    end

    private

    def build_upstream_repo(upstream)
      FileUtils.mkdir_p(upstream)
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      Nabu::Shell.run("git", "init", "-q", upstream)
      FileUtils.cp_r(File.join(FIXTURES, "xml"), upstream)
      File.write(File.join(upstream, "README.md"), "# Théâtre Classique\n")
      File.write(File.join(upstream, "update"), "#!/bin/bash\n")
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
    end
  end
end
