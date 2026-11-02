# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# Nabu::Adapters::Cgpg (P153): the Calfa/GREgORI Patrologia Graeca deposit
# (Zenodo 19915273, CC BY 4.0) — 33 Migne volumes, machine OCR with
# automatic lemma/POS. Fixtures: three volume files trimmed to whole pages
# plus the raw-OCR rejected grain (see the fixture README).
class CgpgTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("cgpg")
  ZIP_URL = Nabu::Adapters::Cgpg::ZIP_URL

  def conformance_adapter = Nabu::Adapters::Cgpg.new

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "cgpg"

  def adapter = conformance_adapter

  def parse(urn)
    adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id == urn })
  end

  def test_manifest
    manifest = Nabu::Adapters::Cgpg.manifest
    assert_equal "cgpg", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "cgpg-vert", manifest.parser_family
    assert_match(/CC BY 4\.0/, manifest.license)
  end

  def test_discover_mints_one_document_per_volume_file
    assert_equal %w[urn:nabu:cgpg:pg8 urn:nabu:cgpg:pg101 urn:nabu:cgpg:pg153],
                 adapter.discover(FIXTURES).map(&:id), "volume order, the .txt member included"
  end

  def test_part_volumes_mint_their_dotted_number
    assert_equal "16.3", Nabu::Adapters::Cgpg.volume_of("PG016_3_tagged_text.vert")
    assert_equal "87.1", Nabu::Adapters::Cgpg.volume_of("PG087_1_tagged_text.vert")
    assert_equal "101", Nabu::Adapters::Cgpg.volume_of("PG101_tagged_text.vert")
    assert_nil Nabu::Adapters::Cgpg.volume_of("PG101_text.txt")
  end

  def test_the_volume_table_covers_the_whole_deposit
    assert_equal 33, Nabu::Adapters::Cgpg::VOLUMES.size
    assert_equal %w[3 5 6 8 9 16.3 21 42 67 71 73 87.1], Nabu::Adapters::Cgpg::VOLUMES.keys.first(12)
  end

  def test_the_raw_ocr_grain_is_skipped_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_match(/PG101_text\.txt/, skips.notes.join)
    assert_match(/raw OCR/, skips.notes.join)
  end

  def test_volume_metadata_transcribes_the_upstream_table
    document = parse("urn:nabu:cgpg:pg153")
    assert_equal "grc", document.language
    assert_equal "PG 153 — John Cantacuzene (vol. 1): Historia Byzantina in 4 books (events from 1320–1354)",
                 document.title
    metadata = document.metadata
    assert_equal "153", metadata["pg_volume"]
    assert_equal "14th century", metadata["period"]
    assert_equal 230_239, metadata["words_advertised"]
    assert_equal "uncorrected-ocr", metadata["text_nature"]
    assert_equal({ "not_before" => 1301, "not_after" => 1400, "raw" => "14th century", "class" => "composition" },
                 metadata["date"])
    assert_equal "PG 153 - AI processed", metadata["doc_id"]
  end

  def test_the_pre_nicaean_label_carries_no_date
    metadata = parse("urn:nabu:cgpg:pg8").metadata
    assert_equal "Pre-Nicaean", metadata["period"]
    refute metadata.key?("date"), "a label with no century bound mints no envelope"
  end

  def test_pages_become_passages_with_silver_tokens
    document = parse("urn:nabu:cgpg:pg101")
    assert_equal ["urn:nabu:cgpg:pg101:p14"], document.passages.map(&:urn)
    assert_equal 388, document.passages.first.annotations["tokens"].size
    assert document.passages.first.text.start_with?("«Ἐπειδὴ τοίνυν οἱ παρὰ τοῦ βασιλέως")
  end

  def test_century_labels_band_to_centuries
    assert_equal [401, 500], Nabu::Adapters::Cgpg.century_band("5th century")
    assert_equal [1001, 1100], Nabu::Adapters::Cgpg.century_band("11th century")
    assert_equal [1, 100], Nabu::Adapters::Cgpg.century_band("1st century")
    assert_nil Nabu::Adapters::Cgpg.century_band("Pre-Nicaean")
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_verifies_the_pin_and_unpacks_the_single_top_dir
    body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |workdir|
      fetcher = Nabu::Adapters::Cgpg.new(pin: Digest::SHA256.hexdigest(body))
      report = fetcher.fetch(workdir)
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal %w[urn:nabu:cgpg:pg8 urn:nabu:cgpg:pg101 urn:nabu:cgpg:pg153],
                   fetcher.discover(workdir).map(&:id), "PG/ maps onto the workdir"
    end
  end

  def test_fetch_aborts_on_a_pin_mismatch_with_the_tree_untouched
    stub_request(:get, ZIP_URL).to_return(status: 200, body: stub_zip_body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Cgpg.new.fetch(workdir) }
      assert_match(/pin/, error.message)
      assert_empty(Dir.children(workdir).reject { |name| name.start_with?(".") })
    end
  end

  def test_fetch_wraps_http_failure
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Cgpg.new.fetch(workdir) }
    end
  end

  # --- idempotency ---------------------------------------------------------------

  def test_loading_the_fixture_set_twice_is_idempotent
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "cgpg", name: "CGPG", adapter_class: "Nabu::Adapters::Cgpg",
                                        license_class: "attribution")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 4, db[:passages].count
    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 3, second.skipped
    assert_equal 4, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  end

  private

  # The upstream layout: one top-level PG/ directory holding the members.
  def stub_zip_body
    Dir.mktmpdir do |dir|
      staging = File.join(dir, "staging", "PG")
      FileUtils.mkdir_p(staging)
      Dir.glob(File.join(FIXTURES, "PG*_tagged_text.*")).each { |path| FileUtils.cp(path, staging) }
      zip_path = File.join(dir, "PG.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "PG", chdir: File.join(dir, "staging"))
      return File.binread(zip_path)
    end
  end
end
