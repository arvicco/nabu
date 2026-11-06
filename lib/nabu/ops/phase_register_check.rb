# frozen_string_literal: true

require_relative "../errors"
require_relative "../shell"

module Nabu
  module Ops
    # `rake boards:check` — the phase-register freshness probe. The local
    # boards keep a phase register: one `## P<N> · <title>` row appended
    # per phase at its gate. Nothing else reads it on a schedule, so a
    # missed append goes unseen for as long as nobody looks. The probe
    # compares the register's newest row (the highest `## P<N>` heading)
    # against the highest phase merged on the main branch — a merge commit
    # "Merge pull request #<n> from <owner>/phase-<N>", read from the local
    # git history (offline: never the GitHub API). A register row behind
    # the merges fails, naming both numbers. A row AHEAD of the merges is
    # fine: the row lands at the gate, before the owner's merge.
    #
    # Like BoardCheck this is a LOCAL instrument over a gitignored file: no
    # register (any public clone, a lane worktree) is an announced skip,
    # and history is not even read. Unreadable history with a register
    # present fails loudly — an unjudgeable register is never passed.
    class PhaseRegisterCheck
      FILE = "phase-register.md"
      ROW = /^##\s+P(\d+)\b/
      PHASE_MERGE = %r{\AMerge pull request #\d+ from \S*/phase-(\d+)\b}

      Report = Data.define(:skipped, :newest_row, :highest_merged, :findings) do
        def clean? = findings.empty?
      end

      # The main branch's first-parent merge subjects, newest first.
      def self.main_merge_subjects(repo:, branch: "main")
        Nabu::Shell.run("git", "-C", repo, "log", branch, "--merges", "--first-parent", "--format=%s")
                   .lines(chomp: true)
      end

      # +merge_subjects+ is a callable returning commit subject lines (the
      # seam tests stub); the default reads +repo+'s main branch.
      def initialize(register_path:, merge_subjects: nil, repo: Dir.pwd)
        @path = register_path
        @merge_subjects = merge_subjects || -> { self.class.main_merge_subjects(repo: repo) }
      end

      def run
        return Report.new(skipped: true, newest_row: nil, highest_merged: nil, findings: []) unless File.file?(@path)

        newest = File.read(@path, encoding: Encoding::UTF_8).scan(ROW).flatten.map(&:to_i).max
        highest, history_error = highest_merged
        Report.new(skipped: false, newest_row: newest, highest_merged: highest,
                   findings: judge(newest, highest, history_error))
      end

      private

      # [highest merged phase or nil, error message or nil].
      def highest_merged
        numbers = @merge_subjects.call.filter_map { |subject| subject[PHASE_MERGE, 1]&.to_i }
        [numbers.max, nil]
      rescue Nabu::Shell::Error => e
        [nil, e.message]
      end

      def judge(newest, highest, history_error)
        name = File.basename(@path)
        return ["#{name}: git history unreadable (#{history_error}) — cannot judge the register"] if history_error
        return ["#{name}: no `## P<N>` row found — the register carries no phase"] unless newest
        return [] if highest.nil? || newest >= highest

        ["#{name}: newest row is P#{newest} but P#{highest} is merged on main — " \
         "append the missing row(s) P#{newest + 1}..P#{highest}"]
      end
    end
  end
end
