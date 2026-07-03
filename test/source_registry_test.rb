# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class SourceRegistryTest < Minitest::Test
  include StoreTestDB

  # A resolvable adapter for the lazy-resolution and sync_source! paths. Named
  # at the top level so "FakeAdapter" resolves via Object.const_get.
  class FakeAdapter < Nabu::Adapter
    MANIFEST = Nabu::SourceManifest.new(
      id: "fake-src", name: "Fake Source", license: "CC BY 4.0",
      license_class: "attribution", upstream_url: "https://example.invalid/fake",
      parser_family: "plaintext"
    )

    def self.manifest
      MANIFEST
    end
  end

  # -- parsing -------------------------------------------------------------

  def test_parses_entry_with_all_fields
    registry = load_registry(<<~YAML)
      perseus-greek:
        adapter: Nabu::Adapters::Perseus
        enabled: true
        sync_policy: live
    YAML

    entry = registry["perseus-greek"]
    assert_equal "perseus-greek", entry.slug
    assert_equal "Nabu::Adapters::Perseus", entry.adapter_class_name
    assert entry.enabled
    assert_equal "live", entry.sync_policy
    assert_equal %w[perseus-greek], registry.slugs
    assert_equal 1, registry.size
    refute_predicate registry, :empty?
  end

  def test_defaults_enabled_false_and_sync_policy_manual
    registry = load_registry(<<~YAML)
      minimal-src:
        adapter: Some::Adapter
    YAML

    entry = registry["minimal-src"]
    refute entry.enabled
    assert_equal "manual", entry.sync_policy
  end

  def test_each_source_yields_every_entry
    registry = load_registry(<<~YAML)
      a-src:
        adapter: A
      b-src:
        adapter: B
    YAML

    assert_equal %w[a-src b-src], registry.each_source.map(&:slug).sort
  end

  # -- empty / missing -----------------------------------------------------

  def test_missing_file_is_empty_valid_registry
    Dir.mktmpdir do |dir|
      registry = Nabu::SourceRegistry.load(File.join(dir, "does-not-exist.yml"))
      assert_predicate registry, :empty?
      assert_equal 0, registry.size
    end
  end

  def test_comments_only_file_is_empty_valid_registry
    registry = load_registry("# only comments here\n")
    assert_predicate registry, :empty?
  end

  # -- validation ----------------------------------------------------------

  def test_bad_slug_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        Bad Slug:
          adapter: A
      YAML
    end
    assert_match(/Bad Slug/, error.message)
    assert_match(/slug/, error.message)
  end

  def test_bad_sync_policy_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src:
          adapter: A
          sync_policy: weekly
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/sync_policy/, error.message)
  end

  def test_non_hash_entry_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src: just-a-string
      YAML
    end
    assert_match(/my-src/, error.message)
  end

  def test_missing_adapter_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src:
          enabled: true
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/adapter/, error.message)
  end

  def test_non_boolean_enabled_raises_naming_the_slug
    error = assert_raises(Nabu::ValidationError) do
      load_registry(<<~YAML)
        my-src:
          adapter: A
          enabled: yesplease
      YAML
    end
    assert_match(/my-src/, error.message)
    assert_match(/enabled/, error.message)
  end

  def test_top_level_non_mapping_raises
    assert_raises(Nabu::ValidationError) do
      load_registry("- just\n- a\n- list\n")
    end
  end

  # -- lazy adapter resolution --------------------------------------------

  def test_unknown_adapter_class_is_lazy
    # Loading succeeds even though the class does not exist...
    registry = load_registry(<<~YAML)
      ghost-src:
        adapter: Nabu::Adapters::DoesNotExist
    YAML
    entry = registry["ghost-src"]

    # ...the error only surfaces on resolution, and names class + source.
    error = assert_raises(Nabu::ValidationError) { entry.adapter_class }
    assert_match(/unknown adapter class/, error.message)
    assert_match(/Nabu::Adapters::DoesNotExist/, error.message)
    assert_match(/ghost-src/, error.message)
  end

  def test_adapter_class_and_manifest_resolve_for_real_adapter
    entry = load_registry(<<~YAML)["fake-src"]
      fake-src:
        adapter: SourceRegistryTest::FakeAdapter
    YAML

    assert_equal FakeAdapter, entry.adapter_class
    assert_equal "Fake Source", entry.manifest.name
  end

  # -- sync_source! --------------------------------------------------------

  def test_sync_source_creates_row_from_manifest
    db = store_test_db
    entry = load_registry(<<~YAML)["fake-src"]
      fake-src:
        adapter: SourceRegistryTest::FakeAdapter
        enabled: true
    YAML

    source = entry.sync_source!(db)
    assert_equal "fake-src", source.slug
    assert_equal "Fake Source", source.name
    assert_equal "SourceRegistryTest::FakeAdapter", source.adapter_class
    assert_equal "CC BY 4.0", source.license
    assert_equal "attribution", source.license_class
    assert_equal "https://example.invalid/fake", source.upstream_url
    assert source.enabled, "enabled seeds from the registry entry on create"
  end

  def test_sync_source_preserves_runtime_state_on_update
    db = store_test_db
    Nabu::Store::Source.create(
      slug: "fake-src", name: "STALE NAME", adapter_class: "Stale",
      license_class: "restricted", enabled: true, last_sync_sha: "deadbeef"
    )
    entry = load_registry(<<~YAML)["fake-src"]
      fake-src:
        adapter: SourceRegistryTest::FakeAdapter
        enabled: false
    YAML

    source = entry.sync_source!(db)
    # metadata refreshed from the manifest...
    assert_equal "Fake Source", source.name
    assert_equal "attribution", source.license_class
    # ...runtime state (db-owned) preserved.
    assert source.enabled, "existing enabled must not be clobbered by the entry"
    assert_equal "deadbeef", source.last_sync_sha
    assert_equal 1, Nabu::Store::Source.count
  end

  private

  def load_registry(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sources.yml")
      File.write(path, yaml)
      return Nabu::SourceRegistry.load(path)
    end
  end
end
