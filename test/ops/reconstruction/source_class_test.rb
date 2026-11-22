# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "nabu/ops/reconstruction/source_class"

# The reconstruction-class guard: every registered source answers "how would
# this source's canonical asset come back if canonical/ were lost, with no
# backup?" with exactly one known class — so no source can ever be
# unclassifiable. Runs against the REAL config/sources/ (the registry
# census pattern of test/docs/manual_acquisition_docs_test.rb).
class ReconstructionSourceClassTest < Minitest::Test
  SourceClass = Nabu::Ops::Reconstruction::SourceClass
  ROOT = Nabu::Config::PROJECT_ROOT
  SOURCES_PATH = File.join(ROOT, "config", "sources")
  MANUAL_DIR = File.join(ROOT, "docs", "manual")

  def setup
    @tmp = Dir.mktmpdir("nabu-reconstruction")
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  # No local/ and no canonical/ at all: the public-clone shape.
  def classifier(sources_path: SOURCES_PATH, grants_path: nil, canonical_dir: nil)
    SourceClass.new(sources_path: sources_path, manual_dir: MANUAL_DIR,
                    grants_path: grants_path || File.join(@tmp, "absent", "grants.yml"),
                    canonical_dir: canonical_dir || File.join(@tmp, "absent-canonical"))
  end

  def write_grants(*slugs)
    path = File.join(@tmp, "grants.yml")
    File.write(path, YAML.dump("grants" => slugs.map { |slug| { "source" => slug, "how" => "flag" } }))
    path
  end

  def write_sources(rows)
    path = File.join(@tmp, "sources.yml")
    File.write(path, YAML.dump(rows))
    path
  end

  # THE COVERAGE GUARD.
  def test_every_registered_source_resolves_to_exactly_one_known_class
    verdicts = classifier.verdicts
    registry = Nabu::SourceRegistry.load(SOURCES_PATH)

    assert_equal registry.slugs.sort, verdicts.map(&:slug).sort
    verdicts.each do |verdict|
      assert_includes SourceClass::CLASSES, verdict.klass, "#{verdict.slug}: unknown class #{verdict.klass.inspect}"
    end
  end

  def test_rail_sources_resolve_rail_paced
    %w[wellcome ndl-kotenseki].each do |slug|
      assert_equal :rail_paced, classifier.classify(slug).klass, slug
    end
  end

  def test_a_manual_doc_source_resolves_manual
    assert_equal :manual, classifier.classify("sillok").klass
  end

  def test_a_non_source_manual_doc_never_matches
    refute_includes classifier.verdicts.map(&:slug), "embed-venv"
  end

  def test_granted_wins_over_manual
    # aclt carries a docs/manual recipe AND, on a granted box, a grant row.
    assert_equal :manual, classifier.classify("aclt").klass
    assert_equal :granted, classifier(grants_path: write_grants("aclt")).classify("aclt").klass
  end

  def test_a_research_private_source_without_a_recipe_resolves_restricted
    verdict = classifier.classify("seal")

    assert_equal :restricted, verdict.klass
  end

  def test_a_plain_public_source_resolves_public_stable
    assert_equal :public_stable, classifier.classify("perseus-greek").klass
  end

  def test_absent_grants_file_never_yields_granted
    refute_includes classifier.verdicts.map(&:klass), :granted
  end

  def test_attic_flag_requires_a_non_empty_attic
    canonical = File.join(@tmp, "canonical")
    FileUtils.mkdir_p(File.join(canonical, "perseus-greek", ".attic", "data"))
    File.write(File.join(canonical, "perseus-greek", ".attic", "data", "gone.xml"), "<TEI/>")
    FileUtils.mkdir_p(File.join(canonical, "perseus-latin", ".attic"))

    classes = classifier(canonical_dir: canonical)

    assert classes.classify("perseus-greek").attic
    refute classes.classify("perseus-latin").attic, "an empty attic holds no backup-only bytes"
    refute classifier.classify("perseus-greek").attic, "absent canonical/ degrades to attic: false"
  end

  def test_census_counts_every_class_and_lists_the_attic
    canonical = File.join(@tmp, "canonical")
    FileUtils.mkdir_p(File.join(canonical, "cbeta", ".attic"))
    File.write(File.join(canonical, "cbeta", ".attic", "x"), "x")

    census = classifier(canonical_dir: canonical).census

    assert_equal SourceClass::CLASSES.sort, census[:counts].keys.sort
    assert_equal Nabu::SourceRegistry.load(SOURCES_PATH).size, census[:counts].values.sum
    assert_equal ["cbeta"], census[:attic]
  end

  def test_an_override_replaces_the_computed_class
    path = write_sources("wellcome" => { "adapter" => "Nabu::Adapters::Wellcome", "wired" => false,
                                         "reconstruct" => "manual" })
    verdict = classifier(sources_path: path).classify("wellcome")

    assert_equal :manual, verdict.klass
    assert_equal :rail_paced, verdict.computed
  end

  def test_an_unknown_override_value_fails
    path = write_sources("wellcome" => { "adapter" => "Nabu::Adapters::Wellcome", "wired" => false,
                                         "reconstruct" => "carrier_pigeon" })
    error = assert_raises(Nabu::ValidationError) { classifier(sources_path: path).verdicts }
    assert_match(/carrier_pigeon/, error.message)
  end

  def test_an_override_with_no_effect_fails
    path = write_sources("wellcome" => { "adapter" => "Nabu::Adapters::Wellcome", "wired" => false,
                                         "reconstruct" => "rail_paced" })
    error = assert_raises(Nabu::ValidationError) { classifier(sources_path: path).verdicts }
    assert_match(/no effect/, error.message)
  end

  def test_the_real_registry_overrides_all_validate
    classifier.verdicts.each { |verdict| assert_kind_of Symbol, verdict.computed }
  end

  def test_render_prints_counts_attic_and_local_inventory
    local = File.join(@tmp, "local")
    FileUtils.mkdir_p(File.join(local, "config"))
    census = { counts: SourceClass::CLASSES.to_h { |klass| [klass, 1] }, attic: %w[cbeta] }

    text = SourceClass.render(census, local_dir: local)

    SourceClass::CLASSES.each { |klass| assert_includes text, klass.to_s }
    assert_includes text, "cbeta"
    assert_match(%r{config/\s+present}, text)
    assert_match(%r{shelves/\s+absent}, text)
    assert_includes text, "mined-links.sqlite3"
  end
end
