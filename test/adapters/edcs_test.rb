# frozen_string_literal: true

require "test_helper"
require "digest"
require "tmpdir"

# EDCS adapter tests: the SDAM cleaned dump of the Epigraphik-Datenbank
# Clauss-Slaby (Zenodo record 7072337, v2.0, 2022-09-12) — one JSON array
# streamed record by record, one document per inscription, the text-less
# and duplicate records skipped by rule, language by script, the axis
# fields mined into the house metadata shapes, and the WebMock'd streamed
# fetch with the frozen pins. Fixtures are records cut verbatim from the
# real dump (test/fixtures/edcs/README.md).
class EdcsTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("edcs")
  DUMP = File.join(FIXTURES, Nabu::Adapters::Edcs::FILENAME)

  URNS = %w[
    urn:nabu:edcs:24700151
    urn:nabu:edcs:24900077
    urn:nabu:edcs:09700347
    urn:nabu:edcs:65000225
    urn:nabu:edcs:34700317
    urn:nabu:edcs:69800124
    urn:nabu:edcs:82200035
    urn:nabu:edcs:13001449
    urn:nabu:edcs:31200870
    urn:nabu:edcs:09001312
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Edcs.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "edcs"
  end

  # text_normalized is minted from SDAM's interpretive cleaning (the
  # abbreviations expanded, the markup gone), stored verbatim in the
  # passage annotations — the documented derivation.
  def conformance_search_source(passage)
    Nabu::Adapters::Edcs.search_source(passage.text, passage.annotations)
  end

  def parse_urn(urn)
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "no ref for #{urn}"
    adapter.parse(ref)
  end

  # --- manifest + probe -------------------------------------------------------

  def test_manifest_names_the_deposit_both_credits_and_the_attribution_class
    manifest = Nabu::Adapters::Edcs.manifest
    assert_equal "edcs", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(/7072337/, manifest.license)
    assert_match(/Clauss/, manifest.license, "EDCS is credited")
    assert_match(/SDAM/, manifest.license, "the cleaning project is credited")
    assert_equal "https://zenodo.org/records/7072337", manifest.upstream_url
    assert_equal "edcs-json", manifest.parser_family
  end

  def test_remote_probe_heads_the_one_deposit_file
    targets = Nabu::Adapters::Edcs.http_probe_targets
    assert_equal 1, targets.size
    assert_equal Nabu::Adapters::Edcs::FILE_URL, targets.first.zip_url
    assert_equal Nabu::FileFetch::STATE_FILE, targets.first.state_file
    assert_nil targets.first.metadata_url
  end

  def test_registry_row_is_registered_wired_and_frozen
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["edcs"]
    refute_nil entry
    assert entry.wired, "wired after the verified first sync of 2026-11-28"
    assert_equal "frozen", entry.sync_policy
    assert_equal ["epigraphy"], entry.axes
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_text_bearing_record_in_file_order
    refs = conformance_adapter.discover(FIXTURES).to_a
    assert_equal URNS, refs.map(&:id)
    ref = refs.first
    slice = File.binread(DUMP, ref.metadata.fetch("length"), ref.metadata.fetch("offset"))
    assert_match(/\A\{"EDCS-ID":"EDCS-24700151"/, slice, "the ref locates its record's bytes")
  end

  def test_text_less_and_duplicate_records_are_skipped_by_rule
    ids = conformance_adapter.discover(FIXTURES).map(&:id)
    refute_includes ids, "urn:nabu:edcs:77400214", "no inscription key at all"
    refute_includes ids, "urn:nabu:edcs:28000525", "inscription \"?\" carries no letter"
    assert_equal 1, ids.count("urn:nabu:edcs:69800124"), "the dump's second identical copy is dropped"
  end

  def test_discovery_skips_count_every_rejected_record
    skips = conformance_adapter.discovery_skips(FIXTURES)
    assert_equal 3, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert skips.clean?
    assert_equal ["1 record without an inscription", "1 inscription without a letter (EDCS \"?\": text not given)",
                  "1 repeated copy of an earlier record"], skips.notes
  end

  def test_a_workdir_without_the_dump_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty conformance_adapter.discover(dir).to_a
      assert_equal 0, conformance_adapter.discovery_skips(dir).skipped_by_rule
    end
  end

  # --- parse: text, layers, language ------------------------------------------

  def test_the_raw_edcs_text_is_the_passage_and_the_cleanings_ride_as_annotations
    document = parse_urn("urn:nabu:edcs:24700151")
    assert_equal 1, document.size
    passage = document.first
    assert_equal "urn:nabu:edcs:24700151:1", passage.urn
    assert_equal "Δέκιος Λείβιος (Ζ)εῦξις // D(ecimi) Leivei D(ecimi) Leivei salve", passage.text
    assert_equal "Δέκιος Λείβιος εῦξις D Leivei D Leivei salve", passage.annotations.fetch("clean_text_conservative")
    assert_equal "Δέκιος Λείβιος Ζεῦξις Decimi Leivei Decimi Leivei salve",
                 passage.annotations.fetch("clean_text_interpretive_word")
    assert_includes passage.text_normalized, "decimi leiuei", "search speaks the expanded reading"
  end

  def test_language_follows_the_dominant_script
    assert_equal "lat", parse_urn("urn:nabu:edcs:24700151").language,
                 "a Greek//Latin bilingual with more Latin letters stays Latin"
    greek = parse_urn("urn:nabu:edcs:65000225")
    assert_equal "grc", greek.language
    assert_equal "grc", greek.first.language
    assert_equal "lat", parse_urn("urn:nabu:edcs:34700317").language
  end

  def test_text_is_nfc_at_the_boundary
    raw = JSON.parse(File.read(DUMP)).find { |record| record["EDCS-ID"] == "EDCS-65000225" }.fetch("inscription")
    assert_includes raw, "ί", "upstream's iota with OXIA (U+1F77), verbatim in the fixture"
    refute raw.unicode_normalized?(:nfc)
    assert_equal raw.unicode_normalize(:nfc), parse_urn("urn:nabu:edcs:65000225").first.text
  end

  def test_the_untranscribed_other_language_marker_rides_verbatim
    document = parse_urn("urn:nabu:edcs:13001449")
    assert_equal "lat", document.language, "EDCS transcribes the Latin half; the Punic half is only flagged"
    assert_equal "PU", document.metadata.fetch("language")
    assert_equal({ "values" => ["PU"] }, document.metadata.fetch("facets").fetch("other_language"))
  end

  # --- parse: metadata and axes -----------------------------------------------

  def test_identity_concordance_and_partner_ids
    document = parse_urn("urn:nabu:edcs:24700151")
    metadata = document.metadata
    assert_equal "EDCS-24700151", metadata.fetch("edcs_id")
    assert_equal "CIL 01, 02650 (p 1097) = IG-05-01, 00741 = ILLRP 00962", metadata.fetch("publication")
    assert_equal "CIL 01, 02650 (p 1097)", document.title, "the first concordance item titles the record"
    assert_equal ["HD057726"], metadata.fetch("edh_ids"), "the EDH partner id, for the cross-database join"
    assert_match(/partner\.php/, metadata.fetch("partner_link"))
  end

  def test_facets_carry_genre_status_material_province_and_process
    facets = parse_urn("urn:nabu:edcs:34700317").metadata.fetch("facets")
    assert_equal({ "values" => ["tituli fabricationis", "tituli operum"] }, facets.fetch("genre"))
    assert_equal({ "values" => ["mulieres", "tria nomina"] }, facets.fetch("social"))
    assert_equal({ "values" => ["sigilla impressa"] }, facets.fetch("execution"))
    assert_equal({ "value" => "opus figlinae" }, facets.fetch("material"))
    assert_equal({ "value" => "Aemilia / Regio VIII" }, facets.fetch("province"))
  end

  def test_empty_upstream_values_mint_nothing
    facets = parse_urn("urn:nabu:edcs:09700347").metadata.fetch("facets")
    refute facets.key?("genre"), "inscr_type {} is empty, not a value"
    refute facets.key?("social")
    refute facets.key?("material")
  end

  def test_dates_ride_the_structured_shape_with_the_raw_dating
    date = parse_urn("urn:nabu:edcs:24900077").metadata.fetch("date")
    assert_equal({ "not_before" => -68, "not_after" => -68, "raw" => "-68 to -68" }, date)
    envelope = parse_urn("urn:nabu:edcs:09700347").metadata.fetch("date")
    assert_equal [71, 130], envelope.values_at("not_before", "not_after")
    assert_equal "a:  71 to 130;   b:  71 to 130;   c:  71 to 130", envelope.fetch("raw")
    refute parse_urn("urn:nabu:edcs:24700151").metadata.key?("date"), "undated records carry no date"
  end

  def test_reversed_upstream_bounds_ride_verbatim_for_the_builder_to_reorder
    date = parse_urn("urn:nabu:edcs:09001312").metadata.fetch("date")
    assert_equal [171, 138], date.values_at("not_before", "not_after")
    assert_includes Nabu::Store::TimelineBuilder::MetadataDates::REORDER, "edcs"
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES.fetch("edcs")
  end

  def test_place_carries_the_findspot_name_and_its_coordinates
    place = parse_urn("urn:nabu:edcs:24900077").metadata.fetch("place")
    assert_equal({ "ancient" => "Agia Triada / Merbaka / Midea", "geo" => "37.6381128, 22.8052991" }, place)
    assert_equal({ "ancient" => "Afesou" }, parse_urn("urn:nabu:edcs:24700151").metadata.fetch("place"))
  end

  def test_an_unknown_place_keeps_only_its_coordinates
    place = parse_urn("urn:nabu:edcs:31200870").metadata.fetch("place")
    assert_equal({ "geo" => "35.051359, 33.221283" }, place, "place \"?\" is EDCS's unknown, never a name")
  end

  def test_the_place_lane_reads_the_hash
    meta = parse_urn("urn:nabu:edcs:24900077").metadata
    claim = Nabu::Store::TimelineBuilder::MetadataDates.place_claim(meta)
    assert_equal ["Agia Triada / Merbaka / Midea", nil, 37.6381128, 22.8052991], claim
  end

  # --- fetch --------------------------------------------------------------------

  def pinned_adapter(body)
    Nabu::Adapters::Edcs.new(sha256: Digest::SHA256.hexdigest(body), md5: Digest::MD5.hexdigest(body))
  end

  def test_fetch_streams_the_dump_into_the_workdir_and_verifies_both_pins
    body = File.binread(DUMP)
    stub_request(:get, Nabu::Adapters::Edcs::FILE_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      report = pinned_adapter(body).fetch(dir)
      assert_equal body, File.binread(File.join(dir, Nabu::Adapters::Edcs::FILENAME))
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_match(/sha256 \+ md5 pins verified/, report.notes)
      assert_equal URNS, conformance_adapter.discover(dir).map(&:id)
    end
  end

  def test_fetch_aborts_on_drift_with_the_tree_untouched
    body = File.binread(DUMP)
    stub_request(:get, Nabu::Adapters::Edcs::FILE_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      adapter = Nabu::Adapters::Edcs.new(sha256: Digest::SHA256.hexdigest(body), md5: "0" * 32)
      error = assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
      assert_match(/re-pin/, error.message)
      refute File.exist?(File.join(dir, Nabu::Adapters::Edcs::FILENAME)), "the drifted body never lands"
    end
  end

  def test_the_frozen_pins_are_the_published_deposit
    assert_equal "7ee22c65f442d54ba3537955603cc0ba", Nabu::Adapters::Edcs::MD5, "Zenodo's own md5"
    assert_equal 465_523_658, Nabu::Adapters::Edcs::SIZE
    assert_match(/\A\h{64}\z/, Nabu::Adapters::Edcs::SHA256)
  end
end
