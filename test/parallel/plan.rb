# frozen_string_literal: true

module Nabu
  # The multi-process suite runner (`bundle exec rake test`). The suite is
  # partitioned into JOBS, each run in a FRESH worker process (test/parallel/
  # worker.rb) with at most N alive at once. Why processes, and why fresh
  # ones per job: a single-process suite grows to gigabytes of resident
  # memory, and every subprocess a test launches (git, fork-based loader
  # equivalence, fetch fixtures) gets slower as the parent grows — ~1.7 ms
  # per spawn at 20 MB vs ~8 ms at 490 MB. Small short-lived workers keep
  # both the wall time and the spawn tax down.
  module ParallelTests
    # One unit of work: a batch of whole test files, or ONE shard of a single
    # heavy file (shard = [index, count], methods split by a stable hash of
    # "Class#method", so the shards of a file cover every method exactly once).
    Job = Data.define(:files, :shard, :weight) do
      def label
        shard ? "#{files.first} [shard #{shard[0] + 1}/#{shard[1]}]" : files.join(" ")
      end
    end

    # Pure scheduling: turn the file list (+ optional recorded timings) into
    # jobs, heaviest first, so the dynamic queue ends with a short tail.
    module Plan
      # A file heavier than SHARD_FRACTION of one worker's ideal share is
      # split into shards so one huge file can't set the wall time alone.
      # Lighter files are packed into batches (amortizing the ~0.5 s worker
      # startup) whose size SHRINKS as the remaining work does — about
      # 1/TAIL_ROUNDS of what is left per worker, between MIN_ and
      # MAX_BATCH_FRACTION of a share — so the run ends on many small jobs
      # instead of a last round of big ones (the 4P+6E-core tail).
      SHARD_FRACTION = 0.35
      MAX_BATCH_FRACTION = 1.0 / 5
      MIN_BATCH_FRACTION = 1.0 / 12
      TAIL_ROUNDS = 3

      # +timings+: { file => seconds } from earlier runs (may be partial or
      # empty); +sizes+: { file => bytes } — the fallback weight, converted
      # into seconds by the observed seconds-per-byte ratio when timings exist.
      def self.build(files:, workers:, timings: {}, sizes: {})
        raise ArgumentError, "workers must be >= 1" if workers < 1
        return [] if files.empty?

        weights = weigh(files: files, timings: timings, sizes: sizes)
        share = weights.values.sum / workers
        shard_cap = share * SHARD_FRACTION

        heavy, light = files.partition { |file| shard_cap.positive? && weights[file] > shard_cap }
        jobs = heavy.flat_map { |file| shards(file, weights[file], shard_cap, workers) }
        jobs.concat(batches(light.sort_by { |file| [-weights[file], file] }, weights, share: share, workers: workers))
        jobs.sort_by { |job| [-job.weight, job.label] }
      end

      def self.weigh(files:, timings:, sizes:)
        timed = files.select { |file| timings[file] }
        timed_bytes = timed.sum { |file| sizes.fetch(file, 0) }
        ratio = timed_bytes.positive? ? timed.sum { |file| timings[file] } / timed_bytes.to_f : 1.0
        files.to_h do |file|
          weight = timings.fetch(file) { sizes.fetch(file, 0) * ratio }
          [file, [weight.to_f, Float::EPSILON].max]
        end
      end

      def self.shards(file, weight, cap, workers)
        count = (weight / cap).ceil.clamp(1, workers)
        Array.new(count) { |index| Job.new(files: [file], shard: [index, count], weight: weight / count) }
      end

      def self.batches(files, weights, share:, workers:)
        jobs = []
        current = []
        current_weight = 0.0
        remaining = files.sum { |file| weights[file] }
        files.each do |file|
          current << file
          current_weight += weights[file]
          cap = (remaining / (workers * TAIL_ROUNDS)).clamp(share * MIN_BATCH_FRACTION, share * MAX_BATCH_FRACTION)
          next if current_weight < cap

          remaining -= current_weight

          jobs << Job.new(files: current.sort, shard: nil, weight: current_weight)
          current = []
          current_weight = 0.0
        end
        jobs << Job.new(files: current.sort, shard: nil, weight: current_weight) unless current.empty?
        jobs
      end
    end
  end
end
