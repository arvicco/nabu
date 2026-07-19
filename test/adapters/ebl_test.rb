# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"
require "digest"

module Adapters
  # Nabu::Adapters::Ebl (P31-3): conformance + source specifics over the
  # trimmed real fixture slice (14 member objects byte-verbatim from the
  # Zenodo 10018951 fragments.json, incl. the K.5808 byte-identical twin;
  # see test/fixtures/ebl/README.md).
  class EblTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("ebl")

    def conformance_adapter
      Nabu::Adapters::Ebl.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "ebl"
    end

    # K.21002 is real upstream reality: an atf of state lines only —
    # catalogued as a zero-passage document, marked honestly.
    def conformance_metadata_only?(document)
      document.metadata["text_layer"] == "none"
    end

    def adapter = conformance_adapter

    def refs
      adapter.discover(FIXTURES).to_a
    end

    def parse(urn)
      ref = refs.find { |r| r.id == urn }
      refute_nil ref, "no ref #{urn}"
      adapter.parse(ref)
    end

    # -- manifest: both license quotes verbatim, class stays nc ---------------

    def test_manifest_records_both_license_claims_verbatim_and_stays_nc
      manifest = Nabu::Adapters::Ebl.manifest
      assert_equal "nc", manifest.license_class,
                   "the JOHD License section's CC BY-NC-SA 4.0 governs until email #24 resolves the conflict"
      assert_includes manifest.license,
                      "Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)"
      assert_includes manifest.license, "cc-by-4.0",
                      "the Zenodo record's own license field must also be recorded verbatim"
      assert_equal "atf", manifest.parser_family
    end

    def test_urn_minting_is_one_rule
      assert_equal "urn:nabu:ebl:k.11360", Nabu::Adapters::Ebl.urn_for("K.11360")
      assert_equal "urn:nabu:ebl:1868,0523.2", Nabu::Adapters::Ebl.urn_for("1868,0523.2")
      assert_equal "urn:nabu:ebl:u.7321.?", Nabu::Adapters::Ebl.urn_for("U.7321 ?"),
                   "whitespace inside a museum number folds to the house dot"
    end

    # -- discovery ------------------------------------------------------------

    def test_discover_yields_one_ref_per_fragment_sorted_first_twin_wins
      all = refs
      assert_equal 13, all.size, "14 fixture members minus the K.5808 byte-identical twin"
      assert_equal all.map(&:id).sort, all.map(&:id)
      assert(all.all? { |r| r.path.end_with?("fragments.json") })
      skips = adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      assert_predicate skips, :clean?
    end

    def test_discover_of_an_unfetched_workdir_yields_nothing
      Dir.mktmpdir do |dir|
        assert_empty Nabu::Adapters::Ebl.new.discover(dir).to_a
      end
    end

    # -- catalog metadata, facets, edges --------------------------------------

    def test_cdli_number_mints_a_reference_edge_into_the_cdli_urn_space
      document = parse("urn:nabu:ebl:k.11360")
      assert_includes document.metadata["related"], "urn:nabu:cdli:p399253"
      assert_equal "P399253", document.metadata.dig("external_numbers", "cdliNumber")
      assert_equal "W_K-11360", document.metadata.dig("external_numbers", "bmIdNumber"),
                   "unschemed external numbers stay metadata, never edges"
    end

    def test_oracc_edition_mints_a_project_edge_beside_the_cdli_edge
      document = parse("urn:nabu:ebl:k.20565")
      assert_equal "saao", document.metadata["edited_in_oracc"]
      assert_includes document.metadata["related"], "urn:nabu:oracc:saao:P336787"
      assert_includes document.metadata["related"], "urn:nabu:cdli:p336787"
    end

    def test_facets_carry_period_genre_collection_and_museum
      document = parse("urn:nabu:ebl:im.61678")
      facets = document.metadata["facets"]
      assert_equal "Ur III", facets["period"]["value"]
      assert_equal "ARCHIVAL/Administrative/Receipts", facets["genre"]["value"]
      assert_equal "Nippur (mod. Nuffar)", facets["collection"]["value"]
      assert_equal "The Iraq Museum, Baghdad", facets["museum"]["value"]
      assert_equal ["CAIC"], document.metadata["projects"]
      assert_equal "2", document.metadata.dig("date", "month", "value"),
                   "the structured king/year date rides verbatim"
      assert_equal "BBVO 11, 299, 6N-T840", document.metadata["notes"]
    end

    def test_the_none_period_sentinel_never_becomes_a_facet
      document = parse("urn:nabu:ebl:n.7458")
      refute document.metadata.key?("period"), "'None' is upstream's no-value sentinel"
      assert_nil document.metadata.dig("facets", "period")
    end

    def test_zero_text_fragment_is_a_marked_metadata_only_document
      document = parse("urn:nabu:ebl:k.21002")
      assert_equal 0, document.size
      assert_equal "none", document.metadata["text_layer"]
      assert_equal %w[illegible blank], document.metadata["states"]
      assert_equal "akk", document.language
    end

    def test_title_is_the_museum_number_designation
      assert_equal "K.11360", parse("urn:nabu:ebl:k.11360").title
      document = parse("urn:nabu:ebl:1868,0523.2")
      assert_equal "1868,0523.2", document.title
      assert_equal "Edition by NinMed", document.metadata["publication"]
      assert_equal "Kuyunjik", document.metadata["collection"]
    end

    # -- fetch (WebMock; no network ever) -------------------------------------

    def test_fetch_downloads_the_snapshot_and_verifies_the_pin
      body = File.read(File.join(FIXTURES, "fragments.json"))
      stub_request(:get, Nabu::Adapters::Ebl::SNAPSHOT_URL)
        .to_return(status: 200, body: body, headers: { "Last-Modified" => "Wed, 18 Oct 2023 00:00:00 GMT" })
      Dir.mktmpdir do |dir|
        adapter = Nabu::Adapters::Ebl.new(pin: Digest::SHA256.hexdigest(body))
        report = adapter.fetch(dir)
        assert_equal Digest::SHA256.hexdigest(body), report.sha
        assert_equal 13, adapter.discover(dir).to_a.size
      end
    end

    def test_fetch_rejects_a_body_missing_the_sha_pin
      stub_request(:get, Nabu::Adapters::Ebl::SNAPSHOT_URL)
        .to_return(status: 200, body: "[]")
      Dir.mktmpdir do |dir|
        error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Ebl.new.fetch(dir) }
        assert_match(/sha256 pin/, error.message)
        refute File.exist?(File.join(dir, "fragments.json")),
               "a pin miss must abort before the tree mutates"
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      stub_request(:get, Nabu::Adapters::Ebl::SNAPSHOT_URL).to_return(status: 500)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { Nabu::Adapters::Ebl.new.fetch(dir) }
      end
    end

    # -- remote-health probe shape --------------------------------------------

    def test_remote_probe_is_http_with_the_snapshot_url_and_no_metadata_endpoint
      assert_equal :http_zip, Nabu::Adapters::Ebl.remote_probe_strategy
      target = Nabu::Adapters::Ebl.http_probe_targets.fetch(0)
      assert_equal Nabu::Adapters::Ebl::SNAPSHOT_URL, target.zip_url
      assert_nil target.metadata_url
      assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
    end
  end
end
