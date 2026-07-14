# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

# Nabu::LocalFetch (P19-1): the no-network fetch strategy behind
# sync_policy: local — tree validation, per-file sha accounting (the ledger
# pins' feed), the state file, un-atticked disappearance reporting, and the
# house mass-deletion breaker.
class LocalFetchTest < Minitest::Test
  def with_tree
    Dir.mktmpdir("nabu-local-fetch") do |dir|
      yield dir, File.join(dir, ".attic")
    end
  end

  def write(dir, rel, body)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def sync(dir, attic, force: false)
    Nabu::LocalFetch.sync!(dir: dir, attic_dir: attic, force: force)
  end

  def test_scan_hashes_every_live_file_and_writes_the_state_file
    with_tree do |dir, attic|
      write(dir, "chu.md", "one")
      write(dir, "zle.md", "two")
      result = sync(dir, attic)
      assert_equal %w[chu.md zle.md], result.files.keys.sort
      assert_equal Digest::SHA256.hexdigest("one"), result.files["chu.md"]
      assert_empty result.vanished
      assert_equal 0, result.retired
      state = JSON.parse(File.read(File.join(dir, Nabu::LocalFetch::STATE_FILE)))
      assert_equal result.files, state.fetch("files")
    end
  end

  def test_tree_sha_is_stable_across_rescans_and_moves_on_edit
    with_tree do |dir, attic|
      write(dir, "chu.md", "one")
      first = sync(dir, attic)
      assert_equal first.sha, sync(dir, attic).sha, "an unchanged tree re-pins the same sha"
      write(dir, "chu.md", "edited")
      refute_equal first.sha, sync(dir, attic).sha
    end
  end

  def test_missing_or_empty_tree_raises_with_guidance
    with_tree do |dir, attic|
      error = assert_raises(Nabu::LocalFetch::Error) { sync(File.join(dir, "nope"), attic) }
      assert_match(/no local tree/, error.message)
      assert_match(/export-dossiers/, error.message)
    end
  end

  def test_attic_and_state_file_are_never_scanned
    with_tree do |dir, attic|
      write(dir, "chu.md", "one")
      write(attic, "old.md", "retired bytes")
      sync(dir, attic)
      result = sync(dir, attic)
      assert_equal %w[chu.md], result.files.keys
    end
  end

  def test_deletion_into_the_attic_reads_as_retired_and_drops_the_pin
    with_tree do |dir, attic|
      write(dir, "chu.md", "one")
      write(dir, "zle.md", "two")
      write(dir, "zlw.md", "three")
      write(dir, "gkm.md", "four")
      write(dir, "lat.md", "five")
      sync(dir, attic)
      FileUtils.mkdir_p(attic)
      FileUtils.mv(File.join(dir, "zle.md"), File.join(attic, "zle.md"))
      result = sync(dir, attic)
      assert_equal 1, result.retired
      assert_empty result.vanished, "a deliberate retire is not loss"
      refute_includes result.files.keys, "zle.md"
    end
  end

  def test_unatticked_deletion_is_reported_with_its_last_known_sha
    with_tree do |dir, attic|
      write(dir, "chu.md", "one")
      write(dir, "zle.md", "two")
      write(dir, "zlw.md", "three")
      write(dir, "gkm.md", "four")
      write(dir, "lat.md", "five")
      sync(dir, attic)
      FileUtils.rm(File.join(dir, "zle.md"))
      result = sync(dir, attic)
      assert_equal({ "zle.md" => Digest::SHA256.hexdigest("two") }, result.vanished)
      assert_equal 0, result.retired
    end
  end

  def test_mass_unatticked_deletion_trips_the_breaker_and_force_overrides
    with_tree do |dir, attic|
      %w[a b c d e].each { |code| write(dir, "#{code}.md", code) }
      sync(dir, attic)
      FileUtils.rm(File.join(dir, "a.md"))
      FileUtils.rm(File.join(dir, "b.md"))
      error = assert_raises(Nabu::SyncAborted) { sync(dir, attic) }
      assert_equal 5, error.existing_count
      assert_equal 2, error.would_withdraw_count
      # The breaker aborts BEFORE the state file advances: the loss stays
      # judged against the full previous scan on retry.
      state = JSON.parse(File.read(File.join(dir, Nabu::LocalFetch::STATE_FILE)))
      assert_equal 5, state.fetch("files").size
      result = sync(dir, attic, force: true)
      assert_equal 2, result.vanished.size
      assert_equal 3, result.files.size
    end
  end

  def test_mass_retire_into_the_attic_never_trips_the_breaker
    with_tree do |dir, attic|
      %w[a b c d e].each { |code| write(dir, "#{code}.md", code) }
      sync(dir, attic)
      FileUtils.mkdir_p(attic)
      %w[a b c].each { |code| FileUtils.mv(File.join(dir, "#{code}.md"), File.join(attic, "#{code}.md")) }
      result = sync(dir, attic)
      assert_equal 3, result.retired
      assert_empty result.vanished
    end
  end
end
