# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

# Nabu::Adapters::Paramara: the Siddham network's Zenodo community
# `paramara` — one inscription per record as a PennGlobal PMR### text
# file (CC BY 4.0 per record). Fixtures: a trimmed real community
# listing (six real record objects) + three real text files (PMR198, a
# numbered copper-plate charter in plate sections; PMR203, a short pillar
# inscription; PMR47, a verse-laid edition without line numbers) and the
# rejected grains (an image-only record, a file-less record, the IN060027
# EpiDoc hybrid). No network: fetch runs against WebMock stubs.
class ParamaraTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("paramara")
  RAJPUR = "urn:nabu:paramara:pmr198"
  BUDHERA = "urn:nabu:paramara:pmr203"
  PIPLIANAGAR = "urn:nabu:paramara:pmr47"
  DOC_URNS = [RAJPUR, BUDHERA, PIPLIANAGAR].freeze

  def conformance_adapter = Nabu::Adapters::Paramara.new(delay: 0)

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "paramara"

  def adapter = conformance_adapter

  def parse(urn) = adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id == urn })

  def test_manifest_records_the_per_record_cc_by
    manifest = Nabu::Adapters::Paramara.manifest
    assert_equal "attribution", manifest.license_class
    assert_match(/cc-by-4\.0 on all 114 text records/, manifest.license)
    assert_equal "paramara-text", manifest.parser_family
  end

  def test_discover_yields_the_text_records_by_filename_identity
    assert_equal DOC_URNS, adapter.discover(FIXTURES).map(&:id)
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  def test_the_rejected_grains_skip_by_rule_and_are_counted
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 3, skips.skipped_by_rule
    assert_equal ["record 447273: no text file (Bhagdei rock inscription.jpg)",
                  "record 8189595: no text file (no files)",
                  "record 18416373: IN060027.txt is an EpiDoc rendering under a PMR header " \
                  "(the PMR text record covers the inscription)"], skips.notes
  end

  def test_numbered_lines_are_the_passages_with_footnote_markers_resolved
    document = parse(BUDHERA)
    assert_equal "san", document.language
    assert_equal "Būdhērā Pillar Inscription of the Time of Gaṇapati", document.title
    assert_equal 7, document.size
    first = document.first
    assert_equal "#{BUDHERA}:1", first.urn
    assert_equal "[saṃ]vat 1351 śāke 1[21]6 || svasti śrīkī-", first.text,
                 "Trivedi's restorations verbatim, the {n} markers out of the text"
    assert_match(/palatal and not dental/, first.annotations.dig("notes", "2"))
  end

  def test_plate_sections_ride_the_line_annotations
    document = parse(RAJPUR)
    assert_equal 56, document.size
    assert_equal "First Plate", document.first.annotations["section"]
    assert(document.any? { |passage| passage.annotations["section"].to_s.start_with?("Second Plate") })
  end

  def test_a_verse_laid_edition_without_numbers_falls_back_to_positional_refs
    document = parse(PIPLIANAGAR)
    assert_equal "#{PIPLIANAGAR}:s1", document.first.urn
    assert_equal "oṃ namaḥ puruṣārthacūḍāmaṇaye dharmmāya ||", document.first.text
    assert document.first.annotations["unnumbered"]
  end

  def test_the_header_mines_dating_place_and_the_record
    metadata = parse(BUDHERA).metadata
    assert_equal({ "not_before" => 1294, "not_after" => 1294, "raw" => "VS 1351 śaka 1216" }, metadata["date"],
                 "the leading era-typed year through config/eras.yml (VS → −57)")
    assert_equal "Būdhērā", metadata["place"]
    assert_equal "Gaṇapati", metadata["king"]
    assert_equal "PMR203", metadata["siglum"]
    assert_equal "22938192", metadata["record_id"]
    assert_equal "cc-by-4.0", metadata["license_id"]
    assert_match(/Trivedi \(1989\), no\. 203/, metadata["published_reference"])
  end

  def test_paramara_is_registered_for_the_structured_metadata_dates_shape
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["paramara"]
  end

  def test_a_record_not_under_cc_by_goes_restricted
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")), dir)
      records = JSON.parse(File.read(File.join(dir, "records.json")))
      records.find { |r| r["id"] == 22_938_192 }["metadata"]["license"] = { "id" => "cc-by-nc-nd-4.0" }
      File.write(File.join(dir, "records.json"), JSON.generate(records))
      ref = adapter.discover(dir).find { |r| r.id == BUDHERA }
      assert_equal "restricted", adapter.parse(ref).license_override
    end
    assert_nil parse(BUDHERA).license_override
  end

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "paramara", name: "Paramāra", adapter_class: "Nabu::Adapters::Paramara",
                                        license_class: "attribution")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 56 + 7 + 56, db[:passages].count
    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 3, second.skipped
    assert_equal 119, db[:passages].count
  ensure
    db&.disconnect
  end

  def test_fetch_pages_the_community_and_downloads_each_text_once
    records = JSON.parse(File.read(File.join(FIXTURES, "records.json")))
    listing = "https://zenodo.org/api/communities/paramara/records"
    stub_request(:get, listing).with(query: hash_including("page" => "1"))
                               .to_return(status: 200, body: JSON.generate("hits" => { "hits" => records.first(4),
                                                                                       "total" => records.size }))
    stub_request(:get, listing).with(query: hash_including("page" => "2"))
                               .to_return(status: 200, body: JSON.generate("hits" => { "hits" => records.drop(4),
                                                                                       "total" => records.size }))
    texts = records.select { |r| Nabu::Adapters::Paramara.text_file(r) }
    texts.each do |record|
      key = Nabu::Adapters::Paramara.text_file(record)
      stub_request(:get, "https://zenodo.org/api/records/#{record['id']}/files/#{key}/content")
        .to_return(status: 200, body: File.binread(File.join(FIXTURES, record["id"].to_s, key)))
    end
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_match(/6 records listed; 4 text files downloaded/, report.notes)
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id)
      second = adapter.fetch(workdir)
      assert_match(/0 text files downloaded/, second.notes, "a present file with a matching md5 is kept")
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, /zenodo\.org/).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end
end
