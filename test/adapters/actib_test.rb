# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Adapters
  # Nabu::Adapters::Actib (P55-4) — the ACTib v2.0 eKangyur seg+POS layers
  # registered as a FEATURE MODULE (kind: module), not a text source (the
  # pedecerto/hypotactic shape): discover yields NOTHING and parse is
  # unreachable. Its work is the xct/actib-anchors nabu-data builder, which
  # reads canonical/actib/seg/ (exercised in its own test); this file pins
  # the module contract, the record-level license honesty, and the fetch.
  class ActibTest < Minitest::Test
    FIXTURES = File.join(Nabu::TestSupport::FIXTURES_ROOT, "data_build", "actib")

    # --- the module row / manifest ------------------------------------------

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["actib"]
      refute_nil entry, "actib must be registered in config/sources.yml"
      assert entry.feature_module?, "a corpus-layer instrument is a kind: module row"
      assert entry.wired, "channel verified (the 2026-08-18 wired-semantics ruling)"
      assert_equal "manual", entry.sync_policy
      assert_equal ["tibetan"], entry.axes, "the anchor layer rides the tibetan desk"
    end

    def test_manifest_records_the_record_level_license_honestly
      manifest = Nabu::Adapters::Actib.manifest
      assert_equal "actib", manifest.id
      assert_equal "attribution", manifest.license_class, "CC BY 4.0 → the attribution class"
      assert_includes manifest.license, "CC BY 4.0"
      assert_includes manifest.license, "Zenodo record",
                      "the license basis is the RECORD's declared license"
      assert_match(/no license file/i, manifest.license,
                   "the zip ships no license text — the absence is recorded honestly")
      assert_includes manifest.upstream_url, "10.5281/zenodo.3951503"
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::Actib.new
      Dir.mktmpdir do |workdir|
        assert_empty adapter.discover(workdir).to_a, "a corpus-layer instrument mints no documents"
      end
      ref = Nabu::DocumentRef.new(source_id: "actib", id: "urn:nabu:actib:x", path: "/dev/null", metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/anchor/, error.message)
    end

    # --- fetch is an http_zip source (the pedecerto probe shape) ------------

    def test_remote_probe_is_http_zip_over_the_zenodo_artifact
      assert_equal :http_zip, Nabu::Adapters::Actib.remote_probe_strategy
      target = Nabu::Adapters::Actib.http_probe_targets.first
      assert_equal "https://zenodo.org/records/3951503/files/SegPOS-eKangyur_July2020.zip",
                   target.zip_url
      assert_nil target.metadata_url
    end

    # --- fetch (WebMock only, no network) -----------------------------------
    # The real artifact carries EXACTLY ONE top-level directory
    # (SegPOS-eKangyur_July2020/ holding seg/ + pos/; verified in the
    # 2026-07-30 download), so ZipFetch's single-top-dir strip fires and the
    # layer trees land at canonical/actib/{seg,pos} — where the
    # xct/actib-anchors builder reads them.

    def zip_body
      @zip_body ||= Dir.mktmpdir do |tmp|
        stage = File.join(tmp, "stage", "SegPOS-eKangyur_July2020")
        FileUtils.mkdir_p(File.join(stage, "seg"))
        FileUtils.cp(File.join(FIXTURES, "actib", "seg", "UT4CZ5369-I1KG9167-0000.txt"),
                     File.join(stage, "seg"))
        zip = File.join(tmp, "SegPOS-eKangyur_July2020.zip")
        Dir.chdir(File.join(tmp, "stage")) { Nabu::Shell.run("zip", "-qr", zip, "SegPOS-eKangyur_July2020") }
        File.binread(zip)
      end
    end

    def test_fetch_unpacks_the_layer_trees_and_a_304_repeats_the_pin
      stub_request(:get, Nabu::Adapters::Actib::ZIP_URL).to_return(
        status: 200, body: zip_body,
        headers: { "Last-Modified" => "Sat, 18 Jul 2020 19:51:00 GMT" }
      )
      Dir.mktmpdir do |workdir|
        report = Nabu::Adapters::Actib.new.fetch(workdir)
        assert_instance_of Nabu::FetchReport, report
        assert_match(/\A\h{64}\z/, report.sha)
        assert_includes report.notes, "SegPOS-eKangyur_July2020.zip unpacked"
        refute_empty Dir.glob(File.join(workdir, "seg", "*.txt")),
                     "the seg layer must land at canonical/actib/seg (top dir stripped) " \
                     "where the anchors builder reads it"

        stub_request(:get, Nabu::Adapters::Actib::ZIP_URL)
          .with(headers: { "If-Modified-Since" => "Sat, 18 Jul 2020 19:51:00 GMT" })
          .to_return(status: 304)
        second = Nabu::Adapters::Actib.new.fetch(workdir)
        assert_equal report.sha, second.sha, "a 304 keeps the pinned sha"
        assert_includes second.notes, "not modified (304)"
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      stub_request(:get, Nabu::Adapters::Actib::ZIP_URL).to_return(status: 500)
      Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { Nabu::Adapters::Actib.new.fetch(workdir) } }
    end
  end
end
