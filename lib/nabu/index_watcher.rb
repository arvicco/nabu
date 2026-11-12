# frozen_string_literal: true

require "fileutils"
require_relative "duration_format"
require_relative "process_probe"

module Nabu
  # Index writers supervise themselves (the incrementality review, R6).
  #
  # == Why a separate PROCESS
  #
  # The hours-class stalls of 2026-11 all ran inside ONE sqlite3_step: the
  # sqlite3 gem holds Ruby's GVL for the whole statement, so no thread,
  # timer or signal trap inside the writer can run until the engine
  # returns — the in-process watchdog was designed, measured dead, and
  # killed for exactly that reason. Supervision therefore lives in a tiny
  # forked WATCHER subprocess that never touches the writer's memory or
  # connections: it samples the writer from outside (the pid's ps state,
  # the age of the heartbeat file the writer's progress ticks keep fresh)
  # and acts through the kernel (signals) and fresh connections of its own.
  #
  # == What it does
  #
  #   - HEARTBEAT: once ticks stall for STALL_SECONDS it prints one line
  #     ("no progress tick for 12m — inside one statement …; fts5 merge
  #     suspected") and repeats it every HEARTBEAT_EVERY while the stall
  #     lasts — a grind becomes a visible, timed event instead of a hang.
  #   - DEADLINE: at ~2× the stage ledger's estimate (deadline_for — never
  #     under MIN_DEADLINE_SECONDS; the command's --deadline flag
  #     overrides, 0 disables the kill; no history = heartbeats only) it
  #     SIGTERMs the writer, and SIGKILLs it after KILL_GRACE_SECONDS — a
  #     GVL-held statement never runs the TERM handler, which is the point.
  #   - HYGIENE, after a kill or after the writer died on its own without a
  #     clean finish: the work its ensure-blocks never ran — a read-write
  #     connect (which replays the engine-config intent journal, restoring
  #     the persisted merge settings — Store::EngineIntents), a TRUNCATE
  #     checkpoint of the WAL, and the refreshed source's slice marker left
  #     honestly PENDING so the next sync heals it.
  #
  # A clean finish (the supervised block returns or raises — its own
  # ensure-blocks ran) writes "stop" down a pipe; the watcher exits
  # without hygiene. A writer killed from outside closes the pipe without
  # the word (EOF) — and the ps probe catches a writer that is not the
  # pipe's owner (the suite's fake writers) — so death without a clean
  # finish always earns the hygiene. The watcher ignores SIGINT: a ^C
  # reaches the whole process group, and the writer's own ensure path
  # still ends in a clean stop.
  #
  # Dependency-free by construction: fork, a pipe, File.mtime and ps.
  class IndexWatcher
    include DurationFormat

    # Tick silence before the first stall line, and its repeat cadence.
    # The writer ticks per 2,000-row batch and per stage; a quiet minute is
    # normal, ten is one statement grinding.
    STALL_SECONDS = 10 * 60
    HEARTBEAT_EVERY = 5 * 60
    # How often the watcher samples; small against any stall it reports.
    SAMPLE_SECONDS = 15
    # The deadline is DEADLINE_FACTOR × the ledger estimate, floored: a
    # seconds-scale estimate must not arm a seconds-scale kill (statement
    # variance on a cold page cache alone exceeds it). The factor prices
    # estimate UNCERTAINTY, not the estimate (owner, 2026-11-12, after a
    # healthy first-sync shadow build was killed at the floor): a ledger
    # estimate is one past run, so the killer stands well back from it.
    DEADLINE_FACTOR = 2.5
    MIN_DEADLINE_SECONDS = 15 * 60
    KILL_GRACE_SECONDS = 30

    # The kill deadline in seconds, or nil (heartbeats only): the flag
    # wins (0 = never kill); else DEADLINE_FACTOR × +estimate+, floored.
    # +arm_default+ false means the command never arms a kill from history
    # alone — only an explicit flag does. Rebuilds run that way: a
    # rebuild's ledger estimate is a backward-looking sum, and the very
    # rebuilds that matter most are the ones that GROW past it (new
    # sources, a re-flagged lane, a new storage layout) — a kill armed at
    # 2× yesterday would execute the crash-loss incident on purpose.
    def self.deadline_for(estimate:, override_minutes: nil, arm_default: true)
      unless override_minutes.nil?
        return override_minutes.to_f.positive? ? override_minutes.to_f * 60 : nil
      end
      return nil unless arm_default
      return nil if estimate.nil? || !estimate.positive?

      [estimate * DEADLINE_FACTOR, MIN_DEADLINE_SECONDS].max
    end

    # A kill may only be armed on evidence that DESCRIBES the run: every
    # named non-corpus scope must carry its own history under +kind+, or
    # the summed "estimate" is just the corpus riders' seconds — about a
    # first sync it says nothing (measured 2026-11-12: a healthy
    # 1.26M-row first-sync shadow build killed at the floor, armed off
    # 40.9s of corpus rows). nil +scopes+ = an unscoped command whose
    # estimate sums everything it will run: covered by construction.
    # +stages+ names the stage class whose history must exist (a killed
    # run flushes the stages that FINISHED, so scope-level history can
    # exist while the dominant stage — the one the kill endangers — has
    # no row at all; measured 2026-11-12, the rerun after the first
    # kill: fetch+parse rows summed to an 11m25s "estimate" with the
    # index stage absent from it entirely).
    def self.evidence_covers?(ledger, kind:, scopes:, stages: nil)
      return true if scopes.nil?

      own = scopes - ["corpus"]
      return true if own.empty?
      return false unless Store::StageTimings.table?(ledger)

      rows = ledger[Store::StageTimings::TABLE].where(kind: kind, scope: own)
      rows = rows.where(stage: stages) if stages
      covered = rows.distinct.select_map(:scope)
      (own - covered).empty?
    end

    # The stage ledger's estimate for a command: the sum of the LATEST row
    # of every (scope, stage) recorded under +kind+ for +scopes+ (nil =
    # every scope). nil when the ledger has no history for them.
    # +stages+ (nil = all) narrows to the stages the command actually runs
    # (an index refresh runs a sync's index stages, never its fetch/load).
    def self.ledger_estimate(ledger, kind:, scopes: nil, stages: nil)
      return nil unless Store::StageTimings.table?(ledger)

      rows = ledger[Store::StageTimings::TABLE].where(kind: kind)
      rows = rows.where(scope: scopes) if scopes
      rows = rows.where(stage: stages) if stages
      latest = rows.group(:scope, :stage).select { max(:id).as(:id) }
      total = ledger[Store::StageTimings::TABLE].where(id: latest).sum(:seconds)
      total&.positive? ? total.to_f : nil
    end

    def self.alive?(pid) = ProcessProbe.alive?(pid)

    # The one line a supervised command opens with: what the watcher will
    # do, and on what evidence. The CLI prints it whenever a kill is armed,
    # and the heartbeats-only case on a tty alone — honesty on a screen,
    # never noise in a log (the no-estimate note's P78-r3 rule).
    def self.arming_line(deadline:, estimate:, kill_default: true)
      fmt = Object.new.extend(DurationFormat)
      if deadline.nil?
        unless kill_default
          return "index watcher: heartbeats only — this command arms no kill by default " \
                 "(--deadline MINUTES arms one)"
        end
        return "index watcher: heartbeats only — no kill deadline (--deadline MINUTES arms one)" if estimate

        return "index watcher: heartbeats only — no ledger estimate for this run (--deadline MINUTES arms a kill)"
      end
      basis = estimate ? "the ledger's #{fmt.format_duration(estimate)} estimate" : "--deadline"
      "index watcher: armed — kills the writer at #{fmt.format_duration(deadline)} (#{basis}; " \
        "--deadline 0 disables)"
    end

    # The sync stages an index refresh runs (Indexer.refresh_source!'s
    # timed stages; a dictionary sync's closure re-walk included). The
    # shadow builds are arrival events sized by the load, never planned
    # from history (Store::IndexCostClasses).
    REFRESH_STAGES = %w[index_slice postings_swaps fts_merge reflex_closure reflex_rewalk].freeze

    # Run the block as the supervised writer: a watcher forked over THIS
    # process, the heartbeat file fed through the progress tee the block
    # receives (call it on the command's reporter), and a clean stop —
    # heartbeat file removed — however the block ends.
    def self.supervise(label:, fulltext_path:, deadline:, heartbeat_path: nil, slug: nil, log_path: nil)
      heartbeat_path ||= File.join(File.dirname(fulltext_path), ".index-writer-#{Process.pid}.heartbeat")
      FileUtils.mkdir_p(File.dirname(heartbeat_path))
      heartbeat = Heartbeat.new(heartbeat_path)
      heartbeat.beat!("start #{label}")
      watcher = new(writer_pid: Process.pid, heartbeat_path: heartbeat_path, fulltext_path: fulltext_path,
                    label: label, deadline: deadline, slug: slug, log_path: log_path)
      watcher.start!
      begin
        yield ->(progress) { tee(progress, heartbeat) }
      ensure
        watcher.stop!
        FileUtils.rm_f(heartbeat_path)
      end
    end

    # A ProgressReporter that freshens the heartbeat on every event, then
    # hands it to +progress+'s own sinks unchanged.
    def self.tee(progress, heartbeat)
      progress ||= ProgressReporter.new
      ProgressReporter.new(
        on_fetch_line: lambda { |line|
          heartbeat.tick!("fetch")
          progress.on_fetch_line&.call(line)
        },
        on_load_tick: lambda { |processed, errored|
          heartbeat.tick!("load_tick #{processed}")
          progress.on_load_tick&.call(processed, errored)
        },
        on_stage: lambda { |label, eta|
          heartbeat.beat!("stage #{label}")
          progress.on_stage&.call(label, eta)
        },
        on_note: lambda { |line|
          heartbeat.beat!("note #{line}")
          progress.on_note&.call(line)
        },
        on_explain: progress.on_explain
      )
    end

    # The writer's side of the heartbeat: the file's mtime IS the tick age
    # the watcher reads, its content the last event (for the stall line).
    # Stage/note events always write; per-document ticks are throttled to
    # one write per +min_interval+ so a hot load loop pays nothing.
    class Heartbeat
      def initialize(path, min_interval: 1.0)
        @path = path
        @min_interval = min_interval
        @last = nil
      end

      def beat!(line)
        File.write(@path, "#{line}\n")
        @last = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def tick!(line)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if @last && now - @last < @min_interval

        beat!(line)
      end
    end

    def initialize(writer_pid:, heartbeat_path:, fulltext_path:, label:, deadline:, slug: nil, log_path: nil,
                   sample_seconds: SAMPLE_SECONDS, stall_seconds: STALL_SECONDS,
                   heartbeat_every: HEARTBEAT_EVERY, kill_grace: KILL_GRACE_SECONDS)
      @writer_pid = writer_pid
      @heartbeat_path = heartbeat_path
      @fulltext_path = fulltext_path
      @label = label
      @deadline = deadline
      @slug = slug
      @log_path = log_path
      @sample = sample_seconds
      @stall = stall_seconds
      @heartbeat_every = heartbeat_every
      @kill_grace = kill_grace
    end

    # Fork the watcher; returns its pid.
    def start!
      reader, @stop_writer = IO.pipe
      @pid = quiet_sqlite_fork_warning do
        fork do
          @stop_writer.close
          trap("INT", "IGNORE")
          begin
            watch(reader)
          ensure
            exit!(0) # never the writer's at_exit handlers (a suite, a CLI)
          end
        end
      end
      reader.close
      @pid
    end

    # The sqlite3 gem (2.10.x) warns in the child about every writable
    # handle the fork inherited, then discards it. This fork is deliberate
    # and the child touches no inherited connection by construction (pipe +
    # File.mtime + ps only), so the warning is silenced for it alone — any
    # other fork in the process still warns. The parse-pool precedent.
    def quiet_sqlite_fork_warning
      return yield unless defined?(SQLite3::ForkSafety)

      previous = SQLite3::ForkSafety.instance_variable_get(:@suppress)
      SQLite3::ForkSafety.suppress_warnings!
      begin
        yield
      ensure
        SQLite3::ForkSafety.instance_variable_set(:@suppress, previous)
      end
    end

    # The clean finish: tell the watcher, reap it.
    def stop!
      return if @pid.nil?

      begin
        @stop_writer.write("stop\n")
        @stop_writer.close
      rescue IOError, Errno::EPIPE
        nil # the watcher already left (its deadline fired, or it was killed)
      end
      begin
        Process.wait(@pid)
      rescue Errno::ECHILD
        nil
      end
      @pid = nil
    end

    private

    def watch(stop_reader)
      started = now
      last_line = nil
      loop do
        return if stopped?(stop_reader)
        return writer_died! unless self.class.alive?(@writer_pid)

        age = tick_age(started)
        if age >= @stall && (last_line.nil? || now - last_line >= @heartbeat_every)
          say(stall_line(age))
          last_line = now
        end
        return deadline! if @deadline && now - started >= @deadline
      end
    end

    # Wait one sample on the stop pipe: "stop" = clean finish; EOF without
    # it = the pipe's owner died (falls through to the liveness probe).
    def stopped?(stop_reader)
      return false unless stop_reader.wait_readable(@sample)

      message = stop_reader.read_nonblock(16, exception: false)
      message.is_a?(String) && message.include?("stop")
    rescue EOFError
      false
    end

    # Seconds since the writer last freshened the heartbeat (wall clock on
    # both sides — File.mtime is wall time); since the watch began when the
    # file is gone.
    def tick_age(started)
      Time.now - File.mtime(@heartbeat_path)
    rescue Errno::ENOENT
      now - started
    end

    def stall_line(age)
      last = File.read(@heartbeat_path).strip
      "index watcher: no progress tick for #{format_duration(age)} — inside one statement " \
        "(#{@label}; writer pid #{@writer_pid}, state #{ProcessProbe.state(@writer_pid) || '?'}, " \
        "last: #{last}); fts5 merge suspected"
    rescue Errno::ENOENT
      "index watcher: no progress tick for #{format_duration(age)} (#{@label}); fts5 merge suspected"
    end

    def deadline!
      say("index watcher: deadline #{format_duration(@deadline)} passed — killing the writer (pid #{@writer_pid})")
      kill_writer!
      hygiene!
    end

    def writer_died!
      say("index watcher: writer (pid #{@writer_pid}) died without a clean finish — running the hygiene")
      hygiene!
    end

    # TERM first (a writer between statements exits through its ensure
    # path), KILL after the grace (a GVL-held statement never sees TERM).
    def kill_writer!
      signal(:TERM)
      return if dead_within?(@kill_grace)

      signal(:KILL)
      dead_within?(@kill_grace)
    end

    def signal(name)
      Process.kill(name, @writer_pid)
    rescue Errno::ESRCH
      nil
    end

    def dead_within?(seconds)
      deadline = now + seconds
      while now < deadline
        return true unless self.class.alive?(@writer_pid)

        sleep(0.05)
      end
      !self.class.alive?(@writer_pid)
    end

    # The work the writer's ensure-blocks never ran (class note).
    def hygiene!
      return say("index watcher: hygiene skipped — no fulltext at #{@fulltext_path}") unless
        File.file?(@fulltext_path)

      db = Store.connect_fulltext(@fulltext_path) # replays the engine-config intent journal
      Store::Indexer.checkpoint_wal!(db)
      Store::Indexer.mark_slice_pending!(db, @slug) if @slug
      pending = @slug ? ", slice #{@slug} left pending" : ""
      say("index watcher: hygiene: engine config restored, WAL truncated#{pending}")
    ensure
      db&.disconnect
    end

    def say(line)
      if @log_path
        File.open(@log_path, "a") { |file| file.puts(line) }
      else
        warn(line)
      end
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
