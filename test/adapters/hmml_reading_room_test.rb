# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"
require "fileutils"

module Adapters
  # vHMML Reading Room — the weekly full dataset, the Syriac + Ethiopic
  # slice (CC BY 4.0 → attribution). Fixture: a trimmed re-pack of the
  # 2026-11-01 generation (test/fixtures/hmml-reading-room/README.md).
  class HmmlReadingRoomTest < Minitest::Test
    include AdapterConformance

    SLUG = "hmml-reading-room"
    FIXTURES = File.expand_path("../fixtures/hmml-reading-room", __dir__)
    ZIP = File.join(FIXTURES, "dataset", "vhmml_rr_fulldata.zip")
    URL = Nabu::Adapters::HmmlReadingRoom::DATASET_URL
    URN = "urn:nabu:hmml-reading-room"

    # One materialized workdir per run: the held zip + the slice the
    # adapter cuts from it (the fetch's second step, network-free).
    def self.workdir
      @workdir ||= begin
        dir = Dir.mktmpdir("hmml-rr")
        FileUtils.mkdir_p(File.join(dir, "dataset"))
        FileUtils.cp(ZIP, File.join(dir, "dataset"))
        Nabu::Adapters::HmmlReadingRoom.new.materialize!(dir)
        Minitest.after_run { FileUtils.rm_rf(dir) }
        dir
      end
    end

    def conformance_adapter = Nabu::Adapters::HmmlReadingRoom.new
    def conformance_workdir = self.class.workdir
    def conformance_expected_source_id = SLUG
    def conformance_metadata_only?(document) = document.metadata["text_layer"] == "none"

    def documents
      @documents ||= conformance_adapter.discover(conformance_workdir).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(id) = documents.find { |d| d.urn == "#{URN}:#{id}" } || flunk("#{id} missing")

    def test_manifest_is_attribution_with_the_terms_statement
      manifest = Nabu::Adapters::HmmlReadingRoom.manifest
      assert_equal "attribution", manifest.license_class
      assert_match(/CC BY 4\.0/, manifest.license)
    end

    def test_the_slice_takes_syriac_and_ethiopic_records_only
      ids = [2419, 56_720, 77_409, 123_348, 128_042, 134_100, 136_660, 200_191, 206_358, 207_131, 207_990,
             507_776, 511_958, 518_049, 539_548]
      assert_equal ids.map { |id| "#{URN}:#{id}" }, conformance_adapter.discover(conformance_workdir).map(&:id)
    end

    def test_census_counts_the_out_of_slice_records_and_the_empty_record
      census = JSON.parse(File.read(File.join(conformance_workdir, "scope", "census.json")))
      assert_equal 16, census["records"]
      assert_equal 15, census["taken"]
      assert_equal 1, census["out_of_slice"]
      assert_equal 1, census["empty_records"]
      assert_equal Digest::SHA256.file(ZIP).hexdigest, census["dataset_sha256"]

      skips = conformance_adapter.discovery_skips(conformance_workdir)
      assert_equal 2, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
    end

    def test_geez_record_with_incipit_passages
      d = doc(77_409)
      assert_equal "gez", d.language
      assert_equal "Universal chronicle (Ms. or. 40)", d.title
      assert_equal %W[#{URN}:77409:1.1 #{URN}:77409:1.2], d.passages.map(&:urn)
      p1 = d.passages.first
      assert_equal "gez", p1.language
      assert p1.text.start_with?("በስመ ፡ አብ ፡ ወወልድ"), p1.text
      assert_equal "Universal chronicle", p1.annotations["title"]
      assert_equal ["Ge'ez"], p1.annotations["languages"]
    end

    def test_record_metadata_is_mined
      m = doc(77_409).metadata
      assert_equal "https://w3id.org/vhmml/readingRoom/view/77409", m["purl"]
      assert_equal "45196", m["hmml_project_number"]
      assert_equal "Ms. or. 40", m["shelf_mark"]
      assert_equal "MANUSCRIPT", m["object_type"]
      assert_equal "Universitätsbibliothek Johann Christian Senckenberg", m.dig("repository", "name")
      assert_equal "Frankfurt am Main", m.dig("repository", "city")
      assert_equal "Germany", m.dig("repository", "country")
      assert_equal({ "not_before" => 1778, "not_after" => 1800, "raw" => "18th century" }, m["date"])
      assert_equal "Ethiopia", m["place"]
      assert_equal ["Historical works"], m["genres"]
      assert_equal({ "values" => ["Historical works"] }, m.dig("facets", "genre"))
      assert_equal "Fidäl", m["parts"].first["script"]
      assert_equal 2, m["parts"].first["contents"].size
    end

    def test_garshuni_incipits_are_arabic_in_syriac_script
      d = doc(56_720)
      assert_equal "ara-Syrc", d.language
      assert_equal 3, d.passages.size
      assert(d.passages.all? { |p| p.language == "ara-Syrc" })
      assert_nil d.metadata["place"], "no origin is catalogued — the holding place is not the origin"
      assert_equal({ "not_before" => 1800, "not_after" => 1900 }, d.metadata["date"])
    end

    def test_precise_and_native_dates_and_origin_city
      m = doc(123_348).metadata
      assert_equal({ "not_before" => 1716, "not_after" => 1716, "raw" => "18th century" }, m["date"])
      assert_equal "Diyarbakir", m["place"]
      part = m["parts"].first
      assert_equal 1716, part["date_precise_year"]
      assert_equal "2025 AG", part["native_date"]
      assert_equal "syc", doc(123_348).passages.first.language
    end

    def test_neo_aramaic_incipit_skips_by_rule_and_is_named
      d = doc(128_042)
      assert_equal %W[#{URN}:128042:1.1 #{URN}:128042:1.2], d.passages.map(&:urn)
      assert_equal [{ "item" => "1.3", "languages" => ["Neo-Aramaic"],
                      "reason" => "no lect mapping for the item's language" }],
                   d.metadata["skipped_incipits"]
    end

    def test_amharic_record_without_shelf_mark_titles_by_project_number
      d = doc(200_191)
      assert_equal "amh", d.language
      assert_equal "Fetḥa nagaśt (EMML 6555)", d.title
      assert_equal({ "not_before" => 1884, "not_after" => 1884 }, d.metadata["date"])
    end

    # The impossible part bounds upstream ships (all six records real,
    # 2026-11-01 generation; README "What is here"): a 5-digit year, a
    # lost digit, swapped/typo'd bounds. A broken pair is repaired from
    # the part's own evidence — its precise year, else the bounds that
    # fit its centuries band, the band filling the rest — and the raw
    # names the verbatim upstream bounds it replaced.
    REPAIRED = {
      206_358 => [1800, 1913, "18891–1913"], # beginDate 18891 (centuries 19, 20)
      207_131 => [1700, 1800, "17000–1800"], # beginDate 17000 (century 18)
      207_990 => [1750, 1900, "1750–150"],   # endDate 150 (centuries 18, 19)
      507_776 => [1954, 1954, "1954–1854"],  # endDate typo; precise year 1954
      511_958 => [1684, 1684, "1684–1594"],  # endDate typo; precise 1684 (native 1996 AG)
      539_548 => [1657, 1657, "16757–1657"]  # beginDate 16757; precise 1657
    }.freeze

    def test_impossible_part_bounds_are_repaired_from_the_parts_own_evidence
      REPAIRED.each do |id, (from, to, verbatim)|
        date = doc(id).metadata["date"]
        assert_equal [from, to], [date["not_before"], date["not_after"]], "record #{id}"
        assert_includes date["raw"], "upstream bounds #{verbatim} repaired", "record #{id}"
      end
    end

    # 136660's third part ships 1767–767 (precise 767) beside two sound
    # 1700–1800 parts: the part repairs to 1767–1800, the envelope holds.
    def test_a_broken_part_beside_sound_parts_repairs_inside_the_envelope
      date = doc(136_660).metadata["date"]
      assert_equal [1700, 1800], [date["not_before"], date["not_after"]]
      assert_includes date["raw"], "upstream bounds 1767–767 repaired"
      assert_equal 767, doc(136_660).metadata["parts"].last["end_date"], "the part keeps upstream verbatim"
    end

    def test_every_fixture_envelope_is_ordered_and_plausible
      documents.filter_map { |d| d.metadata["date"] }.each do |date|
        assert_operator date["not_before"], :<=, date["not_after"], date.inspect
        assert(date.values_at("not_before", "not_after").all? { |y| y.between?(-3000, 2100) }, date.inspect)
      end
    end

    # The copying place the cataloguer wrote only in the provenance note
    # ("Copied in Ankawa, fol. 3v"; no structured origin) is the
    # manuscript's origin; an institution phrase ("Copied in Dayr
    # al-Kuraym; colophon …") is not a town and mints nothing.
    def test_provenance_copying_town_is_the_origin_when_none_is_structured
      assert_equal "Ankawa", doc(134_100).metadata["place"]
      assert_nil doc(518_049).metadata["place"]
      assert_match(/\ACopied in Dayr al-Kuraym/, doc(518_049).metadata["provenance"])
    end

    # Upstream writes "uri": "" for the labels without an authority id;
    # genre_uris carries the ids only (the labels ride genres).
    def test_genre_uris_carry_no_empty_members
      m = doc(134_100).metadata
      assert_equal ["Liturgical books (Eastern Christian)", "Psalters"], m["genres"]
      assert_equal ["http://vocab.getty.edu/page/aat/300026477"], m["genre_uris"]
    end

    def test_record_without_incipits_is_metadata_only
      d = doc(2419)
      assert_empty d.passages
      assert_equal "none", d.metadata["text_layer"]
      assert_equal "syc", d.language
      assert_equal "Psalter (Codex 401)", d.title
    end

    def test_fetch_pins_the_weekly_generation_and_cuts_the_slice
      Dir.mktmpdir do |dir|
        stub_request(:get, URL).to_return(
          status: 200, body: File.binread(ZIP),
          headers: { "Last-Modified" => "Sun, 01 Nov 2026 07:05:49 GMT" }
        )
        report = conformance_adapter.fetch(dir)
        assert_equal Digest::SHA256.file(ZIP).hexdigest, report.sha
        state = JSON.parse(File.read(File.join(dir, "dataset", Nabu::FileFetch::STATE_FILE)))
        assert_equal "Sun, 01 Nov 2026 07:05:49 GMT", state["last_modified"]
        census = JSON.parse(File.read(File.join(dir, "scope", "census.json")))
        assert_equal "Sun, 01 Nov 2026 07:05:49 GMT", census["dataset_last_modified"]
        assert_equal 15, conformance_adapter.discover(dir).count
      end
    end

    def test_a_held_generation_answers_304_and_keeps_the_slice
      Dir.mktmpdir do |dir|
        stub_request(:get, URL).to_return(
          status: 200, body: File.binread(ZIP), headers: { "Last-Modified" => "Sun, 01 Nov 2026 07:05:49 GMT" }
        )
        conformance_adapter.fetch(dir)
        slice = File.join(dir, "scope", "records.jsonl")
        before = File.mtime(slice)
        stub_request(:get, URL).with(headers: { "If-Modified-Since" => "Sun, 01 Nov 2026 07:05:49 GMT" })
                               .to_return(status: 304)
        report = conformance_adapter.fetch(dir)
        assert_equal Digest::SHA256.file(ZIP).hexdigest, report.sha
        assert_equal before, File.mtime(slice), "an unchanged generation is not re-cut"
      end
    end

    def test_materialized_paths_declare_the_slice
      assert_equal ["scope"], Nabu::Adapters::HmmlReadingRoom.materialized_paths
    end
  end
end
