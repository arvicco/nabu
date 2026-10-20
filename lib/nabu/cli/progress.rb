# frozen_string_literal: true

# Nabu::CLI — shared progress-narration helpers for long-running commands.
# Carved out of lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    no_commands do
      # A print-free runner needs a sink for live progress; the CLI owns all
      # formatting and tty decisions here. Progress goes to $stderr (final counts
      # go to $stdout via `say`, so scripts piping stdout are unaffected). When
      # $stderr is a tty: git output streams raw (its own \r overwrites the line)
      # and a \r-updating "loading…" counter refreshes each tick. Non-tty: no git
      # streaming (callbacks stay nil) and one plain line per 100 documents.
      def progress_reporter
        tty = $stderr.tty?
        state = { stage: nil, started: nil, processed: 0, errored: 0, last: 0 }
        @progress_state = state
        Nabu::ProgressReporter.new(
          on_fetch_line: tty ? ->(line) { $stderr.print(line) } : nil,
          on_load_tick: load_tick(tty, state),
          on_stage: stage_tick(tty, state),
          on_note: progress_note(state),
          on_explain: verbose_narrator
        )
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
      # any open stage first, then prints on tty and non-tty alike.
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
            $stderr.print("\r\e[K  #{label}… #{suffix}")
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

        line = "  #{state[:stage]}… #{stage_counts(state)}#{format_elapsed(state)}"
        $stderr.tty? ? $stderr.print("\r\e[K#{line}\n") : warn(line)
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
            $stderr.print("\r\e[K  #{label}… #{processed} docs#{quarantine_suffix(errored)}#{left}  ")
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
