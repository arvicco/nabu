# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# PerseusLatin adapter tests (P7-3). PerseusDL's canonical-latinLit is the
# structural twin of canonical-greekLit, so the adapter is the documented
# one-line SUBCLASS of Perseus (its header spells out the exact shape): only
# NAMESPACE shifts to "latinLit", flipping the manifest to perseus-latin, the
# language tag to "lat", and the edition-slug rule to perseus-lat<n>. Everything
# else — discover/parse/fetch, __cts__.xml title resolution, highest-version
# selection — is inherited unchanged and already exercised by PerseusTest, so
# this file focuses on the namespace delta plus the shared conformance suite.
#
# Fixtures: the checked-in latinLit sample (stoa0045 — Ausonius' Genethliacon,
# Cicero-era stoa content) fetched at P2-1, living under the SAME perseus/
# fixture dir as the greekLit sample. No network.
class PerseusLatinTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("perseus") # NABU_FIXTURE_DIR-aware (fixtures:check)
  LATIN_WORKDIR = File.join(FIXTURES, "latinLit")

  AUSONIUS_URN = "urn:cts:latinLit:stoa0045.stoa013.perseus-lat2"
  # P4-fallback fixtures (P9-2): legacy pre-P5 TEI, recovered by the parser's
  # P4 ladder — lb-numbered verse and a milestone-cited Livy book.
  DIRAE_CLASS_URN = "urn:cts:latinLit:phi0692.phi012.perseus-lat1"
  LIVY_URN = "urn:cts:latinLit:phi0914.phi0011.perseus-lat3"

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::PerseusLatin.new
  end

  def conformance_workdir
    LATIN_WORKDIR
  end

  def conformance_expected_source_id
    "perseus-latin"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest_is_the_latinlit_manifest
    manifest = Nabu::Adapters::PerseusLatin.manifest
    assert_equal "perseus-latin", manifest.id
    assert_equal "Perseus Digital Library — canonical Latin literature", manifest.name
    assert_equal "CC BY-SA 4.0", manifest.license
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/PerseusDL/canonical-latinLit", manifest.upstream_url
    assert_equal "epidoc", manifest.parser_family
  end

  def test_instance_manifest_agrees_with_class_manifest
    assert_equal Nabu::Adapters::PerseusLatin.manifest, Nabu::Adapters::PerseusLatin.new.manifest
  end

  # The whole point of the subclass: a distinct upstream identity from the
  # greekLit parent, resolved purely from the flipped NAMESPACE.
  def test_manifest_is_distinct_from_the_greeklit_parent
    refute_equal Nabu::Adapters::Perseus.manifest, Nabu::Adapters::PerseusLatin.manifest
  end

  # --- discover -----------------------------------------------------------

  def test_discover_finds_the_lat_editions_with_lat_language_refs
    refs = Nabu::Adapters::PerseusLatin.new.discover(LATIN_WORKDIR).to_a
    # The eng fixtures (phi1351, stoa0058) are translations: skipped with the
    # default flag. The two P4 lat fixtures are ordinary editions.
    assert_equal [DIRAE_CLASS_URN, LIVY_URN, AUSONIUS_URN], refs.map(&:id).sort

    ref = refs.find { |r| r.id == AUSONIUS_URN }
    assert_equal "perseus-latin", ref.source_id
    assert_equal "lat", ref.metadata["language"]
    assert_equal "Genethliacon ad Ausonium Nepotem", ref.metadata["title"]
    assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
    assert File.file?(ref.path), "path must exist: #{ref.path.inspect}"
  end

  def test_discover_returns_an_enumerator_without_a_block
    assert_kind_of Enumerator, Nabu::Adapters::PerseusLatin.new.discover(LATIN_WORKDIR)
  end

  # The latinLit urn namespace and the perseus-lat<n> slug rule both fall out of
  # NAMESPACE alone — assert them together on a synthetic tree so the delta is
  # pinned independently of the single checked-in edition.
  def test_discover_uses_latinlit_urns_and_skips_translations
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "phi9999", "phi001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "phi9999.phi001.perseus-lat1.xml"))
      FileUtils.touch(File.join(work, "phi9999.phi001.perseus-lat2.xml"))
      FileUtils.touch(File.join(work, "phi9999.phi001.perseus-eng2.xml"))
      FileUtils.touch(File.join(work, "phi9999.phi001.perseus-grc2.xml"))
      refs = Nabu::Adapters::PerseusLatin.new.discover(dir).to_a
      # perseus-lat2 wins (highest version); eng translation and the grc edition
      # (wrong language for this namespace) are both filtered out.
      assert_equal ["urn:cts:latinLit:phi9999.phi001.perseus-lat2"], refs.map(&:id)
    end
  end

  # --- parse --------------------------------------------------------------

  def test_parse_round_trips_the_ausonius_genethliacon
    adapter = Nabu::Adapters::PerseusLatin.new
    ref = adapter.discover(LATIN_WORKDIR).find { |r| r.id == AUSONIUS_URN }
    document = adapter.parse(ref)
    assert_equal AUSONIUS_URN, document.urn
    assert_equal "lat", document.language
    assert_equal "Genethliacon ad Ausonium Nepotem", document.title
    assert_equal 28, document.size
    assert_equal "#{AUSONIUS_URN}:1", document.first.urn
    # Opening hexameter of the Genethliacon.
    assert_equal "carmina prima tibi eum iam puerilibus annis", document.first.text
  end

  # The P4 fallback through the full adapter path (P9-2): Livy's legacy
  # book/chapter/section milestones mint, praefatio chapter included.
  def test_parse_round_trips_the_p4_livy_fixture
    adapter = Nabu::Adapters::PerseusLatin.new
    ref = adapter.discover(LATIN_WORKDIR).find { |r| r.id == LIVY_URN }
    document = adapter.parse(ref)
    assert_equal LIVY_URN, document.urn
    assert_equal "lat", document.language
    assert_equal 30, document.size
    assert_equal "#{LIVY_URN}:1.pr.1", document.first.urn
    assert_includes document.first.text, "facturusne operae pretium sim"
  end

  # --- registry round-trip ------------------------------------------------

  # enabled: false until the owner-initiated first sync, but the entry must
  # still resolve (the registry loads disabled sources too).
  def test_registry_resolves_perseus_latin_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["perseus-latin"]
    refute_nil entry, "perseus-latin must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::PerseusLatin, entry.adapter_class
    assert_equal "perseus-latin", entry.manifest.id
    assert_equal Nabu::Adapters::PerseusLatin.manifest, entry.manifest
  end

  # --- the greek sibling is unaffected ------------------------------------

  def test_greek_parent_manifest_and_namespace_are_unchanged
    assert_equal "perseus-greek", Nabu::Adapters::Perseus.manifest.id
    assert_equal "greekLit", Nabu::Adapters::Perseus::NAMESPACE
    greek = Nabu::Adapters::Perseus.new.discover(File.join(FIXTURES, "greekLit")).to_a
    assert(greek.all? { |ref| ref.id.include?(":greekLit:") }, "greek discover must stay in the greekLit namespace")
    assert(greek.all? { |ref| ref.metadata["language"] == "grc" })
  end
end
