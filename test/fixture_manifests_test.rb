# frozen_string_literal: true

require "test_helper"

# Manifest presence & validity for every real-source fixture directory (P5-4).
# Iterates test/fixtures/*/ (skipping the synthetic conformance rig, which has
# no README.md), and asserts each real source ships a parseable manifest whose
# listed files exist on disk — and vice versa (no orphan fixtures). This doubles
# as the completeness check the packet calls for.
class FixtureManifestsTest < Minitest::Test
  FIXTURES_ROOT = File.expand_path("fixtures", __dir__)
  EXPECTED = %w[perseus first1k ud proiel torot ddbdp papyri-ddbdp].freeze

  def real_source_dirs
    Dir.children(FIXTURES_ROOT).select do |name|
      dir = File.join(FIXTURES_ROOT, name)
      File.directory?(dir) && File.file?(File.join(dir, "README.md"))
    end.sort
  end

  def test_all_expected_sources_are_real_source_dirs_with_a_manifest
    dirs = real_source_dirs
    EXPECTED.each do |source|
      assert_includes dirs, source, "expected fixture source #{source} missing"
      assert File.file?(File.join(FIXTURES_ROOT, source, "manifest.yml")), "#{source} lacks manifest.yml"
    end
  end

  def test_each_manifest_parses_and_lists_only_files_that_exist_on_disk
    sentinel = Nabu::FixtureSentinel.new
    real_source_dirs.each do |name|
      manifest = sentinel.load_manifest(name)
      assert_equal name, manifest.source, "#{name}: manifest `source` must match its directory"
      refute_empty manifest.entries, "#{name}: manifest lists no files"
      manifest.entries.each do |entry|
        assert File.file?(manifest.file_path(entry)), "#{name}: #{entry.path} listed but missing on disk"
        if entry.refetchable?
          refute_nil entry.url, "#{name}: #{entry.path} is refetchable but records no url"
        else
          refute_nil entry.reason, "#{name}: #{entry.path} is non-refetchable but records no reason"
        end
      end
    end
  end

  def test_no_orphan_fixture_files_go_unlisted
    sentinel = Nabu::FixtureSentinel.new
    real_source_dirs.each do |name|
      manifest = sentinel.load_manifest(name)
      dir = File.join(FIXTURES_ROOT, name)
      on_disk = Dir.glob("**/*", base: dir)
                   .select { |rel| File.file?(File.join(dir, rel)) } - %w[README.md manifest.yml]
      assert_equal on_disk.sort, manifest.entries.map(&:path).sort,
                   "#{name}: manifest file list and on-disk fixtures differ"
    end
  end

  def test_papyri_ddbdp_entries_are_local_trim_and_non_refetchable
    manifest = Nabu::FixtureSentinel.new.load_manifest("papyri-ddbdp")
    manifest.entries.each do |entry|
      refute entry.refetchable?, "#{entry.path} must be non-refetchable (local-trim)"
      assert_equal "local-trim", entry.provenance
    end
  end
end
