# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "parallel/runner"
require_relative "parallel/worker_support"

# The multi-process suite runner: planning, shard coverage, result merging,
# crash loudness, and one real worker round trip.
class ParallelRunnerTest < Minitest::Test
  PT = Nabu::ParallelTests
  FakeStatus = Struct.new(:ok) do
    def success? = ok
  end

  def result(count: 1, assertions: 1, failures: 0, errors: 0, skips: 0, results: [])
    { "count" => count, "assertions" => assertions, "failures" => failures, "errors" => errors,
      "skips" => skips, "results" => results, "file_times" => {} }
  end

  def outcome(result:, success: true, label: "test/a_test.rb", log_path: "/nonexistent.log")
    PT::Outcome.new(job: PT::Job.new(files: [label], shard: nil, weight: 1.0),
                    status: FakeStatus.new(success), result: result, log_path: log_path)
  end

  # --- Plan --------------------------------------------------------------

  def test_plan_covers_every_file_exactly_once_and_shards_the_heavy_one
    sizes = { "a_test.rb" => 100, "b_test.rb" => 100, "c_test.rb" => 100, "huge_test.rb" => 5_000 }
    jobs = PT::Plan.build(files: sizes.keys, workers: 4, sizes: sizes)

    whole = jobs.reject(&:shard).flat_map(&:files)
    assert_equal %w[a_test.rb b_test.rb c_test.rb], whole.sort
    shards = jobs.select(&:shard)
    assert(shards.all? { |job| job.files == ["huge_test.rb"] })
    count = shards.first.shard[1]
    assert_operator count, :>, 1
    assert_operator count, :<=, 4
    assert_equal (0...count).to_a, shards.map { |job| job.shard[0] }.sort
    assert(shards.all? { |job| job.shard[1] == count })
    assert_equal jobs.map(&:weight).sort.reverse, jobs.map(&:weight), "heaviest first"
  end

  def test_plan_prefers_recorded_timings_and_scales_sizes_for_untimed_files
    weights = PT::Plan.weigh(files: %w[t_test.rb u_test.rb], timings: { "t_test.rb" => 10.0 },
                             sizes: { "t_test.rb" => 1000, "u_test.rb" => 500 })
    assert_in_delta 10.0, weights["t_test.rb"]
    assert_in_delta 5.0, weights["u_test.rb"], 1e-9, "untimed file weighed at the observed s/byte"
  end

  def test_plan_with_one_worker_never_splits_a_file
    sizes = { "x_test.rb" => 10, "y_test.rb" => 9_000 }
    jobs = PT::Plan.build(files: sizes.keys, workers: 1, sizes: sizes)
    assert(jobs.all? { |job| job.shard.nil? || job.shard == [0, 1] })
    assert_equal %w[x_test.rb y_test.rb], jobs.flat_map(&:files).sort
  end

  def test_plan_rejects_zero_workers
    assert_raises(ArgumentError) { PT::Plan.build(files: ["a_test.rb"], workers: 0) }
  end

  # --- Shards ------------------------------------------------------------

  def test_shards_are_disjoint_and_exhaustive
    ids = Array.new(500) { |i| "SomeTest#test_case_#{i}" }
    members = (0...4).map do |index|
      ids.select { |id| PT::ShardFilter.member?(id, index: index, count: 4) }
    end
    assert_equal ids.sort, members.flatten.sort
    assert(members.all? { |shard| shard.size.positive? })
  end

  # --- Summary -----------------------------------------------------------

  def test_summary_sums_counts_into_minitests_own_line
    summary = PT::Summary.new(outcomes: [outcome(result: result(count: 3, assertions: 7)),
                                         outcome(result: result(count: 2, assertions: 5))])
    assert_equal "5 runs, 12 assertions, 0 failures, 0 errors, 0 skips", summary.summary_line
    assert_predicate summary, :passed?
  end

  def test_failure_text_is_preserved_verbatim_and_fails_the_run
    text = "Failure:\nFooTest#test_bar [test/foo_test.rb:3]:\nExpected: 1\n  Actual: 2"
    failed = { "code" => "F", "skipped" => false, "text" => text }
    failing = outcome(success: false, result: result(failures: 1, results: [failed]))
    summary = PT::Summary.new(outcomes: [outcome(result: result), failing])
    io = StringIO.new
    summary.render(io)
    assert_includes io.string, "\n  1) #{text}\n"
    assert_includes io.string, "2 runs, 2 assertions, 1 failures, 0 errors, 0 skips"
    refute_predicate summary, :passed?
  end

  def test_a_worker_without_a_result_is_a_loud_error
    Dir.mktmpdir do |dir|
      log = File.join(dir, "job.log")
      File.write(log, "LoadError: boom\n")
      crashed = outcome(success: false, result: nil, label: "test/broken_test.rb", log_path: log)
      summary = PT::Summary.new(outcomes: [outcome(result: result), crashed])
      io = StringIO.new
      summary.render(io)
      assert_includes io.string, "Worker crash:\ntest/broken_test.rb"
      assert_includes io.string, "LoadError: boom"
      assert_includes io.string, "1 runs, 1 assertions, 0 failures, 1 errors, 0 skips"
      refute_predicate summary, :passed?
    end
  end

  def test_nonzero_exit_with_a_clean_result_counts_as_a_crash
    assert_predicate outcome(success: false, result: result), :crashed?
    refute_predicate outcome(success: true, result: result), :crashed?
    refute_predicate outcome(success: false, result: result(failures: 1)), :crashed?
  end

  # --- Run keying (concurrent runs never share an artifact) -----------------

  def test_run_token_carries_the_worktree_digest_and_a_fresh_random_part
    Dir.mktmpdir do |a|
      Dir.mktmpdir do |b|
        first = PT::RunKey.token(root: a)
        second = PT::RunKey.token(root: a)
        other = PT::RunKey.token(root: b)
        refute_equal first, second, "two invocations in ONE worktree never share a token"
        assert_equal first.split("-").first, second.split("-").first, "same worktree → same digest part"
        refute_equal first.split("-").first, other.split("-").first, "different worktrees → different digest"
        assert_match(/\A\h{12}-\h{16}\z/, first)
      end
    end
  end

  def test_every_runner_artifact_path_is_keyed_by_the_run_token
    artifacts = PT::RunKey::Artifacts.new(run_dir: "/r", token: "abc-123")
    assert_equal "/r/job-7-abc-123.json", artifacts.result(7)
    assert_equal "/r/job-7-abc-123.log", artifacts.log(7)
    assert_equal "/r/job-7-abc-123-tmp", artifacts.job_tmp(7)
    refute_equal artifacts.result(7), PT::RunKey::Artifacts.new(run_dir: "/r", token: "abc-124").result(7)
  end

  def test_run_dir_is_a_fresh_directory_named_by_the_token
    dir = PT::RunKey.make_run_dir("abc-123")
    assert File.directory?(dir)
    assert_includes File.basename(dir), "nabu-test-abc-123-"
    refute_equal dir, (other = PT::RunKey.make_run_dir("abc-123"))
  ensure
    [dir, other].compact.each { |d| FileUtils.rm_rf(d) }
  end

  def test_a_result_from_a_foreign_run_is_never_merged
    Dir.mktmpdir do |dir|
      path = File.join(dir, "job-0.json")
      File.write(path, JSON.generate(result.merge("run" => "theirs")))
      assert_nil PT::RunKey.read_result(path, token: "ours"), "a foreign run's result is rejected"
      File.write(path, JSON.generate(result.merge("run" => "ours")))
      assert_equal 1, PT::RunKey.read_result(path, token: "ours")["count"]
      File.write(path, "{torn")
      assert_nil PT::RunKey.read_result(path, token: "ours")
      assert_nil PT::RunKey.read_result(File.join(dir, "absent.json"), token: "ours")
    end
  end

  # --- A real worker -----------------------------------------------------

  def run_worker(dir, body)
    file = File.join(dir, "sample_case.rb")
    File.write(file, body)
    result_path = File.join(dir, "result.json")
    env = { "NABU_TEST_RESULT" => result_path, "NABU_TEST_RUN" => "run-tok", "NABU_ALLOW_SKIPS" => "1" }
    root = PT::Runner::ROOT
    _out, status = Open3.capture2e(env, RbConfig.ruby, "-I#{root}/lib", "-I#{root}/test", PT::Runner::WORKER,
                                   file, "--", "--seed", "1", chdir: root)
    [status, File.exist?(result_path) ? JSON.parse(File.read(result_path)) : nil]
  end

  def test_worker_reports_counts_and_verbatim_failures
    Dir.mktmpdir do |dir|
      status, result = run_worker(dir, <<~RUBY)
        require "test_helper"
        class ParallelSampleCase < Minitest::Test
          def test_passes = assert(true)
          def test_fails = assert_equal(1, 2)
        end
      RUBY
      refute_predicate status, :success?
      assert_equal 2, result["count"]
      assert_equal "run-tok", result["run"], "the result is stamped with its invocation's token"
      assert_equal 1, result["failures"]
      assert_match(/ParallelSampleCase#test_fails.*Expected: 1\n  Actual: 2/m, result["results"].first["text"])
      assert_operator result["file_times"].values.sum, :>=, 0.0
    end
  end

  def test_worker_load_crash_leaves_no_result
    Dir.mktmpdir do |dir|
      status, result = run_worker(dir, "require \"test_helper\"\nraise \"exploded at load\"\n")
      refute_predicate status, :success?
      assert_nil result
    end
  end
end
