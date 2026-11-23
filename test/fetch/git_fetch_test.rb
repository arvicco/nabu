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

  # --- submodules: never recursed ----------------------------------------------
  # The house never wants submodules: adapters treat a gitlink as an empty
  # dir. git's default fetch.recurseSubmodules=on-demand once failed a whole
  # sync (tamilex, 2026-10-29) because upstream added a submodule whose
  # gitlink commit was never pushed ("Could not access submodule 'lib'").
  # Every fetch must pass --recurse-submodules=no, on BOTH the quiet and the
  # progress path, so no config default (or a box-local override) can recurse.
  # The live failure needs a GitHub-side unreachable gitlink that a local
  # fixture cannot fake (git only recurses into submodules it can reach), so
  # the argv spy is the regression proof; the repo test pins the outcome.

  def test_pull_survives_an_upstream_submodule_with_an_unreachable_gitlink
    make_repo("alpha.txt" => "alpha v1\n")
    sync!
    # The worst-case box config: recursion forced on in the working repo.
    git(@dir, "config", "fetch.recurseSubmodules", "true")
    add_unreachable_submodule_upstream("lib")

    result = sync!

    assert_equal head(@upstream), result.sha
    refute_path_exists File.join(@dir, "lib", "README.md"), "a gitlink stays an empty dir"
  end

  def test_every_fetch_invocation_refuses_submodule_recursion
    make_repo("alpha.txt" => "alpha v1\n")
    sync!
    commit_upstream("alpha.txt" => "alpha v2\n")

    fetches = record_fetch_argvs { sync! }
    commit_upstream("alpha.txt" => "alpha v3\n")
    fetches += record_fetch_argvs { sync!(progress: ->(_line) {}) }

    assert_equal 2, fetches.size, "one quiet and one progress fetch"
    fetches.each do |argv|
      assert_includes argv, "--recurse-submodules=no", "fetch must never recurse: #{argv.join(' ')}"
    end
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

  # --- atomic fresh clone (P44-i1, owner ruling "sync should be atomic") ---
  # An interrupted clone must never leave a half-canonical tree a resume
  # could mistake for a finished acquisition: fresh clones stage into a
  # sibling .partial dir and land by ONE rename.

  def test_fresh_clone_lands_atomically_with_no_staging_residue
    make_repo("keep/a.txt" => "kept\n")
    sync!(sparse: ["keep"])
    refute Dir.exist?("#{@dir}.partial"), "staging is renamed away, never left beside the tree"
    assert File.exist?(File.join(@dir, "keep", "a.txt"))
  end

  def test_stale_staging_debris_is_swept_before_a_fresh_clone
    make_repo("keep/a.txt" => "kept\n")
    FileUtils.mkdir_p(File.join("#{@dir}.partial", ".git"))
    File.write(File.join("#{@dir}.partial", "junk"), "interrupted")
    lines = []
    sync!(sparse: ["keep"], progress: ->(line) { lines << line })
    refute Dir.exist?("#{@dir}.partial"), "interrupt debris is removed"
    assert lines.any? { |l| l.include?("removing interrupted clone staging") },
           "the sweep announces itself"
    assert File.exist?(File.join(@dir, "keep", "a.txt")), "the fresh clone proceeds normally"
  end

  def test_sparse_clone_of_a_cone_matching_nothing_is_a_loud_failure
    make_repo("keep/a.txt" => "kept\n")
    error = assert_raises(Nabu::FetchError) { sync!(sparse: ["no-such-dir"]) }
    assert_match(/materialized nothing/, error.message)
    refute Dir.exist?(@dir), "a failed acquisition leaves NO canonical tree (atomicity)"
    refute Dir.exist?("#{@dir}.partial"), "and no staging residue either"
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

  # GLOB-pattern cones (P38-3, the aozora shape): the no-cone sparse grammar
  # is gitignore-style, so a cone can be a filename PATTERN over a wide tree
  # — cards/*/files/*_ruby_*.zip picks the ~210 MB of text zips out of a
  # 22.8 GB repo whose per-author dirs also hold card pages, XHTML and ebk
  # binaries. Pinned here so the grammar the aozora adapter relies on can
  # never regress silently.
  def test_sparse_clone_materializes_glob_pattern_cones
    make_repo("cards/000001/files/1_ruby_9.zip" => "text zip\n",
              "cards/000001/files/1_5555.html" => "xhtml\n",
              "cards/000001/card1.html" => "card page\n",
              "index_pages/list.zip" => "index\n")

    sync!(sparse: ["cards/*/files/*_ruby_*.zip", "index_pages/list.zip"])

    assert File.file?(File.join(@dir, "cards", "000001", "files", "1_ruby_9.zip"))
    assert File.file?(File.join(@dir, "index_pages", "list.zip"))
    refute File.exist?(File.join(@dir, "cards", "000001", "files", "1_5555.html")),
           "non-matching siblings inside a matched dir stay outside the cone"
    refute File.exist?(File.join(@dir, "cards", "000001", "card1.html"))
  end

  def test_sparse_pull_attics_glob_cone_deletions_and_ignores_outside_ones
    make_repo("cards/000001/files/1_ruby_9.zip" => "v1\n",
              "cards/000001/files/2_ruby_7.zip" => "kept\n",
              "cards/000001/card1.html" => "card page\n")
    cone = ["cards/*/files/*_ruby_*.zip"]
    sync!(sparse: cone)
    delete_upstream("cards/000001/files/1_ruby_9.zip")
    delete_upstream("cards/000001/card1.html")

    result = sync!(sparse: cone)

    assert_equal ["cards/000001/files/1_ruby_9.zip"], result.atticked,
                 "only glob-cone deletions are this source's retained assets"
    assert_equal "v1\n", File.read(File.join(@attic, "cards", "000001", "files", "1_ruby_9.zip"))
    assert File.file?(File.join(@dir, "cards", "000001", "files", "2_ruby_7.zip"))
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

  # --- attic-and-reset on a diverged upstream (owner ruling 2026-11-12) ------
  # An upstream history REWRITE (force-push) leaves FETCH_HEAD unreachable
  # from HEAD, so the ff-only merge can never succeed and the source would
  # park forever (the kanripo case: ~17% of the text repos diverged, almost
  # all rewrite-only with an IDENTICAL tree). The ruled policy, opt-in per
  # caller: attic every file the reset would delete or change, THEN reset
  # to the upstream tip, and record the event. Identical trees take a fast
  # path that touches no working-tree file at all.

  def test_diverged_upstream_without_the_opt_in_keeps_the_hard_stop
    make_repo("alpha.txt" => "alpha v1\n")
    sync!
    before_head = head(@dir)
    before = tree_snapshot(@dir)
    rewrite_upstream("alpha.txt" => "alpha rewritten\n")

    assert_raises(Nabu::Shell::Error) { sync! }

    assert_equal before_head, head(@dir), "ordinary sources never move off their line"
    assert_equal before, tree_snapshot(@dir)
  end

  def test_zero_delta_rewrite_moves_head_without_touching_any_file
    make_repo("alpha.txt" => "alpha v1\n", "keep/beta.txt" => "beta\n")
    sync!
    old_head = head(@dir)
    before = tree_snapshot(@dir)
    git(@upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--amend", "-m", "rewritten")
    refute_equal old_head, head(@upstream), "the rewrite minted a new, unrelated tip"

    argvs = record_git_argvs { @result = sync!(reset_on_divergence: true) }

    assert_equal head(@upstream), @result.sha
    assert_equal head(@upstream), head(@dir)
    assert_empty @result.atticked
    reset = @result.reset
    assert reset.zero_delta, "identical trees take the fast path"
    assert_equal old_head, reset.from
    assert_equal head(@upstream), reset.to
    assert_equal 0, reset.atticked
    assert_equal before, tree_snapshot(@dir).reject { |rel, _| rel.start_with?(".attic") },
                 "no live file is rewritten"
    file_work = argvs.select { |argv| argv.include?("diff") || argv.include?("status") || argv.include?("--hard") }
    assert_empty file_work, "tree identity is decided by tree ids alone: #{file_work.inspect}"
    assert_equal "", git(@dir, "status", "--porcelain")
    log = reset_log
    assert_equal 1, log.size
    assert_equal({ "from" => old_head, "to" => head(@upstream), "zero_delta" => true, "atticked" => 0 },
                 log.first.slice("from", "to", "zero_delta", "atticked"))
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, log.first.fetch("at"))
  end

  def test_rewrite_with_changes_attics_every_changed_and_deleted_file_then_resets
    make_repo("alpha.txt" => "alpha v1\n", "gone/beta.txt" => "beta\n",
              "same.txt" => "same\n", "renamed.txt" => "moves intact\n")
    sync!
    old_head = head(@dir)
    rewrite_upstream({ "alpha.txt" => "alpha v2\n", "same.txt" => "same\n",
                       "new.txt" => "brand new\n", "moved/renamed.txt" => "moves intact\n" })
    new_head = head(@upstream)

    result = sync!(reset_on_divergence: true)

    assert_equal new_head, result.sha
    assert_equal new_head, head(@dir)
    assert_equal %w[alpha.txt gone/beta.txt], result.atticked,
                 "changed + deleted files are atticked; unchanged and renamed ones are not"
    # attic verified file by file: the PRE-reset bytes at the same relative path
    assert_equal "alpha v1\n", File.read(File.join(@attic, "alpha.txt"))
    assert_equal "beta\n", File.read(File.join(@attic, "gone", "beta.txt"))
    refute File.exist?(File.join(@attic, "same.txt"))
    refute File.exist?(File.join(@attic, "renamed.txt")), "a rename is not a scrapping"
    manifest = JSON.parse(File.read(File.join(@attic, ".attic.json")))
    assert_equal({ "alpha.txt" => new_head, "gone/beta.txt" => new_head }, manifest)
    # the live tree is upstream's rewritten line
    assert_equal "alpha v2\n", File.read(File.join(@dir, "alpha.txt"))
    refute File.exist?(File.join(@dir, "gone", "beta.txt"))
    assert_equal "brand new\n", File.read(File.join(@dir, "new.txt"))
    assert_equal "moves intact\n", File.read(File.join(@dir, "moved", "renamed.txt"))
    assert_equal "", git(@dir, "status", "--porcelain")
    reset = result.reset
    refute reset.zero_delta
    assert_equal [old_head, new_head, 2], [reset.from, reset.to, reset.atticked]
    assert_equal [false, 2], reset_log.last.values_at("zero_delta", "atticked")

    # the reset line is now the tracked line: the next pull is an ordinary no-op
    again = sync!(reset_on_divergence: true)
    assert_nil again.reset
    assert_empty again.atticked
  end

  def test_reset_never_overwrites_an_existing_attic_copy
    make_repo("alpha.txt" => "alpha v1\n", "beta.txt" => "beta\n")
    sync!
    FileUtils.mkdir_p(@attic)
    File.write(File.join(@attic, "alpha.txt"), "first scrapped\n")
    rewrite_upstream("alpha.txt" => "alpha v2\n", "beta.txt" => "beta\n")

    result = sync!(reset_on_divergence: true)

    assert_empty result.atticked
    assert_equal "first scrapped\n", File.read(File.join(@attic, "alpha.txt")), "first copy wins"
    assert_equal "alpha v2\n", File.read(File.join(@dir, "alpha.txt"))
  end

  def test_breaker_runs_before_a_reset_and_a_trip_leaves_everything_unchanged
    make_repo("alpha.txt" => "alpha v1\n", "beta.txt" => "beta\n", "gamma.txt" => "gamma\n")
    sync!
    before_head = head(@dir)
    before = tree_snapshot(@dir)
    rewrite_upstream("gamma.txt" => "gamma rewritten\n") # a mass deletion riding a rewrite

    seen = nil
    boom = Nabu::SyncAborted.new(existing_count: 3, would_withdraw_count: 2, threshold: 0.2)
    assert_raises(Nabu::SyncAborted) do
      sync!(reset_on_divergence: true, guard: lambda { |doomed|
        seen = doomed
        raise boom
      })
    end

    assert_equal %w[alpha.txt beta.txt].map { |rel| File.expand_path(File.join(@dir, rel)) }, seen,
                 "the guard sees the reset's deletions"
    assert_equal before_head, head(@dir), "no reset happened"
    assert_equal before, tree_snapshot(@dir), "byte-unchanged"
    refute Dir.exist?(@attic), "no attic writes, no event recorded"

    result = sync!(reset_on_divergence: true) # the guard allows: the reset completes
    assert_equal %w[alpha.txt beta.txt gamma.txt], result.atticked
    assert_equal head(@upstream), head(@dir)
  end

  def test_reset_refuses_a_locally_modified_tracked_tree
    make_repo("alpha.txt" => "alpha v1\n", "beta.txt" => "beta\n")
    sync!
    File.write(File.join(@dir, "beta.txt"), "local edit\n")
    before_head = head(@dir)
    rewrite_upstream("alpha.txt" => "alpha v2\n", "beta.txt" => "beta\n")

    error = assert_raises(Nabu::FetchError) { sync!(reset_on_divergence: true) }

    assert_match(/local modifications/, error.message)
    assert_equal before_head, head(@dir)
    assert_equal "local edit\n", File.read(File.join(@dir, "beta.txt")), "never clobbered"
    refute Dir.exist?(@attic)
  end

  def test_plain_fast_forward_is_unchanged_under_the_opt_in
    make_repo("alpha.txt" => "alpha v1\n", "beta.txt" => "beta\n")
    sync!
    commit_upstream("alpha.txt" => "alpha v2\n")
    delete_upstream("beta.txt")

    result = sync!(reset_on_divergence: true)

    assert_nil result.reset, "an ff-able upstream merges as ever"
    assert_equal ["beta.txt"], result.atticked, "modified files are not atticked on the ff path"
    assert_equal head(@upstream), head(@dir)
    assert_equal "alpha v2\n", File.read(File.join(@dir, "alpha.txt"))
    refute File.exist?(File.join(@attic, Nabu::GitFetch::RESET_LOG))
  end

  def test_sparse_rewrite_scopes_the_attic_to_the_cone
    make_repo("keep/data.txt" => "v1\n", "papers/big.pdf" => "outside\n")
    sync!(sparse: ["keep"])
    rewrite_upstream("keep/data.txt" => "v2\n", "papers/big.pdf" => "outside changed\n")

    result = sync!(sparse: ["keep"], reset_on_divergence: true)

    assert_equal ["keep/data.txt"], result.atticked
    assert_equal "v1\n", File.read(File.join(@attic, "keep", "data.txt"))
    assert_equal "v2\n", File.read(File.join(@dir, "keep", "data.txt"))
    refute File.exist?(File.join(@dir, "papers", "big.pdf")), "the reset keeps the sparse cone"
  end

  private

  def sync!(guard: nil, progress: nil, ref: nil, sparse: nil, reset_on_divergence: false)
    Nabu::GitFetch.sync!(repo_url: @upstream, dir: @dir, attic_dir: @attic,
                         progress: progress, guard: guard, ref: ref, sparse: sparse,
                         reset_on_divergence: reset_on_divergence)
  end

  # Upstream force-pushes a NEW ROOT commit carrying exactly +files+ (every
  # other path is gone) — history unrelated to anything the clone holds.
  def rewrite_upstream(files)
    git(@upstream, "checkout", "-q", "--orphan", "rewritten")
    git(@upstream, "rm", "-rq", "--cached", ".")
    Dir.children(@upstream).sort.each do |entry|
      FileUtils.rm_rf(File.join(@upstream, entry)) unless entry == ".git"
    end
    write_files(@upstream, files)
    git(@upstream, "add", ".")
    commit(@upstream, "rewritten history")
    branch = git(@dir, "rev-parse", "--abbrev-ref", "HEAD")
    git(@upstream, "branch", "-M", branch)
  end

  def reset_log
    JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::RESET_LOG)))
  end

  # The argv of every `git` command GitFetch issues inside the block AFTER
  # the fetch (the post-fetch decision and tree work).
  def record_git_argvs
    seen = []
    singleton = Nabu::Shell.singleton_class
    originals = %i[run stream].to_h { |name| [name, Nabu::Shell.method(name)] }
    originals.each do |name, original|
      singleton.define_method(name) do |*argv, &blk|
        seen << argv if argv.first == "git"
        original.call(*argv, &blk)
      end
    end
    yield
    fetch_at = seen.index { |argv| argv.include?("fetch") }
    fetch_at ? seen.drop(fetch_at + 1) : seen
  ensure
    originals&.each { |name, original| singleton.define_method(name, original) }
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

  # Upstream gains a submodule at +path+ whose gitlink names a commit the
  # submodule repo does not carry (the never-pushed-commit shape).
  def add_unreachable_submodule_upstream(path)
    sub = File.join(@root, "sub")
    FileUtils.mkdir_p(sub)
    git(sub, "init", "-q")
    git(sub, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "seed")
    File.write(File.join(@upstream, ".gitmodules"), "[submodule \"#{path}\"]\n\tpath = #{path}\n\turl = #{sub}\n")
    git(@upstream, "add", ".gitmodules")
    git(@upstream, "update-index", "--add", "--cacheinfo", "160000,#{'1' * 40},#{path}")
    commit(@upstream, "add submodule #{path}")
  end

  # The argv of every `git … fetch …` GitFetch issues inside the block
  # (Shell.run and Shell.stream both spied; the real call still runs).
  # Hand-rolled define/yield/restore — minitest 6 ships no minitest/mock.
  def record_fetch_argvs
    seen = []
    singleton = Nabu::Shell.singleton_class
    originals = %i[run stream].to_h { |name| [name, Nabu::Shell.method(name)] }
    originals.each do |name, original|
      singleton.define_method(name) do |*argv, &blk|
        seen << argv if argv.first == "git" && argv.include?("fetch")
        original.call(*argv, &blk)
      end
    end
    yield
    seen
  ensure
    originals&.each { |name, original| singleton.define_method(name, original) }
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
