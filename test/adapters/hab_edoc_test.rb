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
  #
  # The editions whose texts keep their own file names (the per-edition
  # review) pin one file per new shape: a Hainhofer travel report (a
  # transcription fileGrp, a non-ASCII file name, the title's year),
  # Christian II's diary (the editors' <index> regests, a register
  # sourceDesc), a Bahnsen letter (a group-less file-name rule beside the
  # edition's apparatus — einleitung/editionsrichtlinien.xml, held, never
  # a document), Lessing's translation (the _ue file admitted, its _org
  # original held back by rule) and two FMG letters whose language is
  # read from their own description file (a third listed letter has no
  # description: skipped by rule).
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

    # The URNs minted before the per-edition review, unchanged by it.
    STANDARD_URNS = %w[urn:nabu:hab-edoc:ed000226 urn:nabu:hab-edoc:ed000238
                       urn:nabu:hab-edoc:ed000248:Brief001-D urn:nabu:hab-edoc:ed000278].freeze

    def test_discovers_one_document_per_held_transcript
      assert_equal %w[urn:nabu:hab-edoc:ed000146:abauzit_offenbarung_ue urn:nabu:hab-edoc:ed000226
                      urn:nabu:hab-edoc:ed000228:1621_11 urn:nabu:hab-edoc:ed000233:0001
                      urn:nabu:hab-edoc:ed000238 urn:nabu:hab-edoc:ed000248:Brief001-D
                      urn:nabu:hab-edoc:ed000249:h-fmg-rara-fmg-artot-de-padilla-d-001
                      urn:nabu:hab-edoc:ed000249:h-fmg-rara-fmg-bahr-mildenburg-a-001
                      urn:nabu:hab-edoc:ed000251:Munchen-1603 urn:nabu:hab-edoc:ed000278],
                   ADAPTER.new.discover(FIXTURES).map(&:id)
    end

    def test_the_review_leaves_every_standard_transcript_urn_unchanged
      ids = ADAPTER.new.discover(FIXTURES).map(&:id)
      assert_equal STANDARD_URNS, ids & STANDARD_URNS
      standard = ADAPTER.new.discover(FIXTURES).select { |ref| Nabu::Adapters::HabEdocMets.transcript_name?(ref.metadata["file"]) }
      assert_equal (STANDARD_URNS + %w[urn:nabu:hab-edoc:ed000249:h-fmg-rara-fmg-artot-de-padilla-d-001
                                       urn:nabu:hab-edoc:ed000249:h-fmg-rara-fmg-bahr-mildenburg-a-001]).sort,
                   standard.map(&:id).sort, "the WDB-named transcripts keep the stem-cut token"
    end

    def test_urn_tokens_cut_the_transcript_stem
      assert_equal "urn:nabu:hab-edoc:ed000238", ADAPTER.urn("ed000238", "tei-transcript.xml")
      assert_equal "urn:nabu:hab-edoc:ed000278", ADAPTER.urn("ed000278", "texts/tei-transcription.xml")
      assert_equal "urn:nabu:hab-edoc:ed000145:pnr", ADAPTER.urn("ed000145", "tei-transcript-pnr.xml")
      assert_equal "urn:nabu:hab-edoc:ed000267:Augsburg_1530",
                   ADAPTER.urn("ed000267", "texts/tei-transcript_Augsburg_1530.xml")
      assert_equal "urn:nabu:hab-edoc:ed000008:01-contents", ADAPTER.urn("ed000008", "tei-transcript_01-contents.xml")
    end

    def test_own_name_tokens_fold_accents_keep_directories_or_name_the_edition
      assert_equal "urn:nabu:hab-edoc:ed000251:Munchen-1603", ADAPTER.urn("ed000251", "texts/München 1603.xml")
      assert_equal "urn:nabu:hab-edoc:ed000251:Eichstatt-1611", ADAPTER.urn("ed000251", "texts/Eichstätt 1611.xml")
      assert_equal "urn:nabu:hab-edoc:ed000133:simpli_b1", ADAPTER.urn("ed000133", "simpli/transcript_b1.xml")
      assert_equal "urn:nabu:hab-edoc:ed000133:anhang", ADAPTER.urn("ed000133", "anhang/transcript.xml")
      assert_equal "urn:nabu:hab-edoc:ed000276", ADAPTER.urn("ed000276", "texts/Johannes Hartlieb.xml")
      assert_equal "urn:nabu:hab-edoc:ed000228:1621_11", ADAPTER.urn("ed000228", "1621_11.xml")
    end

    def test_rejected_grains_are_skipped_by_rule_with_their_notes
      skips = ADAPTER.new.discovery_skips(FIXTURES)
      assert_equal 0, skips.unrecognized, skips.notes.join("\n")
      assert_equal 6, skips.skipped_by_rule, "ed000020 (1) + ed000132 (1 listed) + ed000239 (2 listed) + " \
                                             "ed000146's _org original (1) + ed000249's description-less letter (1)"
      notes = skips.notes.join("\n")
      assert_match(/ed000020: no TEI transcript in the edition's METS/, notes)
      assert_match(/ed000132: held back .*serves no such file \(404\)/, notes)
      assert_match(/ed000239: held back \(2 transcript\(s\)\) .*Arndt-Projekt Test2/, notes)
      assert_match(/ed000146: 1 file\(s\) held back — the originals Lessing translated/, notes)
      assert_match(%r{ed000249/texts/h-fmg-rara-fmg-orgeni-a-002-1/.*: no description file listed}, notes)
    end

    def test_an_edition_held_back_after_review_is_skipped_with_its_reason
      with_copy("ed000020") do |work|
        FileUtils.mv(File.join(work, "ed000020"), File.join(work, "ed000257"))
        skips = ADAPTER.new.discovery_skips(work)
        assert_equal [0, 1], [skips.unrecognized, skips.skipped_by_rule]
        assert_match(/\Aed000257: held back — .*Latin pieces/, skips.notes.first)
      end
    end

    # --- the per-edition text rules ------------------------------------------------

    def test_an_editions_own_name_rule_selects_its_texts_never_its_apparatus
      bahnsen = Nabu::Adapters::HabEdocMets.read(File.join(FIXTURES, "ed000233", "mets.xml"))
      assert_includes bahnsen.xml_files, "einleitung/editionsrichtlinien.xml"
      assert_equal ["briefe/0001.xml"], bahnsen.transcripts(ADAPTER::EDITIONS.dig("ed000233", :texts)).map(&:href)
      assert_empty bahnsen.transcripts, "no WDB transcript name in the METS"
      assert File.file?(File.join(FIXTURES, "ed000233", "einleitung", "editionsrichtlinien.xml")),
             "the apparatus specimen is held in the tree"
      refute(ADAPTER.new.discover(FIXTURES).any? { |ref| ref.metadata["file"].start_with?("einleitung/") })
      lessing = Nabu::Adapters::HabEdocMets.read(File.join(FIXTURES, "ed000146", "mets.xml"))
      assert_equal ["abauzit_offenbarung_ue.xml"],
                   lessing.transcripts(ADAPTER::EDITIONS.dig("ed000146", :texts)).map(&:href)
      refute ADAPTER.wanted?("ed000146", "abauzit_offenbarung_org.xml"), "the original is held back"
      assert ADAPTER.wanted?("ed000146", "law_ermunterung.xml"), "upstream's METS ID names it the _ue file"
    end

    def test_holdings_add_each_letters_listed_description
      mets = Nabu::Adapters::HabEdocMets.read(File.join(FIXTURES, "ed000249", "mets.xml"))
      letters = %w[artot-de-padilla-d-001 bahr-mildenburg-a-001 orgeni-a-002-1].map do |name|
        "texts/h-fmg-rara-fmg-#{name}/h-fmg-rara-fmg-#{name}_tei-transcript.xml"
      end
      descriptions = letters.first(2).map { |href| href.sub("_tei-transcript.xml", "_tei-msDesc_fmg.xml") }
      assert_equal letters + descriptions, ADAPTER.holdings("ed000249", mets)
      hainhofer = Nabu::Adapters::HabEdocMets.read(File.join(FIXTURES, "ed000251", "mets.xml"))
      assert_equal ["texts/München 1603.xml"], ADAPTER.holdings("ed000251", hainhofer)
    end

    def test_a_letter_whose_description_is_not_held_is_a_hole_until_the_fetch_records_it
      description = "texts/h-fmg-rara-fmg-artot-de-padilla-d-001/" \
                    "h-fmg-rara-fmg-artot-de-padilla-d-001_tei-msDesc_fmg.xml"
      with_copy("ed000249") do |work|
        FileUtils.rm(File.join(work, "ed000249", description))
        skips = ADAPTER.new.discovery_skips(work)
        assert_equal 1, skips.unrecognized
        assert_match(/msDesc_fmg\.xml: listed in the METS but not held — a fetch hole/, skips.notes.first)
        File.write(File.join(work, Nabu::HabEdocFetch::STATE_FILE),
                   JSON.generate("missing" => { "ed000249" => [description] }))
        assert_equal 0, ADAPTER.new.discovery_skips(work).unrecognized
        assert_equal ["urn:nabu:hab-edoc:ed000249:h-fmg-rara-fmg-bahr-mildenburg-a-001"],
                     ADAPTER.new.discover(work).map(&:id)
      end
    end

    def test_a_description_without_a_usable_text_language_never_guesses
      description = "texts/h-fmg-rara-fmg-bahr-mildenburg-a-001/h-fmg-rara-fmg-bahr-mildenburg-a-001_tei-msDesc_fmg.xml"
      with_copy("ed000249") do |work|
        path = File.join(work, "ed000249", description)
        File.write(path, File.read(path).sub('<textLang mainLang="de">Deutsch</textLang>', ""))
        notes = ADAPTER.new.discovery_skips(work).notes.join("\n")
        assert_match(/bahr-mildenburg-a-001_tei-transcript\.xml: its description states no textLang/, notes)
        File.write(path, File.read(path).sub("</summary>", '</summary><textLang mainLang="xx">X</textLang>'))
        skips = ADAPTER.new.discovery_skips(work)
        assert_equal 1, skips.unrecognized
        assert_match(/unrecognized textLang "xx"/, skips.notes.join("\n"))
      end
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
      assert_equal %w[de lat de de de gml fr de de de], documents.values.map(&:language)
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
      refute ADAPTER.wanted?("ed000239", "texts/tei-transcript-1605.xml"), "held back"
      refute ADAPTER.wanted?("ed000020", "tei-transcript.xml"), "not censused"
    end

    # --- parse: the reviewed editions --------------------------------------------------

    def test_the_fmg_letter_reads_language_and_correspondents_from_its_description
      bahr = documents.fetch("urn:nabu:hab-edoc:ed000249:h-fmg-rara-fmg-bahr-mildenburg-a-001")
      assert_equal "de", bahr.language
      assert_equal "open", bahr.license_override, "the transcript's CC0"
      meta = bahr.metadata
      assert_equal "Anna v. Mildenburg", meta["sender"]
      assert_equal "Unbekannter Herr", meta["addressee"]
      assert_equal "Hamburg", meta["place"]
      assert_equal({ "not_before" => 1898, "not_after" => 1898, "raw" => "27.02.1898", "basis" => "correspDesc" },
                   meta["date"])
      assert_equal "Rara/FMG Bahr-Mildenburg,A.1", meta["shelfmark"]
      assert_match(/\ABrief von Anna Bahr-Mildenburg an einen unbekannten Herrn/, meta["letter_title"])
      assert_equal "de", meta["text_lang"]
      assert_equal "texts/h-fmg-rara-fmg-bahr-mildenburg-a-001/h-fmg-rara-fmg-bahr-mildenburg-a-001_tei-msDesc_fmg.xml",
                   meta["description"]
      artot = documents.fetch("urn:nabu:hab-edoc:ed000249:h-fmg-rara-fmg-artot-de-padilla-d-001")
      assert_equal "fr", artot.language
      assert artot.first.text.start_with?("Vendredi 6 heures Mon cher Pietsch"), artot.first.text
    end

    def test_the_diary_drops_the_editors_regests_and_dates_by_its_title
      diary = documents.fetch("urn:nabu:hab-edoc:ed000228:1621_11")
      refute_includes diary.first.text, "Verlegung des Arrests", "the <index> regest terms are the editors'"
      assert_equal(%w[p1r p1v p2r p2v], diary.map { |p| p.urn.split(":").last })
      meta = diary.metadata
      assert_equal "Christian II. von Anhalt-Bernburg", meta["author"]
      assert_equal({ "not_before" => 1621, "not_after" => 1621,
                     "raw" => "Tagebuch des Fürsten Christian II. von Anhalt-Bernburg: November 1621",
                     "basis" => "title" }, meta["date"])
      assert_nil meta["place"], "the register sourceDesc is never the imprint"
      assert_equal "https://creativecommons.org/licenses/by-sa/4.0/", meta["license"]
    end

    def test_the_letter_drops_the_editors_heading_and_dates_by_its_title
      letter = documents.fetch("urn:nabu:hab-edoc:ed000233:0001")
      assert_equal "urn:nabu:hab-edoc:ed000233:0001:p1r", letter.first.urn
      assert letter.first.text.start_with?("Amsterdam 1660 April 4."), letter.first.text
      assert_equal "Bahnsen, Benedikt", letter.metadata["author"]
      assert_equal 1660, letter.metadata.dig("date", "not_before")
      assert_equal "site default", letter.metadata["license_basis"]
    end

    def test_the_travel_report_and_the_translation
      report = documents.fetch("urn:nabu:hab-edoc:ed000251:Munchen-1603")
      assert_equal "texts/München 1603.xml", report.metadata["file"]
      assert_equal "Philipp Hainhofer", report.metadata["author"]
      assert_equal 1603, report.metadata.dig("date", "not_before")
      assert_equal "the transcript's TEI licence", report.metadata["license_basis"]
      assert_equal(%w[pfol127v pfol127ar], report.map { |p| p.urn.split(":").last })
      lessing = documents.fetch("urn:nabu:hab-edoc:ed000146:abauzit_offenbarung_ue")
      assert_equal "Lessing, Gotthold Ephraim", lessing.metadata["author"]
      assert_equal "Abauzit", lessing.metadata["header_author"]
      assert_equal({ "not_before" => 1784, "not_after" => 1784, "raw" => "1784", "basis" => "imprint",
                     "class" => "edition" }, lessing.metadata["date"])
    end

    def test_edition_drop_lists_remove_template_placeholders
      assert_equal %w[author header_author], ADAPTER::EDITIONS.dig("ed000271", :drop),
                   "Liber modorum's header author is the template's \"[Name des Autors]\""
      assert_equal %w[edition_title], ADAPTER::EDITIONS.dig("ed000235", :drop),
                   "the psalter's METS title is the template's \"Autor und Titel\""
      assert_equal %w[place], ADAPTER::EDITIONS.dig("ed000276", :drop), "Hartlieb's pubPlace is the holding library"
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

    def test_fetch_lands_an_editions_own_name_texts_and_letter_descriptions
      stub_request(:get, METS).to_return(status: 404)
      stub_mets("ed000249", "ed000249")
      stub_request(:get, %r{\Ahttps://diglib\.hab\.de/edoc/ed000249/texts/.+\.xml\z})
        .to_return(status: 200, body: "<TEI/>")
      Dir.mktmpdir do |dir|
        result = Nabu::HabEdocFetch.sync!(dir: dir, attic_dir: File.join(dir, ".attic"), delay: 0, last_known: 249,
                                          files: ->(id, mets) { ADAPTER.holdings(id, mets) },
                                          want: ->(id, href) { ADAPTER.wanted?(id, href) })
        assert_equal 5, result.fetched, "3 listed letters + the 2 descriptions the METS lists"
        held = Dir.glob("ed000249/texts/**/*.xml", base: dir)
        assert_equal 2, held.grep(/_tei-msDesc_fmg\.xml\z/).size
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
