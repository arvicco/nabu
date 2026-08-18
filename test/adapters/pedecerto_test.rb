# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::Pedecerto (P44-7) — Latin metrical scansions registered as a
  # FEATURE MODULE (kind: module), not a text source: discover yields NOTHING
  # and parse is unreachable (the trismegistos/kitab shape). Its work is the
  # ENRICHMENT producer Nabu::PedecertoScansions (exercised in its own test);
  # this file pins the module contract, the manifest license, and the fetch
  # capability wiring.
  class PedecertoTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("pedecerto")

    # --- the module row / manifest --------------------------------------------

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["pedecerto"]
      refute_nil entry, "pedecerto must be registered in config/sources.yml"
      assert entry.feature_module?, "a meter-enrichment instrument is a kind: module row"
      assert entry.wired, "channel verified (the 2026-08-18 wired-semantics ruling)"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "classical", "the meter layer rides the classical desk"
    end

    def test_manifest_is_nc_by_nc_nd_verbatim
      manifest = Nabu::Adapters::Pedecerto.manifest
      assert_equal "pedecerto", manifest.id
      assert_equal "nc", manifest.license_class, "CC BY-NC-ND → the nc class"
      assert_includes manifest.license, "BY-NC-ND 4.0"
      assert_includes manifest.license, "non vengano alterati"
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::Pedecerto.new
      assert_empty adapter.discover(FIXTURES).to_a, "a meter instrument mints no documents"
      ref = Nabu::DocumentRef.new(source_id: "pedecerto", id: "urn:nabu:pedecerto:x",
                                  path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/meter-enrichment instrument/, error.message)
    end

    # --- the enrichment producer capability (the seam SyncRunner/Rebuild use) --

    def test_adapter_declares_and_builds_the_enrichment_producer
      assert Nabu::Adapters::Pedecerto.enrichment_producer?, "its data rides the enrichments table"
      refute Nabu::Adapters::Pedecerto.reference_edges?, "meter is an enrichment, NOT a links edge"
      producer = Nabu::Adapters::Pedecerto.enrichment_producer(catalog: :db_placeholder)
      assert_instance_of Nabu::PedecertoScansions, producer
    end

    def test_base_adapter_default_has_no_enrichment_producer
      refute Nabu::Adapter.enrichment_producer?, "the capability is opt-in"
      assert_nil Nabu::Adapter.enrichment_producer(catalog: :db_placeholder)
    end

    # --- fetch is an http_zip source (the ORACC/Diorisis probe shape) ---------

    def test_remote_probe_is_http_zip_over_the_bulk_artifact
      assert_equal :http_zip, Nabu::Adapters::Pedecerto.remote_probe_strategy
      target = Nabu::Adapters::Pedecerto.http_probe_targets.first
      assert_equal "https://www.pedecerto.eu/allpedecertoscans.zip", target.zip_url
      assert_nil target.metadata_url, "the governing license lives in the artifact's own <rights>"
    end

    # --- fetch (WebMock only, no network) — the P44-i3 live repro -------------
    # The owner's first sync crashed in fetch_notes (`not_modified?` on a
    # ZipFetch::Result, whose field is plain `not_modified`): nothing had ever
    # driven fetch end to end, because a module row escapes the conformance
    # suite's discover→parse round-trip. This test IS that drive: real zip
    # body, both fetch outcomes (fresh unpack and 304), notes asserted.

    # The real artifact's layout (verified in the 2026-07-25 first sync's
    # landed bytes): TWO top-level entries — allpedecertoscans/ beside a
    # macOS __MACOSX/ junk dir — so ZipFetch's single-top-dir strip does NOT
    # fire and the xml files land under DIRNAME, where the producer reads
    # them. A single-top-dir test zip would be stripped to the workdir root
    # and assert a layout upstream doesn't ship.
    def zip_body
      @zip_body ||= Dir.mktmpdir do |tmp|
        stage = File.join(tmp, "stage")
        FileUtils.mkdir_p(stage)
        FileUtils.cp_r(File.join(FIXTURES, Nabu::PedecertoScansions::DIRNAME),
                       File.join(stage, Nabu::PedecertoScansions::DIRNAME))
        junk = File.join(stage, "__MACOSX", Nabu::PedecertoScansions::DIRNAME)
        FileUtils.mkdir_p(junk)
        File.write(File.join(junk, "._.DS_Store"), "")
        zip = File.join(tmp, "allpedecertoscans.zip")
        Dir.chdir(stage) { Nabu::Shell.run("zip", "-qr", zip, Nabu::PedecertoScansions::DIRNAME, "__MACOSX") }
        File.binread(zip)
      end
    end

    def test_fetch_unpacks_the_zip_and_a_304_repeats_the_pin
      stub_request(:get, Nabu::Adapters::Pedecerto::ZIP_URL).to_return(
        status: 200, body: zip_body,
        headers: { "Last-Modified" => "Mon, 18 Aug 2025 15:51:14 GMT" }
      )
      Dir.mktmpdir do |workdir|
        report = Nabu::Adapters::Pedecerto.new.fetch(workdir)
        assert_instance_of Nabu::FetchReport, report
        assert_match(/\A\h{64}\z/, report.sha)
        assert_includes report.notes, "allpedecertoscans.zip unpacked"
        refute_empty Dir.glob(File.join(workdir, Nabu::PedecertoScansions::DIRNAME, "*.xml")),
                     "the corpus xml files must land where PedecertoScansions reads them"

        stub_request(:get, Nabu::Adapters::Pedecerto::ZIP_URL)
          .with(headers: { "If-Modified-Since" => "Mon, 18 Aug 2025 15:51:14 GMT" })
          .to_return(status: 304)
        second = Nabu::Adapters::Pedecerto.new.fetch(workdir)
        assert_equal report.sha, second.sha, "a 304 keeps the pinned sha"
        assert_includes second.notes, "not modified (304)"
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      stub_request(:get, Nabu::Adapters::Pedecerto::ZIP_URL).to_return(status: 500)
      Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { Nabu::Adapters::Pedecerto.new.fetch(workdir) } }
    end
  end
end
