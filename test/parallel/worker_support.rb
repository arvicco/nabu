# frozen_string_literal: true

require "json"
require "zlib"
require "minitest"

module Nabu
  module ParallelTests
    # Keeps only this shard's methods: a stable hash of "Class#method" mod
    # the shard count, so shards are disjoint and jointly exhaustive.
    module ShardFilter
      class << self
        attr_accessor :index, :count
      end

      def self.member?(test_id, index:, count:)
        (Zlib.crc32(test_id) % count) == index
      end

      def runnable_methods
        super.select do |method|
          ShardFilter.member?("#{name}##{method}", index: ShardFilter.index, count: ShardFilter.count)
        end
      end
    end

    # Collects counts, the verbatim failure/error/skip text Minitest itself
    # would print, and per-file seconds (for the parent's scheduling).
    class WorkerReporter < Minitest::StatisticsReporter
      def initialize(path:, class_files:, options: {})
        super($stdout, options)
        @path = path
        @class_files = class_files
        @file_times = Hash.new(0.0)
      end

      def record(result)
        super
        file = @class_files[result.klass]
        @file_times[file] += result.time if file
      end

      def report
        super
        payload = {
          "count" => count, "assertions" => assertions, "failures" => failures,
          "errors" => errors, "skips" => skips, "warnings" => warnings,
          "seconds" => total_time,
          "results" => results.map { |r| { "code" => r.result_code, "skipped" => r.skipped?, "text" => r.to_s } },
          "file_times" => @file_times
        }
        File.write(@path, JSON.generate(payload))
      end
    end

    # Loads one job's files and arms the reporter; the suite itself then runs
    # through test_helper's minitest/autorun at process exit, exactly as in a
    # single-process run. Used by worker.rb (a spawned worker) and by the
    # runner's forked children alike.
    module Worker
      def self.prepare(files:, args:, result_path:, shard: nil)
        apply_shard(shard) if shard
        class_files = {}
        files.each do |file|
          before = Minitest::Runnable.runnables.dup
          require File.expand_path(file)
          (Minitest::Runnable.runnables - before).each { |klass| class_files[klass.name] = file }
        end
        Minitest.register_plugin(reporter_plugin(result_path, class_files))
        ARGV.replace(args)
      end

      def self.apply_shard(shard)
        ShardFilter.index, ShardFilter.count = shard.split("/").map { |part| Integer(part, 10) }
        Minitest::Test.singleton_class.prepend(ShardFilter)
      end

      def self.reporter_plugin(result_path, class_files)
        Module.new do
          define_singleton_method(:minitest_plugin_init) do |options|
            Minitest.reporter << WorkerReporter.new(path: result_path, class_files: class_files, options: options)
          end
        end
      end
    end
  end
end
