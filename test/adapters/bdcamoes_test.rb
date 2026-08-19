# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::BdCamoes (P80-7): BDCamões Part I — the Corpus of
  # Portuguese Literary Documents (PORTULAN CLARIN, CC-BY; the download
  # click-through accepted on owner ruling №R-37, 2026-08-19). 127
  # one-work XML wrappers; document = one work (urn from a transliterated
  # slug of the upstream basename), passage = one paragraph/stanza (blank
  # -line blocks, then the newline+single-tab paragraph convention);
  # per-work YY: years feed MetadataDates :structured. Fixtures: three
  # real trimmed works pinning the drama/prose/poetry layout conventions
  # — see test/fixtures/bdcamoes/README.md.
  class BdcamoesTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("bdcamoes")

    def conformance_adapter
      Nabu::Adapters::BdCamoes.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "bdcamoes"
    end

    # -- registry -------------------------------------------------------------

    def test_registry_resolves_bdcamoes_unwired_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["bdcamoes"]
      refute_nil entry, "bdcamoes must be registered in config/sources.yml"
      refute entry.wired, "wired stays false until the first real sync is owner-verified"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "romance"
    end

    def test_manifest_records_the_click_through_provenance_and_part_ii_exclusion
      manifest = Nabu::Adapters::BdCamoes.manifest
      assert_match(/CC - BY/, manifest.license, "the record's licence field verbatim")
      assert_match(/№R-37/, manifest.license, "the click-through rides the recorded owner ruling")
      assert_match(/Part II/, manifest.license, "the Part II exclusion is stated, not implied")
      assert_equal "attribution", manifest.license_class
    end

    def test_bdcamoes_is_registered_for_structured_metadata_dates
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["bdcamoes"],
                   "per-work YY: years feed the timeline via the :structured shape"
    end

    # -- discovery ------------------------------------------------------------

    def test_discovers_the_three_works_with_transliterated_slug_urns
      refs = Nabu::Adapters::BdCamoes.new.discover(FIXTURES).to_a
      assert_equal %w[urn:nabu:bdcamoes:castilho-poesias
                      urn:nabu:bdcamoes:queiros-um-poeta-lirico
                      urn:nabu:bdcamoes:vicente-auto-barcado-inferno], refs.map(&:id),
                   "slugs transliterate the upstream basename (marks stripped, camel bounds " \
                   "hyphenated) — stable across NFC/NFD filesystems and both unzip paths"
      assert_equal "QueirósUmPoetaLírico.xml", refs[1].metadata["member"],
                   "the verbatim upstream basename rides as provenance"
    end

    def test_discovery_skips_recognizes_the_license_pdf_and_counts_strays
      skips = Nabu::Adapters::BdCamoes.new.discovery_skips(FIXTURES)
      assert_equal 3, skips.unrecognized,
                   "license.pdf is the zip's own recognized non-corpus member; the fixture " \
                   "rig's README.md, manifest.yml and fetch/ page are strays the census " \
                   "counts LOUDLY — exactly what it must do in a real workdir"
      assert_equal ["non-corpus file: README.md", "non-corpus file: fetch/licence-agree-page.html",
                    "non-corpus file: manifest.yml"], skips.notes
    end

    # -- parse: the three layout conventions ----------------------------------

    def test_parses_the_vicente_drama_with_tab_indented_verse_intact
      document = parse("urn:nabu:bdcamoes:vicente-auto-barcado-inferno")
      assert_equal "por", document.language
      assert_equal "Auto da Barca do Inferno", document.title
      assert_equal "Gil Vicente", document.metadata["author"]
      assert_equal "Drama", document.metadata["genre"]
      assert_equal({ "value" => "Drama" }, document.metadata["facets"]["genre"])
      assert_equal({ "not_before" => 1517, "not_after" => 1517, "raw" => "1517" },
                   document.metadata["date"])

      assert_equal 27, document.passages.size
      barca = document.passages.find { |passage| passage.text.include?("À barca, à barca, houlá!") }
      refute_nil barca, "the opening line of Cena I"
      assert_includes barca.text, "\n", "multi-tab continuation lines stay inside the speech passage"
      assert_equal "urn:nabu:bdcamoes:vicente-auto-barcado-inferno:1", document.passages.first.urn
    end

    def test_parses_the_queiros_tale_with_the_tab_paragraph_convention
      document = parse("urn:nabu:bdcamoes:queiros-um-poeta-lirico")
      assert_equal "UM POETA LÍRICO", document.title, "upstream's own casing, verbatim"
      assert_equal({ "not_before" => 1900, "not_after" => 1900, "raw" => "1900" },
                   document.metadata["date"])
      assert_equal 6, document.passages.size,
                   "no blank lines upstream — paragraphs are marked by newline + a single tab"
      assert document.passages.first.text.start_with?("Aqui está, simplesmente"),
             "each tab paragraph is one passage"
      assert_match(/In QUEIRÓS, Eça\. CONTOS/, document.metadata["edition"],
                   "the footer's edition citation rides metadata, never a passage")
    end

    def test_parses_the_castilho_poetry_with_stanza_grain_and_raw_only_year
      document = parse("urn:nabu:bdcamoes:castilho-poesias")
      assert_equal "Poesias", document.title
      assert_equal({ "raw" => "18??" }, document.metadata["date"],
                   "an unresolved YY mark claims no bounds — raw only, skipped honestly by the timeline")
      assert_equal 8, document.passages.size, "title line + 6 stanzas + trimmed stanza head"
      stanza = document.passages.find { |passage| passage.text.include?("quem livre de inquietação") }
      refute_nil stanza
      assert_equal 4, stanza.text.lines.size, "a stanza stays one passage — unindented verse " \
                                              "lines are never paragraph boundaries"
    end

    # -- the YY envelope (all six real shapes of the 2026-08-19 census) -------

    def test_year_envelope_covers_every_real_yy_shape
      envelope = ->(raw) { Nabu::Adapters::BdCamoes.year_envelope(raw) }
      assert_equal({ "not_before" => 1517, "not_after" => 1517, "raw" => "1517" }, envelope.call("1517"))
      assert_equal({ "not_before" => 1880, "not_after" => 1881, "raw" => "1880-1881" },
                   envelope.call("1880-1881"))
      assert_equal({ "not_before" => 1889, "not_after" => 1894, "raw" => "1889-1894" },
                   envelope.call("1889-1894"))
      assert_equal({ "not_before" => 1876, "not_after" => 1877, "raw" => "1876/77" },
                   envelope.call("1876/77"), "the split-year shape completes from the first year's century")
      assert_equal({ "raw" => "18??" }, envelope.call("18??"), "unresolved marks claim nothing")
      assert_equal({ "raw" => "19??" }, envelope.call("19??"))
      assert_nil envelope.call(nil)
    end

    # -- fetch ----------------------------------------------------------------

    def test_fetch_returns_a_fetch_report_with_the_zip_sha
      rig = Class.new do
        def prepare! = nil
        def doomed_paths = []
        def complete! = 7
        def cleanup! = nil
        def sha = "abc123"
      end.new
      adapter = Nabu::Adapters::BdCamoes.new(zip_fetch_factory: ->(**) { rig })
      report = Dir.mktmpdir { |dir| adapter.fetch(dir) }
      assert_instance_of Nabu::FetchReport, report
      assert_equal "abc123", report.sha
    end

    def test_fetch_rides_the_licence_agree_arm_with_the_recorded_grant
      captured = nil
      rig = Class.new do
        def prepare! = nil
        def doomed_paths = []
        def complete! = 0
        def cleanup! = nil
        def sha = "x"
      end.new
      adapter = Nabu::Adapters::BdCamoes.new(zip_fetch_factory: lambda { |**kwargs|
        captured = kwargs
        rig
      })
      Dir.mktmpdir { |dir| adapter.fetch(dir) }
      assert_equal Nabu::Adapters::BdCamoes::ARTIFACT_URL, captured[:url]
      assert_instance_of Nabu::LicenseAgreeFetch, captured[:http],
                         "the artifact GET is the agree dance — ZipFetch rides it as its connection"
      assert_equal "CC-BY", captured[:http].licence,
                   "the declared grant is the form's recorded licence value, never a guess"
    end

    def test_probe_is_liveness_only_against_the_record_page
      targets = Nabu::Adapters::BdCamoes.http_probe_targets
      assert_equal 1, targets.size
      assert targets.first.liveness_only,
             "the artifact URL is a POST — nothing to HEAD statelessly; the record page answers liveness"
      assert_equal :http_zip, Nabu::Adapters::BdCamoes.remote_probe_strategy
    end

    private

    def parse(urn)
      adapter = Nabu::Adapters::BdCamoes.new
      ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == urn }
      refute_nil ref, "#{urn} must be discovered"
      adapter.parse(ref)
    end
  end
end
