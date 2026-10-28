# frozen_string_literal: true

# A parallel-suite worker: runs ONE job (a batch of test files, or one shard
# of a heavy file) and writes a machine-readable result for the parent runner
# (test/parallel/runner.rb). Usage:
#
#   ruby -Ilib -Itest test/parallel/worker.rb FILE... -- MINITEST_ARGS...
#
# Environment: NABU_TEST_RESULT (where the JSON result goes — required),
# NABU_TEST_SHARD ("index/count", optional), NABU_TEST_RUN (the parent run's
# token, stamped into the result so the parent refuses any other run's file). The worker is an ordinary
# Minitest process (test_helper's autorun, StrictSkips, WebMock all apply
# unchanged); it only adds a reporter and, for a shard, a method filter.
# Any crash before the reporter writes leaves NO result file — the parent
# treats that as a loud failure, never as an empty partition.

require_relative "worker_support"

separator = ARGV.index("--") || ARGV.length
Nabu::ParallelTests::Worker.prepare(files: ARGV[0...separator], args: ARGV[(separator + 1)..] || [],
                                    result_path: ENV.fetch("NABU_TEST_RESULT"),
                                    shard: ENV.fetch("NABU_TEST_SHARD", nil),
                                    run_token: ENV.fetch("NABU_TEST_RUN", nil))
# test_helper's minitest/autorun runs the suite at exit with ARGV.
