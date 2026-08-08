# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "tmpdir"

module Adapters
  # Nabu::Adapters::TrismegistosGeo (P63-1) — the Trismegistos Geo gazetteer
  # as a FEATURE MODULE behind the Manual Adapter pattern (Dp-a): the dump
  # sits behind a captcha interstitial + POST form (measured 2026-08-08), so
  # fetch ingests an owner-acquired drop from incoming/trismegistos-geo/
  # instead of touching the network. Fixtures are trimmed REAL dump rows
  # (test/fixtures/trismegistos-geo/README.md) with the `";` line endings and
  # the ghost-name/coordinate quirks intact.
  class TrismegistosGeoTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("trismegistos-geo")

    def test_registry_carries_the_module_row_manual_drop
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["trismegistos-geo"]
      refute_nil entry, "trismegistos-geo must be registered in config/sources.yml"
      assert entry.feature_module?, "a gazetteer instrument is a kind: module row"
      assert_equal "manual", entry.sync_policy
    end

    def test_manifest_is_cc_by_sa_attribution_verbatim
      manifest = Nabu::Adapters::TrismegistosGeo.manifest
      assert_equal "trismegistos-geo", manifest.id
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC BY-SA 4.0",
                      "the dataservices page's verbatim grant rides the manifest"
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::TrismegistosGeo.new
      assert_empty adapter.discover(FIXTURES).to_a
      ref = Nabu::DocumentRef.new(source_id: "trismegistos-geo", id: "urn:nabu:trismegistos-geo:x",
                                  path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/gazetteer instrument/, error.message)
    end

    # --- the manual-acquisition spec -----------------------------------------

    def test_the_acquisition_spec_names_the_real_door_and_both_files
      spec = Nabu::Adapters::TrismegistosGeo.manual_acquisition
      assert_equal "trismegistos-geo", spec.slug
      assert_includes spec.upstream_url, "trismegistos.org/dataservices"
      assert_includes spec.steps.join("\n").downcase, "captcha", "the card warns about the interstitial"
      assert_includes spec.steps.join("\n").downcase, "every", "tick every live field — partial dumps lose columns"
      names = spec.files.map(&:name)
      assert_equal %w[TM_geo.csv TM_geo.json], names
      assert spec.files.first.required, "the CSV is the canonical asset"
      refute spec.files.last.required, "the JSON rides along when taken"
    end

    def test_the_csv_sniff_accepts_the_real_dump_shape_and_refuses_html
      sniff = Nabu::Adapters::TrismegistosGeo.manual_acquisition.files.first.sniff
      assert_nil sniff.call(File.join(FIXTURES, "TM_geo.csv")), "the trimmed real dump passes"
      Dir.mktmpdir do |dir|
        bogus = File.join(dir, "TM_geo.csv")
        File.write(bogus, "<!doctype html><title>Security Check</title>")
        refute_nil sniff.call(bogus), "a saved captcha page is refused, not ingested"
      end
    end

    def test_the_json_sniff_accepts_the_real_feature_collection
      sniff = Nabu::Adapters::TrismegistosGeo.manual_acquisition.files.last.sniff
      assert_nil sniff.call(File.join(FIXTURES, "TM_geo.json"))
    end

    # --- fetch = the drop gateway --------------------------------------------

    def with_root
      Dir.mktmpdir do |root|
        workdir = File.join(root, "canonical", "trismegistos-geo")
        drop = File.join(root, "incoming", "trismegistos-geo")
        FileUtils.mkdir_p(workdir)
        yield root, workdir, drop
      end
    end

    def test_fetch_without_a_drop_aborts_with_the_instruction_card
      with_root do |_root, workdir, drop|
        error = assert_raises(Nabu::FetchError) do
          Nabu::Adapters::TrismegistosGeo.new.fetch(workdir)
        end
        assert_includes error.message, "trismegistos.org/dataservices"
        assert_includes error.message, drop, "the card points at incoming/trismegistos-geo/"
      end
    end

    def test_fetch_ingests_a_valid_drop_into_canonical_with_provenance
      with_root do |_root, workdir, drop|
        FileUtils.mkdir_p(drop)
        FileUtils.cp(File.join(FIXTURES, "TM_geo.csv"), drop)
        FileUtils.cp(File.join(FIXTURES, "TM_geo.json"), drop)
        report = Nabu::Adapters::TrismegistosGeo.new.fetch(workdir)
        refute_nil report.sha
        assert File.exist?(File.join(workdir, "TM_geo.csv"))
        state = JSON.parse(File.read(File.join(workdir, ".manual-fetch.json")))
        assert_equal %w[TM_geo.csv TM_geo.json], state["files"].keys.sort
        second = Nabu::Adapters::TrismegistosGeo.new.fetch(workdir)
        assert_equal report.sha, second.sha, "an empty drop over a held shelf is a no-op re-sync"
        assert_includes second.notes.to_s, "up to date"
      end
    end
  end
end
