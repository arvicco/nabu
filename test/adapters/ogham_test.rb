# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Ogham adapter tests (P25-1): layer-sibling discovery (ogham = bare urn,
# transliteration/roman as -suffix documents), the empty-layer skip census,
# the nc-pending license posture, and the dil.ie reference-edge capability.
# Includes the shared AdapterConformance suite over the real fixture records
# (test/fixtures/ogham/README.md).
class OghamTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("ogham")

  def conformance_adapter
    Nabu::Adapters::Ogham.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "ogham"
  end

  # --- manifest: the license conflict held at the restrictive reading ---------

  def test_manifest_quotes_both_conflicting_grants_and_holds_nc
    manifest = Nabu::Adapters::Ogham.manifest
    assert_equal "ogham", manifest.id
    assert_equal "nc", manifest.license_class, "restrictive reading PENDING the clarification reply"
    assert_match(/CC-BY-NC-SA/, manifest.license)
    assert_match(/Creative Commons Attribution 4\.0 International License/, manifest.license)
    assert_match(/registry #14/, manifest.license)
    assert_equal "ogham-epidoc", manifest.parser_family
  end

  def test_reference_edges_capability_names_its_own_producer
    assert Nabu::Adapters::Ogham.reference_edges?
    assert_equal "ogham", Nabu::Adapters::Ogham.reference_producer
  end

  def test_fetch_is_the_git_path
    assert_equal :git, Nabu::Adapters::Ogham.remote_probe_strategy
    assert_equal ["https://github.com/lguariento/og-h-am"], Nabu::Adapters::Ogham.upstream_repo_urls
  end

  # --- discover: layer siblings ----------------------------------------------

  def test_discover_mints_layer_documents_ogham_bare_siblings_suffixed
    refs = Nabu::Adapters::Ogham.new.discover(FIXTURES).to_a
    assert_equal %w[
      urn:nabu:ogham:e-con-x03-roman
      urn:nabu:ogham:e-dev-001 urn:nabu:ogham:e-dev-001-roman urn:nabu:ogham:e-dev-001-translit
      urn:nabu:ogham:i-may-010 urn:nabu:ogham:i-may-010-translit
      urn:nabu:ogham:i-wat-042 urn:nabu:ogham:i-wat-042-translit
      urn:nabu:ogham:s-she-001 urn:nabu:ogham:s-she-001-translit
    ], refs.map(&:id), "I-COR-L11 (both edition divs empty) yields nothing; " \
                       "E-CON-X03 has no ogham layer, so -roman is its only document"
  end

  def test_discover_marks_exactly_one_primary_per_record
    refs = Nabu::Adapters::Ogham.new.discover(FIXTURES).to_a
    primaries = refs.select { |ref| ref.metadata["primary"] }
    assert_equal %w[
      urn:nabu:ogham:e-con-x03-roman urn:nabu:ogham:e-dev-001 urn:nabu:ogham:i-may-010
      urn:nabu:ogham:i-wat-042 urn:nabu:ogham:s-she-001
    ], primaries.map(&:id).sort, "the record's FIRST layer carries the stone-grain metadata"
    assert(refs.all? { |ref| ref.metadata["chardecl"]&.end_with?("charDecl.xml") })
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Ogham.new.discover(dir).to_a
    end
  end

  # --- discovery census -------------------------------------------------------

  def test_discovery_skips_count_empty_layers_by_rule
    skips = Nabu::Adapters::Ogham.new.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule, "I-COR-L11's two self-closed edition divs"
    assert_equal 0, skips.unrecognized
    assert skips.clean?
  end

  # --- parse round-trips ------------------------------------------------------

  def test_parse_round_trips_the_ogham_and_translit_pair
    adapter = Nabu::Adapters::Ogham.new
    refs = adapter.discover(FIXTURES).to_a
    ogham = adapter.parse(refs.find { |r| r.id == "urn:nabu:ogham:i-may-010" })
    translit = adapter.parse(refs.find { |r| r.id == "urn:nabu:ogham:i-may-010-translit" })
    assert_equal "ᚇᚑᚈᚐᚌᚅᚔ", ogham.first.text
    assert_equal "DOTAGNI", translit.first.text
    assert_equal ogham.first.urn.delete_prefix("urn:nabu:ogham:i-may-010"),
                 translit.first.urn.delete_prefix("urn:nabu:ogham:i-may-010-translit"),
                 "identical line suffixes — the suffix-equality alignment contract"
  end

  def test_primary_metadata_rides_the_first_layer_only
    adapter = Nabu::Adapters::Ogham.new
    refs = adapter.discover(FIXTURES).to_a
    primary = adapter.parse(refs.find { |r| r.id == "urn:nabu:ogham:i-may-010" })
    sibling = adapter.parse(refs.find { |r| r.id == "urn:nabu:ogham:i-may-010-translit" })
    assert_equal %w[https://dil.ie/12667 https://dil.ie/18492], primary.metadata["related"]
    assert_nil sibling.metadata["related"]
  end

  # --- registry ---------------------------------------------------------------

  def test_registry_row_is_disabled_manual
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ogham"]
    refute_nil entry, "ogham must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Ogham, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first sync (and the license reply)"
    assert_equal "manual", entry.sync_policy
  end
end
