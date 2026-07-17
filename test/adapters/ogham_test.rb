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

  # P19-4 marker-driven override (the local-library precedent): a stone with
  # NO citable layer at all is catalogued metadata-only, never quarantined.
  def conformance_metadata_only?(document)
    document.metadata["text_layer"] == "none"
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
    # The P25-0/P25-1 reconciled seam: reference_producer returns the
    # producer OBJECT (corph ships its own class); concordance sources ride
    # LibraryReferences constructed with their own producer name.
    producer = Nabu::Adapters::Ogham.reference_producer(catalog: nil, journal: nil)
    assert_instance_of Nabu::LibraryReferences, producer
    assert_equal "ogham", producer.producer
  end

  def test_fetch_is_the_git_path
    assert_equal :git, Nabu::Adapters::Ogham.remote_probe_strategy
    assert_equal ["https://github.com/lguariento/og-h-am"], Nabu::Adapters::Ogham.upstream_repo_urls
  end

  # --- discover: layer siblings ----------------------------------------------

  def test_discover_mints_layer_documents_ogham_bare_siblings_suffixed
    refs = Nabu::Adapters::Ogham.new.discover(FIXTURES).to_a
    assert_equal %w[
      urn:nabu:ogham:e-con-x01
      urn:nabu:ogham:e-con-x03-roman
      urn:nabu:ogham:e-dev-001 urn:nabu:ogham:e-dev-001-roman urn:nabu:ogham:e-dev-001-translit
      urn:nabu:ogham:e-sts-001
      urn:nabu:ogham:i-cor-l11
      urn:nabu:ogham:i-may-010 urn:nabu:ogham:i-may-010-translit
      urn:nabu:ogham:i-wat-042 urn:nabu:ogham:i-wat-042-translit
      urn:nabu:ogham:s-she-001 urn:nabu:ogham:s-she-001-translit
    ], refs.map(&:id), "empty layers mint no layer document; all-empty stones " \
                       "(E-CON-X01, E-STS-001, I-COR-L11) mint ONE metadata-only bare-urn ref; " \
                       "E-CON-X03 has no ogham layer, so -roman is its only document"
  end

  def test_discover_marks_exactly_one_primary_per_record
    refs = Nabu::Adapters::Ogham.new.discover(FIXTURES).to_a
    primaries = refs.select { |ref| ref.metadata["primary"] }
    assert_equal %w[
      urn:nabu:ogham:e-con-x03-roman urn:nabu:ogham:e-dev-001 urn:nabu:ogham:i-may-010
      urn:nabu:ogham:i-wat-042 urn:nabu:ogham:s-she-001
    ], primaries.map(&:id).sort, "the record's FIRST citable layer carries the stone-grain metadata"
    layer_refs = refs.reject { |ref| ref.metadata["kind"] == "metadata_only" }
    assert(layer_refs.all? { |ref| ref.metadata["chardecl"]&.end_with?("charDecl.xml") })
  end

  # P25-3 hotfix regression (the 195-noise-quarantine shape): a DECLARED but
  # empty edition layer (E-STS-001's <ab><lb n="1"/></ab> under an open div —
  # not self-closed, so the old byte peek minted it) is an honest absence.
  # No layer document mints; the never-encoded stone is catalogued
  # metadata-only instead (the local-library text_layer:none precedent).
  def test_declared_but_empty_layers_mint_no_layer_refs
    refs = Nabu::Adapters::Ogham.new.discover(FIXTURES).to_a
    ids = refs.map(&:id)
    refute_includes ids, "urn:nabu:ogham:e-sts-001-translit",
                    "an empty transliteration layer must not mint a ref the parser cannot fill"
    ref = refs.find { |r| r.id == "urn:nabu:ogham:e-sts-001" }
    assert_equal "metadata_only", ref.metadata["kind"],
                 "the stone itself stays catalogued — metadata-only, never quarantined"
  end

  # P25-3 hotfix regression (the commented-out shape): E-CON-X01's edition
  # divs live inside <!-- --> — the old raw-byte peek saw them, the DOM
  # honestly does not. No layer refs; the stone is metadata-only.
  def test_commented_out_edition_divs_are_invisible_to_discovery
    refs = Nabu::Adapters::Ogham.new.discover(FIXTURES).to_a
    e_con_x01 = refs.select { |r| r.path.end_with?("E-CON-X01.xml") }
    assert_equal ["urn:nabu:ogham:e-con-x01"], e_con_x01.map(&:id)
    assert_equal "metadata_only", e_con_x01.first.metadata["kind"]
  end

  def test_parse_metadata_only_stone_is_catalogued_never_quarantined
    adapter = Nabu::Adapters::Ogham.new
    refs = adapter.discover(FIXTURES).to_a
    document = adapter.parse(refs.find { |r| r.id == "urn:nabu:ogham:e-con-x01" })
    assert_predicate document, :empty?, "no citable text anywhere — zero passages, honestly"
    assert_equal "none", document.metadata["text_layer"], "the local-library metadata-only marker"
    assert_equal "und", document.language, "upstream removed textLang (\"no text\") — honest und"
    assert_equal "Lewannick 3", document.title
    assert_equal "Cornwall", document.metadata.dig("place", "county")
    assert_equal "LWNCC/1", document.metadata["cisp"]
    # E-STS-001 keeps its declared textLang on the metadata-only document.
    sts = adapter.parse(refs.find { |r| r.id == "urn:nabu:ogham:e-sts-001" })
    assert_equal "pgl-Ogam", sts.language
    assert_equal "none", sts.metadata["text_layer"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Ogham.new.discover(dir).to_a
    end
  end

  # --- discovery census -------------------------------------------------------

  def test_discovery_skips_count_empty_layers_by_rule
    skips = Nabu::Adapters::Ogham.new.discovery_skips(FIXTURES)
    assert_equal 4, skips.skipped_by_rule,
                 "I-COR-L11's two self-closed + E-STS-001's two declared-but-empty edition divs " \
                 "(E-CON-X01's commented-out divs are invisible to the DOM, counted nowhere)"
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
    assert entry.enabled, "live (owner sign-off 2026-07-18: 834 docs, flipped; still nc pending registry #14)"
    assert_equal "manual", entry.sync_policy
  end
end
