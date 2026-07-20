# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The Unihan adapter (P32-4): the Sinoxenic bridge's spine — one dictionary
# entry per CJK codepoint, shelf keyed "U+XXXX" so KANJIDIC2 and the HDIC
# headword characters join by codepoint. Dictionary-shaped, so like
# BosworthTollerTest it mirrors the passage conformance checks for the
# dictionary shape and adds the ZipFetch path (WebMock only), the probe
# shape, the DictionaryLoader contract and the registry row.
class UnihanTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("unihan")

  ZIP_URL = "https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip"

  def adapter = Nabu::Adapters::Unihan.new

  # --- manifest + content kind ----------------------------------------------------

  def test_manifest_identifies_unihan_with_the_unicode_license_v3_verdict
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "unihan", manifest.id
    assert_equal "open", manifest.license_class
    assert_match(/Unicode License V3/, manifest.license)
    assert_match(/Permission is hereby granted, free of charge/, manifest.license,
                 "the verbatim grant head travels in the manifest")
    assert_equal ZIP_URL, manifest.upstream_url
    assert_equal "unihan-txt", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Unihan.content_kind
  end

  # --- discover → parse round-trip -------------------------------------------------

  def test_discover_yields_one_ref_anchored_on_the_readings_file
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["unihan:Unihan_Readings.txt"], refs.map(&:id)
    assert_equal "unihan", refs.first.source_id
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_zho_dictionary_document_with_variants_merged
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "unihan", document.slug
    assert_equal "zho", document.language
    assert_equal 15, document.size
    entry = document.find { |e| e.entry_id == "U+4E9E" }
    assert_includes entry.body, "kSimplifiedVariant: U+4E9A",
                    "the Variants sibling file is merged into the codepoint entries"
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = -> { adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  def test_parse_without_the_variants_sibling_still_yields_the_readings_entries
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(FIXTURES, "Unihan_Readings.txt"), dir)
      document = adapter.parse(adapter.discover(dir).first)
      assert_equal 13, document.size,
                   "the variants-only codepoints (U+340A/U+340B, the spoofing pair) cannot mint without the file"
      refute(document.any? { |e| e.entry_id == "U+340A" })
    end
  end

  # --- fetch (WebMock only, no network) --------------------------------------------

  def zip_body
    @zip_body ||= Dir.mktmpdir do |tmp|
      zip = File.join(tmp, "Unihan.zip")
      Dir.chdir(FIXTURES) do
        Nabu::Shell.run("zip", "-q", zip, "Unihan_Readings.txt", "Unihan_Variants.txt")
      end
      File.binread(zip)
    end
  end

  def test_fetch_unpacks_the_zip_and_discovers_the_shelf
    stub_request(:get, ZIP_URL).to_return(
      status: 200, body: zip_body,
      headers: { "Last-Modified" => "Mon, 18 Aug 2025 15:51:14 GMT" }
    )
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 15, adapter.parse(adapter.discover(workdir).first).size

      stub_request(:get, ZIP_URL)
        .with(headers: { "If-Modified-Since" => "Mon, 18 Aug 2025 15:51:14 GMT" })
        .to_return(status: 304)
      assert_equal report.sha, adapter.fetch(workdir).sha, "a 304 keeps the pinned sha"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end

  # --- remote-health probe shape ---------------------------------------------------

  def test_probe_heads_the_zip_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Unihan.remote_probe_strategy
    targets = Nabu::Adapters::Unihan.http_probe_targets
    assert_equal 1, targets.size
    assert_equal ZIP_URL, targets.first.zip_url
    assert_nil targets.first.metadata_url, "the license is a static page, not a probe shape"
    assert_equal Nabu::ZipFetch::STATE_FILE, targets.first.state_file
  end

  # --- DictionaryLoader contract ---------------------------------------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "unihan", name: "Unihan", adapter_class: "Nabu::Adapters::Unihan",
      license: "Unicode License V3", license_class: "open",
      upstream_url: ZIP_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_codepoint_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 15, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 15, second.skipped
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    one = db[:dictionary_entries].where(entry_id: "U+4E00").first
    assert_equal "urn:nabu:dict:unihan:U+4E00", one[:urn]
    assert_equal "一", one[:headword]
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["unihan"]
    refute_nil entry, "config/sources.yml must register unihan"
    assert_equal Nabu::Adapters::Unihan, entry.adapter_class
    assert entry.enabled, "live (owner order 2026-07-20: P32+P33 sources flipped, post-P34 gate)"
    assert_equal "manual", entry.sync_policy
  end
end
