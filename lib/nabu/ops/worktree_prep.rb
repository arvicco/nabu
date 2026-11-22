# frozen_string_literal: true

require "open3"
require "fileutils"
require_relative "../errors"

module Nabu
  module Ops
    # `rake worktree:prepare` — make a linked git worktree run the STRICT
    # suite. local/ is gitignored, so a fresh worktree carries none of it:
    # the test_helper's StrictSkips gate (skips escalate to failures when
    # local/fixtures/ is present) never binds, restricted-source tests skip
    # quietly, and a lane reports green on a suite the main checkout would
    # fail. This links the main checkout's local/fixtures, local/shelves
    # and local/config into the worktree's local/ (created when absent).
    #
    # The main checkout is resolved from git (the common git dir's parent —
    # what the worktree's .git file points back to), never a hardcoded
    # path. On the main checkout itself the task is a no-op that says so.
    # Idempotent: a correct link is an announced skip; anything else
    # already at a link's path (a real folder, a foreign link) is never
    # replaced. Lives in lib/nabu/ops/ (outside the derivation
    # fingerprint's shared core) and loads only the stdlib.
    class WorktreePrep
      LINKED = %w[fixtures shelves config].freeze

      def initialize(root:, out: $stdout)
        @root = File.expand_path(root)
        @out = out
      end

      # Returns :main_checkout, or the per-folder states
      # (:linked / :present / :foreign / :missing_source).
      def prepare!
        if main_checkout?
          say "== worktree:prepare — #{@root} is the main checkout; nothing to do " \
              "(run it from a linked worktree)"
          return :main_checkout
        end

        say "== worktree:prepare — linking #{main_root}/local/{#{LINKED.join(',')}} into #{@root}/local"
        states = LINKED.to_h { |name| [name, link!(name)] }
        say "== done — the StrictSkips gate now binds here as on the main checkout"
        states
      end

      def main_root
        @main_root ||= File.dirname(File.expand_path(git("rev-parse", "--git-common-dir").strip, @root))
      end

      def toplevel
        @toplevel ||= git("rev-parse", "--show-toplevel").strip
      end

      def main_checkout?
        File.realpath(toplevel) == File.realpath(main_root)
      end

      private

      def link!(name)
        source = File.join(main_root, "local", name)
        link = File.join(toplevel, "local", name)
        unless File.directory?(source)
          say "   local/#{name} — NOT LINKED: #{source} is absent on the main checkout"
          return :missing_source
        end
        if File.symlink?(link) && File.readlink(link) == source
          say "   local/#{name} — present, skipped"
          return :present
        end
        if File.exist?(link) || File.symlink?(link)
          say "   local/#{name} — something already at #{link}, not replaced (move it aside and re-run)"
          return :foreign
        end
        FileUtils.mkdir_p(File.dirname(link))
        File.symlink(source, link)
        say "   local/#{name} — linked #{link} -> #{source}"
        :linked
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
