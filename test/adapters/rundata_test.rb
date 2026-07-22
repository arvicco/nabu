# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "json"
require "tmpdir"

# Rundata adapter tests (P40-6): the five-lane sibling design over the SRDB
# SQLite artifact (schema-preserving trim of the real 45 MB rundata.info
# file), the Django-slugify urn mint, the dating-driven Proto-Norse
# language decision (N KJ101), the odbl license class, and the WebMock'd
# page-scrape fetch with never-delete retention. Includes the shared
# AdapterConformance suite; the JSON API fixtures beside the trim document
# the expected field values.
class RundataTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("rundata")
  TRIM = File.join(FIXTURES, "runes-trim.sqlite3")

  # All four inscriptions carry run/fvn/rsv/eng; U 344 and Ög 136 add swe.
  ALL_URNS = %w[
    urn:nabu:rundata:dr-42
    urn:nabu:rundata:dr-42-eng
    urn:nabu:rundata:dr-42-fvn
    urn:nabu:rundata:dr-42-rsv
    urn:nabu:rundata:n-kj101
    urn:nabu:rundata:n-kj101-eng
    urn:nabu:rundata:n-kj101-fvn
    urn:nabu:rundata:n-kj101-rsv
    urn:nabu:rundata:og-136
    urn:nabu:rundata:og-136-eng
    urn:nabu:rundata:og-136-fvn
    urn:nabu:rundata:og-136-rsv
    urn:nabu:rundata:og-136-swe
    urn:nabu:rundata:u-344
    urn:nabu:rundata:u-344-eng
    urn:nabu:rundata:u-344-fvn
    urn:nabu:rundata:u-344-rsv
    urn:nabu:rundata:u-344-swe
  ].freeze

  ORIGINAL_URNS = ALL_URNS.reject { |urn| urn.end_with?("-eng", "-swe") }.freeze

  def conformance_adapter
    # translations: true — the registry row's posture; the -eng/-swe
    # siblings must pass conformance too.
    Nabu::Adapters::Rundata.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "rundata"
  end

  # A run-less inscription mints a metadata-only bare document (marker-
  # driven, the ogham precedent).
  def conformance_metadata_only?(document)
    document.metadata["kind"] == "metadata_only"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_mints_the_odbl_class_with_the_verbatim_grant_and_caveat
    manifest = Nabu::Adapters::Rundata.manifest
    assert_equal "rundata", manifest.id
    assert_equal "odbl", manifest.license_class
    assert_match(/Open Database License/, manifest.license, "the Uppsala grant rides verbatim")
    assert_match(/Database Contents License/, manifest.license)
    assert_match(/based on the Scandinavian Runic-text Database/, manifest.license,
                 "the ODbL-required attribution statement lives in the credit line")
    assert_match(/re-confirm before enabling/, manifest.license, "the D40-c caveat is carried")
    assert_equal "https://rundata.info/", manifest.upstream_url
    assert_equal "rundata-sqlite", manifest.parser_family
  end

  def test_remote_probe_heads_the_app_page_against_the_fetch_state
    targets = Nabu::Adapters::Rundata.http_probe_targets
    assert_equal 1, targets.size
    assert_equal "https://rundata.info/", targets.first.zip_url
    assert_equal ".rundata-fetch.json", targets.first.state_file
    assert_nil targets.first.metadata_url, "no machine license endpoint — the grant is Uppsala's page"
  end

  # --- identity ---------------------------------------------------------------

  def test_slug_for_agrees_with_rundata_nets_canonical_slugs
    # Pinned against the canonical_slug field of the JSON API fixtures.
    %w[U_344 DR_42 Og_136 N_KJ101].each do |name|
      record = JSON.parse(File.read(File.join(FIXTURES, "#{name}.json")))
      assert_equal record.fetch("canonical_slug"),
                   Nabu::Adapters::Rundata.slug_for(record.fetch("signature")),
                   "slug_for(#{record.fetch('signature').inspect}) must match upstream"
    end
  end

  # --- language honesty -------------------------------------------------------

  def test_language_for_the_dating_period_codes
    assert_equal "non", Nabu::Adapters::Rundata.language_for("V"), "Viking Age"
    assert_equal "non", Nabu::Adapters::Rundata.language_for("V Jelling")
    assert_equal "non", Nabu::Adapters::Rundata.language_for("M"), "medieval"
    assert_equal "non", Nabu::Adapters::Rundata.language_for(""), "undated stays attested-default"
    assert_equal "non", Nabu::Adapters::Rundata.language_for("U?"),
                 "uncertain urnordisk stays the conservative attested default"
    assert_equal "gmq-pro", Nabu::Adapters::Rundata.language_for("U 650-700 (Grønvik)"),
                 "urnordisk (Proto-Norse) — the Wiktionary etymology code, no ISO code exists"
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_inscription_lane_sorted
    refs = conformance_adapter.discover(FIXTURES).to_a
    assert_equal ALL_URNS, refs.map(&:id), "census pinned: 4 inscriptions, 18 lane documents"
  end

  def test_discover_without_translations_flag_mints_original_lanes_only
    refs = Nabu::Adapters::Rundata.new.discover(FIXTURES).to_a
    assert_equal ORIGINAL_URNS, refs.map(&:id),
                 "eng/swe are parallel translations — registry translations: true opt-in"
  end

  def test_discover_yields_nothing_before_the_first_fetch
    Dir.mktmpdir do |dir|
      assert_empty conformance_adapter.discover(dir).to_a
    end
  end

  def test_discovery_skips_are_clean
    skips = conformance_adapter.discovery_skips(FIXTURES)
    assert_equal 0, skips.skipped_by_rule
    assert skips.clean?
  end

  # --- parse ------------------------------------------------------------------

  def parse_urn(urn, adapter: conformance_adapter, workdir: FIXTURES)
    ref = adapter.discover(workdir).find { |r| r.id == urn }
    refute_nil ref, "no ref for #{urn}"
    adapter.parse(ref)
  end

  def test_u344_transliteration_is_the_bare_urn_byte_pinned
    document = parse_urn("urn:nabu:rundata:u-344")
    assert_equal "non", document.language
    assert_equal "U 344", document.title
    assert_equal 1, document.size
    passage = document.first
    assert_equal "urn:nabu:rundata:u-344:1", passage.urn
    assert_equal "in ulfr hafiR o| |onklati ' þru kialt| |takat þit uas fursta þis " \
                 "tusti ka-t ' þ(a) ---- (þ)urktil ' þa kalt knutr",
                 passage.text,
                 "the transliteration notation (|, ', (a), ----, -) IS content — byte-verbatim NFC"
    assert passage.text.unicode_normalized?(:nfc)
  end

  def test_u344_english_translation_sibling_byte_pinned
    document = parse_urn("urn:nabu:rundata:u-344-eng")
    assert_equal "eng", document.language
    assert_equal "U 344 — English translation", document.title
    assert_equal "translation", document.metadata.fetch("kind")
    assert_equal "eng", document.metadata.fetch("lane")
    assert_equal "And Ulfr has taken three payments in England. That was the first that " \
                 "Tosti paid. Then Þorketill paid. Then Knútr paid.",
                 document.first.text
  end

  def test_u344_stone_metadata_rides_the_primary_document
    metadata = parse_urn("urn:nabu:rundata:u-344").metadata
    assert_equal "U 344", metadata.fetch("signum")
    assert_equal "V", metadata.fetch("dating")
    assert_equal 725, metadata.fetch("year_from")
    assert_equal 1100, metadata.fetch("year_to")
    assert_equal "Yttergärde", metadata.fetch("found_location")
    assert_equal "Orkesta sn", metadata.fetch("parish")
    assert_equal "Åsmund (A)", metadata.fetch("carver")
    assert_equal "Pr 3", metadata.fetch("style"), "the upstream NBSP is data"
    assert_equal "granit", metadata.fetch("material")
    assert_equal "stone", metadata.fetch("material_type")
    assert_equal "runsten", metadata.fetch("objectInfo")
    # BOTH WGS84 pairs, metadata-only (the EDH coordinates decision).
    assert_in_delta 59.604644, metadata.dig("coordinates", "latitude")
    assert_in_delta 18.109098, metadata.dig("coordinates", "longitude")
    assert_in_delta 59.604637, metadata.dig("present_coordinates", "latitude")
    assert_in_delta 18.109983, metadata.dig("present_coordinates", "longitude")
    refute metadata.key?("lost"), "false booleans mint no key"
    refute metadata.key?("aliases"), "U 344 has no alias signa"
  end

  def test_sibling_documents_carry_light_metadata_only
    metadata = parse_urn("urn:nabu:rundata:u-344-fvn").metadata
    assert_equal({ "kind" => "normalization", "lane" => "fvn", "signum" => "U 344" }, metadata)
  end

  def test_n_kj101_proto_norse_language_decision_pinned
    document = parse_urn("urn:nabu:rundata:n-kj101")
    assert_equal "gmq-pro", document.language,
                 "Eggja is dated U 650-700 (urnordisk) — Proto-Norse, honestly tagged"
    assert_equal "U 650-700 (Grønvik)", document.metadata.fetch("dating")
    assert document.first.text.start_with?("§A (m)in wArb nAseu wilR"),
           "side markers and uncertain-rune parentheses verbatim"
    assert_equal "gmq-pro", parse_urn("urn:nabu:rundata:n-kj101-fvn").language,
                 "the normalisation lanes follow the inscription's dated language"
    assert_equal "eng", parse_urn("urn:nabu:rundata:n-kj101-eng").language
    refute metadata_missing_present_coordinates_minted?
  end

  def metadata_missing_present_coordinates_minted?
    # N KJ101's present pair is upstream's 0/0 unknown filler — no key.
    parse_urn("urn:nabu:rundata:n-kj101").metadata.key?("present_coordinates")
  end

  def test_no_runic_unicode_anywhere
    adapter = conformance_adapter
    adapter.discover(FIXTURES).each do |ref|
      document = adapter.parse(ref)
      document.each do |passage|
        refute passage.text.match?(/[ᚠ-᛿]/),
               "#{passage.urn}: the SRDB stores Latin transliteration only — " \
               "runic codepoints must never be invented"
      end
    end
  end

  def test_a_run_less_inscription_mints_a_metadata_only_bare_document
    Dir.mktmpdir do |dir|
      doctored = File.join(dir, "runes-doctored.sqlite3")
      FileUtils.cp(TRIM, doctored)
      db = SQLite3::Database.new(doctored)
      db.execute("DELETE FROM transliterated_text WHERE signature_id = 1997")
      db.close
      adapter = conformance_adapter
      refs = adapter.discover(dir).to_a
      bare = refs.find { |r| r.id == "urn:nabu:rundata:u-344" }
      assert_equal "metadata_only", bare.metadata["kind"]
      assert_includes refs.map(&:id), "urn:nabu:rundata:u-344-fvn",
                      "the other lanes still ride as siblings"
      document = adapter.parse(bare)
      assert document.empty?, "catalogued, zero passages, never quarantined"
      assert_equal "metadata_only", document.metadata.fetch("kind")
      assert_equal "Åsmund (A)", document.metadata.fetch("carver"), "the stone metadata survives"
    end
  end

  # --- fetch (WebMock'd page scrape + never-delete retention) -----------------

  PAGE_URL = Nabu::Adapters::Rundata::PAGE_URL

  def stub_page_and_artifact(hash, body: File.binread(TRIM))
    stub_request(:get, PAGE_URL).to_return(
      status: 200,
      body: "<html><script>const DB_URL = \"/static/runes/runes.#{hash}.sqlite3\";</script></html>"
    )
    stub_request(:get, "#{PAGE_URL}static/runes/runes.#{hash}.sqlite3")
      .to_return(status: 200, body: body, headers: { "Last-Modified" => "Sat, 12 Jul 2026 00:00:00 GMT" })
  end

  def test_fetch_extracts_the_hashed_artifact_url_and_lands_it
    stub_page_and_artifact("abc123def456")
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::Rundata.new.fetch(dir)
      target = File.join(dir, "runes.abc123def456.sqlite3")
      assert File.file?(target)
      assert_equal Digest::SHA256.file(TRIM).hexdigest, report.sha
      assert_match(/runes\.abc123def456\.sqlite3/, report.notes)
      assert_match(/4 inscriptions/, report.notes, "the honest per-artifact census")
      state = JSON.parse(File.read(File.join(dir, ".rundata-fetch.json")))
      assert_equal "runes.abc123def456.sqlite3", state.fetch("current")
      assert_equal report.sha, state.fetch("sha256")
      assert_equal "Sat, 12 Jul 2026 00:00:00 GMT", state.fetch("last_modified")
    end
  end

  def test_a_new_hash_keeps_the_old_artifact_and_repoints_current
    Dir.mktmpdir do |dir|
      stub_page_and_artifact("aaaa11")
      Nabu::Adapters::Rundata.new.fetch(dir)
      WebMock.reset!
      stub_page_and_artifact("bbbb22")
      report = Nabu::Adapters::Rundata.new.fetch(dir)
      assert File.file?(File.join(dir, "runes.aaaa11.sqlite3")),
             "the previous artifact is RETAINED — the house never-delete posture"
      assert File.file?(File.join(dir, "runes.bbbb22.sqlite3"))
      assert_match(/retained 1 previous artifact/, report.notes)
      state = JSON.parse(File.read(File.join(dir, ".rundata-fetch.json")))
      assert_equal "runes.bbbb22.sqlite3", state.fetch("current")
      # discover follows the state pointer, not the leftover file.
      refs = Nabu::Adapters::Rundata.new.discover(dir).to_a
      assert_equal File.join(dir, "runes.bbbb22.sqlite3"), refs.first.path
    end
  end

  def test_refetching_the_same_hash_downloads_nothing
    Dir.mktmpdir do |dir|
      stub_page_and_artifact("cccc33")
      Nabu::Adapters::Rundata.new.fetch(dir)
      WebMock.reset!
      stub_request(:get, PAGE_URL).to_return(
        status: 200, body: "\"/static/runes/runes.cccc33.sqlite3\""
      )
      report = Nabu::Adapters::Rundata.new.fetch(dir)
      assert_match(/already current/, report.notes)
      assert_equal Digest::SHA256.file(TRIM).hexdigest, report.sha
    end
  end

  def test_fetch_fails_loudly_when_the_page_carries_no_artifact_reference
    stub_request(:get, PAGE_URL).to_return(status: 200, body: "<html>a redesign</html>")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Rundata.new.fetch(dir) }
      assert_match(/no runes\.<hash>\.sqlite3 reference/, error.message)
    end
  end

  def test_a_corrupt_download_never_lands_under_the_canonical_name
    stub_page_and_artifact("dddd44", body: "not a database")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Rundata.new.fetch(dir) }
      assert_match(/not a readable SRDB database/, error.message)
      assert_empty Dir.glob(File.join(dir, "runes*")), "no artifact, no .part leftovers"
    end
  end
end
