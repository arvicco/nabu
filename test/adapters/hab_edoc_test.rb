# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "support/adapter_conformance"
require "tmpdir"

module Adapters
  # Nabu::Adapters::HabEdoc — the Herzog August Bibliothek's digital
  # editions (diglib.hab.de/edoc/), mirrored as upstream's own tree:
  # <id>/mets.xml + the transcripts the METS lists. The fixture tree pins
  # one transcript per licence basis — Hans Sachs (the TEI's own CC BY
  # 4.0), Sibylla Schwarz (the TEI's CC0 → open override), Conring (the
  # site default), a Lüne letter (CC BY-SA 3.0 DE; the file-name language
  # letter) — and one specimen per rejected grain: a transcript-less
  # Theatrum record (ed000020), the repertory whose METS lists a file it
  # does not serve (ed000132), the Arndt test conversion (ed000239).
  class HabEdocTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("hab-edoc")
    ADAPTER = Nabu::Adapters::HabEdoc
    METS = %r{\Ahttps://diglib\.hab\.de/edoc/ed\d{6}/mets\.xml\z}
    # Conring's transcription div, which upstream leaves without an ADMID
    # (the tests below give it one in a scratch copy).
    TRANSCRIPT_DIV = 'ID="drucke_ed000226_tei_transcript1"'

    def conformance_adapter = ADAPTER.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "hab-edoc"

    def documents
      @documents ||= ADAPTER.new.discover(FIXTURES).to_h { |ref| [ref.id, ADAPTER.new.parse(ref)] }
    end

    # --- manifest + registry ---------------------------------------------------

    def test_manifest_names_the_per_transcript_licence_law
      manifest = ADAPTER.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "frei, bevorzugt unter einer CC BY-SA Lizenz"
      assert_includes manifest.license, "https://www.hab.de/digitale-editionen/"
      assert_equal "hab-edoc-tei", manifest.parser_family
      assert_empty ADAPTER.materialized_paths, "the mirror is upstream's own tree (+ the fetch state file)"
    end

    def test_registry_row_is_wired_and_manual
      entry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))["hab-edoc"]
      refute_nil entry
      assert_equal ADAPTER, entry.adapter_class
      assert entry.wired, "wired since the verified first sync (472 transcripts)"
      assert_equal "manual", entry.sync_policy
    end

    # --- discovery ---------------------------------------------------------------

    def test_discovers_one_document_per_held_transcript
      assert_equal %w[urn:nabu:hab-edoc:ed000226 urn:nabu:hab-edoc:ed000238
                      urn:nabu:hab-edoc:ed000248:Brief001-D urn:nabu:hab-edoc:ed000278],
                   ADAPTER.new.discover(FIXTURES).map(&:id)
    end

    def test_urn_tokens_cut_the_transcript_stem
      assert_equal "urn:nabu:hab-edoc:ed000238", ADAPTER.urn("ed000238", "tei-transcript.xml")
      assert_equal "urn:nabu:hab-edoc:ed000278", ADAPTER.urn("ed000278", "texts/tei-transcription.xml")
      assert_equal "urn:nabu:hab-edoc:ed000145:pnr", ADAPTER.urn("ed000145", "tei-transcript-pnr.xml")
      assert_equal "urn:nabu:hab-edoc:ed000267:Augsburg_1530",
                   ADAPTER.urn("ed000267", "texts/tei-transcript_Augsburg_1530.xml")
      assert_equal "urn:nabu:hab-edoc:ed000008:01-contents", ADAPTER.urn("ed000008", "tei-transcript_01-contents.xml")
    end

    def test_rejected_grains_are_skipped_by_rule_with_their_notes
      skips = ADAPTER.new.discovery_skips(FIXTURES)
      assert_equal 0, skips.unrecognized, skips.notes.join("\n")
      assert_equal 4, skips.skipped_by_rule, "ed000020 (1) + ed000132 (1 listed) + ed000239 (2 listed)"
      notes = skips.notes.join("\n")
      assert_match(/ed000020: no TEI transcript in the edition's METS/, notes)
      assert_match(/ed000132: held back .*serves no such file \(404\)/, notes)
      assert_match(/ed000239: held back \(2 transcript\(s\)\) .*Arndt-Projekt Test2/, notes)
    end

    def test_a_listed_file_upstream_does_not_serve_is_skipped_only_when_the_fetch_recorded_it
      with_copy("ed000238") do |work|
        FileUtils.rm(File.join(work, "ed000238", "tei-transcript.xml"))
        skips = ADAPTER.new.discovery_skips(work)
        assert_equal 1, skips.unrecognized
        assert_match(%r{ed000238/tei-transcript\.xml: listed in the METS but not held — a fetch hole},
                     skips.notes.first)

        File.write(File.join(work, Nabu::HabEdocFetch::STATE_FILE),
                   JSON.generate("missing" => { "ed000238" => ["tei-transcript.xml"] }))
        skips = ADAPTER.new.discovery_skips(work)
        assert_equal [0, 1], [skips.unrecognized, skips.skipped_by_rule]
        assert_match(/not served upstream \(404\)/, skips.notes.first)
        assert_empty ADAPTER.new.discover(work).to_a
      end
    end

    def test_an_uncensused_edition_with_transcripts_is_unrecognized
      with_copy("ed000238") do |work|
        FileUtils.mv(File.join(work, "ed000238"), File.join(work, "ed000999"))
        skips = ADAPTER.new.discovery_skips(work)
        assert_equal 1, skips.unrecognized
        assert_match(/ed000999: 1 transcript\(s\) listed, but the edition is not in HabEdoc::EDITIONS/,
                     skips.notes.first)
      end
    end

    def test_a_restricted_mets_statement_is_skipped_by_rule
      with_copy("ed000226") do |work|
        mets = File.join(work, "ed000226", "mets.xml")
        File.write(mets, File.read(mets).sub(TRANSCRIPT_DIV,
                                             "#{TRANSCRIPT_DIV} ADMID=\"rmd_edoc_ed000226_restricted\""))
        skips = ADAPTER.new.discovery_skips(work)
        assert_equal 1, skips.skipped_by_rule, skips.notes.join("\n")
        assert_match(/METS rights statement is "rights restricted"/, skips.notes.first)
        assert_empty ADAPTER.new.discover(work).to_a
      end
    end

    # --- the licence law -----------------------------------------------------------

    def test_the_transcripts_own_licence_wins_and_cc0_overrides_to_open
      sachs = documents.fetch("urn:nabu:hab-edoc:ed000238")
      assert_nil sachs.license_override
      assert_equal "http://creativecommons.org/licenses/by/4.0/", sachs.metadata["license"]
      assert_equal "the transcript's TEI licence", sachs.metadata["license_basis"]
      schwarz = documents.fetch("urn:nabu:hab-edoc:ed000278")
      assert_equal "open", schwarz.license_override, "the TEI's CC0 beats the METS label CC BY-SA 4.0"
    end

    def test_a_transcript_without_a_statement_rides_the_site_default
      conring = documents.fetch("urn:nabu:hab-edoc:ed000226")
      assert_nil conring.license_override
      assert_equal "site default", conring.metadata["license_basis"]
      assert_includes conring.metadata["license"], "bevorzugt unter einer CC BY-SA Lizenz"
    end

    def test_the_edition_mets_statement_is_the_middle_rung
      with_copy("ed000226") do |work|
        mets = File.join(work, "ed000226", "mets.xml")
        File.write(mets, File.read(mets).sub(TRANSCRIPT_DIV, "#{TRANSCRIPT_DIV} ADMID=\"rmd_edoc_ed000226_CC\""))
        ref = ADAPTER.new.discover(work).first
        assert_equal "the edition's METS rights statement", ref.metadata["license_basis"]
        assert_equal "CC BY-SA 3.0", ref.metadata["license"]
      end
    end

    # --- parse: languages, mined axes -------------------------------------------------

    def test_languages_come_from_the_edition_table_and_its_file_rules
      assert_equal %w[lat de gml de], documents.values.map(&:language)
      assert_equal "lat", ADAPTER.language("ed000248", "texts/Brief002-L_tei-transcript.xml")
      assert_equal "lat", ADAPTER.language("ed000248", "texts/Brief005-LD_tei-transcript.xml")
      assert_equal "gml", ADAPTER.language("ed000248", "texts/Brief010-DL_tei-transcript.xml")
      assert_equal "de", ADAPTER.language("ed000145", "tei-transcript-nul.xml")
      assert_equal "it", ADAPTER.language("ed000145", "tei-transcript-pnr.xml")
      assert_equal "grc", ADAPTER.language("ed000266", "texts/tei-transcript_print_grc.xml")
    end

    def test_the_print_yields_author_printer_place_and_an_edition_class_date
      meta = documents.fetch("urn:nabu:hab-edoc:ed000238").metadata
      assert_equal "Hans Sachs", meta["author"]
      assert_equal "Georg Erlinger", meta["printer"]
      assert_equal "Nürnberg", meta["place"]
      assert_equal({ "not_before" => 1523, "not_after" => 1523, "raw" => "1523", "basis" => "imprint",
                     "class" => "edition" }, meta["date"])
      assert_equal "ed000238", meta["edition"]
      assert_equal "https://diglib.hab.de/edoc/ed000238/start.htm", meta["start_url"]
      assert_match(/Hrsg\. und bearbeitet von Charlotte Hartmann/, meta["edition_title"])
    end

    def test_the_prose_bibl_print_is_dated_and_placed_too
      meta = documents.fetch("urn:nabu:hab-edoc:ed000226").metadata
      assert_equal "Conring, Hermann", meta["author"]
      assert_equal "Helmstedt", meta["place"]
      assert_equal 1708, meta.dig("date", "not_before")
      assert_equal "edition", meta.dig("date", "class")
    end

    def test_the_undated_letter_mints_no_date_and_keeps_its_correspondents
      letter = documents.fetch("urn:nabu:hab-edoc:ed000248:Brief001-D")
      assert_nil letter.metadata["date"]
      assert_nil letter.metadata["place"], "the holding convent (msIdentifier) is never the place"
      assert_equal "vermutlich Garnlieferant", letter.metadata["sender"]
      assert_equal "nds", letter.metadata["text_lang"], "upstream's own textLang rides metadata"
    end

    def test_the_edition_override_names_the_author_when_the_header_names_the_encoder
      assert_equal "Andreas de Escobar", ADAPTER::EDITIONS.fetch("ed000236")[:author]
      assert_equal "tei-transcript-mwb.xml", ADAPTER::EDITIONS.fetch("ed000223")[:whole]
      refute ADAPTER.wanted?("ed000223", "tei-transcript-mwb1.xml"), "a part of the whole transcript"
      assert ADAPTER.wanted?("ed000223", "tei-transcript-mwb.xml")
      refute ADAPTER.wanted?("ed000249", "texts/x_tei-transcript.xml"), "held back"
      refute ADAPTER.wanted?("ed000020", "tei-transcript.xml"), "not censused"
    end

    def test_kind_fold_covers_every_admitted_edition
      map = YAML.load_file(File.expand_path("../../config/kind_map.yml", __dir__)).dig("sources", "hab-edoc", "map")
      admitted = ADAPTER::EDITIONS.reject { |_id, entry| entry[:skip] }.keys
      assert_equal admitted.sort, map.keys.sort
    end

    # --- fetch (WebMock only) -------------------------------------------------------

    def test_fetch_walks_the_mets_ids_and_lands_the_admitted_transcripts
      stub_request(:get, METS).to_return(status: 404, body: "not found")
      stub_mets("ed000001", "ed000238")
      stub_mets("ed000002", "ed000020")
      transcript = stub_request(:get, "https://diglib.hab.de/edoc/ed000001/tei-transcript.xml")
                   .to_return(status: 200, body: fixture("ed000238/tei-transcript.xml"))
      Dir.mktmpdir do |dir|
        result = Nabu::HabEdocFetch.sync!(dir: dir, attic_dir: File.join(dir, ".attic"), delay: 0,
                                          last_known: 2, want: ->(id, _href) { id == "ed000001" })
        assert_equal 2, result.editions
        assert_equal 1, result.fetched
        assert_requested transcript, times: 1
        assert File.file?(File.join(dir, "ed000002", "mets.xml"))
        assert_equal fixture("ed000238/tei-transcript.xml"),
                     File.binread(File.join(dir, "ed000001", "tei-transcript.xml"))
        state = Nabu::HabEdocFetch.state(dir)
        assert_equal %w[ed000001 ed000002], state["editions"]

        again = Nabu::HabEdocFetch.sync!(dir: dir, attic_dir: File.join(dir, ".attic"), delay: 0,
                                         last_known: 2, want: ->(id, _href) { id == "ed000001" })
        assert_equal [0, 1], [again.fetched, again.cached], "file-grain resume"
        assert_requested transcript, times: 1
      end
    end

    def test_fetch_stops_after_the_miss_run_past_the_last_known_id
      stub_request(:get, METS).to_return(status: 404)
      stub_mets("ed000001", "ed000020")
      Dir.mktmpdir do |dir|
        Nabu::HabEdocFetch.sync!(dir: dir, attic_dir: File.join(dir, ".attic"), delay: 0, last_known: 1,
                                 want: ->(*) { false })
      end
      assert_requested :get, METS, times: 1 + Nabu::HabEdocFetch::MISS_RUN
    end

    def test_a_listed_transcript_that_404s_is_recorded_missing
      stub_request(:get, METS).to_return(status: 404)
      stub_mets("ed000001", "ed000132")
      stub_request(:get, "https://diglib.hab.de/edoc/ed000001/tei-transcript-pnr.xml").to_return(status: 404)
      Dir.mktmpdir do |dir|
        result = Nabu::HabEdocFetch.sync!(dir: dir, attic_dir: File.join(dir, ".attic"), delay: 0,
                                          last_known: 1, want: ->(*) { true })
        assert_equal({ "ed000001" => ["tei-transcript-pnr.xml"] }, result.missing)
        assert_equal({ "ed000001" => ["tei-transcript-pnr.xml"] }, Nabu::HabEdocFetch.state(dir)["missing"])
      end
    end

    def test_a_wall_aborts_the_fetch
      stub_request(:get, METS).to_return(status: 429)
      Dir.mktmpdir do |dir|
        error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(dir) }
        assert_match(/HTTP 429/, error.message)
        assert_empty Dir.children(dir), "the tree is untouched"
      end
    end

    def test_a_server_error_is_retried
      stub_request(:get, METS).to_return(status: 404)
      stub_request(:get, "https://diglib.hab.de/edoc/ed000001/mets.xml")
        .to_return({ status: 503 }, { status: 200, body: fixture("ed000020/mets.xml") })
      Dir.mktmpdir do |dir|
        result = Nabu::HabEdocFetch.sync!(dir: dir, attic_dir: File.join(dir, ".attic"), delay: 0,
                                          last_known: 1, want: ->(*) { false })
        assert_equal 1, result.editions
      end
    end

    def test_a_vanished_transcript_goes_to_the_attic
      stub_request(:get, METS).to_return(status: 404)
      stub_mets("ed000001", "ed000020")
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "ed000001"))
        File.write(File.join(dir, "ed000001", "tei-transcript.xml"), "<TEI/>")
        result = Nabu::HabEdocFetch.sync!(dir: dir, attic_dir: File.join(dir, ".attic"), delay: 0,
                                          last_known: 1, want: ->(*) { true })
        assert_equal ["ed000001/tei-transcript.xml"], result.atticked
        refute File.exist?(File.join(dir, "ed000001", "tei-transcript.xml"))
        assert File.file?(File.join(dir, ".attic", "ed000001", "tei-transcript.xml"))
      end
    end

    private

    def fixture(rel) = File.binread(File.join(FIXTURES, rel))

    def stub_mets(id, fixture_edition)
      stub_request(:get, "https://diglib.hab.de/edoc/#{id}/mets.xml")
        .to_return(status: 200, body: fixture("#{fixture_edition}/mets.xml"))
    end

    def with_copy(*editions)
      Dir.mktmpdir do |work|
        editions.each { |id| FileUtils.cp_r(File.join(FIXTURES, id), work) }
        yield work
      end
    end
  end
end
