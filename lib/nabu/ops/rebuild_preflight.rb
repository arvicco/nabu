# frozen_string_literal: true

require "time"

require_relative "../eta"
require_relative "../shell"
require_relative "../rebuild_profile"
require_relative "../store/stage_timings"
require_relative "../store/rebuild_runs"
require_relative "../store/lanes"
require_relative "../catalog_write_lock"
require_relative "../fetch_lock"
require_relative "db_snapshot"

module Nabu
  module Ops
    # The full rebuild's BEFORE half: what `nabu rebuild` announces — and,
    # on `--dry-run`, only announces — before it drops anything.
    #
    # Three findings, each read from evidence this box already holds:
    #
    # - THE PRICE. One row per stage the run will execute, in run order:
    #   every replayable source's load, then the corpus stages the
    #   profiler times (RebuildProfile::CORPUS_STAGE_LABELS), each priced
    #   from the LATEST stage_timings row the ledger holds for it (kind
    #   "rebuild" — the same rows the run's own stage announcements read).
    #   A source load without a rebuild row (a source added since the last
    #   full rebuild) takes its heaviest sync load row as a labelled first
    #   estimate. A stage with neither is listed UNPRICED, never guessed;
    #   the total sums the priced stages and says how many are not in it,
    #   and how many of those in it are sync-row estimates. Beside it,
    #   the wall time of the last COMPLETED full run (rebuild_runs) — the
    #   cross-check a summed estimate cannot give (stage gaps, the small
    #   unprofiled stages).
    # - THE DISK. The rebuild is DROP-FIRST, not shadow/swap-in: it
    #   deletes the catalog and the fulltext family (main file + lane
    #   files, each with its sidecars) and then writes fresh ones. The
    #   fresh build's size is priced by the files it replaces, times
    #   DISK_HEADROOM. Available = free space now + the bytes the drop
    #   frees — but a dropped file some process still holds open (a
    #   long-lived `nabu mcp` reader) keeps its blocks until that process
    #   lets go, so when the run DEPENDS on those freed bytes the holders
    #   are probed (lsof) and their files do not count as freed.
    # - THE WRITERS. Anything that would write the catalog or the
    #   canonical tree under the run: the catalog write window held (a
    #   sync's load, an index refresh, the diet — CatalogWriteLock), a
    #   fetch lock held (a fetching sync or a trickle runner — FetchLock),
    #   or a writer process in the process table (a sync between its
    #   windows, another rebuild, an index refresh/maintain). Probes are
    #   non-blocking and release at once; nothing is created.
    #
    # A writer, or a disk shortfall even before headroom, is a BLOCKER:
    # the real run refuses before the drop. Inside the headroom is a
    # warning. READ-ONLY by construction: the ledger is read, locks are
    # probed (shared, non-blocking, released), files are stat'ed.
    class RebuildPreflight
      # const: the fresh build's size over the files it replaces — the
      # replaced files are the best predictor this box has (same corpus,
      # same code); the margin covers the WAL a batched bulk load carries
      # and growth since the last build. A declared margin, not a
      # measurement — so only a shortfall BEFORE it refuses.
      DISK_HEADROOM = 1.25

      # Process-table writers: sync, a non-dry rebuild, an index refresh or
      # maintain pass (the commands that write db/ or canonical/).
      WRITER_COMMAND = %r{(?:\A|[\s/])nabu\s+(?:sync|rebuild|index\s+(?:refresh|maintain))\b}
      DRY_RUN = /--dry-run\b/

      # +corpus+: a corpus stage (scope "corpus") vs a source's load — kept
      # as its own member so a source slugged "corpus" cannot pass for one.
      # +basis+: :rebuild (the stage's own rebuild row), :sync (a first
      # estimate for a source never rebuilt — its heaviest sync load row)
      # or nil (unpriced).
      Stage = Data.define(:scope, :stage, :seconds, :finished_at, :corpus, :basis) do
        def initialize(scope:, stage:, seconds:, finished_at:, corpus:, basis: seconds && :rebuild) = super
        def label = corpus ? RebuildProfile::CORPUS_STAGE_LABELS.fetch(stage.to_sym, stage) : "load #{scope}"
        def priced? = !seconds.nil?
        def estimated? = basis == :sync
      end

      LastRun = Data.define(:started_at, :seconds)

      Forecast = Data.define(:stages, :last_full) do
        def priced = stages.select(&:priced?)
        def unpriced = stages.reject(&:priced?)
        def estimated = stages.select(&:estimated?)
        def total = priced.sum(&:seconds)
      end

      # +files+: [[path, bytes]] the rebuild drops. +pinned+: [[pid,
      # command, path]] holders of those files (probed only when needed).
      Disk = Data.define(:files, :free_bytes, :pinned) do
        def drop_bytes = files.sum { |_, bytes| bytes }
        def pinned_bytes = files.select { |path, _| pinned.any? { |_, _, held| held == path } }.sum { |_, b| b }
        def available = free_bytes && (free_bytes + drop_bytes - pinned_bytes)
        def need = drop_bytes * DISK_HEADROOM
        def short? = !available.nil? && drop_bytes > available
        def tight? = !available.nil? && !short? && need > available
      end

      # +blocking+: false for a holder that never writes the catalog (a
      # trickle runner only fetches) — named in the report, never a blocker.
      Writer = Data.define(:kind, :detail, :blocking) do
        def initialize(kind:, detail:, blocking: true) = super
      end

      Report = Data.define(:forecast, :disk, :writers) do
        def blockers
          lines = writers.select(&:blocking).map { |writer| "#{writer.kind}: #{writer.detail}" }
          if disk.short?
            lines << "disk: the fresh build needs ≈ #{RebuildPreflight.human(disk.drop_bytes)} (what it replaces) " \
                     "but only #{RebuildPreflight.human(disk.available)} is available at the drop"
          end
          lines
        end

        def blocked? = !blockers.empty?
      end

      def self.human(bytes) = DbSnapshot.human(bytes.to_i)

      # +slugs+: the replayable sources in run order (Rebuild#plan's
      # :replay items). +ledger+: the history ledger, nil on a fresh box.
      # The seams (+free_bytes+, +holders+, +ps_output+) default to the
      # real probes; tests hand in their own.
      def initialize(db_dir:, catalog_path:, fulltext_path:, canonical_dir:, slugs:, ledger: nil, trickle_dir: nil,
                     free_bytes: method(:df_free_bytes), holders: RebuildPreflight.method(:lsof_holders),
                     ps_output: -> { GitHooks.ps_output }, own_pids: [Process.pid, Process.ppid])
        @db_dir = db_dir
        @catalog_path = catalog_path
        @fulltext_path = fulltext_path
        @canonical_dir = canonical_dir
        @slugs = slugs
        @ledger = ledger
        @trickle_dir = trickle_dir
        @free_bytes = free_bytes
        @holders = holders
        @ps_output = ps_output
        @own_pids = own_pids
      end

      def report
        Report.new(forecast: forecast, disk: disk, writers: writers)
      end

      # -- the price ------------------------------------------------------------

      def forecast
        loads = @slugs.map { |slug| stage_row(slug, "load", corpus: false) }
        corpus = RebuildProfile::CORPUS_STAGE_LABELS.keys.map { |stage| stage_row("corpus", stage.to_s, corpus: true) }
        Forecast.new(stages: loads + corpus, last_full: last_full)
      end

      def stage_row(scope, stage, corpus:)
        row = Store::StageTimings.last(@ledger, kind: "rebuild", scope: scope, stage: stage)
        return sync_estimate(scope) if row.nil? && !corpus

        Stage.new(scope: scope, stage: stage, seconds: row && row[:seconds].to_f, finished_at: row && row[:finished_at],
                  corpus: corpus)
      end

      # A source added since the last full rebuild has no rebuild load row.
      # Its first estimate is its HEAVIEST sync load row: a rebuild's load
      # is a fresh, full one — the first sync's — while a later no-change
      # sync skips every unchanged document in seconds and would underprice
      # it. Labelled as an estimate; unpriced when it never synced either.
      def sync_estimate(slug)
        row = if Store::StageTimings.table?(@ledger)
                @ledger[Store::StageTimings::TABLE].where(kind: "sync", scope: slug, stage: "load")
                                                   .order(Sequel.desc(:seconds)).select(:seconds, :finished_at).first
              end
        Stage.new(scope: slug, stage: "load", seconds: row && row[:seconds].to_f, finished_at: row && row[:finished_at],
                  corpus: false, basis: row && :sync)
      end

      def last_full
        return nil unless Store::RebuildRuns.table?(@ledger)

        row = @ledger[Store::RebuildRuns::TABLE].where(mode: "full").exclude(completed_at: nil)
                                                .order(Sequel.desc(:id)).first
        return nil if row.nil?

        started = Time.iso8601(row[:started_at].to_s)
        LastRun.new(started_at: started, seconds: Time.iso8601(row[:completed_at].to_s) - started)
      end

      # -- the disk ---------------------------------------------------------------

      def dropped_paths
        [@catalog_path, @fulltext_path, *Store::Lanes.paths_for(@fulltext_path)]
          .flat_map { |path| [path, "#{path}-wal", "#{path}-shm"] }
      end

      def disk
        files = dropped_paths.select { |path| File.file?(path) }.map { |path| [path, File.size(path)] }
        free = @free_bytes.call(@db_dir)
        drop = files.sum { |_, bytes| bytes }
        # Holders matter only when the run needs the freed bytes: free
        # space alone covering the build makes pinning irrelevant.
        pinned = free.nil? || free >= drop * DISK_HEADROOM ? [] : @holders.call(files.map(&:first))
        Disk.new(files: files, free_bytes: free, pinned: pinned)
      end

      # Available bytes on the volume holding +dir+ (`df -k`, asked of its
      # nearest existing ancestor — a fresh box has no db/ yet), nil when
      # unreadable.
      def df_free_bytes(dir)
        dir = File.dirname(dir) until File.directory?(dir) || File.dirname(dir) == dir
        line = Shell.run("df", "-k", dir).lines[1].to_s.split
        line[3] && (Integer(line[3]) * 1024)
      rescue Shell::Error, ArgumentError
        nil
      end

      # [[pid, command, path]] of processes holding any of +paths+ open.
      # One lsof per path: lsof exits 1 for a name nobody holds, and a
      # multi-name call would drop the holders of the others with it.
      # Shared with DbSnapshot.restore!'s open-handle refusal.
      def self.lsof_holders(paths)
        paths.flat_map do |path|
          Shell.run("lsof", "-nP", "-Fpc", "--", path).then { |out| holder_rows(out, path) }
        rescue Shell::Error
          []
        end
      end

      def self.holder_rows(output, path)
        rows = []
        output.each_line do |line|
          case line[0]
          when "p" then rows << [line[1..].to_i, nil, path]
          when "c" then rows[-1] = [rows[-1][0], line[1..].strip, path] if rows.any?
          end
        end
        rows
      end

      # -- the writers ------------------------------------------------------------

      def writers
        write_window + fetch_locks + writer_processes
      end

      def write_window
        path = File.join(@db_dir, CatalogWriteLock::FILENAME)
        return [] if held_by(path).nil?

        slug, pid, since = File.read(path).to_s.split
        held = since ? ", held #{[Time.now.to_i - since.to_i, 0].max}s" : ""
        [Writer.new(kind: "catalog write window", detail: "held by #{slug || 'another writer'}" \
                                                          "#{" (pid #{pid}#{held})" if pid}")]
      rescue SystemCallError
        []
      end

      def fetch_locks
        Dir.glob(File.join(@canonical_dir, FetchLock::LOCKS_DIRNAME, "*.lock")).filter_map do |path|
          next if held_by(path).nil?

          pid = File.read(path).to_s.strip
          slug = File.basename(path, ".lock")
          next trickle_writer(slug, pid) if trickle_runner?(slug, pid)

          Writer.new(kind: "fetch lock", detail: "#{File.basename(path, '.lock')} is being fetched " \
                                                 "(a sync or trickle runner#{", pid #{pid}" unless pid.empty?})")
        rescue SystemCallError
          nil
        end
      end

      # A trickle runner (Ops::Trickle) holds its source's fetch lock for the
      # whole drain — days — but only crawls into canonical/, never loads.
      # It is recognised by its own pidfile naming the lock's holder; a
      # fetching SYNC has no such pidfile and stays a blocker (it loads).
      def trickle_runner?(slug, pid)
        return false if @trickle_dir.nil? || pid.empty?

        File.read(File.join(@trickle_dir, "#{slug}.pid")).to_s.strip == pid
      rescue SystemCallError
        false
      end

      def trickle_writer(slug, pid)
        Writer.new(kind: "trickle crawl", blocking: false,
                   detail: "#{slug} is being crawled by its trickle runner (pid #{pid}) — it only fetches, never " \
                           "loads, so it does not block; the rebuild loads what is held when it reaches #{slug}, " \
                           "and later arrivals land at that source's next sync")
      end

      # true when another process holds an exclusive flock on +path+ (a
      # SHARED non-blocking probe, released at once); nil when the file is
      # absent or free. Never creates the file.
      def held_by(path)
        return nil unless File.file?(path)

        File.open(path, File::RDONLY) do |file|
          return true unless file.flock(File::LOCK_SH | File::LOCK_NB)

          file.flock(File::LOCK_UN)
          nil
        end
      end

      def writer_processes
        @ps_output.call.to_s.each_line.filter_map do |line|
          pid, command = line.strip.split(/\s+/, 2)
          next unless command && pid.to_i.positive? && command.match?(WRITER_COMMAND)
          next if command.match?(DRY_RUN) || @own_pids.include?(pid.to_i)

          Writer.new(kind: "writer process", detail: "pid #{pid}: #{command[0, 100]}")
        end
      end

      # -- rendering --------------------------------------------------------------

      # The announcement, one string per line. +stages+: true prints every
      # stage's row (the dry run and the run log); false prints the
      # heaviest few.
      def self.render(report, stages: true, heaviest: 8)
        Render.new(report).lines(stages: stages, heaviest: heaviest)
      end

      # The announcement's text.
      class Render
        def initialize(report)
          @report = report
        end

        def lines(stages:, heaviest:)
          out = ["rebuild preflight — read before anything is dropped"]
          out.concat(price_lines(stages: stages, heaviest: heaviest))
          out.concat(disk_lines)
          out.concat(writer_lines)
          out << verdict
        end

        private

        def fmt(seconds) = Eta.format_seconds(seconds)
        def human(bytes) = RebuildPreflight.human(bytes)

        def price_lines(stages:, heaviest:)
          forecast = @report.forecast
          loads = forecast.stages.count { |stage| !stage.corpus }
          head = "  price: ~#{fmt(forecast.total)} summed over #{forecast.priced.size} of " \
                 "#{forecast.stages.size} stages (#{loads} source loads + #{forecast.stages.size - loads} " \
                 "corpus stages; each stage's latest ledger row)"
          notes = []
          notes << "#{forecast.estimated.size} priced from a sync row (an estimate)" if forecast.estimated.any?
          notes << "#{forecast.unpriced.size} UNPRICED (no ledger row: first run, no estimate)" if
            forecast.unpriced.any?
          head += " — #{notes.join(', ')}" if notes.any?
          out = [head]
          out << last_full_line(forecast.last_full)
          dated = forecast.priced.filter_map(&:finished_at)
          out << "    basis rows dated #{day(dated.min)} … #{day(dated.max)}" if dated.any?
          shown = stages ? forecast.stages : forecast.priced.max_by(heaviest, &:seconds)
          out << (stages ? "    every stage, in run order:" : "    heaviest #{shown.size}:")
          shown.each { |stage| out << stage_line(stage) }
          out
        end

        def stage_line(stage)
          price = if stage.estimated? then "~#{fmt(stage.seconds)} (sync row)"
                  elsif stage.priced? then "~#{fmt(stage.seconds)}"
                  else "unpriced"
                  end
          format("      %-34<l>s %<t>s", l: stage.label, t: price)
        end

        def last_full_line(last)
          return "    last completed full rebuild: none recorded" if last.nil?

          "    last completed full rebuild: #{fmt(last.seconds)} wall (started #{day(last.started_at)})"
        end

        def day(time) = time.respond_to?(:utc) ? time.utc.strftime("%Y-%m-%d") : time.to_s[0, 10]

        def disk_lines
          disk = @report.disk
          out = ["  disk: drop-first — the run deletes #{human(disk.drop_bytes)} " \
                 "(#{disk.files.size} file(s): catalog + fulltext family with sidecars), then builds fresh ones"]
          if disk.free_bytes.nil?
            out << "    free space unreadable (df) — the need is ≈ #{human(disk.need)}; check by hand"
            return out
          end
          out << "    need ≈ #{human(disk.need)} (#{DISK_HEADROOM}× what it replaces — a declared margin); " \
                 "available at the drop #{human(disk.available)} (free now #{human(disk.free_bytes)} + freed by " \
                 "the drop #{human(disk.drop_bytes - disk.pinned_bytes)})"
          disk.pinned.each do |pid, command, path|
            out << "    ⚠ pid #{pid} (#{command}) holds #{File.basename(path)} open — its " \
                   "#{human(disk.files.to_h.fetch(path, 0))} stay pinned after the drop until it lets go"
          end
          out << "    ⚠ inside the margin: the build fits only if it does not outgrow what it replaces" if disk.tight?
          out
        end

        def writer_lines
          return ["  writers: none (catalog write window free · no fetch lock held · no writer process)"] if
            @report.writers.empty?

          ["  writers: #{@report.writers.size} found"] +
            @report.writers.map { |writer| "    #{writer.blocking ? '⚠' : '·'} #{writer.kind}: #{writer.detail}" }
        end

        def verdict
          blockers = @report.blockers
          return "  verdict: CLEAR — nothing blocks the rebuild" if blockers.empty?

          "  verdict: BLOCKED — #{blockers.join('; ')}"
        end
      end
    end
  end
end
