# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

module Ops
  # Nabu::Ops::GitHooks — the local hook pack `rake tools:hooks` installs.
  # Each check is anchored to a re-offended discipline: conflict markers
  # committed by a hand-resolved merge (an orphan ======= line survived a
  # <<<<<<<-only sweep), a shared-core commit landing mid-rebuild (it
  # staled every derivation stamp that run minted), and attribution / id
  # leaks in commit messages (caught once only by a manual sweep over a
  # whole phase's commits). Workflow-id samples below are assembled at
  # runtime so this file never carries them literally.
  class GitHooksTest < Minitest::Test
    H = Nabu::Ops::GitHooks
    LT = "<" * 7
    EQ = "=" * 7
    GT = ">" * 7
    ROOT = File.expand_path("../..", __dir__)

    # -- (a) conflict markers in staged content --------------------------------

    def diff_adding(path, *lines)
      header = "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n@@ -1,0 +3,#{lines.size} @@\n"
      header + lines.map { |line| "+#{line}\n" }.join
    end

    def test_all_three_marker_strings_are_caught_with_their_lines
      offenses = H.conflict_markers(diff_adding("lib/x.rb", "#{LT} HEAD", "a", EQ, "b", "#{GT} theirs"))
      assert_equal ["lib/x.rb:3: #{LT} HEAD", "lib/x.rb:5: #{EQ}", "lib/x.rb:7: #{GT} theirs"], offenses
    end

    def test_an_orphan_separator_alone_is_caught
      assert_equal 1, H.conflict_markers(diff_adding("docs/a.md", "text", EQ)).size
    end

    def test_marker_lookalikes_and_removed_lines_pass
      diff = diff_adding("docs/a.md", "#{EQ}=", "x #{LT}", "#{LT}<") + "-#{EQ}\n"
      assert_empty H.conflict_markers(diff)
    end

    def test_upstream_fixture_bytes_are_exempt
      assert_empty H.conflict_markers(diff_adding("test/fixtures/src/a.txt", EQ))
    end

    def test_non_utf8_diff_bytes_never_crash_the_scan
      # A Windows-1252 fixture (0x93 = curly quote) rides a staged diff as
      # raw bytes; the scan scrubs rather than raising, and still catches a
      # marker on a neighbouring line.
      diff = diff_adding("lib/x.rb", "sm\x93art quote", EQ).force_encoding(Encoding::UTF_8)
      offenses = H.conflict_markers(diff)
      assert_equal 1, offenses.size
      assert_match(/lib\/x\.rb:4/, offenses.first)
    end

    # -- (b) the mid-rebuild hold -----------------------------------------------

    PS = <<~PS
      101 /bin/zsh -l
      202 ruby bin/nabu rebuild --incremental
      303 ruby bin/nabu rebuild --dry-run
      404 ruby bin/nabu sync perseus --parse-only
    PS

    def test_rebuild_processes_skip_dry_runs_and_other_commands
      assert_equal [[202, "ruby bin/nabu rebuild --incremental"]], H.rebuild_processes(PS)
    end

    def hold(staged, cwd: "/repo")
      Dir.mktmpdir do |dir|
        top = File.join(dir, "repo")
        FileUtils.mkdir_p(File.join(top, "sub"))
        where = cwd && File.join(dir, cwd.delete_prefix("/"))
        FileUtils.mkdir_p(where) if where
        return H.rebuild_hold(staged: staged, processes: H.rebuild_processes(PS),
                              toplevel: top, cwd_of: ->(_pid) { where })
      end
    end

    def test_a_shared_core_commit_during_a_rebuild_of_this_checkout_is_held
      message = hold(["docs/a.md", "lib/nabu/store/indexer.rb"])
      assert_match(/HOLD/, message)
      assert_match(/pid 202/, message)
      assert_match(%r{lib/nabu/store/indexer\.rb}, message)
      assert_match(/--no-verify/, message)
      assert_match(/stamp/, message, "the refusal says WHY")
    end

    def test_adapters_and_migrations_are_core_too
      refute_nil hold(["lib/nabu/adapters/perseus.rb"])
      refute_nil hold(["db/migrate/048_x.rb"])
    end

    def test_non_core_commits_pass_during_a_rebuild
      assert_nil hold(["docs/a.md", "test/foo_test.rb", "config/kind_map.yml"])
    end

    def test_a_rebuild_of_another_checkout_does_not_hold_this_one
      assert_nil hold(["lib/nabu/store/indexer.rb"], cwd: "/elsewhere")
    end

    def test_an_unknowable_rebuild_cwd_holds_conservatively
      refute_nil hold(["lib/nabu/store/indexer.rb"], cwd: nil)
    end

    def test_no_rebuild_no_hold
      assert_nil H.rebuild_hold(staged: ["lib/nabu/cli.rb"], processes: [], toplevel: "/r", cwd_of: ->(_) {})
    end

    # -- (c) commit-message refusals ---------------------------------------------

    # Id-shape fragments, joined at runtime (see the class comment).
    QUEUE = "Q"
    THREAD = "T"
    OWNER = "OWNER"
    MAIL = "email"
    DRAFT = "draft"

    def leaks
      ["Co-Authored-By: Claude Opus <noreply@anthropic.com>",
       "#{0x1F916.chr(Encoding::UTF_8)} Generated with [Claude Code](https://claude.com/claude-code)",
       "see https://claude.ai/code/session_x",
       "per #{H::NUMERO}R-54",
       "carries the #{QUEUE}104 sources",
       "thread #{THREAD}-12 answered",
       "#{OWNER} ACTIONS: none",
       "update the #{MAIL}-register row",
       "the thank-you #{DRAFT} is staged"]
    end

    def test_each_attribution_and_workflow_id_shape_is_refused
      leaks.each do |leak|
        refute_empty H.message_offenses("Add the widget\n\n#{leak}\n"), "must refuse #{leak.inspect}"
      end
    end

    def test_a_plain_technical_message_passes
      message = "Mine kaikki etymology templates into typed reflex rows\n\n" \
                "The P133 lane (docs/architecture.md section 10) keeps Q-shaped words like Quran.\n"
      assert_empty H.message_offenses(message)
    end

    def test_git_comment_lines_and_the_scissors_tail_are_ignored
      message = "Fix it\n# Co-Authored-By: Claude\n# ------------------------ >8 ------------------------\n" \
                "+Co-Authored-By: Claude\n"
      assert_empty H.message_offenses(message)
    end

    # -- the installer + the real hooks end to end --------------------------------

    def git!(dir, *)
      out, err, status = Open3.capture3("git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.org",
                                        "-c", "commit.gpgsign=false", *)
      [status.success?, out + err]
    end

    # A scratch repo carrying the tracked hook scripts and their module at
    # the real relative paths (the hooks resolve lib/ from their realpath).
    def with_repo
      Dir.mktmpdir("hooks") do |dir|
        repo = File.join(dir, "repo")
        FileUtils.mkdir_p(repo)
        git!(repo, "init", "-q", "-b", "main")
        H::HOOKS.each do |hook|
          FileUtils.mkdir_p(File.join(repo, H::SCRIPT_DIR))
          FileUtils.cp(File.join(ROOT, H::SCRIPT_DIR, hook), File.join(repo, H::SCRIPT_DIR, hook))
        end
        %w[lib/nabu/ops/git_hooks.rb lib/nabu/errors.rb].each do |rel|
          FileUtils.mkdir_p(File.dirname(File.join(repo, rel)))
          FileUtils.cp(File.join(ROOT, rel), File.join(repo, rel))
        end
        yield repo
      end
    end

    def test_install_links_every_hook_idempotently_into_the_main_checkout
      with_repo do |repo|
        out = StringIO.new
        states = H::Installer.new(root: repo, out: out).install!
        assert_equal({ "pre-commit" => :installed, "commit-msg" => :installed }, states)
        link = File.join(repo, ".git", "hooks", "pre-commit")
        assert File.symlink?(link)
        assert_equal File.join(File.realpath(repo), H::SCRIPT_DIR, "pre-commit"), File.realpath(link)

        again = H::Installer.new(root: repo, out: out).install!
        assert_equal(%i[present present], again.values)
        assert(H::Installer.new(root: repo, out: out).status.values.all? { |s| s.start_with?("installed") })
      end
    end

    def test_a_foreign_hook_is_never_clobbered
      with_repo do |repo|
        foreign = File.join(repo, ".git", "hooks", "commit-msg")
        File.write(foreign, "#!/bin/sh\nexit 0\n")
        states = H::Installer.new(root: repo, out: StringIO.new).install!
        assert_equal :foreign, states["commit-msg"]
        assert_equal "#!/bin/sh\nexit 0\n", File.read(foreign)
      end
    end

    def test_a_linked_worktree_install_targets_the_main_checkout
      with_repo do |repo|
        git!(repo, "add", "-A")
        git!(repo, "commit", "-q", "-m", "Seed")
        lane = File.join(File.dirname(repo), "lane")
        assert git!(repo, "worktree", "add", "-q", "-b", "lane", lane).first
        installer = H::Installer.new(root: lane, out: StringIO.new)
        installer.install!
        assert_equal File.join(File.realpath(repo), H::SCRIPT_DIR, "pre-commit"),
                     File.realpath(File.join(installer.hooks_dir, "pre-commit"))
      end
    end

    def test_the_installed_hooks_refuse_markers_and_attribution_and_pass_clean_commits
      with_repo do |repo|
        H::Installer.new(root: repo, out: StringIO.new).install!
        File.write(File.join(repo, "a.md"), "one\n#{EQ}\ntwo\n")
        git!(repo, "add", "-A")
        ok, out = git!(repo, "commit", "-q", "-m", "Add a")
        refute ok, "a staged marker must refuse the commit"
        assert_match(/conflict markers.*a\.md:2/m, out)
        assert_match(/--no-verify/, out)

        File.write(File.join(repo, "a.md"), "one\ntwo\n")
        git!(repo, "add", "-A")
        ok, out = git!(repo, "commit", "-q", "-m", "Add a\n\nCo-Authored-By: Claude <noreply@anthropic.com>")
        refute ok, "an attribution trailer must refuse the commit"
        assert_match(/AI co-author trailer/, out)

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ok, out = git!(repo, "commit", "-q", "-m", "Add a")
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        assert ok, out
        assert_operator elapsed, :<, 5, "both hooks together stay cheap (budget <1s; slack for a loaded box)"
      end
    end

    def test_a_live_rebuild_of_this_checkout_is_detected_from_the_process_table
      with_repo do |repo|
        H::Installer.new(root: repo, out: StringIO.new).install!
        FileUtils.mkdir_p(File.join(repo, "lib/nabu/store"))
        File.write(File.join(repo, "lib/nabu/store/x.rb"), "# x\n")
        git!(repo, "add", "-A")
        # A stand-in process whose command line reads as a rebuild, running
        # from the scratch checkout.
        pid = Process.spawn("ruby", "-e", "sleep 30", "--", "nabu", "rebuild", chdir: repo)
        begin
          ok, out = git!(repo, "commit", "-q", "-m", "Touch the core")
          refute ok, "a core commit under a live rebuild must hold"
          assert_match(/HOLD.*pid #{pid}/m, out)
        ensure
          Process.kill("TERM", pid)
          Process.wait(pid)
        end
        ok, out = git!(repo, "commit", "-q", "-m", "Touch the core")
        assert ok, "the hold lifts when the rebuild exits: #{out}"
      end
    end
  end
end
