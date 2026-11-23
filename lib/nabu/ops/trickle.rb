# frozen_string_literal: true

require "English"
require "fileutils"
require "rbconfig"
require "time"

require_relative "../errors"
require_relative "../duration_format"
require_relative "../fetch_lock"
require_relative "../paced_crawl"
require_relative "../process_probe"

module Nabu
  module Ops
    # The TRICKLE RUNNER (architecture §19): an owner-fired standing crawl
    # of one large, slow-paced source, run OUTSIDE phase work and detached
    # from any session. Where `rake crawl:chain` / `rail:step` spend a
    # phase's capped slice allotment, a trickle loops the source's
    # PacedCrawl slices BACK TO BACK, at the engine's own declared pace,
    # until the cone ends, the engine's declared zero-yield budget or an
    # upstream clean stop / outage ends it, a stop is requested, or a fatal
    # error. It is resumable by construction — the engine's ledger and the
    # held payloads are the state; a re-start picks up at the frontier.
    #
    # The runner only CRAWLS: it fetches into canonical/<slug>/ through the
    # engine's fetch_one (the adapter's sanctioned fetch arm) and never
    # loads, syncs or touches db/ — loading stays with normal syncs
    # (`bin/nabu sync <slug> --parse-only` while a trickle runs: it holds
    # the source's FetchLock for its whole life, so a fetching sync of the
    # same source fails fast instead of doubling the request rate against
    # upstream's robots rule, while --parse-only never takes that lock).
    #
    # The loop READS its state; nothing in it is loop-controlled. All of it
    # lives in local/trickle/ (inside the gitignored instance folder,
    # created on demand):
    #
    #   <slug>.pid   the live runner's pid (written at spawn, removed on exit)
    #   <slug>.log   append-only progress: START per lane, one SLICE line per
    #                slice (+N held, held, remaining) with the slice report
    #                indented under it, STOP + SUMMARY when it ends
    #   <slug>.stop  the stop flag (`trickle:stop`), checked before every
    #                request, consumed on exit
    module Trickle
      class Refused < Nabu::Error; end

      # The halt reason a stop request answers through the engine's own
      # clean-stop path (Outcome.halt: the id stays selectable, never
      # ledgered) — so a stop never cuts a request in half.
      STOP_REASON = "trickle stop requested"
      DIRNAME = "trickle"

      # One source's state files under local/trickle/.
      Paths = Data.define(:dir, :slug) do
        def self.for(local_dir:, slug:) = new(dir: File.join(local_dir, DIRNAME), slug: slug)

        def pid = File.join(dir, "#{slug}.pid")
        def log = File.join(dir, "#{slug}.log")
        def stop = File.join(dir, "#{slug}.stop")
      end

      # The pid a pidfile names, nil when absent or unreadable.
      def self.read_pid(path)
        text = File.file?(path) ? File.read(path).strip : ""
        text.match?(/\A\d+\z/) ? Integer(text, 10) : nil
      end

      # Every lane must carry a positive declared pace: the runner never
      # chooses a pace of its own, and a zero-delay lane is a hammer.
      def self.check_lanes!(slug, engines)
        raise Refused, "#{slug} has no paced_crawls lanes — a trickle runs paced-crawl sources only" if
          engines.empty?

        engines.each do |lane, engine|
          next if engine.spec.delay.positive?

          raise Refused, "#{slug}/#{lane} declares no pace (delay #{engine.spec.delay}) — a trickle runs only " \
                         "at an engine's declared, positive delay"
        end
      end

      # The detached child's entry (spawned by Control#start! through
      # spawn_runner): a new session, the adapter's lanes built here, the
      # FetchLock held for the run's whole life, TERM/INT turned into the
      # graceful stop.
      def self.child_main(slug)
        Process.setsid # no controlling terminal: closing the starter's session sends nothing here
        $stdout.sync = true
        $stderr.sync = true
        config = Nabu::Config.load
        entry = Nabu::SourceRegistry.load(config.sources_path)[slug] or raise Refused, "unknown source: #{slug}"
        progress = ->(line) { $stdout.print("  #{line}") }
        engines = entry.build_adapter.paced_crawls(File.join(config.canonical_dir, slug), progress: progress)
        paths = Paths.for(local_dir: config.local_dir, slug: slug)
        runner = Runner.new(slug: slug, engines: engines, paths: paths)
        %w[TERM INT].each { |signal| trap(signal) { runner.request_stop! } }
        FetchLock.hold(canonical_dir: config.canonical_dir, slug: slug) { runner.run! }
      rescue FetchLock::AlreadyHeld, Refused => e
        warn("#{Time.now.utc.iso8601} REFUSED #{slug}: #{e.message}")
        File.delete(paths.pid) if paths && Trickle.read_pid(paths.pid) == Process.pid
        exit 1
      end

      # Detach the runner: a FRESH ruby (spawn), not a fork of the rake
      # process — a forked macOS process inherits whatever the parent
      # initialized (rake, bundler, any native extension's runtime) and
      # fork-safety there is not ours to vouch for; spawn starts clean,
      # returns the pid at once (setsid keeps it, so the pidfile is right
      # from the first instant) and lets the parent report and exit. The
      # child calls setsid itself, so it survives the starting terminal or
      # agent session; Process.detach reaps it should the parent outlive it.
      # stdout/stderr append to the log, so a crash's backtrace lands there.
      # (Nabu::Shell captures and waits — the one thing a detach must not do.)
      def self.spawn_runner(slug:, log:)
        lib = File.expand_path("../..", __dir__)
        script = "require 'nabu'; require 'nabu/ops/trickle'; Nabu::Ops::Trickle.child_main(ARGV.fetch(0))"
        pid = Process.spawn(RbConfig.ruby, "-I", lib, "-e", script, slug,
                            chdir: File.expand_path("..", lib), in: File::NULL,
                            out: [log, "a"], err: [log, "a"])
        Process.detach(pid)
        pid
      end

      # The in-process loop body: everything the daemon does, minus the
      # detach (testable against a real engine over fake lambdas).
      class Runner
        include Nabu::DurationFormat

        Summary = Data.define(:slug, :slices, :added, :held, :remaining, :stop_reason, :elapsed)

        MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        NOW = -> { Time.now.utc }
        SLEEP = ->(seconds) { sleep(seconds) }
        # The lane-opening pause sleeps in steps this long, checking the
        # stop flag between them.
        PAUSE_STEP = 1.0

        def initialize(slug:, engines:, paths:, pid: Process.pid, now: NOW, clock: MONOTONIC, sleeper: SLEEP)
          Trickle.check_lanes!(slug, engines)
          @slug = slug
          @paths = paths
          @pid = pid
          @now = now
          @clock = clock
          @sleeper = sleeper
          @stop = false
          # Every request goes through the stop check: a requested stop
          # answers the engine's clean stop instead of the next request.
          @engines = engines.transform_values do |engine|
            engine.rewire(fetch_one: ->(id, original) { stop_requested? ? stop_outcome : original.call(id) })
          end
        end

        # The signal path's stop (TERM/INT in the daemon): same effect as
        # the flag file.
        def request_stop! = @stop = true

        def stop_requested? = @stop || File.exist?(@paths.stop)

        def run!
          started = @clock.call
          open_log!
          File.write(@paths.pid, "#{@pid}\n")
          @slices = 0
          @state = {}
          finished = false
          reason = begin
            drive
          rescue Nabu::Error => e
            "fatal: #{e.class}: #{e.message}"
          end
          summary = finish!(reason, started)
          finished = true
          summary
        ensure
          # An unexpected exception still leaves its SUMMARY line (and then
          # propagates — its backtrace lands in the log via stderr).
          finish!("fatal (unexpected): #{$ERROR_INFO.class}: #{$ERROR_INFO.message}", started) if
            !finished && @log
        end

        private

        def stop_outcome = PacedCrawl::Outcome.halt(reason: STOP_REASON)

        def open_log!
          FileUtils.mkdir_p(@paths.dir)
          @log = File.open(@paths.log, "a")
          @log.sync = true
        end

        def line(text) = @log.puts("#{@now.call.utc.iso8601} #{text}")

        # The stop reason: every lane in turn, slices back to back.
        def drive
          @engines.each do |lane, engine|
            start_lane(lane, engine)
            reason = drive_lane(lane, engine)
            return reason if reason
          end
          "cone end — every lane exhausted"
        end

        def start_lane(lane, engine)
          diagnosis = engine.diagnose
          @state[lane] = [diagnosis.held_count, diagnosis.remaining_count]
          @start_held ||= {}
          @start_held[lane] = diagnosis.held_count
          line("START #{@slug}/#{lane} (pid #{@pid}): held #{diagnosis.held_count}, remaining " \
               "#{diagnosis.remaining_count} — delay #{engine.spec.delay}s/request, slice #{engine.spec.slice}")
          # One pace interval before the lane's first request: the engine
          # paces between its own requests, but not against the last
          # request of a previous run, lane or sync.
          pause(engine.spec.delay)
        end

        # nil when the lane's cone is done; the stop reason otherwise.
        def drive_lane(lane, engine)
          zero_streak = 0
          budget = engine.spec.schedule.stop_after_zero_slices
          loop do
            return "stop requested" if stop_requested?

            report = engine.slice!
            record_slice(lane, report)
            return nil if report.classification == :cone_exhausted

            reason = stop_reason(report)
            return reason if reason

            zero_streak = report.zero_yield? ? zero_streak + 1 : 0
            next if zero_streak < budget

            return "#{zero_streak} consecutive zero-yield slice(s) — the declared budget " \
                   "(stop_after_zero_slices: #{budget}); read the last slice report before restarting"
          end
        end

        def stop_reason(report)
          if report.classification == :clean_stop
            return "stop requested" if report.halt[:reason] == STOP_REASON

            return "clean stop at #{report.halt[:id]}: #{report.halt[:reason]} — upstream asked the crawl to stop"
          end
          return unless report.classification == :outage_abort

          "upstream outage — #{report.outage[:count]} consecutive outage answer(s) at #{report.outage[:ids].first}" \
            "…#{report.outage[:ids].last}; restart once upstream recovers"
        end

        def record_slice(lane, report)
          @slices += 1
          @state[lane] = [report.held[:after], report.remaining[:after]]
          added = report.held[:after] - report.held[:before]
          label = report.classification.to_s.tr("_", "-")
          line("SLICE #{@slug}/#{lane} ##{@slices} [#{label}]: #{format('%+d', added)} held, held " \
               "#{report.held[:after]}, remaining #{report.remaining[:after]} (#{report.attempted} asked, " \
               "#{report.requests} request(s) in #{format_duration(report.elapsed)})")
          report.lines.each { |text| @log.puts("  #{text}") }
        end

        # Sleeps +seconds+ in PAUSE_STEP steps (counted, not measured — the
        # sleeper is injectable), ending early on a stop request.
        def pause(seconds)
          left = seconds
          while left.positive? && !stop_requested?
            step = [left, PAUSE_STEP].min
            @sleeper.call(step)
            left -= step
          end
        end

        def finish!(reason, started)
          refresh_state!
          held = @state.values.sum(&:first)
          remaining = @state.values.sum(&:last)
          added = @state.sum { |lane, (lane_held, _)| lane_held - @start_held.to_h.fetch(lane, lane_held) }
          elapsed = @clock.call - started
          line("STOP #{@slug}: #{reason}")
          line("SUMMARY #{@slug}: #{@slices} slice(s), #{format('%+d', added)} held, held #{held}, remaining " \
               "#{remaining}, #{format_duration(elapsed)} — #{reason}")
          Summary.new(slug: @slug, slices: @slices, added: added, held: held, remaining: remaining,
                      stop_reason: reason, elapsed: elapsed)
        ensure
          cleanup!
        end

        # The summary's numbers from a fresh OFFLINE diagnosis (a fatal
        # error mid-slice leaves the last report behind the disk); the
        # last known state stands for a lane whose diagnosis fails.
        def refresh_state!
          @state.each_key do |lane|
            diagnosis = @engines.fetch(lane).diagnose
            @state[lane] = [diagnosis.held_count, diagnosis.remaining_count]
          rescue Nabu::Error
            next
          end
        end

        def cleanup!
          File.delete(@paths.pid) if Trickle.read_pid(@paths.pid) == @pid
          FileUtils.rm_f(@paths.stop)
          @log&.close
          @log = nil
        end
      end

      # The owner-facing control surface behind the three rake tasks.
      class Control
        DEFAULT_STOP_WAIT = 90
        SETTLE = 3
        POLL = 0.5
        HELD_RE = /held (\d+), remaining (\d+)/

        def initialize(paths:, canonical_dir:, alive: ProcessProbe.method(:alive?),
                       spawner: Trickle.method(:spawn_runner), out: $stdout, sleeper: ->(seconds) { sleep(seconds) })
          @paths = paths
          @canonical_dir = canonical_dir
          @alive = alive
          @spawner = spawner
          @out = out
          @sleeper = sleeper
        end

        # The live runner's pid, nil when none runs.
        def running_pid
          pid = Trickle.read_pid(@paths.pid)
          pid && @alive.call(pid) ? pid : nil
        end

        # Refuses (Refused) without lanes, beside a live runner, or while a
        # sync/rail step holds the source's FetchLock; otherwise detaches a
        # runner and returns its pid.
        def start!(engines:, settle: SETTLE)
          slug = @paths.slug
          Trickle.check_lanes!(slug, engines)
          pid = running_pid
          if pid
            raise Refused,
                  "a trickle of #{slug} is already running (pid #{pid}) — rake \"trickle:stop[#{slug}]\" first"
          end

          probe_fetch_lock!
          FileUtils.mkdir_p(@paths.dir)
          FileUtils.rm_f(@paths.stop)
          pid = @spawner.call(slug: slug, log: @paths.log)
          File.write(@paths.pid, "#{pid}\n")
          settle!(pid, settle)
          @out.puts("trickle #{slug} started (pid #{pid}) — #{engines.size} lane(s): #{engines.keys.join(', ')}")
          @out.puts("log: #{@paths.log}")
          @out.puts("stop: bundle exec rake \"trickle:stop[#{slug}]\"; status: bundle exec rake trickle:status")
          pid
        end

        # :idle (nothing ran — stale state cleared), :stopped (the runner
        # exited within +wait+ seconds) or :requested (it is finishing its
        # current request).
        def stop!(wait: DEFAULT_STOP_WAIT)
          slug = @paths.slug
          pid = running_pid
          unless pid
            FileUtils.rm_f(@paths.pid)
            FileUtils.rm_f(@paths.stop)
            last = Control.last_line(@paths.log, /SUMMARY/)
            @out.puts("no trickle running for #{slug}#{" — last: #{last}" if last}")
            return :idle
          end

          File.write(@paths.stop, "#{Time.now.utc.iso8601}\n")
          if exited_within?(pid, wait)
            summary = Control.last_line(@paths.log, /SUMMARY/) || "(no SUMMARY)"
            @out.puts("trickle #{slug} stopped (pid #{pid}): #{summary}")
            return :stopped
          end

          @out.puts("stop requested for #{slug} (pid #{pid}) — the runner finishes its current request (at most one " \
                    "pace interval plus the request) and writes its SUMMARY line; rake trickle:status shows it")
          :requested
        end

        # One line per local/trickle/ entry: RUNNING / finished / DIED.
        def self.status(dir:, out: $stdout, alive: ProcessProbe.method(:alive?))
          slugs = Dir.glob(File.join(dir, "*.{pid,log}")).map { |path| File.basename(path, ".*") }.uniq.sort
          if slugs.empty?
            out.puts("no trickles (#{dir} holds no runner state)")
            return
          end

          slugs.each { |slug| out.puts(status_line(Paths.new(dir: dir, slug: slug), alive)) }
        end

        def self.status_line(paths, alive)
          pid = Trickle.read_pid(paths.pid)
          summary = last_line(paths.log, /SUMMARY/)
          state = if pid && alive.call(pid) then "RUNNING (pid #{pid})"
                  elsif summary || pid.nil? then "finished"
                  else "DIED (pid #{pid} gone, no SUMMARY line)"
                  end
          counts = last_line(paths.log, HELD_RE)&.match(HELD_RE)
          numbers = counts ? " — held #{counts[1]}, remaining #{counts[2]}" : ""
          last = last_line(paths.log, /\A\S/) || "(empty log)"
          "#{paths.slug}: #{state}#{numbers}; last: #{last}"
        end

        # The log's last line matching +pattern+ (report lines are indented
        # and skipped by an anchored pattern), nil when none.
        def self.last_line(path, pattern)
          return nil unless File.file?(path)

          File.readlines(path, chomp: true).reverse_each.find { |text| text.match?(pattern) && !text.start_with?(" ") }
        end

        private

        def probe_fetch_lock!
          FetchLock.hold(canonical_dir: @canonical_dir, slug: @paths.slug) { nil }
        rescue FetchLock::AlreadyHeld => e
          raise Refused, "a sync or rail step is fetching #{@paths.slug} (#{e.message}) — let it finish first"
        end

        # A runner that dies at birth (unknown census, a refused lock) is
        # reported with its log tail instead of a false "started".
        def settle!(pid, seconds)
          polls = (seconds / POLL).ceil
          polls.times do
            break unless @alive.call(pid)

            @sleeper.call(POLL)
          end
          return if @alive.call(pid)

          FileUtils.rm_f(@paths.pid) if Trickle.read_pid(@paths.pid) == pid
          tail = File.file?(@paths.log) ? File.readlines(@paths.log).last(8).join : ""
          raise Refused, "the trickle runner for #{@paths.slug} (pid #{pid}) exited at once — log tail:\n#{tail}"
        end

        def exited_within?(pid, seconds)
          polls = (seconds / POLL).ceil
          polls.times do
            return true unless @alive.call(pid)

            @sleeper.call(POLL)
          end
          !@alive.call(pid)
        end
      end
    end
  end
end
