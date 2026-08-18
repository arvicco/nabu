# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::CldfSpine (P46-6) — Concepticon + Glottolog registered as
  # ONE feature module (kind: module), not a text source: discover yields
  # NOTHING and parse is unreachable (the pleiades/lila shape). Its data is
  # the pure read seam Nabu::CldfSpine (exercised in test/cldf_spine_test.rb);
  # this file pins the module-row / manifest / two-file fetch contract.
  class CldfSpineTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("cldf-spine")

    def adapter = Nabu::Adapters::CldfSpine.new

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["cldf-spine"]
      refute_nil entry, "cldf-spine must be registered in config/sources.yml"
      assert entry.feature_module?, "a reference resolver instrument is a kind: module row"
      assert entry.wired, "channel verified (the 2026-08-18 wired-semantics ruling)"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "etym"
    end

    def test_manifest_is_cc_by_attribution_for_both_datasets
      manifest = Nabu::Adapters::CldfSpine.manifest
      assert_equal "cldf-spine", manifest.id
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC BY 4.0"
      assert_includes manifest.license, "Concepticon"
      assert_includes manifest.license, "Glottolog"
      assert_equal "cldf-spine", manifest.parser_family
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      assert_empty adapter.discover(FIXTURES).to_a, "a resolver instrument mints no documents"
      ref = Nabu::DocumentRef.new(source_id: "cldf-spine", id: "urn:nabu:cldf-spine:x",
                                  path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/resolver instrument/, error.message)
    end

    def test_urls_are_pinned_to_upstream_release_tags
      assert_includes Nabu::Adapters::CldfSpine::CONCEPTICON_URL, "/v3.4.0/",
                      "a raw URL at a release tag is a stable git blob — the reproducibility pin"
      assert_includes Nabu::Adapters::CldfSpine::GLOTTOLOG_URL, "/v5.3/"
    end

    def test_probe_heads_both_reference_files_with_per_subdir_state
      assert_equal :http_zip, Nabu::Adapters::CldfSpine.remote_probe_strategy
      targets = Nabu::Adapters::CldfSpine.http_probe_targets
      assert_equal %w[concepticon glottolog], targets.map(&:state_subdir)
      assert_equal [Nabu::FileFetch::STATE_FILE] * 2, targets.map(&:state_file)
    end

    # --- fetch (WebMock only, no network) ------------------------------------

    def test_fetch_lands_both_files_in_their_subdirs_and_the_spine_loads
      stub_request(:get, Nabu::Adapters::CldfSpine::CONCEPTICON_URL)
        .to_return(status: 200, body: File.read(File.join(FIXTURES, "concepticon", "concepticon.tsv")))
      stub_request(:get, Nabu::Adapters::CldfSpine::GLOTTOLOG_URL)
        .to_return(status: 200, body: File.read(File.join(FIXTURES, "glottolog", "languages.csv")))
      Dir.mktmpdir do |workdir|
        report = adapter.fetch(workdir)
        assert_instance_of Nabu::FetchReport, report
        assert_match(/\A\h{64}\z/, report.sha)
        assert File.file?(File.join(workdir, "concepticon", "concepticon.tsv"))
        assert File.file?(File.join(workdir, "glottolog", "languages.csv"))
        spine = Nabu::CldfSpine.load(workdir)
        assert_equal "WORLD", spine.concept("965").gloss
        assert_equal "Latin", spine.languoid("lati1261").name
      end
    end

    def test_fetch_wraps_http_failures_as_fetch_errors
      stub_request(:get, Nabu::Adapters::CldfSpine::CONCEPTICON_URL).to_return(status: 503)
      Dir.mktmpdir do |workdir|
        assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      end
    end
  end
end
