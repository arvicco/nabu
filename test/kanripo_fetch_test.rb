# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::KanripoFetch (P33-0): the many-repo fetch — KR-Catalog as the
# discovery index, per-text shallow GitFetch scoped by class, polite
# sequential pacing, per-text commit pins in a resumable fetch ledger.
#
# No network: catalog and text repos are local tmpdir git fixtures seeded
# with the REAL fixture bytes (the house pattern), so the catalog scope
# parsing runs against upstream's actual org shapes.
class KanripoFetchTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/kanripo", __dir__)

  def setup
    @root = Dir.mktmpdir("nabu-kanripo-fetch")
    @upstream = File.join(@root, "upstream")
    @dir = File.join(@root, "work")
    @attic = File.join(@dir, ".attic")
    @slept = []
    seed_catalog
    seed_text("KR1a0170", "KR1a0170_000.txt", "KR1a0170_001.txt", "Readme.org")
    seed_text("KR3g0023", "KR3g0023_000.txt", "Readme.org")
    # KR1b0049 is listed in the catalog trim but has NO upstream repo — the
    # real org has 61 such wave-1 catalog ids (census 2026-07-20).
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # -- the fresh wave --------------------------------------------------------

  def test_fresh_wave_clones_catalog_and_scoped_texts_and_pins_the_ledger
    result = sync!

    assert_equal head(File.join(@upstream, "KR-Catalog")), result.catalog_sha
    assert_equal %w[KR1a0170 KR3g0023], result.cloned.sort
    assert_equal ["KR1b0049"], result.absent
    assert_empty result.refreshed
    assert_equal 0, result.skipped
    assert File.file?(File.join(@dir, "KR-Catalog", "KR", "KR1a.txt"))
    assert File.file?(File.join(@dir, "KR1a0170", "KR1a0170_001.txt"))

    ledger = read_ledger
    assert_equal head(File.join(@upstream, "KR1a0170")), ledger.dig("texts", "KR1a0170", "sha")
    assert_equal result.catalog_sha, ledger.dig("texts", "KR1a0170", "catalog_sha")
    assert_equal "absent", ledger.dig("texts", "KR1b0049", "status")
  end

  # P37-r1 (owner's KR5 wave, 2026-07-21): upstream repos can EXIST yet hold
  # ZERO commits (KR5c0144 — "cloned an empty repository"). The old flow
  # died pinning HEAD on the fresh clone, then the on-disk empty clone
  # wedged EVERY re-run (existing-clone failures propagate). An empty repo
  # must be recorded like an absent one (status "empty", retried on catalog
  # advance), the useless clone removed, and the wave must move on.
  def test_empty_upstream_repo_records_empty_and_wave_continues
    empty_dir = File.join(@upstream, "KR1a0171")
    FileUtils.mkdir_p(empty_dir)
    Nabu::Shell.run("git", "-C", empty_dir, "init", "-q")
    add_catalog_id("KR1a0171")

    result = sync!

    assert_equal %w[KR1a0170 KR3g0023], result.cloned.sort, "the wave completes past the empty repo"
    assert_includes result.absent, "KR1a0171", "an empty repo reports beside the absent ids"
    assert_equal "empty", read_ledger.dig("texts", "KR1a0171", "status")
    refute Dir.exist?(File.join(@dir, "KR1a0171")), "the zero-data clone is removed, not left to wedge"
  end

  def test_wedged_empty_clone_on_disk_unwedges_on_the_next_wave
    # Reproduce the owner's state: a prior run left an empty clone behind.
    empty_dir = File.join(@upstream, "KR1a0171")
    FileUtils.mkdir_p(empty_dir)
    Nabu::Shell.run("git", "-C", empty_dir, "init", "-q")
    add_catalog_id("KR1a0171")
    wedged = File.join(@dir, "KR1a0171")
    FileUtils.mkdir_p(wedged)
    Nabu::Shell.run("git", "clone", "-q", empty_dir, wedged)

    result = sync!

    assert_includes result.absent, "KR1a0171"
    assert_equal "empty", read_ledger.dig("texts", "KR1a0171", "status")
    refute Dir.exist?(wedged)
    assert_equal %w[KR1a0170 KR3g0023], result.cloned.sort
  end

  def test_scope_is_the_configured_classes_only
    result = sync!(classes: ["KR3"])

    assert_equal ["KR3g0023"], result.cloned
    refute Dir.exist?(File.join(@dir, "KR1a0170")), "KR1 text is out of a KR3-only scope"
  end

  def test_unknown_class_with_no_catalog_file_is_a_loud_error
    error = assert_raises(Nabu::KanripoFetch::Error) { sync!(classes: ["KR9"]) }
    assert_match(/KR9/, error.message)
  end

  # -- resumability ----------------------------------------------------------

  def test_completed_texts_are_never_refetched_while_the_catalog_pin_holds
    sync!
    # Make every text upstream UNREACHABLE: a resumed wave that touched them
    # would fail loudly, so a green re-sync proves zero per-text network.
    FileUtils.mv(File.join(@upstream, "KR1a0170"), File.join(@root, "parked-1"))
    FileUtils.mv(File.join(@upstream, "KR3g0023"), File.join(@root, "parked-2"))

    result = sync!

    assert_empty result.cloned
    assert_empty result.refreshed
    assert_empty result.absent
    assert_equal 3, result.skipped, "two pinned texts + the standing absent id"
  end

  def test_interrupted_wave_resumes_cloning_only_the_missing_texts
    sync!
    FileUtils.rm_rf(File.join(@dir, "KR3g0023")) # as if the wave died mid-flight

    result = sync!

    assert_equal ["KR3g0023"], result.cloned
    assert_equal 2, result.skipped
    assert File.file?(File.join(@dir, "KR3g0023", "KR3g0023_000.txt"))
  end

  # -- catalog advance = a new wave -----------------------------------------

  def test_catalog_advance_refreshes_pinned_texts_and_retries_absent_ids
    sync!
    commit_file(File.join(@upstream, "KR1a0170"), "KR1a0170_001.txt",
                fixture_bytes("KR1a0170/KR1a0170_001.txt") + "追記一行¶\n".b)
    advance_catalog

    result = sync!

    assert_equal %w[KR1a0170 KR3g0023], result.refreshed.sort
    assert_equal ["KR1b0049"], result.absent, "absent ids are retried once per catalog advance"
    assert_includes File.read(File.join(@dir, "KR1a0170", "KR1a0170_001.txt")), "追記一行"
    assert_equal head(File.join(@upstream, "KR1a0170")), read_ledger.dig("texts", "KR1a0170", "sha")
  end

  def test_refresh_attics_upstream_deleted_files
    sync!
    Nabu::Shell.run("git", "-C", File.join(@upstream, "KR1a0170"), "rm", "-q", "KR1a0170_000.txt")
    commit(File.join(@upstream, "KR1a0170"), "drop 000")
    advance_catalog

    result = sync!

    assert_equal ["KR1a0170/KR1a0170_000.txt"], result.atticked
    assert File.file?(File.join(@attic, "KR1a0170", "KR1a0170_000.txt"))
    refute File.file?(File.join(@dir, "KR1a0170", "KR1a0170_000.txt"))
  end

  def test_per_text_guard_sees_doomed_paths_before_any_tree_change
    sync!
    Nabu::Shell.run("git", "-C", File.join(@upstream, "KR1a0170"), "rm", "-q", "KR1a0170_001.txt")
    commit(File.join(@upstream, "KR1a0170"), "gut the text")
    advance_catalog
    doomed_seen = nil
    guard = lambda do |text_dir, doomed|
      doomed_seen = [text_dir, doomed]
      raise Nabu::SyncAborted.new(existing_count: 2, would_withdraw_count: 1, threshold: 0.2)
    end

    assert_raises(Nabu::SyncAborted) { sync!(guard: guard) }

    assert_equal File.join(@dir, "KR1a0170"), doomed_seen.first
    assert_equal [File.join(@dir, "KR1a0170", "KR1a0170_001.txt")], doomed_seen.last
    assert File.file?(File.join(@dir, "KR1a0170", "KR1a0170_001.txt")),
           "a tripped guard leaves the text tree byte-unchanged"
    assert_equal head_of_clone("KR1a0170"), read_ledger.dig("texts", "KR1a0170", "sha"),
                 "the ledger pin stays at the completed state"
  end

  # -- pacing ----------------------------------------------------------------

  def test_paces_every_network_operation_with_the_configured_delay
    sync!(delay: 0.25)

    # catalog clone + two text clones + one absent attempt = four network ops.
    assert_equal [0.25] * 4, @slept
  end

  def test_all_skip_resync_paces_only_the_catalog_fetch
    sync!
    @slept.clear

    sync!(delay: 0.5)

    assert_equal [0.5], @slept
  end

  def test_zero_delay_never_sleeps
    sync!(delay: 0)

    assert_empty @slept
  end

  private

  def sync!(classes: %w[KR1 KR3], delay: 1, guard: nil)
    Nabu::KanripoFetch.sync!(
      catalog_url: File.join(@upstream, "KR-Catalog"),
      repo_base: @upstream,
      dir: @dir, attic_dir: @attic,
      classes: classes, delay: delay, guard: guard,
      sleeper: ->(seconds) { @slept << seconds }
    )
  end

  def add_catalog_id(id)
    kclass = id[0, 4]
    path = File.join(@upstream, "KR-Catalog", "KR", "#{kclass}.txt")
    extra = "*** #{id} 測試空倉\n:PROPERTIES:\n:KR_ID: #{id}\n:END:\n"
    content = (File.exist?(path) ? File.read(path) : "") + extra
    commit_file(File.join(@upstream, "KR-Catalog"), "KR/#{kclass}.txt", content)
  end

  def seed_catalog
    dir = File.join(@upstream, "KR-Catalog")
    seed_repo(dir,
              "KR/KR1a.txt" => fixture_bytes("KR-Catalog/KR/KR1a.txt"),
              "KR/KR1b.txt" => fixture_bytes("KR-Catalog/KR/KR1b.txt"),
              "KR/KR3g.txt" => fixture_bytes("KR-Catalog/KR/KR3g.txt"))
  end

  def seed_text(id, *files)
    seed_repo(File.join(@upstream, id),
              files.to_h { |name| [name, fixture_bytes("#{id}/#{name}")] })
  end

  def seed_repo(dir, files)
    FileUtils.mkdir_p(dir)
    Nabu::Shell.run("git", "-C", dir, "init", "-q")
    write_files(dir, files)
    Nabu::Shell.run("git", "-C", dir, "add", ".")
    commit(dir, "seed")
  end

  def commit_file(dir, rel, content)
    write_files(dir, rel => content)
    Nabu::Shell.run("git", "-C", dir, "add", ".")
    commit(dir, "update #{rel}")
  end

  def advance_catalog
    commit_file(File.join(@upstream, "KR-Catalog"), "KR/KR1a.txt",
                "#{fixture_bytes('KR-Catalog/KR/KR1a.txt')}\n# regenerated\n".b)
  end

  def write_files(dir, files)
    files.each do |rel, content|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
    end
  end

  def commit(dir, message)
    Nabu::Shell.run("git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t",
                    "commit", "-q", "-m", message)
  end

  def head(dir)
    Nabu::Shell.run("git", "-C", dir, "rev-parse", "HEAD").strip
  end

  def head_of_clone(id)
    head(File.join(@dir, id))
  end

  def fixture_bytes(rel)
    File.binread(File.join(FIXTURES, rel))
  end

  def read_ledger
    JSON.parse(File.read(File.join(@dir, Nabu::KanripoFetch::LEDGER_FILE)))
  end
end
