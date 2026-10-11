# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # ticha — the Ticha project's colonial Valley Zapotec TEI (P117-5): one
  # git repo; document = one XML file, passage = one page. Fixture: the
  # repo's real files, whole or structurally trimmed (README): the 1744
  # Teitipac testament (Zapotec) and its Spanish translation, three
  # manuscript translations (unclosed <br>, truncation, stray </head>, a
  # duplicated page number), an AGEO testament (teiHeader, n-less breaks),
  # trims of Córdova's Arte, Levanto's Cathecismo and Agüero's
  # Miscelaneo, plus the skip-rule files (schema, an encoding example,
  # the superseded manuscripts/encoded/Te744T.xml) and places.json.
  class TichaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("ticha")
    URN = "urn:nabu:ticha"

    def conformance_adapter = Nabu::Adapters::Ticha.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "ticha"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(stem) = documents.find { |d| d.urn == "#{URN}:#{stem}" } || flunk("#{stem} missing")

    def test_discovers_nine_documents_and_skips_by_rule
      assert_equal %w[AGEO_Testaments_AGEO42 Al642T Al698T Fr720T Te744 Te744T aguero-miscelaneo cordova-arte
                      levanto-cathecismo].map { |s| "#{URN}:#{s}" },
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 3, skips.skipped_by_rule, "schema/, the _example doc, the superseded encoded/Te744T.xml"
      assert skips.clean?
    end

    def test_the_work_directory_encoding_wins_over_the_encoded_duplicate
      ref = conformance_adapter.discover(FIXTURES).find { |r| r.id == "#{URN}:Te744T" }
      assert ref.path.end_with?("/Te744T/Te744T.xml")
    end

    def test_the_zapotec_original_reads_zap_and_is_titled_from_its_comment
      d = doc("Te744")
      assert_equal "zap", d.language
      assert_equal "Testament from San Sebastián Teitipac, 1744", d.title
      assert_equal "zapotec-original", d.metadata["text_role"]
      assert_equal 5, d.passages.size
      first = d.passages.first
      assert_equal "#{URN}:Te744:1", first.urn
      assert_equal "zap", first.language
      assert_match(/\A\+ 7 8\nLaa stissima trinidad Dios bixoce Dios xini Dios espiritu\n/, first.text)
    end

    def test_a_t_id_is_a_spanish_translation_of_its_original
      d = doc("Te744T")
      assert_equal "spa", d.language
      assert_equal "spanish-translation", d.metadata["text_role"]
      assert_equal "Te744", d.metadata["translation_of"]
      assert_equal({ "spa" => 1050, "lat" => 26 }, d.metadata["languages"])
      assert_equal ["#{URN}:Te744T:s1", "#{URN}:Te744T:2", "#{URN}:Te744T:3"], d.passages.map(&:urn),
                   "text before the first <pb/> is an unnumbered page, cited by its sequence"
    end

    def test_manuscript_ids_mine_year_and_town
      meta = doc("Al642T").metadata
      assert_equal({ "not_before" => 1642, "not_after" => 1642,
                     "raw" => "Ticha id Al642T (the original document's year)" }, meta["date"])
      assert_equal "San Pedro el Alto", meta["place"]
      assert_equal "Al", meta["town_code"]
      assert_equal({ "name" => "San Pedro el Alto", "lon" => -96.4722989, "lat" => 16.0362827, "ticha_place_id" => 11 },
                   meta["ticha_place"], "places.json coordinates ride metadata-only")
      assert_equal 4, meta["markup_repairs"]
      assert meta["translation_statement"], "the text attests 'tradusido del ydioma zapoteco'"
      assert_equal "Ticha manuscript Al642T (Spanish translation of Al642)", doc("Al642T").title
    end

    def test_regularized_reading_rides_as_an_annotation
      passage = doc("Al642T").passages.first
      assert passage.text.start_with?("Oy domingo a dos del mes de Junio de 1642 años")
      assert passage.annotations["regularized"].start_with?("Hoy domingo a dos del mis de Junio")
      assert_equal({ "spa" => 281 }, passage.annotations["languages"])
    end

    def test_duplicated_page_numbers_are_suffixed
      assert_equal ["#{URN}:Fr720T:1", "#{URN}:Fr720T:2", "#{URN}:Fr720T:2#2"], doc("Fr720T").passages.map(&:urn),
                   "upstream numbers the third page 2 again"
    end

    def test_an_ageo_testament_is_spanish_unmarked_undated_unplaced
      d = doc("AGEO_Testaments_AGEO42")
      assert_equal "Testament AGEO 42", d.title
      assert_equal "spanish-unmarked", d.metadata["text_role"]
      assert_nil d.metadata["date"]
      assert_nil d.metadata["place"]
      assert_equal ["#{URN}:AGEO_Testaments_AGEO42:s1", "#{URN}:AGEO_Testaments_AGEO42:s2"], d.passages.map(&:urn)
    end

    def test_cordova_is_a_dated_placed_bilingual_work
      d = doc("cordova-arte")
      assert_equal "spa", d.language
      assert_equal "Arte en lengua zapoteca", d.title
      assert_equal "bilingual-work", d.metadata["text_role"]
      assert_equal "Juan de Córdova", d.metadata["author"]
      assert_equal({ "not_before" => 1578, "not_after" => 1578, "raw" => "title page: Año de. 1578" },
                   d.metadata["date"])
      assert_equal "México", d.metadata["place"]
      assert_equal "imprint", d.metadata["place_role"]
      assert_equal({ "value" => "arte", "raw" => "arte" }, d.metadata.dig("facets", "work_type"))
      assert_equal(%w[4 6 1v 2r], d.passages.map { |p| p.annotations["page"] })
      one_v = d.passages[2]
      assert_includes one_v.annotations["foreign"], { "lang" => "zap", "text" => "gönná" }
    end

    def test_aguero_is_a_zapotec_original_with_counted_repairs
      d = doc("aguero-miscelaneo")
      assert_equal "zap", d.language
      assert_equal "zapotec-original", d.metadata["text_role"]
      assert_equal 6, d.metadata["markup_repairs"]
      assert_equal 1666, d.metadata.dig("date", "not_before")
      assert_equal(%w[1 3 4 345 362 363 394 395], d.passages.map { |p| p.annotations["page"] })
    end

    def test_levanto_catechism_pages_carry_their_language_mix
      d = doc("levanto-cathecismo")
      assert_equal "spa", d.language
      assert_equal 1766, d.metadata.dig("date", "not_before")
      assert_equal "Puebla de los Ángeles", d.metadata["place"]
      assert_equal({ "spa" => 181, "zap" => 93 }, d.passages.last.annotations["languages"])
    end

    def test_the_date_rides_the_structured_metadata_dates_lane
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["ticha"]
    end

    def test_manifest_records_the_repository_license_verbatim
      manifest = Nabu::Adapters::Ticha.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "License: cc-by-sa-4.0"
      assert_includes manifest.license, "Creative Commons Attribution Share Alike 4.0"
      assert_includes File.read(File.join(FIXTURES, "license.txt")), "cc-by-sa-4.0"
    end

    def test_registry_row_is_ready_unwired_and_manual_on_the_americas_axis
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["ticha"]
      refute_nil entry
      refute entry.wired
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "americas"
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "ticha", name: "Ticha", adapter_class: "Nabu::Adapters::Ticha",
                                          license_class: "attribution")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 9, first.added
      assert_equal 31, db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 9, second.skipped
      assert_equal 31, db[:passages].count
      assert_equal [1], db[:passages].distinct.select_map(:revision)
    ensure
      db&.disconnect
    end

    # -- fetch (local git only, no network) -------------------------------------

    def test_fetch_clones_the_repo_and_discover_finds_it
      Dir.mktmpdir("nabu-ticha-fetch") do |root|
        upstream = File.join(root, "upstream")
        FileUtils.mkdir_p(upstream)
        FileUtils.cp_r(File.join(FIXTURES, "Te744"), upstream)
        FileUtils.cp(File.join(FIXTURES, "places.json"), upstream)
        git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
        Nabu::Shell.run("git", "init", "-q", upstream)
        git.call("add", ".")
        git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")

        adapter = Nabu::Adapters::Ticha.new
        adapter.define_singleton_method(:repo_url) { upstream }
        work = File.join(root, "canonical")
        report = adapter.fetch(work)
        assert_match(/\A[0-9a-f]{40}\z/, report.sha)
        assert_equal ["#{URN}:Te744"], adapter.discover(work).map(&:id)
      end
    end
  end
end
