# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

class AdapterTest < Minitest::Test
  # A subclass that implements nothing: every contract method must refuse
  # loudly, naming the adapter class and the missing method.
  class BareAdapter < Nabu::Adapter; end

  class ManifestOnlyAdapter < Nabu::Adapter
    MANIFEST = Nabu::SourceManifest.new(
      id: "manifest_only",
      name: "Manifest-only Adapter",
      license: "CC0 1.0",
      license_class: "open",
      upstream_url: "https://example.invalid/manifest_only",
      parser_family: "plaintext"
    )

    def self.manifest
      MANIFEST
    end
  end

  def test_class_manifest_raises_not_implemented_naming_class_and_method
    error = assert_raises(NotImplementedError) { BareAdapter.manifest }
    assert_match(/AdapterTest::BareAdapter/, error.message)
    assert_match(/manifest/, error.message)
  end

  def test_fetch_raises_not_implemented_naming_class_and_method
    error = assert_raises(NotImplementedError) { BareAdapter.new.fetch("canonical/bare") }
    assert_match(/AdapterTest::BareAdapter/, error.message)
    assert_match(/fetch/, error.message)
  end

  def test_discover_raises_not_implemented_naming_class_and_method
    error = assert_raises(NotImplementedError) { BareAdapter.new.discover("canonical/bare") }
    assert_match(/AdapterTest::BareAdapter/, error.message)
    assert_match(/discover/, error.message)
  end

  def test_parse_raises_not_implemented_naming_class_and_method
    ref = Nabu::DocumentRef.new(source_id: "bare", id: "doc.txt", path: "canonical/bare/doc.txt")
    error = assert_raises(NotImplementedError) { BareAdapter.new.parse(ref) }
    assert_match(/AdapterTest::BareAdapter/, error.message)
    assert_match(/parse/, error.message)
  end

  def test_instance_manifest_delegates_to_class_manifest
    assert_same ManifestOnlyAdapter.manifest, ManifestOnlyAdapter.new.manifest
  end

  def test_instance_manifest_raises_when_class_manifest_is_not_implemented
    error = assert_raises(NotImplementedError) { BareAdapter.new.manifest }
    assert_match(/AdapterTest::BareAdapter/, error.message)
  end

  # --- attic discovery (P5-2) ---------------------------------------------
  #
  # Attic knowledge lives HERE, once: adapters implement only #discover and
  # inherit retention. discover_with_attic runs the adapter's own discover
  # against <workdir>/.attic (relative paths preserved by GitFetch, so the
  # adapter sees the same shapes) and flags the refs retained.

  def with_attic_workdir
    Dir.mktmpdir do |workdir|
      write(workdir, "alpha.txt", "Alpha\nμῆνιν\n")
      write(workdir, ".attic/ghost.txt", "Ghost\nεἴδωλον\n")
      write(workdir, ".attic/.attic.json", JSON.generate("ghost.txt" => "cafe1234"))
      yield workdir
    end
  end

  def test_discover_with_attic_yields_live_refs_plus_retained_attic_refs
    with_attic_workdir do |workdir|
      refs = TestAdapter.new.discover_with_attic(workdir).to_a

      assert_equal ["urn:nabu:test_adapter:alpha", "urn:nabu:test_adapter:ghost"], refs.map(&:id).sort
      alpha, ghost = refs.sort_by(&:id)
      assert_nil alpha.metadata["retained"], "live refs carry no retention marker"
      assert_equal true, ghost.metadata["retained"]
      assert_equal "cafe1234", ghost.metadata["retired_sha"],
                   "the attic manifest supplies the upstream sha the file vanished at"
      assert_includes ghost.path, "/.attic/"
      # The conformance identity holds for attic refs too: ref.id IS the urn.
      assert_equal ghost.id, TestAdapter.new.parse(ghost).urn
    end
  end

  def test_discover_with_attic_without_manifest_still_marks_retained
    Dir.mktmpdir do |workdir|
      write(workdir, ".attic/ghost.txt", "Ghost\nεἴδωλον\n")
      write(workdir, "alpha.txt", "Alpha\nμῆνιν\n")

      ghost = TestAdapter.new.discover_with_attic(workdir).find { |ref| ref.id.end_with?("ghost") }
      assert_equal true, ghost.metadata["retained"]
      refute ghost.metadata.key?("retired_sha"), "no manifest → journal without sha"
    end
  end

  def test_discover_with_attic_live_beats_attic_and_reports_superseded
    with_attic_workdir do |workdir|
      write(workdir, ".attic/alpha.txt", "Alpha (stale attic copy)\nμῆνιν\n")

      superseded = []
      refs = TestAdapter.new.discover_with_attic(workdir, on_superseded: ->(ref) { superseded << ref }).to_a

      assert_equal ["urn:nabu:test_adapter:alpha", "urn:nabu:test_adapter:ghost"], refs.map(&:id).sort
      alpha = refs.find { |ref| ref.id.end_with?("alpha") }
      refute_includes alpha.path, "/.attic/", "the live copy wins"
      assert_equal ["urn:nabu:test_adapter:alpha"], superseded.map(&:id)
      assert_includes superseded.first.path, "/.attic/"
    end
  end

  def test_discover_with_attic_without_an_attic_matches_discover
    Dir.mktmpdir do |workdir|
      write(workdir, "alpha.txt", "Alpha\nμῆνιν\n")
      adapter = TestAdapter.new

      assert_equal adapter.discover(workdir).to_a, adapter.discover_with_attic(workdir).to_a
    end
  end

  def test_discover_with_attic_returns_an_enumerator_without_a_block
    with_attic_workdir do |workdir|
      enum = TestAdapter.new.discover_with_attic(workdir)
      assert_kind_of Enumerator, enum
      assert_equal 2, enum.count
    end
  end

  # --- the mass-deletion guard (P5-2) --------------------------------------

  def test_guard_mass_deletion_trips_over_the_threshold_and_force_overrides
    Dir.mktmpdir do |workdir|
      %w[a b c d e].each { |slug| write(workdir, "#{slug}.txt", "Doc #{slug}\nτι\n") }
      adapter = TestAdapter.new
      doomed = %w[a b].map { |slug| File.expand_path(File.join(workdir, "#{slug}.txt")) }

      error = assert_raises(Nabu::SyncAborted) do
        adapter.send(:guard_mass_deletion!, workdir, doomed, force: false)
      end
      assert_equal 5, error.existing_count
      assert_equal 2, error.would_withdraw_count

      # force overrides; at-threshold (1 of 5 = 20%, strict >) passes; and
      # files discover does not ingest never count.
      adapter.send(:guard_mass_deletion!, workdir, doomed, force: true)
      adapter.send(:guard_mass_deletion!, workdir, doomed.first(1), force: false)
      stranger = [File.expand_path(File.join(workdir, "notes.md"))] * 3
      adapter.send(:guard_mass_deletion!, workdir, stranger, force: false)
    end
  end

  private

  def write(workdir, relpath, content)
    path = File.join(workdir, relpath)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
