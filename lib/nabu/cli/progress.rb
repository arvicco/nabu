# frozen_string_literal: true

# Nabu::CLI — shared progress-narration helpers for long-running commands.
# Carved out of lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    # The one-physical-line contract for every \r-rendered progress line: a
    # line wider than the terminal soft-wraps, and "\r\e[K" then rewrites
    # only the LAST wrapped row — so each tick scrolls a permanent line and
    # a stage meant to be ONE updating line prints one line per tick. Every
    # \r site renders through here: the assembled line is clamped to
    # width-1 cells by ellipsis-truncating the LABEL (the counters the
    # viewer watches stay whole). +width+ is the seam tests stub.
    module ProgressLine
      ELLIPSIS = "…"
      MIN_LABEL = 10 # label chars kept before the ellipsis, however long the tail
      NARROW = 20 # below this, just hard-truncate the whole line
      DEFAULT_WIDTH = 80

      module_function

      # The live terminal width: the console's winsize, else $COLUMNS, else 80.
      def width(console: IO.console, env: ENV)
        cols = console_cols(console)
        return cols if cols.positive?

        cols = env["COLUMNS"].to_i
        cols.positive? ? cols : DEFAULT_WIDTH
      end

      def console_cols(console)
        console&.winsize&.last.to_i
      rescue SystemCallError, IOError
        0
      end

      # +lead+ + +label+ + +tail+, fitted to width-1 cells; only the label
      # gives way. Assumes single-cell characters (labels are slugs/prose).
      def fit(lead:, label:, tail:, width: self.width)
        max = width - 1
        line = "#{lead}#{label}#{tail}"
        return line if line.length <= max
        return line[0, max] if width < NARROW

        keep = [max - lead.length - tail.length - ELLIPSIS.length, MIN_LABEL].max
        line = "#{lead}#{label[0, keep]}#{ELLIPSIS}#{tail}" if keep < label.length
        line.length <= max ? line : line[0, max]
      end

      # The \r-overwrite form: return to column 0, clear, print the fitted line.
      def render(lead:, label:, tail:, width: self.width)
        "\r\e[K#{fit(lead: lead, label: label, tail: tail, width: width)}"
      end
    end

    no_commands do
      # A print-free runner needs a sink for live progress; the CLI owns all
      # formatting and tty decisions here. Progress goes to $stderr (final counts
      # go to $stdout via `say`, so scripts piping stdout are unaffected). When
      # $stderr is a tty: git output streams raw (its own \r overwrites the line)
      # and a \r-updating "loading…" counter refreshes each tick. Non-tty: no git
      # streaming (callbacks stay nil) and one plain line per 100 documents.
      # Under supervised_index_write every reporter is TEED into the index
      # watcher's heartbeat (Nabu::IndexWatcher.tee) — the ticks the
      # watcher's stall clock reads.
      def progress_reporter
        tty = $stderr.tty?
        state = { stage: nil, started: nil, processed: 0, errored: 0, last: 0 }
        @progress_state = state
        reporter = Nabu::ProgressReporter.new(
          on_fetch_line: tty ? ->(line) { $stderr.print(line) } : nil,
          on_load_tick: load_tick(tty, state),
          on_stage: stage_tick(tty, state),
          on_note: progress_note(state),
          on_explain: verbose_narrator
        )
        @watch_tee ? @watch_tee.call(reporter) : reporter
      end

      # Run an index-writing command under the forked index watcher
      # (Nabu::IndexWatcher — the incrementality review's R6): heartbeat
      # lines once ticks stall, a kill + hygiene at the deadline (2× the
      # ledger estimate; --deadline MINUTES overrides, 0 disables). The
      # arming line goes to stderr beside the progress lines. +slug+ names
      # the source whose slice the hygiene leaves pending after a kill.
      # +arm_kill+ false (the rebuild flavors) = heartbeats only unless the
      # owner's --deadline arms one (IndexWatcher.deadline_for's rationale).
      def supervised_index_write(config, label:, estimate:, slug: nil, arm_kill: true, &)
        deadline = Nabu::IndexWatcher.deadline_for(estimate: estimate, override_minutes: options[:deadline],
                                                   arm_default: arm_kill)
        if deadline || $stderr.tty?
          warn Nabu::IndexWatcher.arming_line(deadline: deadline, estimate: estimate, kill_default: arm_kill)
        end
        Nabu::IndexWatcher.supervise(label: label, fulltext_path: config.fulltext_path, deadline: deadline,
                                     slug: slug) do |tee|
          @watch_tee = tee
          yield
        ensure
          @watch_tee = nil
        end
      end

      # The ledger estimate for +kind+ over +scopes+ (IndexWatcher) and
      # whether that evidence COVERS the named scopes (a kill is armed
      # only when it does — IndexWatcher.evidence_covers?); read through a
      # short read-only ledger handle. [nil, false] on a fresh box.
      def watcher_estimate(config, kind:, scopes: nil, stages: nil)
        ledger = open_ledger(config)
        return [nil, false] if ledger.nil?

        [Nabu::IndexWatcher.ledger_estimate(ledger, kind: kind, scopes: scopes, stages: stages),
         Nabu::IndexWatcher.evidence_covers?(ledger, kind: kind, scopes: scopes,
                                                     stages: Nabu::IndexWatcher::REFRESH_STAGES)]
      ensure
        ledger&.disconnect
      end

      # --verbose (Ops::StageGuide): ONE narrator per invocation, so each
      # stage explains once however many reporters the command builds
      # (an axis sync builds one per member). Green on stderr beside the
      # stage lines; nil when not verbose, so the reporter's explain seam
      # is a no-op. +before+ closes an open \r stage line first.
      def verbose_narrator
        return nil unless options[:verbose]

        @verbose_narrator ||= Nabu::Ops::StageGuide::Narrator.new(
          io: $stderr, sources: verbose_source_slugs,
          before: -> { close_stage(@progress_state) if @progress_state }
        )
      end

      # The command's intro (what the run is about to do to the library),
      # printed before any work when --verbose is on.
      def explain_command(key)
        verbose_narrator&.intro(key)
      end

      # The registered slugs, so a bare-slug replay stage resolves to the
      # source-replay explanation.
      def verbose_source_slugs
        Nabu::SourceRegistry.load(Nabu::Config.load.sources_path).each_source.map(&:slug)
      rescue Nabu::Error
        []
      end

      # A durable header/tally line (owner UX rule 2026-10-07 — the
      # incremental verdict sweep's ETA header and closing tally): closes
      # any open stage first, then prints on tty and non-tty alike. Not
      # clamped (ProgressLine): the note is printed ONCE and ends in \n, so
      # a soft wrap cannot multiply — and truncating would drop the tally.
      def progress_note(state)
        lambda do |line|
          close_stage(state)
          $stderr.tty? ? $stderr.print("\r\e[K  #{line}\n") : warn("  #{line}")
        end
      end

      # Owner feedback (2026-07-18): a long rebuild must name the source it
      # is on and how long each stage took. A stage closes when the next one
      # opens (or at finish_progress), its line ending in final counts +
      # elapsed; sync paths never call stage, so they keep the bare counter.
      # +eta+ (P78-r2): when the runner consulted the stage_timings
      # history, the open line SPEAKS the estimate — including the honest
      # "first run — no estimate" — and non-tty (the caffeinate/drill logs,
      # where every owner-perceived "hang" of P77 was read) gets the open
      # line too, so the log names what is running BEFORE it finishes.
      def stage_tick(tty, state)
        lambda do |label, eta = nil|
          close_stage(state)
          state[:stage] = label
          state[:eta] = eta
          state[:started] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          state[:processed] = state[:errored] = state[:last] = 0
          suffix = eta ? "#{eta.render} " : ""
          if tty
            $stderr.print(ProgressLine.render(lead: "  ", label: "#{label}…", tail: " #{suffix}"))
          elsif eta&.real?
            # Non-tty prints the open line only when there is a REAL
            # estimate to speak (P78-r3: "first run — no estimate" on
            # every tiny shelf sync is noise in a log; the close line
            # with counts + elapsed is the record either way).
            warn("  #{label}… #{suffix}")
          end
        end
      end

      def close_stage(state)
        return if state[:stage].nil?

        label = "#{state[:stage]}…"
        tail = " #{stage_counts(state)}#{format_elapsed(state)}"
        if $stderr.tty?
          $stderr.print("#{ProgressLine.render(lead: '  ', label: label, tail: tail)}\n")
        else
          warn("  #{label}#{tail}")
        end
        state[:stage] = nil
      end

      # Zero docs is a timeline/facet/index stage, not an empty shelf — show
      # only the timing (compact-output convention: suppress zero fields).
      def stage_counts(state)
        return "" if state[:processed].zero? && state[:errored].zero?

        "#{state[:processed]} docs#{quarantine_suffix(state[:errored])} "
      end

      def format_elapsed(state)
        format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:started])
      end

      def load_tick(tty, state)
        lambda do |processed, errored|
          state[:processed] = processed
          state[:errored] = errored
          label = state[:stage] || "loading"
          left = time_left_suffix(state, processed)
          if tty
            tail = " #{processed} docs#{quarantine_suffix(errored)}#{left}  "
            $stderr.print(ProgressLine.render(lead: "  ", label: "#{label}…", tail: tail))
          elsif processed - state[:last] >= (state[:stage] ? 1000 : 100)
            state[:last] = processed
            warn("  #{label}… #{processed} docs#{quarantine_suffix(errored)}#{left}")
          end
        end
      end

      # P78-r2: the in-stage extrapolation — once ticks flow and the last
      # run recorded a row count, the observed rate projects the remainder
      # (" ~3m left"). Guarded: enough ticks and elapsed time to trust the
      # rate, and only while the recorded total still lies ahead (past it,
      # the estimate would be a lie — drift means more rows this run).
      def time_left_suffix(state, processed)
        basis = state[:eta].respond_to?(:basis_rows) ? state[:eta].basis_rows : nil
        return "" unless basis&.positive? && processed >= 100 && processed < basis

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:started]
        return "" if elapsed < 5

        " ~#{Nabu::Eta.format_seconds(elapsed / processed * (basis - processed))} left"
      end

      def quarantine_suffix(errored)
        errored.positive? ? " (#{errored} quarantined)" : ""
      end

      # Break off the \r-updated counter line before the final counts —
      # closing the open stage (with its timing) when there is one.
      def finish_progress
        if @progress_state && @progress_state[:stage]
          close_stage(@progress_state)
        elsif $stderr.tty?
          $stderr.print("\n")
        end
      end

      # P42-4: the one honest planner-hygiene line — printed only when a bulk
      # load or a rebuild actually refreshed the query-planner statistics,
      # silent otherwise (a sub-threshold sync, a clean-swept incremental run).
      def print_analyzed(analyzed)
        return unless analyzed

        say "  analyzed #{analyzed.scope} (planner stats refreshed, #{format('%.1f', analyzed.seconds)}s)"
      end

      # P39-4: the within-pass collision tail — silent at zero (house
      # compact-zero rule; collisions are pathological), loud when one bit.
      def format_collided(report)
        report.collided.positive? ? "  !#{report.collided} collision" : ""
      end
    end
  end
end
