# frozen_string_literal: true

require "fileutils"
require "time"

require_relative "../eta"
require_relative "../progress_reporter"

module Nabu
  module Ops
    # A long run's own log file — the record readable WHILE the run works
    # (`tail -f` it from another terminal) and after it dies. One file per
    # run, timestamped to the second, in the drill's home for run logs
    # (~/Library/Logs/nabu; NABU_LOG_DIR overrides — the suite points it at
    # a tmp dir). Every line is flushed as written (sync) and stamped with
    # UTC wall time, so a hang reads as the gap after the last line.
    #
    # What lands: whatever the command writes through #line (its
    # preflight, its result), and through #tee every stage OPEN (label +
    # the ledger estimate it announced) and CLOSE (elapsed + documents),
    # durable notes, and a document-count line at most once a minute
    # inside a long stage. Raw fetch lines and \r redraws never land.
    class RunLog
      DIR_ENV = "NABU_LOG_DIR"
      # const: the most often a long stage's document count is logged —
      # a heartbeat for the reader, not a per-document trace
      TICK_EVERY_S = 60

      attr_reader :path

      def self.dir(env: ENV)
        custom = env[DIR_ENV].to_s.strip
        custom.empty? ? File.expand_path("~/Library/Logs/nabu") : custom
      end

      # Open a fresh log for +kind+ ("rebuild"): <dir>/<kind>-<stamp>.log.
      def self.open(kind:, now: Time.now, env: ENV, clock: -> { Time.now })
        dir = self.dir(env: env)
        FileUtils.mkdir_p(dir)
        new(File.join(dir, "#{kind}-#{now.strftime('%Y-%m-%d_%H%M%S')}.log"), clock: clock)
      end

      def initialize(path, clock: -> { Time.now })
        @path = path
        @clock = clock
        @file = File.open(path, "a")
        @file.sync = true
        @stage = nil
      end

      def line(text)
        @file.puts("#{@clock.call.utc.strftime('%Y-%m-%d %H:%M:%S')}Z  #{text}")
      end

      # A ProgressReporter that logs the run's stages, then hands every
      # event to +progress+'s own sinks unchanged.
      def tee(progress)
        progress ||= ProgressReporter.new
        ProgressReporter.new(
          on_fetch_line: progress.on_fetch_line,
          on_load_tick: lambda { |processed, errored|
            tick(processed, errored)
            progress.on_load_tick&.call(processed, errored)
          },
          on_stage: lambda { |label, eta|
            open_stage(label, eta)
            progress.on_stage&.call(label, eta)
          },
          on_note: lambda { |text|
            line("note #{text}")
            progress.on_note&.call(text)
          },
          on_explain: progress.on_explain
        )
      end

      # Close the open stage (its elapsed line), e.g. before the result.
      def close_stage
        return if @stage.nil?

        docs = @stage[:docs].positive? ? ", #{@stage[:docs]} docs" : ""
        line("done  #{@stage[:label]} in #{Eta.format_seconds(@clock.call - @stage[:started])}#{docs}")
        @stage = nil
      end

      def close
        close_stage
        @file.close unless @file.closed?
      end

      private

      def open_stage(label, eta)
        close_stage
        now = @clock.call
        @stage = { label: label, started: now, docs: 0, logged: now }
        line("stage #{label} — #{eta ? eta.render : 'no estimate'}")
      end

      def tick(processed, errored)
        return if @stage.nil?

        @stage[:docs] = processed
        now = @clock.call
        return if now - @stage[:logged] < TICK_EVERY_S

        @stage[:logged] = now
        quarantined = errored.positive? ? " (#{errored} quarantined)" : ""
        line("      #{@stage[:label]}: #{processed} docs#{quarantined}")
      end
    end
  end
end
