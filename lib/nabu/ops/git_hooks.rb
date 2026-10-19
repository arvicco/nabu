# frozen_string_literal: true

require "open3"
require "fileutils"
require_relative "../errors"

module Nabu
  module Ops
    # The local git hook pack (`rake tools:hooks`): three disciplines that
    # were prose-only — and re-offended — compiled into the commit path.
    #
    #   pre-commit  (a) conflict markers in STAGED content (the three
    #                   marker strings, line-anchored — a lone `=======`
    #                   survives a sweep that only looks for `<<<<<<<`);
    #               (b) the mid-rebuild hold: a commit touching the shared
    #                   derivation core (lib/nabu/**, db/migrate/**) while a
    #                   `nabu rebuild` runs FROM THIS CHECKOUT is refused —
    #                   the run stamps derivation fingerprints from the bytes
    #                   on disk hours after it loaded its code, so a mid-run
    #                   commit stales (or falsifies) every stamp it mints.
    #   commit-msg  (c) AI-attribution footers and internal workflow ids
    #                   in the message (the public-surface hygiene rule's
    #                   commit half — the suite can only guard the tree).
    #
    # Each refusal prints WHY and the override (git's own --no-verify).
    # The scripts live tracked under script/git-hooks/; the installer
    # SYMLINKS them into the hooks dir, so an edit to the tracked script
    # is live at once. Linked worktrees share the main checkout's hooks
    # dir, so the links always target the MAIN checkout's scripts — a
    # worktree's copy would dangle when the worktree is removed.
    #
    # Lives in lib/nabu/ops/ (outside the derivation fingerprint's shared
    # core), loads nothing but the stdlib, and keeps to syntax any Ruby a
    # git client might launch can parse: a hook runs on every commit and
    # must cost well under a second.
    module GitHooks
      HOOKS = %w[pre-commit commit-msg].freeze
      SCRIPT_DIR = File.join("script", "git-hooks")

      OVERRIDE = "override deliberately: git commit --no-verify"

      # Upstream fixture bytes are kept verbatim — a marker-shaped line in
      # them is upstream's, never ours (the suite's sweep uses the same
      # exemption).
      MARKER_EXEMPT = %r{\A(?:test/fixtures/|local/)}
      MARKER_LINE = /\A(?:<{7}(?:\s|\z)|={7}\s*\z|>{7}(?:\s|\z))/

      # The shared derivation core a live rebuild digests at stamp time
      # (DerivationFingerprint): every lib/nabu file, adapters included —
      # a mid-run adapter commit mints a stamp naming code the run never
      # loaded — plus the schema.
      HOLD_PATHS = %r{\A(?:lib/nabu/|db/migrate/)}

      # A running full or incremental rebuild; a dry run reads only.
      REBUILD_COMMAND = %r{(?:\A|[\s/])nabu\s+rebuild\b}
      DRY_RUN = /--dry-run\b/

      # [pattern, reason]. Attribution: the project's commits carry no AI
      # attribution of any kind (trailer, footer, product or session link).
      ATTRIBUTION = [
        [/^\s*co-authored-by:.*\b(?:claude|anthropic)\b/i, "an AI co-author trailer"],
        [/generated\s+(?:with|by)\s+\[?claude/i, "a generated-with-Claude footer"],
        [%r{claude\.(?:ai|com)/}i, "a Claude product or session link"],
        [/noreply@anthropic\.com/i, "an Anthropic attribution address"],
        [/\u{1F916}/, "the robot-emoji attribution footer"]
      ].freeze

      # The numero sign, built from its codepoint: a literal one would trip
      # the tracked-file hygiene guard this list mirrors.
      NUMERO = 0x2116.chr(Encoding::UTF_8)

      # Internal workflow ids and correspondence machinery — the same
      # classes test/public_hygiene_test.rb forbids in tracked files,
      # written so this file never matches its own patterns.
      WORKFLOW_IDS = [
        [Regexp.new(NUMERO), "the numero sign only ever marks an internal register/thread id"],
        [/\bQ\d{2,3}\b/, "an internal work-queue id"],
        [/\bT-\d+\b/, "an internal thread id"],
        [/OWNER\s+ACTIONS/, "an owner-action list"],
        [/email.register|external.communications\.md/, "a private correspondence path"],
        [/\b(?:your|the)\s+Drafts\b|Drafts\s+folder|thank-you\s+draft|mailbox\s+draft/i,
         "correspondence workflow state"]
      ].freeze

      SCISSORS = /^# -+ >8 -+$/

      module_function

      # -- the checks (pure; the hooks feed them git/ps output) ---------------

      # Added lines carrying a conflict marker, from `git diff --cached -U0`
      # output: ["path:line: marker", ...].
      def conflict_markers(diff)
        offenses = []
        path = nil
        line_no = 0
        # Staged diffs can carry non-UTF-8 fixture bytes (Windows-1252
        # upstream files); the markers are pure ASCII, so scrubbing loses
        # nothing and the scan must never crash a commit.
        diff = diff.dup.force_encoding(Encoding::UTF_8).scrub("�")
        diff.each_line do |raw|
          line = raw.chomp
          if line.start_with?("+++ ")
            # --diff-filter=ACMR: every post-image is a real b/ path.
            path = line[4..].sub(%r{\Ab/}, "")
          elsif (hunk = line.match(/\A@@ -\S+ \+(\d+)/))
            line_no = hunk[1].to_i
          elsif line.start_with?("+") && path
            added = line[1..]
            if !path.match?(MARKER_EXEMPT) && added.match?(MARKER_LINE)
              offenses << "#{path}:#{line_no}: #{added.strip[0, 40]}"
            end
            line_no += 1
          end
        end
        offenses
      end

      # Live rebuild processes from `ps -Ao pid=,command=` output:
      # [[pid, command], ...]. Dry runs and this probe itself excluded.
      def rebuild_processes(ps_output)
        rows = ps_output.each_line.map do |line|
          pid, command = line.strip.split(/\s+/, 2)
          next unless command && pid.to_i.positive?
          next unless command.match?(REBUILD_COMMAND) && !command.match?(DRY_RUN)
          next if pid.to_i == Process.pid

          [pid.to_i, command]
        end
        rows.compact
      end

      # The hold verdict: nil (commit freely) or the refusal text. +cwd_of+
      # maps a pid to its working directory (nil = unknowable, which holds
      # conservatively); a rebuild running from ANOTHER checkout (the main
      # tree, while this commit lands in a lane worktree) cannot be staled
      # by bytes it never reads.
      def rebuild_hold(staged:, processes:, toplevel:, cwd_of:)
        core = staged.grep(HOLD_PATHS)
        return nil if core.empty?

        holders = processes.select do |pid, _command|
          cwd = cwd_of.call(pid)
          cwd.nil? || same_tree?(cwd, toplevel)
        end
        return nil if holders.empty?

        pid, command = holders.first
        shown = core.first(5)
        shown << "+#{core.size - 5} more" if core.size > 5
        <<~MSG
          pre-commit: HOLD — a rebuild is running from this checkout (pid #{pid}: #{command[0, 80]}).
            Staged shared-core paths: #{shown.join(', ')}
            Why: the rebuild stamps derivation fingerprints from the bytes on disk at
            mint time, hours after it loaded its code — a commit now stales (or
            falsifies) every stamp it mints, and the next incremental replays the
            whole library. Leave the work staged; commit once pid #{pid} exits.
            #{OVERRIDE}
        MSG
      end

      def same_tree?(cwd, toplevel)
        real_cwd = File.realpath(cwd)
        real_top = File.realpath(toplevel)
        real_cwd == real_top || real_cwd.start_with?("#{real_top}/")
      rescue SystemCallError
        true
      end

      # Offending lines of a commit message: ["reason: line", ...]. Comment
      # lines and everything below the scissors line are git's, not the
      # message's.
      def message_offenses(message)
        body = message.split(SCISSORS, 2).first.to_s
        lines = body.each_line.map(&:chomp).reject { |line| line.start_with?("#") }
        (ATTRIBUTION + WORKFLOW_IDS).each_with_object([]) do |(pattern, reason), offenses|
          hit = lines.find { |line| line.match?(pattern) }
          offenses << "#{reason}: #{hit.strip[0, 72]}" if hit
        end
      end

      # -- the hook entry points (exit codes) ---------------------------------

      def pre_commit(err: $stderr, git: method(:git), process_table: method(:ps_output),
                     cwd_of: method(:process_cwd))
        toplevel = git.call("rev-parse", "--show-toplevel").strip
        diff = git.call("diff", "--cached", "--no-color", "--no-ext-diff", "-U0", "--diff-filter=ACMR")
        markers = conflict_markers(diff)
        unless markers.empty?
          err.puts "pre-commit: REFUSED — conflict markers in staged content:"
          markers.first(20).each { |offense| err.puts "  #{offense}" }
          err.puts "  Why: a committed marker is a broken merge shipped; resolve every hunk"
          err.puts "  (all three marker strings — a lone ======= line survives a <<<<<<<-only sweep)."
          err.puts "  #{OVERRIDE}"
          return 1
        end
        staged = git.call("diff", "--cached", "--name-only", "--no-renames").split("\n")
        hold = rebuild_hold(staged: staged, processes: rebuild_processes(process_table.call),
                            toplevel: toplevel, cwd_of: cwd_of)
        if hold
          err.puts hold
          return 1
        end
        0
      end

      def commit_msg(path, err: $stderr)
        offenses = message_offenses(File.read(path, encoding: Encoding::UTF_8))
        return 0 if offenses.empty?

        err.puts "commit-msg: REFUSED — the message carries what a public surface never does:"
        offenses.each { |offense| err.puts "  #{offense}" }
        err.puts "  Why: commit messages are public; they carry technical content and"
        err.puts "  license-provenance facts only — no AI attribution, no internal workflow ids."
        err.puts "  Rewrite the message (your text is kept in #{path})."
        err.puts "  #{OVERRIDE}"
        1
      end

      def git(*args)
        out, status = Open3.capture2("git", *args)
        raise "git #{args.first} failed" unless status.success?

        out
      end

      def ps_output
        out, = Open3.capture2("ps", "-Ao", "pid=,command=")
        out
      rescue SystemCallError
        ""
      end

      def process_cwd(pid)
        out, = Open3.capture2("lsof", "-a", "-p", pid.to_s, "-d", "cwd", "-Fn")
        line = out.each_line.find { |row| row.start_with?("n") }
        line && line[1..].chomp
      rescue SystemCallError
        nil
      end

      # -- the installer (rake tools:hooks) -------------------------------------

      # +root+ is any checkout of the repo (main or linked worktree).
      class Installer
        def initialize(root:, out: $stdout)
          @root = root
          @out = out
        end

        # Link every hook; idempotent (a correct link is an announced skip).
        # A foreign hook already in place is never clobbered. Returns the
        # per-hook states.
        def install!
          say "== nabu git hooks (rake tools:hooks) — idempotent, re-run freely"
          states = HOOKS.to_h { |hook| [hook, link!(hook)] }
          say "== done — refusals print why; #{OVERRIDE}"
          states
        end

        def status
          HOOKS.to_h do |hook|
            link = File.join(hooks_dir, hook)
            state = if linked?(link, target(hook)) then "installed  #{link} -> #{target(hook)}"
                    elsif File.exist?(link) || File.symlink?(link) then "FOREIGN    #{link}"
                    else "MISSING    (#{link})"
                    end
            ["git hook #{hook}", state]
          end
        end

        def hooks_dir
          @hooks_dir ||= File.expand_path(git("rev-parse", "--git-path", "hooks").strip, @root)
        end

        # The main checkout: the common git dir's parent (a linked
        # worktree's own toplevel would vanish with the worktree).
        def main_root
          @main_root ||= File.dirname(File.expand_path(git("rev-parse", "--git-common-dir").strip, @root))
        end

        def target(hook)
          File.join(main_root, SCRIPT_DIR, hook)
        end

        private

        def link!(hook)
          source = target(hook)
          link = File.join(hooks_dir, hook)
          unless File.file?(source)
            say "   #{hook} — NOT LINKED: #{source} is absent (land script/git-hooks/ on the " \
                "main checkout, then re-run)"
            return :missing_source
          end
          if linked?(link, source)
            say "   #{hook} — present, skipped"
            return :present
          end
          if File.exist?(link) || File.symlink?(link)
            say "   #{hook} — FOREIGN hook at #{link}, not replaced (move it aside and re-run)"
            return :foreign
          end
          FileUtils.mkdir_p(hooks_dir)
          File.symlink(source, link)
          say "   #{hook} — linked #{link} -> #{source}"
          :installed
        end

        def linked?(link, source)
          File.symlink?(link) && File.readlink(link) == source
        end

        def git(*args)
          out, status = Open3.capture2("git", "-C", @root, *args)
          raise Nabu::Error, "git #{args.join(' ')} failed in #{@root}" unless status.success?

          out
        end

        def say(line)
          @out.puts(line)
        end
      end
    end
  end
end
