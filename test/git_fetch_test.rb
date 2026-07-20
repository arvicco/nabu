# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::GitFetch (P5-2): the shared non-destructive clone/pull behind every
# git-based adapter. A plain `git pull` deletes working-tree files upstream
# deleted; since canonical/ is the permanent asset and db = f(canonical),
# that would silently lose documents on the next rebuild. GitFetch splits
# the pull: fetch objects only → attic the doomed files → ff-merge, with a
# guard hook between fetch and any tree mutation so a tripped breaker leaves
# the canonical tree byte-unchanged.
#
# No network: all repos are local tmpdir fixtures (the house pattern).
class GitFetchTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("nabu-gitfetch")
    @upstream = File.join(@root, "upstream")
    @dir = File.join(@root, "work")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # --- clone ----------------------------------------------------------------

  def test_fresh_clone_reports_head_and_attics_nothing
    make_repo("alpha.txt" => "alpha v1\n")

    result = sync!

    assert_equal head(@upstream), result.sha
    assert_empty result.atticked
    assert File.file?(File.join(@dir, "alpha.txt"))
    refute Dir.exist?(@attic), "a fresh clone has no local state to protect"
  end

  # --- pull + attic -----------------------------------------------------------

  def test_pull_attics_upstream_deleted_files_before_merging
    make_repo("alpha.txt" => "alpha v1\n", "keep/beta.txt" => "beta\n")
    sync!
    delete_upstream("keep/beta.txt")
    vanished_at = head(@upstream)

    result = sync!

    assert_equal vanished_at, result.sha
    assert_equal ["keep/beta.txt"], result.atticked
    refute File.exist?(File.join(@dir, "keep", "beta.txt")), "the merge applies the deletion to the live tree"
    # The attic preserves the relative path, so adapter discover sees the
    # same shapes under .attic as under the live tree.
    assert_equal "beta\n", File.read(File.join(@attic, "keep", "beta.txt"))
    manifest = JSON.parse(File.read(File.join(@attic, ".attic.json")))
    assert_equal vanished_at, manifest.fetch("keep/beta.txt"),
                 "the attic manifest records the upstream sha the file vanished at"
  end

  def test_first_copy_wins_across_repeated_delete_cycles
    make_repo("alpha.txt" => "alpha v1\n", "beta.txt" => "beta\n")
    sync!
    delete_upstream("alpha.txt")
    first_vanish = head(@upstream)
    sync!
    commit_upstream("alpha.txt" => "alpha v2\n") # reappears, changed
    sync!
    delete_upstream("alpha.txt")                 # scrapped again

    result = sync!

    assert_empty result.atticked, "an already-atticked path is never overwritten"
    assert_equal "alpha v1\n", File.read(File.join(@attic, "alpha.txt")),
                 "first copy wins: the attic keeps the text as first scrapped"
    manifest = JSON.parse(File.read(File.join(@attic, ".attic.json")))
    assert_equal first_vanish, manifest.fetch("alpha.txt")
  end

  def test_a_rename_is_not_a_scrapping_and_attics_nothing
    make_repo("alpha.txt" => "alpha v1\n", "beta.txt" => "beta\n")
    sync!
    git(@upstream, "mv", "alpha.txt", "renamed.txt")
    commit(@upstream, "rename")

    result = sync!

    assert_empty result.atticked
    refute Dir.exist?(@attic), "renamed content survives at its new path; nothing was scrapped"
    assert File.file?(File.join(@dir, "renamed.txt"))
  end

  def test_pull_with_no_upstream_changes_is_a_quiet_no_op
    make_repo("alpha.txt" => "alpha v1\n")
    sync!

    result = sync!

    assert_equal head(@upstream), result.sha
    assert_empty result.atticked
  end

  # --- the guard hook ---------------------------------------------------------

  def test_guard_receives_absolute_doomed_paths_before_any_tree_change
    make_repo("alpha.txt" => "alpha v1\n", "keep/beta.txt" => "beta\n")
    sync!
    delete_upstream("alpha.txt")

    seen = nil
    sync!(guard: ->(doomed) { seen = doomed })

    assert_equal [File.expand_path(File.join(@dir, "alpha.txt"))], seen
  end

  def test_tripped_guard_leaves_the_working_tree_byte_unchanged
    make_repo("alpha.txt" => "alpha v1\n", "keep/beta.txt" => "beta\n")
    sync!
    before_head = head(@dir)
    before = tree_snapshot(@dir)
    delete_upstream("alpha.txt")

    boom = Nabu::SyncAborted.new(existing_count: 2, would_withdraw_count: 1, threshold: 0.2)
    error = assert_raises(Nabu::SyncAborted) { sync!(guard: ->(_doomed) { raise boom }) }

    assert_same boom, error
    assert_equal before, tree_snapshot(@dir), "an aborted pull must leave the canonical tree byte-unchanged"
    assert_equal before_head, head(@dir), "no merge happened"
    refute Dir.exist?(@attic), "no attic writes happened"

    # The abort is recoverable: the same pull completes once the guard allows.
    result = sync!
    assert_equal ["alpha.txt"], result.atticked
    assert_equal head(@upstream), head(@dir)
  end

  # --- git hygiene --------------------------------------------------------------

  def test_attic_is_invisible_to_git_status_and_later_pulls
    make_repo("alpha.txt" => "alpha v1\n", "beta.txt" => "beta\n")
    sync!
    delete_upstream("alpha.txt")
    sync!

    assert_equal "", git(@dir, "status", "--porcelain"),
                 "the attic must not show up as untracked noise in the snapshot repo"

    # Subsequent pulls tolerate the attic sitting inside the working tree.
    commit_upstream("gamma.txt" => "gamma\n")
    result = sync!
    assert_equal head(@upstream), result.sha
    assert File.file?(File.join(@dir, "gamma.txt"))
  end

  # --- progress -----------------------------------------------------------------

  def test_progress_streams_lines_on_clone_and_pull
    make_repo("alpha.txt" => "alpha v1\n")

    clone_lines = []
    sync!(progress: ->(line) { clone_lines << line })
    assert(clone_lines.any? { |line| line.include?("Cloning") })

    pull_lines = []
    sync!(progress: ->(line) { pull_lines << line })
    refute_empty pull_lines
  end

  # --- failure ------------------------------------------------------------------

  def test_shell_failure_raises_shell_error
    assert_raises(Nabu::Shell::Error) do
      Nabu::GitFetch.sync!(repo_url: File.join(@root, "does-not-exist"), dir: @dir, attic_dir: @attic)
    end
  end

  # --- ref pinning (P17-1) ------------------------------------------------------

  def test_ref_pins_clone_and_pull_to_the_tag_never_the_moving_branch
    make_repo("alpha.txt" => "release one\n")
    git(@upstream, "tag", "v1.0.0")
    pinned = head(@upstream)
    commit_upstream("alpha.txt" => "master moved on\n")

    result = sync!(ref: "v1.0.0")
    assert_equal pinned, result.sha, "a fresh pinned clone must land on the tag"
    assert_equal "release one\n", File.read(File.join(@dir, "alpha.txt"))

    # a re-sync at the same pin is a no-op, still on the tag
    assert_equal pinned, sync!(ref: "v1.0.0").sha

    # the owner re-pin: a later tag fast-forwards through the normal pull path
    git(@upstream, "tag", "v2.0.0")
    result = sync!(ref: "v2.0.0")
    assert_equal head(@upstream), result.sha
    assert_equal "master moved on\n", File.read(File.join(@dir, "alpha.txt"))
  end

  # --- sparse checkout (P26-0) ----------------------------------------------
  # A sparse fetch scopes the working tree (and, over a real transport, the
  # blob transfer — local clones ignore --filter, warned and harmless) to the
  # declared paths: the DCS case, where dcs/data/conllu is 844 MB of a much
  # larger research repo.

  def test_sparse_clone_materializes_only_the_declared_paths
    make_repo("keep/data.txt" => "in cone\n", "papers/big.pdf" => "outside\n")

    result = sync!(sparse: ["keep"])

    assert_equal head(@upstream), result.sha
    assert File.file?(File.join(@dir, "keep", "data.txt"))
    refute File.exist?(File.join(@dir, "papers", "big.pdf")),
           "paths outside the sparse cone must not materialize"
  end

  def test_sparse_pull_attics_cone_deletions_and_ignores_outside_ones
    make_repo("keep/data.txt" => "v1\n", "keep/other.txt" => "o\n", "papers/big.pdf" => "outside\n")
    sync!(sparse: ["keep"])
    delete_upstream("keep/data.txt")
    delete_upstream("papers/big.pdf")

    result = sync!(sparse: ["keep"])

    assert_equal ["keep/data.txt"], result.atticked,
                 "only cone deletions are this source's retained assets"
    refute File.exist?(File.join(@dir, "keep", "data.txt")), "the merge applies the cone deletion"
    assert_equal "v1\n", File.read(File.join(@attic, "keep", "data.txt"))
    assert File.file?(File.join(@dir, "keep", "other.txt"))
  end

  # Root-anchored sparse patterns ("/lexicon.xml" — the sparse-checkout
  # spelling for a file at the repo root) must survive a RE-SYNC: the pull
  # path reuses the cone as a `git diff` pathspec scope, where a leading
  # slash is fatal ("outside repository", exit 128 — the ONCOJ owner repro
  # 2026-07-20; the fresh clone worked, every re-sync died).
  def test_sparse_pull_survives_root_anchored_patterns
    make_repo("root.txt" => "v1\n", "papers/big.pdf" => "outside\n")
    sync!(sparse: ["/root.txt"])
    delete_upstream("root.txt")

    result = sync!(sparse: ["/root.txt"])

    assert_equal ["root.txt"], result.atticked,
                 "the root-anchored cone deletion attics like any other"
    refute File.exist?(File.join(@dir, "root.txt"))
  end

  # A source may GROW its cone across releases (P34-4: tls added notes/doc +
  # notes/swl for the attestation crosswalk). A re-sync with a wider cone
  # must materialize the new paths on an EXISTING checkout — and never
  # narrow: a path in the local cone but not in the declared one (an
  # owner-widened checkout) stays put, because hiding materialized canonical
  # files is the destructive-fetch sin.
  def test_pull_widens_a_grown_sparse_cone
    make_repo("keep/data.txt" => "in cone\n", "notes/ann.xml" => "attestations\n",
              "papers/big.pdf" => "outside\n")
    sync!(sparse: ["keep"])
    refute File.exist?(File.join(@dir, "notes", "ann.xml")), "not in the original cone"

    sync!(sparse: %w[keep notes])

    assert File.file?(File.join(@dir, "keep", "data.txt"))
    assert File.file?(File.join(@dir, "notes", "ann.xml")), "the widened cone materializes"
    refute File.exist?(File.join(@dir, "papers", "big.pdf")), "still sparse outside the cone"
  end

  def test_pull_never_narrows_a_locally_wider_cone
    make_repo("keep/data.txt" => "in cone\n", "extra/local.txt" => "owner-widened\n")
    sync!(sparse: %w[keep extra])

    sync!(sparse: ["keep"])

    assert File.file?(File.join(@dir, "extra", "local.txt")),
           "a locally wider cone is kept — widening is union, never replacement"
  end

  def test_pull_of_a_full_checkout_never_sparsifies_it
    make_repo("keep/data.txt" => "v1\n", "papers/big.pdf" => "everything\n")
    sync! # full clone, no cone
    commit_upstream("keep/data.txt" => "v2\n")

    sync!(sparse: ["keep"])

    assert File.file?(File.join(@dir, "papers", "big.pdf")),
           "a full checkout already holds everything — sparsifying would hide canonical files"
    assert_equal "v2\n", File.read(File.join(@dir, "keep", "data.txt"))
  end

  private

  def sync!(guard: nil, progress: nil, ref: nil, sparse: nil)
    Nabu::GitFetch.sync!(repo_url: @upstream, dir: @dir, attic_dir: @attic,
                         progress: progress, guard: guard, ref: ref, sparse: sparse)
  end

  def make_repo(files)
    FileUtils.mkdir_p(@upstream)
    git(@upstream, "init", "-q")
    write_files(@upstream, files)
    git(@upstream, "add", ".")
    commit(@upstream, "seed")
  end

  def commit_upstream(files)
    write_files(@upstream, files)
    git(@upstream, "add", ".")
    commit(@upstream, "update")
  end

  def delete_upstream(relpath)
    git(@upstream, "rm", "-q", relpath)
    commit(@upstream, "delete #{relpath}")
  end

  def write_files(dir, files)
    files.each do |rel, content|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def commit(dir, message)
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", message)
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end

  def head(dir) = git(dir, "rev-parse", "HEAD")

  # Every path + file byte under +dir+, .git excluded (fetch legitimately
  # writes objects there; "canonical tree" means the working files).
  def tree_snapshot(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir)
       .reject { |rel| rel == ".git" || rel.start_with?(".git/") || rel.end_with?("/.", "/..") }
       .sort
       .map { |rel| [rel, file_bytes(File.join(dir, rel))] }
  end

  def file_bytes(path)
    File.file?(path) ? File.binread(path) : :dir
  end
end
