# frozen_string_literal: true

module Nabu
  # The seam-census hook for kind: module rows. A feature module holds ZERO
  # documents by invariant, so the document-grain counters every printout
  # renders ("+0 added ~0 updated", "empty") say nothing about it; what a
  # module adds is its seam's data. Each module adapter MAY expose
  #
  #     def self.module_census(read) -> [Count, ...] | nil
  #
  # where +read+ maps a path relative to the module's canonical tree to its
  # String content (nil when absent). Reading through a callable lets the
  # same counter run over the working tree AND over an old git blob, so a
  # sync prints a delta. The default (Nabu::Adapter) is nil: a module whose
  # seam has no census falls back to an honest descriptor (its pin, or the
  # changed-file list on sync) — never fake zeros. Enriching another module
  # is one method on its adapter.
  #
  # Read-only on canonical/: plain file reads and `git rev-parse` / `git
  # show` / `git diff --name-only`, all through Nabu::Shell.
  module ModuleCensus
    # One labeled figure ("246 anchors").
    Count = Data.define(:label, :count)

    # What one module sync moved, for the summary line. +before+/+after+ are
    # the ref before the fetch and the fetched sha (nil when unknown);
    # +fetched+ false for a parse-only run; +changed+ the changed paths
    # (nil when not computable or nothing moved); +census+ the seam census
    # now and +previous_census+ at +before+ (nil when nothing moved or the
    # seam has none).
    Delta = Data.define(:before, :after, :fetched, :changed, :census, :previous_census) do
      def moved? = fetched && !before.nil? && !after.nil? && before != after
    end

    SHA_WIDTH = 12

    module_function

    # The seam census over +dir+'s working tree; nil when the module has no
    # census hook or its files are absent.
    def at_dir(adapter_class, dir)
      return nil unless adapter_class.respond_to?(:module_census) && Dir.exist?(dir)

      adapter_class.module_census(lambda do |rel|
        path = File.join(dir, rel)
        File.file?(path) ? File.read(path) : nil
      end)
    end

    # The seam census as of git revision +sha+ in +dir+ (the old blob read
    # through `git show`); nil when unreadable.
    def at_revision(adapter_class, dir, sha)
      return nil unless adapter_class.respond_to?(:module_census) && git_repo?(dir)

      adapter_class.module_census(lambda do |rel|
        Shell.run("git", "-C", dir, "show", "#{sha}:#{rel}")
      rescue Shell::Error
        nil
      end)
    end

    # The HEAD sha of +dir+ when it is a git repo OF ITS OWN (a bare
    # rev-parse would walk up into an enclosing checkout); nil otherwise.
    def head(dir)
      return nil unless git_repo?(dir)

      Shell.run("git", "-C", dir, "rev-parse", "HEAD").strip
    rescue Shell::Error
      nil
    end

    def git_repo?(dir)
      File.exist?(File.join(dir, ".git"))
    end

    # Assemble the sync Delta for one module (SyncRunner, after the fetch).
    def delta(adapter_class:, dir:, before:, after:, fetched:)
      moved = fetched && before && after && before != after
      Delta.new(before: before, after: after, fetched: fetched,
                changed: moved ? changed_paths(dir, before, after) : nil,
                census: at_dir(adapter_class, dir),
                previous_census: moved ? at_revision(adapter_class, dir, before) : nil)
    end

    def changed_paths(dir, before, after)
      return nil unless git_repo?(dir)

      Shell.run("git", "-C", dir, "diff", "--name-only", before, after).split("\n").reject(&:empty?)
    rescue Shell::Error
      nil
    end

    # "248 anchors (+2) · 125 stages · …" — nonzero deltas only (the house
    # compact-zero rule); a figure the old census lacks carries no delta.
    def render(counts, previous: nil)
      before = (previous || []).to_h { |count| [count.label, count.count] }
      counts.map do |count|
        diff = before.key?(count.label) ? count.count - before.fetch(count.label) : 0
        "#{count.count} #{count.label}#{delta_tail(diff)}"
      end.join(" · ")
    end

    def delta_tail(diff)
      return "" if diff.zero?

      diff.positive? ? " (+#{diff})" : " (#{diff})"
    end

    # The one-cell descriptor for info printouts (list/status): the census
    # when the seam has one, else the honest generic — the pinned sha the
    # module is held at.
    def summary(counts, pin:)
      return render(counts) if counts && !counts.empty?

      pin ? "module @ #{pin[0, SHA_WIDTH]}" : "module (not synced)"
    end
  end
end
