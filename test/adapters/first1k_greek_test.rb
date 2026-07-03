# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# First1KGreek adapter tests (P3-2). OpenGreekAndLatin's First1KGreek ships the
# same CapiTainS/EpiDoc layout as PerseusDL, so the adapter is a thin SUBCLASS
# of Perseus (reusing discover/parse/fetch machinery wholesale) that overrides
# only the manifest and the original-language edition-slug acceptance rule.
#
# The distinguishing upstream fact: edition slugs are NOT uniformly
# `1st1K-grcN`. The same corpus mixes `opp-grcN`, `perseus-grcN`, etc., so the
# slug matcher accepts ANY `*-grcN[a-z]?` tail rather than a single family.
#
# Includes the shared AdapterConformance suite against the checked-in greekLit
# fixtures (P3-1). No network.
class First1kGreekTest < Minitest::Test
  include AdapterConformance

  FIXTURES = File.expand_path("../fixtures/first1k", __dir__)
  GREEK_WORKDIR = File.join(FIXTURES, "greekLit")

  # The three fixture editions prove BOTH slug families are accepted: two
  # `1st1K-grc1` and one `opp-grc1`.
  SEIKILOS_URN = "urn:cts:greekLit:tlg2139.tlg001.1st1K-grc1"
  ANUBION_URN = "urn:cts:greekLit:tlg1126.tlg003.1st1K-grc1"
  METHODIUS_URN = "urn:cts:greekLit:tlg2959.tlg008.opp-grc1"

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::First1kGreek.new
  end

  def conformance_workdir
    GREEK_WORKDIR
  end

  def conformance_expected_source_id
    "first1k-greek"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest_identifies_the_first1k_greek_source
    manifest = Nabu::Adapters::First1kGreek.manifest
    assert_equal "first1k-greek", manifest.id
    assert_equal "Open Greek and Latin — First1KGreek", manifest.name
    assert_equal "CC BY-SA 4.0", manifest.license
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/OpenGreekAndLatin/First1KGreek", manifest.upstream_url
    assert_equal "epidoc", manifest.parser_family
  end

  def test_instance_manifest_agrees_with_class_manifest
    assert_equal Nabu::Adapters::First1kGreek.manifest, Nabu::Adapters::First1kGreek.new.manifest
  end

  def test_manifest_is_distinct_from_perseus
    refute_equal Nabu::Adapters::Perseus.manifest, Nabu::Adapters::First1kGreek.manifest
  end

  # --- discover -----------------------------------------------------------

  def test_discover_finds_exactly_the_three_fixture_editions_across_slug_families
    refs = Nabu::Adapters::First1kGreek.new.discover(GREEK_WORKDIR).to_a
    assert_equal [ANUBION_URN, SEIKILOS_URN, METHODIUS_URN], refs.map(&:id).sort
  end

  def test_discover_sets_source_id_language_and_absolute_path
    refs = Nabu::Adapters::First1kGreek.new.discover(GREEK_WORKDIR).to_a
    refs.each do |ref|
      assert_equal "first1k-greek", ref.source_id
      assert_equal "grc", ref.metadata["language"]
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path), "path must exist: #{ref.path.inspect}"
    end
  end

  def test_discover_resolves_titles_from_cts_metadata
    titles = Nabu::Adapters::First1kGreek.new.discover(GREEK_WORKDIR).to_a.to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Sicili Epitaphium", titles.fetch(SEIKILOS_URN)
    assert_equal "Fragmenta", titles.fetch(ANUBION_URN)
    assert_equal "De Martyribus (Fragmenta)", titles.fetch(METHODIUS_URN)
  end

  def test_discover_returns_an_enumerator_without_a_block
    assert_kind_of Enumerator, Nabu::Adapters::First1kGreek.new.discover(GREEK_WORKDIR)
  end

  # Accept any `*-grcN` slug family, still one edition per work.
  def test_discover_accepts_perseus_and_opp_slug_families_in_first1k
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-grc1.xml"))
      other = File.join(dir, "data", "tlg9999", "tlg002")
      FileUtils.mkdir_p(other)
      FileUtils.touch(File.join(other, "tlg9999.tlg002.opp-grc3.xml"))
      refs = Nabu::Adapters::First1kGreek.new.discover(dir).to_a
      assert_equal ["urn:cts:greekLit:tlg9999.tlg001.perseus-grc1",
                    "urn:cts:greekLit:tlg9999.tlg002.opp-grc3"], refs.map(&:id).sort
    end
  end

  def test_discover_skips_non_greek_editions_and_translations
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.1st1K-grc1.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.1st1K-eng1.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.1st1K-eng1a.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.opp-lat1.xml"))
      refs = Nabu::Adapters::First1kGreek.new.discover(dir).to_a
      assert_equal ["urn:cts:greekLit:tlg9999.tlg001.1st1K-grc1"], refs.map(&:id)
    end
  end

  # Version-preference rule (P3-2, documented): numeric part ascending, then a
  # letter suffix ascending. So grc1 < grc2 < grc2a — grc2a wins. The families
  # may differ (opp- vs 1st1K-); only the -grc<version> tail decides.
  def test_discover_prefers_highest_version_with_letter_suffix_winning
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.1st1K-grc1.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.1st1K-grc2.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.opp-grc2a.xml"))
      refs = Nabu::Adapters::First1kGreek.new.discover(dir).to_a
      assert_equal ["urn:cts:greekLit:tlg9999.tlg001.opp-grc2a"], refs.map(&:id)
    end
  end

  # --- parse --------------------------------------------------------------

  def test_parse_round_trips_the_seikilos_epitaph
    adapter = Nabu::Adapters::First1kGreek.new
    ref = adapter.discover(GREEK_WORKDIR).find { |r| r.id == SEIKILOS_URN }
    document = adapter.parse(ref)
    assert_equal SEIKILOS_URN, document.urn
    assert_equal "grc", document.language
    assert_equal "Sicili Epitaphium", document.title
    assert_equal "#{SEIKILOS_URN}:1", document.first.urn
    # Distinctive phrase from the famous Seikilos epitaph.
    assert_includes document.first.text, "Σείκιλος"
  end

  # tlg1126 cites at a single level whose unit name is "work" (subtype="work"),
  # exercising the refsDecl-driven citation path against a non-"section" unit.
  def test_parse_round_trips_the_subtype_work_variant
    adapter = Nabu::Adapters::First1kGreek.new
    ref = adapter.discover(GREEK_WORKDIR).find { |r| r.id == ANUBION_URN }
    document = adapter.parse(ref)
    assert_equal ANUBION_URN, document.urn
    assert_equal "#{ANUBION_URN}:1", document.first.urn
    assert_includes document.first.text, "Ἀννουβίων"
  end

  # --- registry round-trip ------------------------------------------------

  def test_registry_resolves_first1k_greek_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["first1k-greek"]
    refute_nil entry, "first1k-greek must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::First1kGreek, entry.adapter_class
    assert_equal "first1k-greek", entry.manifest.id
    assert_equal Nabu::Adapters::First1kGreek.manifest, entry.manifest
  end
end
