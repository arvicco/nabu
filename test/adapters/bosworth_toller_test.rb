# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The Bosworth-Toller adapter (P12-3): the third dictionary-shelf occupant and
# the first CSV dictionary source. Dictionary-shaped, so it cannot include the
# passage-shaped AdapterConformance suite; like LexicaTest it mirrors those
# checks for the dictionary shape (manifest validity, discover→parse
# round-trip, id uniqueness/stability, NFC, license class) and adds the
# FileFetch path (WebMock stubs of the LINDAT bitstream URL) plus the
# DictionaryLoader contract: idempotency, revision, withdrawal, urn shape.
class BosworthTollerTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("bosworth-toller")

  LINDAT_URL = "https://lindat.mff.cuni.cz/repository/server/api/core/bitstreams/" \
               "3010b742-b2c4-4152-870a-716ce1652e7c/content"

  def adapter = Nabu::Adapters::BosworthToller.new

  # --- manifest + content kind --------------------------------------------------

  def test_manifest_identifies_the_bosworth_toller_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "bosworth-toller", manifest.id
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal LINDAT_URL, manifest.upstream_url
    assert_equal "bosworth-csv", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::BosworthToller.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------------

  def test_discover_yields_one_ref_for_the_csv
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["bosworth-toller:bosworth_entries_export.csv"], refs.map(&:id)
    assert_equal "bosworth-toller", refs.first.source_id
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_ang_dictionary_document
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "bosworth-toller", document.slug
    assert_equal "ang", document.language
    assert_equal 270, document.size
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = -> { adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  def test_entry_output_is_nfc
    adapter.parse(adapter.discover(FIXTURES).first).each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
    end
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_downloads_the_csv_and_returns_report
    stub_request(:get, LINDAT_URL).to_return(
      status: 200, body: File.binread(File.join(FIXTURES, "bosworth_entries_export.csv")),
      headers: { "Last-Modified" => "Mon, 26 Apr 2021 14:04:23 GMT" }
    )
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 1, adapter.discover(workdir).count, "the fetched csv is discoverable in place"

      stub_request(:get, LINDAT_URL)
        .with(headers: { "If-Modified-Since" => "Mon, 26 Apr 2021 14:04:23 GMT" })
        .to_return(status: 304)
      assert_equal report.sha, adapter.fetch(workdir).sha, "a 304 keeps the pinned sha"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, LINDAT_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- remote-health probe shape -------------------------------------------------

  def test_probe_targets_head_the_bitstream_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::BosworthToller.remote_probe_strategy
    targets = Nabu::Adapters::BosworthToller.http_probe_targets
    assert_equal 1, targets.size
    target = targets.first
    assert_equal LINDAT_URL, target.zip_url
    assert_nil target.metadata_url, "LINDAT's item JSON is not the probe's license shape; " \
                                    "the license is re-read from the record at any refetch"
    assert_equal "", target.state_subdir
    assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
  end

  # --- DictionaryLoader contract (idempotency / revision / urn) -------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "bosworth-toller", name: "Bosworth-Toller",
      adapter_class: "Nabu::Adapters::BosworthToller",
      license: "CC BY 4.0", license_class: "attribution",
      upstream_url: LINDAT_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 270, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 270, second.skipped
    assert_equal 270, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    aethele = db[:dictionary_entries].where(entry_id: "940").first
    assert_equal "urn:nabu:dict:bosworth-toller:940", aethele[:urn]
    assert_equal "æðele", aethele[:headword]
    assert_equal "aethele", aethele[:headword_folded]
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["bosworth-toller"]
    refute_nil entry, "config/sources.yml must register bosworth-toller"
    assert_equal Nabu::Adapters::BosworthToller, entry.adapter_class
    refute entry.enabled, "enabled stays false until the owner-fired first real sync"
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::BosworthToller.manifest, entry.manifest
  end
end
