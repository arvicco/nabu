# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "nabu/ops/trickle"

# The trickle runner (Nabu::Ops::Trickle): an owner-fired standing crawl of
# one paced-crawl source, detached from any session, looping the source's
# PacedCrawl slices back to back at the engine's own declared pace until the
# cone ends, the engine's zero-yield budget or a clean stop ends it, a stop
# is requested, or a fatal error. It only crawls (canonical/ through the
# engine); its state is local/trickle/<slug>.{pid,log,stop}.
#
# The loop body (Runner) is tested in-process against a REAL
# PacedCrawl::Engine over fake lambdas (tiny delay, no-op sleeper). The
# daemon wrapper is tested shallowly — Control#start! takes the spawner as
# a seam and the tests hand it a fake: a real setsid'd child would outlive
# a failing test, write into the box's own local/trickle/, and race the
# parallel suite's workers on pid liveness. The spawned entry point
# (Trickle.child_main) is the same Runner the tests drive.
class TrickleTest < Minitest::Test
  P = Nabu::PacedCrawl
  T = Nabu::Ops::Trickle

  def setup
    @tmp = Dir.mktmpdir("trickle-test")
    @paths = T::Paths.new(dir: File.join(@tmp, "local", "trickle"), slug: "alpha")
    @held = {}
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def spec(slice: 2, stop_after: 2, delay: 0.01)
    P::Spec.new(
      name: "books", ledger_file: ".trickle-test.json",
      classes: { denied: "denied", empty: "empty", timeout: "timeout-stuck" },
      delay: delay, slice: slice,
      schedule: P::Schedule.new(cadence: :per_phase, slices_per_phase: 3, stop_after_zero_slices: stop_after)
    )
  end

  # ids answering :ok land in @held; ids in +refused+ answer :denied; +hook+
  # runs before each answer (the test's way of acting mid-crawl).
  def engine(universe:, refused: [], hook: nil, sleeper: ->(_) {}, **spec_opts)
    P::Engine.new(
      spec: spec(**spec_opts), dir: File.join(@tmp, "canonical", "alpha"),
      universe: -> { universe },
      held: ->(id) { @held.key?(id) },
      fetch_one: lambda do |id|
        hook&.call(id)
        if refused.include?(id)
          P::Outcome.new(status: :denied, evidence: { http_status: 403, body_head: "no" })
        else
          @held[id] = true
          P::Outcome.new(status: :ok, evidence: { http_status: 200, body_head: "" })
        end
      end,
      sleeper: sleeper
    )
  end

  def runner(engines, sleeper: ->(_) {})
    T::Runner.new(slug: "alpha", engines: engines, paths: @paths, pid: 4242, sleeper: sleeper)
  end

  def log_lines = File.readlines(@paths.log, chomp: true)

  # -- the loop body ---------------------------------------------------------

  def test_the_runner_loops_slices_back_to_back_to_the_cone_end
    summary = runner({ "books" => engine(universe: %w[a b c d e f]) }).run!

    assert_equal 6, @held.size, "every id of the cone was crawled"
    assert_equal "cone end — every lane exhausted", summary.stop_reason
    assert_equal 6, summary.added
    assert_equal 6, summary.held
    assert_equal 0, summary.remaining
    lines = log_lines
    assert_match(%r{\A\S+Z START alpha/books \(pid 4242\): held 0, remaining 6 — delay 0\.01s/request, slice 2\z},
                 lines.first)
    slices = lines.grep(/\A\S+ SLICE /)
    assert_equal 4, slices.size, "three yielding slices + the cone-exhausted one"
    assert_match(%r{SLICE alpha/books #1 \[yield\]: \+2 held, held 2, remaining 4 \(2 asked}, slices.first)
    assert_match(/\[cone-exhausted\]/, slices.last)
    assert_match(/\A\S+Z SUMMARY alpha: 4 slice\(s\), \+6 held, held 6, remaining 0, .+ — cone end/, lines.last)
    refute File.exist?(@paths.pid), "a clean exit removes the pidfile"
  end

  def test_the_pidfile_names_the_runner_while_it_runs
    seen = []
    eng = engine(universe: %w[a b], hook: ->(_id) { seen << File.read(@paths.pid).strip })
    runner({ "books" => eng }).run!
    assert_equal %w[4242 4242], seen
  end

  def test_a_stop_flag_ends_the_runner_cleanly_with_the_summary_line
    eng = engine(universe: %w[a b c d e f], hook: ->(id) { File.write(@paths.stop, "") if id == "c" })
    summary = runner({ "books" => eng }).run!

    assert_equal "stop requested", summary.stop_reason
    assert_equal %w[a b c], @held.keys, "the request in flight finished; no further id was asked"
    assert_equal 3, summary.held
    assert_equal 3, summary.remaining
    assert_match(/STOP alpha: stop requested\z/, log_lines[-2])
    assert_match(/SUMMARY alpha: 2 slice\(s\), \+3 held, held 3, remaining 3, .+ — stop requested\z/, log_lines.last)
    refute File.exist?(@paths.pid)
    refute File.exist?(@paths.stop), "the consumed stop flag is cleared"
    ledger = JSON.parse(File.read(File.join(@tmp, "canonical", "alpha", ".trickle-test.json")))
    refute_includes ledger.values_at("denied", "empty", "timeout-stuck").flatten, "d",
                    "the stop is a clean stop: the next id stays selectable, never ledgered"
  end

  def test_a_signal_style_stop_request_ends_the_runner_the_same_way
    trickle = nil
    eng = engine(universe: %w[a b c d], hook: ->(id) { trickle.request_stop! if id == "a" })
    trickle = runner({ "books" => eng })
    assert_equal "stop requested", trickle.run!.stop_reason
    assert_equal %w[a], @held.keys
  end

  def test_the_engine_zero_yield_budget_stops_the_runner
    summary = runner({ "books" => engine(universe: %w[a b c d e f g h], refused: %w[a b c d e f g h],
                                         stop_after: 2) }).run!

    assert_match(/2 consecutive zero-yield slice\(s\)/, summary.stop_reason)
    assert_equal 2, log_lines.grep(/\A\S+ SLICE /).size
    assert_equal 0, summary.added
    assert_equal 4, summary.remaining
  end

  def test_a_fatal_error_stops_the_runner_with_the_summary_and_no_pidfile
    eng = engine(universe: %w[a b c], hook: ->(id) { raise Nabu::FetchError, "HTTP 503 at #{id}" if id == "b" })
    summary = runner({ "books" => eng }).run!

    assert_match(/\Afatal: Nabu::FetchError: HTTP 503 at b/, summary.stop_reason)
    assert_match(/SUMMARY alpha: .* — fatal: Nabu::FetchError/, log_lines.last)
    refute File.exist?(@paths.pid)
  end

  def test_every_lane_is_crawled_in_turn
    other = P::Engine.new(
      spec: spec.with(name: "pages", ledger_file: ".trickle-pages.json"), dir: File.join(@tmp, "canonical", "alpha"),
      universe: -> { %w[p q] }, held: ->(id) { @held.key?(id) },
      fetch_one: ->(id) { (@held[id] = true) && P::Outcome.new(status: :ok, evidence: {}) },
      sleeper: ->(_) {}
    )
    summary = runner({ "books" => engine(universe: %w[a b]), "pages" => other }).run!
    assert_equal %w[a b p q], @held.keys
    assert_equal 4, summary.held
    assert_equal 2, log_lines.grep(/\A\S+ START /).size
  end

  def test_each_lane_opens_with_one_pace_interval_and_the_engine_paces_between_slices
    slept = []
    sleeper = ->(seconds) { slept << seconds }
    eng = engine(universe: %w[a b c d], delay: 0.5, sleeper: sleeper)
    runner({ "books" => eng }, sleeper: sleeper).run!
    # the lane-opening pause (a restart never hits upstream sooner than the
    # declared delay after the last run's request), then one delay before
    # every request after the first — across the slice boundary too.
    assert_in_delta 0.5, slept.sum - (0.5 * 3), 1e-9
    assert(slept.all? { |seconds| seconds <= 0.5 })
  end

  def test_a_lane_with_no_declared_pace_is_refused
    assert_raises(T::Refused) { runner({ "books" => engine(universe: %w[a], delay: 0) }) }
  end

  # -- start / stop / status (the control surface) ---------------------------

  def control(alive: ->(pid) { [Process.pid, 777].include?(pid) }, spawner: nil, out: StringIO.new)
    @spawned = []
    spawner ||= lambda do |slug:, log:|
      @spawned << [slug, log]
      777
    end
    T::Control.new(paths: @paths, canonical_dir: File.join(@tmp, "canonical"), alive: alive,
                   spawner: spawner, out: out, sleeper: ->(_) {})
  end

  def test_start_detaches_a_runner_and_writes_its_pidfile
    out = StringIO.new
    FileUtils.mkdir_p(@paths.dir)
    File.write(@paths.stop, "") # a stale flag from an earlier run must not stop the new one
    assert_equal 777, control(out: out).start!(engines: { "books" => engine(universe: %w[a]) })
    assert_equal [["alpha", @paths.log]], @spawned
    assert_equal "777", File.read(@paths.pid).strip
    refute File.exist?(@paths.stop)
    assert_match(/trickle alpha started \(pid 777\)/, out.string)
  end

  def test_start_refuses_a_source_without_paced_lanes
    error = assert_raises(T::Refused) { control.start!(engines: {}) }
    assert_match(/no paced_crawls lanes/, error.message)
    assert_empty @spawned
  end

  def test_start_refuses_a_second_trickle_of_the_same_source
    FileUtils.mkdir_p(@paths.dir)
    File.write(@paths.pid, Process.pid.to_s)
    error = assert_raises(T::Refused) { control.start!(engines: { "books" => engine(universe: %w[a]) }) }
    assert_match(/already running \(pid #{Process.pid}\)/, error.message)
    assert_empty @spawned
  end

  def test_start_refuses_while_a_sync_or_rail_step_holds_the_fetch_lock
    Nabu::FetchLock.hold(canonical_dir: File.join(@tmp, "canonical"), slug: "alpha") do
      error = assert_raises(T::Refused) { control.start!(engines: { "books" => engine(universe: %w[a]) }) }
      assert_match(/is fetching alpha/, error.message)
    end
    assert_empty @spawned
  end

  def test_start_reports_a_runner_that_died_at_birth
    ctl = control(alive: ->(_pid) { false })
    FileUtils.mkdir_p(@paths.dir)
    File.write(@paths.log, "boom: no census\n")
    error = assert_raises(T::Refused) { ctl.start!(engines: { "books" => engine(universe: %w[a]) }) }
    assert_match(/exited at once.*boom: no census/m, error.message)
  end

  def test_stop_is_idempotent_when_nothing_runs
    out = StringIO.new
    FileUtils.mkdir_p(@paths.dir)
    File.write(@paths.pid, "999999") # a crashed runner's leftover
    assert_equal :idle, control(alive: ->(_) { false }, out: out).stop!
    assert_match(/no trickle running for alpha/, out.string)
    refute File.exist?(@paths.pid), "a dead pidfile is cleared"
    refute File.exist?(@paths.stop), "no flag is left for a future runner to trip on"
  end

  def test_stop_flags_a_running_trickle_and_reports_its_summary
    out = StringIO.new
    FileUtils.mkdir_p(@paths.dir)
    File.write(@paths.pid, "777")
    File.write(@paths.log, "t SUMMARY alpha: 3 slice(s), +5 held, held 9, remaining 1, 1.0s — stop requested\n")
    alive = ->(_pid) { !File.exist?(@paths.stop) } # the runner exits once it sees the flag
    assert_equal :stopped, control(alive: alive, out: out).stop!(wait: 5)
    assert_match(/trickle alpha stopped \(pid 777\): t SUMMARY alpha: 3 slice\(s\)/, out.string)
  end

  def test_stop_reports_a_runner_still_finishing_its_request
    out = StringIO.new
    FileUtils.mkdir_p(@paths.dir)
    File.write(@paths.pid, "777")
    assert_equal :requested, control(out: out).stop!(wait: 0)
    assert File.exist?(@paths.stop)
    assert_match(/stop requested for alpha \(pid 777\)/, out.string)
  end

  def test_status_with_no_trickles_says_so
    out = StringIO.new
    T::Control.status(dir: @paths.dir, out: out, alive: ->(_) { false })
    assert_equal "no trickles (#{@paths.dir} holds no runner state)\n", out.string
  end

  def test_status_reads_running_finished_and_died_runners
    FileUtils.mkdir_p(@paths.dir)
    dir = @paths.dir
    File.write(File.join(dir, "alpha.pid"), "777")
    File.write(File.join(dir, "alpha.log"),
               "t1 START alpha/books (pid 777): held 0, remaining 6 — delay 30.0s/request, slice 60\n" \
               "t2 SLICE alpha/books #1 [yield]: +2 held, held 2, remaining 4 (2 asked, 2 request(s) in 1.0s)\n  " \
               "books: report line\n")
    File.write(File.join(dir, "beta.log"),
               "t3 SUMMARY beta: 4 slice(s), +6 held, held 6, remaining 0, 2.0s — cone end — every lane exhausted\n")
    File.write(File.join(dir, "gamma.pid"), "888")
    File.write(File.join(dir, "gamma.log"), "t4 SLICE gamma/x #1 [yield]: +1 held, held 1, remaining 9 (1 asked)\n")
    out = StringIO.new
    T::Control.status(dir: dir, out: out, alive: ->(pid) { pid == 777 })
    lines = out.string.lines(chomp: true)
    assert_match(/\Aalpha: RUNNING \(pid 777\) — held 2, remaining 4; last: t2 SLICE/, lines[0])
    assert_match(/\Abeta: finished — held 6, remaining 0; last: t3 SUMMARY beta/, lines[1])
    assert_match(/\Agamma: DIED \(pid 888 gone, no SUMMARY line\) — held 1, remaining 9; last: t4 SLICE/, lines[2])
  end
end
