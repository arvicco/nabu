# frozen_string_literal: true

require "digest"
require "etc"
require "fileutils"
require "json"
require "rbconfig"
require "securerandom"
require "shellwords"
require "tmpdir"
require_relative "plan"

module Nabu
  module ParallelTests
    # What one finished job produced: its exit status, the worker's JSON
    # result (nil when the worker died before writing it) and its log.
    Outcome = Data.define(:job, :status, :result, :log_path) do
      # A crash is a worker that left no result, or exited nonzero while its
      # result claims no failures (it died after/around the report) — either
      # way the partition's tests are unaccounted for, so the run fails.
      def crashed?
        return true if result.nil?

        !status.success? && (result["failures"] + result["errors"]).zero?
      end

      def failed?
        crashed? || (result["failures"] + result["errors"]).positive?
      end
    end

    # Folds every outcome into ONE report in Minitest's own output shape:
    # failure blocks verbatim (numbered across workers), then the standard
    # "N runs, N assertions, N failures, N errors, N skips" line. A crashed
    # worker counts as one error and prints its full log.
    class Summary
      attr_reader :outcomes

      def initialize(outcomes:, show_skips: false)
        @outcomes = outcomes
        @show_skips = show_skips
      end

      def totals
        reported = outcomes.reject(&:crashed?).map(&:result)
        {
          runs: reported.sum { |r| r["count"] },
          assertions: reported.sum { |r| r["assertions"] },
          failures: reported.sum { |r| r["failures"] },
          errors: reported.sum { |r| r["errors"] } + crashes.size,
          skips: reported.sum { |r| r["skips"] }
        }
      end

      def crashes
        outcomes.select(&:crashed?)
      end

      def passed?
        outcomes.none?(&:failed?)
      end

      def summary_line
        t = totals
        line = format("%<runs>d runs, %<assertions>d assertions, %<failures>d failures, " \
                      "%<errors>d errors, %<skips>d skips", t)
        line += "\n\nYou have skipped tests. Run with --verbose for details." if t[:skips].positive? && !@show_skips
        line
      end

      def render(io)
        number = 0
        outcomes.reject(&:crashed?).each do |outcome|
          outcome.result["results"].each do |res|
            next if res["skipped"] && !@show_skips

            number += 1
            io.puts format("\n%<n>3d) %<text>s", n: number, text: res["text"])
          end
        end
        crashes.each do |outcome|
          number += 1
          io.puts format("\n%<n>3d) %<text>s", n: number, text: crash_text(outcome))
        end
        io.puts
        io.puts summary_line
      end

      private

      def crash_text(outcome)
        log = File.exist?(outcome.log_path) ? File.read(outcome.log_path) : "(no log)"
        "Worker crash:\n#{outcome.job.label}\n#{outcome.status.inspect} — " \
          "no complete result; its tests are UNACCOUNTED FOR. Full worker log (#{outcome.log_path}):\n#{log}"
      end
    end

    # Keys every runner artifact by INVOCATION (P147 lane A). Two concurrent
    # `rake test` runs in different git worktrees (the parallel-lane setup)
    # share one $TMPDIR; a foreign run's failures were twice seen merged into
    # another run's report. The run dir already came from Dir.mktmpdir, but
    # nothing tied a result FILE to the run that was collecting it: the
    # worker's result path travels by inherited env (NABU_TEST_RESULT), the
    # names were bare "job-<index>" (index 0..N in EVERY run), and the
    # collector merged whatever JSON sat at that path. Now: the token
    # (<worktree-path digest>-<SecureRandom hex>) names the run dir and every
    # file in it, rides to the worker as NABU_TEST_RUN, is stamped into the
    # result, and a result carrying any other token is refused (counted as a
    # loud crash, never merged). The timings file is written atomically
    # through a token-named temp, so a concurrent run in the SAME worktree
    # never reads a torn file.
    module RunKey
      def self.token(root:)
        "#{Digest::SHA256.hexdigest(File.expand_path(root))[0, 12]}-#{SecureRandom.hex(8)}"
      end

      def self.make_run_dir(token) = Dir.mktmpdir("nabu-test-#{token}-")

      # The parsed result at +path+ iff it was written by THIS run; nil for
      # absent, torn, or foreign (another invocation's token) files.
      def self.read_result(path, token:)
        return nil unless File.exist?(path)

        result = JSON.parse(File.read(path))
        result["run"] == token ? result : nil
      rescue JSON::ParserError
        nil
      end

      Artifacts = Data.define(:run_dir, :token) do
        def result(index) = File.join(run_dir, "job-#{index}-#{token}.json")
        def log(index) = File.join(run_dir, "job-#{index}-#{token}.log")
        def job_tmp(index) = File.join(run_dir, "job-#{index}-#{token}-tmp")
      end
    end

    # The parent process: plans jobs, keeps up to +workers+ worker processes
    # alive, renders the merged report, records per-file timings for the next
    # run's scheduling (tmp/ — gitignored, scheduling only, never results).
    # Every artifact is keyed by the run's token — see RunKey.
    class Runner
      ROOT = File.expand_path("../..", __dir__)
      WORKER = File.join(__dir__, "worker.rb")
      TIMINGS = File.join(ROOT, "tmp", "test-timings.json")

      def self.fork?
        Process.respond_to?(:fork) && ENV["NABU_TEST_SPAWN"] != "1"
      end

      # What every forked worker would otherwise load itself. Only libraries,
      # never test_helper (minitest/autorun must arm in the child, not here).
      def self.preload!
        return unless fork?

        $LOAD_PATH.unshift(File.join(ROOT, "lib"), File.join(ROOT, "test"))
        require "nabu"
        require "webmock"
        require_relative "worker_support"
      end

      def self.default_workers
        Integer(ENV.fetch("NABU_TEST_WORKERS", Etc.nprocessors.to_s), 10)
      end

      def initialize(files:, workers: self.class.default_workers, testopts: ENV.fetch("TESTOPTS", ""), io: $stdout)
        @files = files
        @workers = workers
        @args = Shellwords.split(testopts)
        @io = io
        @token = RunKey.token(root: ROOT)
      end

      # Returns true when everything passed (the caller maps it to the exit code).
      def run # rubocop:disable Naming/PredicateMethod -- a command, its boolean is the verdict
        seed = ensure_seed!
        jobs = Plan.build(files: @files, workers: @workers, timings: load_timings,
                          sizes: @files.to_h { |f| [f, File.size(File.join(ROOT, f))] })
        @io.puts "Run options: #{@args.join(' ')} (parallel: #{@workers} workers, #{jobs.size} jobs; " \
                 "NABU_TEST_SERIAL=1 runs one process)"
        @io.puts
        @io.puts "# Running:"
        @io.puts
        started = clock
        run_dir = RunKey.make_run_dir(@token)
        @artifacts = RunKey::Artifacts.new(run_dir: run_dir, token: @token)
        outcomes = execute(jobs)
        @io.puts
        @io.puts
        @io.puts format("Finished in %<s>.6fs (parallel wall time, seed %<seed>d).", s: clock - started, seed: seed)
        summary = Summary.new(outcomes: outcomes, show_skips: show_skips?)
        summary.render(@io)
        rerun_hints(outcomes.select(&:failed?), seed)
        save_timings(outcomes)
        if summary.passed?
          FileUtils.remove_entry(run_dir)
        else
          @io.puts "\nWorker logs kept in #{run_dir}"
        end
        summary.passed?
      end

      private

      def execute(jobs)
        queue = jobs.each_with_index.to_a
        running = {}
        outcomes = []
        origin = clock
        started_at = {}
        until queue.empty? && running.empty?
          while running.size < @workers && !queue.empty?
            job, index = queue.shift
            running[spawn_job(job, index)] = [job, index]
            started_at[index] = clock
          end
          pid, status = Process.wait2
          job, index = running.delete(pid)
          next unless job # not one of ours (defensive; workers are our only children)

          outcome = collect(job, index, status)
          trace(job, started_at[index] - origin, clock - started_at[index])
          @io.print progress_mark(outcome)
          outcomes << [index, outcome]
        end
        outcomes.sort_by(&:first).map(&:last)
      ensure
        running&.each_key { |pid| kill(pid) }
      end

      # Workers are FORKED from this runner after it preloaded the library
      # (see .preload!) — saving every job the ~1 s interpreter + bundler +
      # lib boot; NABU_TEST_SPAWN=1 (or a fork-less platform) spawns fresh
      # interpreters via worker.rb instead. Either way the child is a fresh,
      # small process that loads only its job's test files.
      def spawn_job(job, index)
        tmp = @artifacts.job_tmp(index)
        FileUtils.mkdir_p(tmp)
        env = {
          "NABU_TEST_RESULT" => @artifacts.result(index),
          "NABU_TEST_RUN" => @token,
          "NABU_TEST_SHARD" => job.shard&.join("/"),
          "NABU_TEST_JOB" => index.to_s,
          "TMPDIR" => tmp
        }
        return fork_job(job, env, @artifacts.log(index)) if self.class.fork?

        command = [RbConfig.ruby, "-I#{File.join(ROOT, 'lib')}", "-I#{File.join(ROOT, 'test')}", WORKER,
                   *job.files, "--", *@args]
        Process.spawn(env, *command, chdir: ROOT, out: @artifacts.log(index), err: %i[child out])
      end

      def fork_job(job, env, log)
        Process.fork do
          env.each { |key, value| value.nil? ? ENV.delete(key) : ENV.store(key, value) }
          $stdout.reopen(log, "w")
          $stderr.reopen($stdout)
          $stdout.sync = true
          Dir.chdir(ROOT)
          Worker.prepare(files: job.files, args: @args, result_path: env["NABU_TEST_RESULT"],
                         shard: env["NABU_TEST_SHARD"], run_token: @token)
          # the block's normal end exits the child -> minitest/autorun runs the job
        end
      end

      # NABU_TEST_TRACE=1: one stderr line per finished job (start offset,
      # wall seconds, label) — the instrument for tuning the schedule.
      def trace(job, offset, seconds)
        return unless ENV["NABU_TEST_TRACE"] == "1"

        warn format("[job] +%<o>6.1fs %<s>6.1fs w=%<w>6.1f %<label>s", o: offset, s: seconds, w: job.weight,
                                                                       label: job.label)
      end

      def collect(job, index, status)
        Outcome.new(job: job, status: status, result: RunKey.read_result(@artifacts.result(index), token: @token),
                    log_path: @artifacts.log(index))
      end

      def progress_mark(outcome)
        return "!" if outcome.crashed?

        outcome.failed? ? "F" : "."
      end

      def rerun_hints(failed, seed)
        return if failed.empty?

        @io.puts "\nRe-run a failing job alone (same seed):"
        failed.each do |outcome|
          shard = outcome.job.shard ? "NABU_TEST_SHARD=#{outcome.job.shard.join('/')} " : ""
          @io.puts "  #{shard}NABU_TEST_RESULT=/dev/null bundle exec ruby -Ilib -Itest " \
                   "test/parallel/worker.rb #{outcome.job.files.join(' ')} -- --seed #{seed}"
        end
      end

      def ensure_seed!
        @args.each_with_index do |arg, i|
          return Integer(arg.delete_prefix("--seed="), 10) if arg.start_with?("--seed=")
          return Integer(@args[i + 1], 10) if arg == "--seed"
        end
        seed = Random.new_seed % 0xFFFF
        @args += ["--seed", seed.to_s]
        seed
      end

      def show_skips?
        @args.intersect?(%w[-v --verbose --show-skips])
      end

      def load_timings
        File.exist?(TIMINGS) ? JSON.parse(File.read(TIMINGS)) : {}
      rescue JSON::ParserError
        {}
      end

      def save_timings(outcomes)
        timings = load_timings
        fresh = Hash.new(0.0)
        outcomes.reject(&:crashed?).each do |outcome|
          outcome.result["file_times"].each { |file, seconds| fresh[file] += seconds }
        end
        FileUtils.mkdir_p(File.dirname(TIMINGS))
        staged = "#{TIMINGS}.#{@token}.tmp"
        File.write(staged, JSON.pretty_generate(timings.merge(fresh).slice(*@files).sort.to_h))
        File.rename(staged, TIMINGS)
      end

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def kill(pid)
        Process.kill("TERM", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  $stdout.sync = true # nothing buffered may be duplicated into forked workers
  Nabu::ParallelTests::Runner.preload!
  files = ARGV.empty? ? Dir.chdir(Nabu::ParallelTests::Runner::ROOT) { Dir["test/**/*_test.rb"].sort } : ARGV
  exit(Nabu::ParallelTests::Runner.new(files: files).run ? 0 : 1)
end
