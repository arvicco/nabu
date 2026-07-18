# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Itant adapter tests (P29-2): discovery over the two corpus dirs (layer +
# translation siblings, the metadata-only lost inscription), the TM/ImIt
# reference-edge capability, and the registry row. Includes the shared
# AdapterConformance suite; fixtures are whole real records
# (test/fixtures/itant/README.md).
class ItantTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("itant")

  def conformance_adapter
    # translations: true — the registry row's posture; the -ita/-eng
    # siblings must pass conformance too.
    Nabu::Adapters::Itant.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "itant"
  end

  # The ten lost inscriptions are catalogued with zero passages (ogham
  # text_layer:none precedent) — marker-driven, never blanket.
  def conformance_metadata_only?(document)
    document.metadata["text_layer"] == "none"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_quotes_the_three_agreeing_grant_layers
    manifest = Nabu::Adapters::Itant.manifest
    assert_equal "itant", manifest.id
    assert_equal "nc", manifest.license_class
    assert_match(/CC BY-NC-SA 4\.0/, manifest.license)
    assert_match(/This file is licensed under the Creative Commons/, manifest.license,
                 "the per-record in-file grant travels verbatim")
    assert_match(/Murano/, manifest.license, "the JOCCH citation request travels with the grant")
    assert_equal "itant-epidoc", manifest.parser_family
  end

  def test_fetch_is_the_git_path
    assert_equal :git, Nabu::Adapters::Itant.remote_probe_strategy
    assert_equal ["https://github.com/DigItAnt/Corpus_ItAnt"], Nabu::Adapters::Itant.upstream_repo_urls
  end

  def test_reference_edges_capability_names_its_own_producer
    assert Nabu::Adapters::Itant.reference_edges?
    producer = Nabu::Adapters::Itant.reference_producer(catalog: nil, journal: nil)
    assert_instance_of Nabu::LibraryReferences, producer
    assert_equal "itant", producer.producer
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_layer_and_translation_siblings
    refs = Nabu::Adapters::Itant.new(translations: true).discover(FIXTURES).to_a
    assert_equal %w[
      urn:nabu:itant:lepontic-1 urn:nabu:itant:lepontic-1-dipl
      urn:nabu:itant:lepontic-1-eng urn:nabu:itant:lepontic-1-ita
      urn:nabu:itant:oscan-2 urn:nabu:itant:oscan-2-eng urn:nabu:itant:oscan-2-ita
      urn:nabu:itant:oscan-492 urn:nabu:itant:oscan-492-eng urn:nabu:itant:oscan-492-ita
      urn:nabu:itant:oscan-576
    ], refs.map(&:id),
                 "the -dipl sibling exactly where the parser's own census finds a diplomatic " \
                 "layer (the 9 Lepontic records); -ita/-eng exactly where translation prose " \
                 "exists; the lost inscription mints its bare metadata-only ref"
  end

  def test_discover_without_translations_is_editions_only
    refs = Nabu::Adapters::Itant.new.discover(FIXTURES).to_a
    assert_equal %w[
      urn:nabu:itant:lepontic-1 urn:nabu:itant:lepontic-1-dipl
      urn:nabu:itant:oscan-2 urn:nabu:itant:oscan-492 urn:nabu:itant:oscan-576
    ], refs.map(&:id)
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Itant.new(translations: true).discover(dir).to_a
    end
  end

  def test_the_lost_inscription_ref_is_marked_metadata_only
    refs = Nabu::Adapters::Itant.new.discover(FIXTURES).to_a
    ref = refs.find { |candidate| candidate.id == "urn:nabu:itant:oscan-576" }
    assert_equal "metadata_only", ref.metadata["kind"]
    document = Nabu::Adapters::Itant.new.parse(ref)
    assert_equal 0, document.size, "catalogued, never quarantined"
    assert_equal "none", document.metadata["text_layer"]
  end

  # --- the translation siblings ----------------------------------------------

  def test_parse_ita_sibling_mints_italian_passages_cited_by_textpart
    adapter = Nabu::Adapters::Itant.new(translations: true)
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:itant:lepontic-1-ita" }
    document = adapter.parse(ref)
    assert_equal "ita", document.language
    assert_equal({ "kind" => "translation" }, document.metadata)
    assert_match(/ — Italian translation\z/, document.title)
    assert_equal %w[urn:nabu:itant:lepontic-1-ita:text_A urn:nabu:itant:lepontic-1-ita:text_B],
                 document.map(&:urn)
    assert_match(/Pala per Kuaśu/, document.first.text)
  end

  def test_parse_eng_sibling_mints_english_passages
    adapter = Nabu::Adapters::Itant.new(translations: true)
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:itant:oscan-2-eng" }
    document = adapter.parse(ref)
    assert_equal "eng", document.language
    assert_equal ["urn:nabu:itant:oscan-2-eng:t1"], document.map(&:urn)
    assert_match(/Pacius Helvius son of Trebius/, document.first.text)
  end

  # --- registry ---------------------------------------------------------------

  def test_registry_row_is_disabled_manual_with_translations
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["itant"]
    refute_nil entry, "itant must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Itant, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first sync is eyeballed (checklist §6)"
    assert_equal "manual", entry.sync_policy
    assert entry.translations, "-ita/-eng siblings ride the registry flag"
  end
end
