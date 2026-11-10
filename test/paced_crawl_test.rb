# frozen_string_literal: true

require "test_helper"
require "support/paced_crawl_conformance"
require "tmpdir"

# The paced-crawl engine (architecture §19), driven through the shared
# conformance suite by an in-memory fake lane, plus the engine-only pins:
# pacing and backoff through the injected sleeper/clock, look-ahead
# spacing, re-probe choice and accounting, spec/outcome validation, the
# ledger's on-disk shape.
class PacedCrawlTest < Minitest::Test
  include PacedCrawlConformance

  PC = Nabu::PacedCrawl

  def spec(slice: 3, delay: 0.0, backoff: 0.0, attempts: 3)
    PC::Spec.new(
      name: "items", ledger_file: ".items-crawl.json",
      classes: { denied: "denied", empty: "empty", timeout: "timeout-stuck" },
      delay: delay, slice: slice, timeout_attempts: attempts, timeout_backoff: backoff,
      schedule: PC::Schedule.new(cadence: :per_phase, slices_per_phase: 2, stop_after_zero_slices: 3)
    )
  end

  def stores = @stores ||= Hash.new { |hash, dir| hash[dir] = Set.new }

  # The fake lane: ids held in memory per dir; the script's symbols become
  # Outcomes the way a real lane's transport would answer.
  def fake_engine(dir:, ids:, script:, spec: self.spec, **)
    store = stores[dir]
    PC::Engine.new(
      spec: spec, dir: dir, universe: -> { ids }, held: ->(id) { store.include?(id) },
      fetch_one: lambda do |id|
        case script.call(id)
        when :ok then (store << id) && PC::Outcome.from_body(:ok, http_status: 200, body: '{"list":[1]}')
        when :denied then PC::Outcome.from_body(:denied, http_status: 403, body: PC_REFUSAL_BODY)
        when :empty then PC::Outcome.from_body(:empty, http_status: 200, body: '{"list":[]}')
        when :timeout then PC::Outcome.new(status: :timeout)
        when :fatal then raise Nabu::FetchError, "HTTP 500 for #{id}"
        end
      end,
      **
    )
  end

  def paced_crawl_engine(dir:, ids:, slice:, script:)
    fake_engine(dir: dir, ids: ids, script: script, spec: spec(slice: slice))
  end

  def paced_crawl_hold!(dir, id) = stores[dir] << id

  # A clock the sleeper advances: elapsed is exactly the paced time.
  def fake_time
    now = [0.0]
    slept = []
    [slept, -> { now[0] }, lambda { |seconds|
      slept << seconds
      now[0] += seconds
    }]
  end

  def test_requests_are_paced_by_the_delay_and_elapsed_reads_the_clock
    slept, clock, sleeper = fake_time
    Dir.mktmpdir do |dir|
      _, script = pc_upstream
      engine = fake_engine(dir: dir, ids: PC_IDS, script: script, spec: spec(delay: 1.0),
                           clock: clock, sleeper: sleeper)
      report = engine.slice!
      assert_equal [1.0, 1.0], slept, "a delay between every two requests, none before the first"
      assert_in_delta 2.0, report.elapsed
      assert_in_delta 2.0 / 3, report.pace
      assert_match(%r{3 request\(s\) in 2\.0s \(0\.67 s/request\)}, report.lines.last)
      engine.slice!
      assert_equal [1.0] * 5, slept, "the pacing holds across slices of one engine"
    end
  end

  def test_a_timeout_backs_off_doubling_between_attempts
    slept, clock, sleeper = fake_time
    Dir.mktmpdir do |dir|
      _, script = pc_upstream({ "101" => :timeout })
      lines = []
      engine = fake_engine(dir: dir, ids: PC_IDS, script: script, spec: spec(slice: 2, delay: 1.0, backoff: 5.0),
                           clock: clock, sleeper: sleeper, progress: ->(line) { lines << line })
      report = engine.slice!
      assert_equal [5.0, 1.0, 10.0, 1.0, 1.0], slept, "backoff 5 s then 10 s, each request still paced"
      assert_equal ["101"], report.stuck
      assert_equal 4, report.requests
      assert_includes lines, "items: 101 timed out 3× — ledgered timeout-stuck, moving on\n"
    end
  end

  def test_look_ahead_probes_are_exponentially_spaced_and_at_most_six
    Dir.mktmpdir do |dir|
      ids = (1000..1199).map(&:to_s)
      asked, script = pc_upstream({}, default: :denied)
      report = fake_engine(dir: dir, ids: ids, script: script, spec: spec(slice: 2)).slice!
      assert_equal :all_refused, report.classification
      assert_equal([2, 4, 8, 16, 32, 64], report.lookahead.map { |probe| probe[:ahead] })
      assert_equal %w[1003 1005 1009 1017 1033 1065], report.lookahead.map { |probe| probe[:id] },
                   "the id that many past the new frontier (1002)"
      assert_nil report.breakout
      assert_nil report.reprobe, "nothing held — no re-probe, the refusals stay per-id"
      assert_equal 2 + 6, asked.size
      assert_match(/no servable text within 64 id\(s\) probed/, report.lines.join("\n"))
    end
  end

  def test_the_reprobe_takes_the_held_id_nearest_before_the_frontier
    Dir.mktmpdir do |dir|
      %w[101 103 105].each { |id| stores[dir] << id }
      ledger = { "denied" => %w[102 104], "empty" => [], "timeout-stuck" => [] }
      File.write(File.join(dir, ".items-crawl.json"), JSON.generate(ledger))
      asked, script = pc_upstream({}, default: :denied)
      report = fake_engine(dir: dir, ids: PC_IDS, script: script, spec: spec(slice: 1)).slice!
      assert_equal "106", report.frontier[:before]
      assert_equal "105", report.reprobe[:id]
      assert_equal %w[106 105], asked, "the slice's one ask, then the one re-probe — refused, so no look-ahead"
      assert_equal :upstream_refusing, report.classification
    end
  end

  def test_the_breakout_estimate_costs_the_distance_at_the_current_pace
    _, clock, sleeper = fake_time
    Dir.mktmpdir do |dir|
      ids = (1000..1019).map(&:to_s)
      answers = (1000..1004).to_h { |n| [n.to_s, :denied] }
      _, script = pc_upstream(answers)
      report = fake_engine(dir: dir, ids: ids, script: script, spec: spec(slice: 2, delay: 1.0),
                           clock: clock, sleeper: sleeper).slice!
      assert_equal([[2, :denied], [4, :ok], [8, :ok], [16, :ok], [18, :ok]],
                   report.lookahead.map { |probe| probe.values_at(:ahead, :status) })
      assert_equal 4, report.breakout[:ahead]
      assert_match(/servable text answers 4 id\(s\) past the frontier \(~2 slice\(s\), ~3\.4s at the current pace\)/,
                   report.lines.join("\n"))
    end
  end

  def test_progress_reports_every_fifty_asks
    Dir.mktmpdir do |dir|
      lines = []
      _, script = pc_upstream({}, default: :denied)
      ids = (1000..1120).map(&:to_s)
      stores[dir] << "1119"
      fake_engine(dir: dir, ids: ids, script: script, spec: spec(slice: 100), progress: ->(line) { lines << line })
        .slice!
      assert_equal ["items: +0 ok, 50 refused (50/100)…\n", "items: +0 ok, 100 refused (100/100)…\n"], lines
    end
  end

  def test_the_ledger_on_disk_keeps_the_class_arrays_and_adds_last_slice
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".items-crawl.json"), JSON.generate({ "denied" => %w[112 101], "legacy" => 1 }))
      _, script = pc_upstream({ "102" => :empty })
      engine = fake_engine(dir: dir, ids: PC_IDS, script: script, spec: spec(slice: 2))
      assert_equal({ "denied" => %w[101 112], "empty" => [], "timeout-stuck" => [] }, engine.ledger,
                   "a ledger from before a class existed reads that class empty")
      engine.slice!
      on_disk = JSON.parse(File.read(engine.ledger_path))
      assert_equal %w[denied empty timeout-stuck last_slice], on_disk.keys
      assert_equal [%w[101 112], ["102"], []], on_disk.values_at("denied", "empty", "timeout-stuck")
      assert_equal "items", on_disk.dig("last_slice", "name")
      refute File.exist?("#{engine.ledger_path}.tmp"), "written through a staging name and renamed"
      assert_equal on_disk["last_slice"], engine.last_slice
    end
  end

  def test_an_undeclared_terminal_answer_raises
    lane = PC::Spec.new(name: "x", ledger_file: ".x.json", classes: { denied: "denied" }, delay: 0, slice: 1,
                        schedule: nil)
    Dir.mktmpdir do |dir|
      engine = PC::Engine.new(spec: lane, dir: dir, universe: -> { %w[1] }, held: ->(_id) { false },
                              fetch_one: ->(_id) { PC::Outcome.new(status: :empty) })
      assert_raises(PC::Error) { engine.slice! }
    end
  end

  # A lane whose upstream answers several refusals of one terminal kind
  # (a 404 "no text" beside a 403) ledgers each under its own declared
  # class: the Outcome names it, the Spec declares it per status.
  def subclass_spec
    PC::Spec.new(
      name: "zips", ledger_file: ".zips-crawl.json",
      classes: { denied: "denied", empty: "empty", timeout: "timeout-stuck" },
      subclasses: { denied: ["missing"], empty: ["malformed"] },
      delay: 0, slice: 4, schedule: PC::Schedule.new(cadence: :per_phase, slices_per_phase: 1,
                                                     stop_after_zero_slices: 1)
    )
  end

  def test_a_lane_ledgers_declared_subclasses_of_a_terminal_answer
    assert_equal %w[denied missing empty malformed timeout-stuck], subclass_spec.class_names,
                 "each status's class, then its subclasses, in declaration order"
    answers = {
      "1" => PC::Outcome.new(status: :denied, ledger_class: "missing"),
      "2" => PC::Outcome.new(status: :denied),
      "3" => PC::Outcome.new(status: :empty, ledger_class: "malformed")
    }
    Dir.mktmpdir do |dir|
      engine = PC::Engine.new(spec: subclass_spec, dir: dir, universe: -> { %w[1 2 3] }, held: ->(_id) { false },
                              fetch_one: ->(id) { answers.fetch(id) })
      report = engine.slice!
      assert_equal({ "denied" => ["2"], "missing" => ["1"], "empty" => [], "malformed" => ["3"],
                     "timeout-stuck" => [] }, engine.ledger)
      assert_equal({ "denied" => 1, "missing" => 1, "empty" => 0, "malformed" => 1, "timeout-stuck" => 0 },
                   report.refused)
      assert_match(/ledgered 3 \(\+3\) \[denied 1, missing 1, empty 0, malformed 1, timeout-stuck 0\]/,
                   report.lines.join("\n"))
    end
  end

  def test_an_outcome_naming_a_class_its_status_does_not_declare_raises
    Dir.mktmpdir do |dir|
      engine = PC::Engine.new(spec: subclass_spec, dir: dir, universe: -> { %w[1] }, held: ->(_id) { false },
                              fetch_one: ->(_id) { PC::Outcome.new(status: :denied, ledger_class: "malformed") })
      error = assert_raises(PC::Error) { engine.slice! }
      assert_match(/malformed/, error.message)
    end
    assert_raises(ArgumentError) { PC::Outcome.new(status: :ok, ledger_class: "missing") }
    assert_raises(ArgumentError) do
      PC::Spec.new(name: "x", ledger_file: ".x", classes: { denied: "denied" }, subclasses: { empty: ["e"] },
                   delay: 0, slice: 1, schedule: nil)
    end
  end

  def test_fetch_one_must_answer_an_outcome
    Dir.mktmpdir do |dir|
      engine = PC::Engine.new(spec: spec, dir: dir, universe: -> { %w[1] }, held: ->(_id) { false },
                              fetch_one: ->(_id) { :ok })
      assert_raises(PC::Error) { engine.slice! }
    end
  end

  def test_spec_and_outcome_validate_their_shape
    assert_raises(ArgumentError) { spec(slice: 0) }
    assert_raises(ArgumentError) { spec(attempts: 0) }
    assert_raises(ArgumentError) do
      PC::Spec.new(name: "x", ledger_file: ".x", classes: { ok: "ok" }, delay: 0, slice: 1, schedule: nil)
    end
    assert_raises(ArgumentError) { PC::Outcome.new(status: :maybe) }
    assert_equal "books", spec.with(name: "books").name, "a lane retunes through #with"
    outcome = PC::Outcome.from_body(:denied, http_status: 403, body: "This  PID\nis not allowed#{'x' * 200}")
    assert_equal 403, outcome.http_status
    assert_operator outcome.body_head.bytesize, :<=, PC::BODY_HEAD_BYTES
    assert outcome.body_head.start_with?("This PID is not allowed"), "whitespace collapsed"
    assert_equal "ab", PC.body_head("ab\xE3\x81".b), "a byte cut mid-character is scrubbed, never raised on"
  end
end
