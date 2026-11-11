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
        when :halt then PC::Outcome.halt(reason: "quota floor", evidence: { http_status: 200, remaining: 3 })
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

  def test_the_default_codec_is_flat_and_passes_foreign_sections_through
    assert_same PC::FLAT_CODEC, spec.codec
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".items-crawl.json"),
                 JSON.generate({ "denied" => %w[112], "pages" => { "7" => %w[a b] }, "server-error" => %w[9],
                                 "legacy" => 1, "last_slice" => { "name" => "old" } }))
      _, script = pc_upstream({ "101" => :denied })
      engine = fake_engine(dir: dir, ids: PC_IDS, script: script, spec: spec(slice: 1))
      assert_equal({ "name" => "old" }, engine.last_slice)
      engine.slice!
      on_disk = JSON.parse(File.read(engine.ledger_path))
      assert_equal %w[denied empty timeout-stuck pages server-error last_slice], on_disk.keys,
                   "classes first, then the foreign sections, then the engine's last_slice"
      assert_equal [%w[101 112], { "7" => %w[a b] }, %w[9]], on_disk.values_at("denied", "pages", "server-error")
      assert_equal "items", on_disk.dig("last_slice", "name")
    end
  end

  # A nested on-disk shape: the classes live under one "refused" map.
  class NestedCodec
    def load(raw) = raw.fetch("refused", {}).transform_values { |ids| ids.to_set(&:to_s) }

    def dump(classes, raw)
      raw.merge("refused" => classes.transform_values { |ids| ids.to_a.sort })
    end
  end

  def test_a_lane_codec_routes_every_ledger_read_and_write
    lane = spec(slice: 2).with(codec: NestedCodec.new)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".items-crawl.json"),
                 JSON.generate({ "refused" => { "denied" => %w[101] }, "pages" => { "1" => [2] } }))
      asked, script = pc_upstream({ "103" => :empty })
      engine = fake_engine(dir: dir, ids: PC_IDS, script: script, spec: lane)
      assert_equal %w[101], engine.ledger.fetch("denied")
      engine.slice!
      assert_equal %w[102 103], asked, "the codec's ledgered id is never asked"
      on_disk = JSON.parse(File.read(engine.ledger_path))
      assert_equal %w[refused pages last_slice], on_disk.keys
      assert_equal({ "denied" => %w[101], "empty" => %w[103], "timeout-stuck" => [] }, on_disk["refused"])
      assert_equal({ "1" => [2] }, on_disk["pages"])
    end
  end

  # ── the clean stop ──

  def test_a_halt_ends_the_slice_cleanly_and_leaves_the_id_selectable
    Dir.mktmpdir do |dir|
      asked, script = pc_upstream({ "102" => :denied, "103" => :halt })
      report = fake_engine(dir: dir, ids: PC_IDS, script: script, spec: spec(slice: 10)).slice!
      assert_equal %w[101 102 103], asked, "nothing is asked after the halt — no further id, no probe"
      assert_equal :clean_stop, report.classification
      assert_predicate report, :halted?
      assert_equal({ id: "103", reason: "quota floor", evidence: { http_status: 200, remaining: 3 } }, report.halt)
      assert_equal [2, 1, 3], [report.attempted, report.ok, report.requests], "the halted id is not an answer"
      assert_equal({ "denied" => 1, "empty" => 0, "timeout-stuck" => 0 }, report.refused, "a halt is never refused")
      assert_nil report.reprobe
      assert_empty report.lookahead
      assert_equal "103", report.frontier[:after], "the halted id stays the frontier"
      assert_match(/CLEAN STOP at 103: quota floor \(http_status 200, remaining 3\)/, report.lines.first)

      resumed_asked, resumed_script = pc_upstream
      engine = fake_engine(dir: dir, ids: PC_IDS, script: resumed_script, spec: spec(slice: 1))
      assert(engine.ledger.values.none? { |ids| ids.include?("103") }, "a halt is never ledgered")
      engine.slice!
      assert_equal %w[103], resumed_asked, "the next slice re-asks the halted id first"
    end
  end

  def test_a_halt_on_the_first_id_is_a_clean_stop_not_a_zero_yield_pathology
    Dir.mktmpdir do |dir|
      stores[dir] << "112"
      _, script = pc_upstream({ "101" => :halt })
      report = fake_engine(dir: dir, ids: PC_IDS, script: script).slice!
      assert_equal :clean_stop, report.classification, "neither SelectionEmpty nor FrozenFrontier fires"
      assert_predicate report, :zero_yield?
      assert_nil report.reprobe, "a halt is not a refusal — no re-probe"
      text = report.lines.join("\n")
      refute_match(/ZERO-YIELD/, text)
      assert_match(/CLEAN STOP at 101/, text)
      on_disk = JSON.parse(File.read(File.join(dir, ".items-crawl.json")))
      assert_equal "clean_stop", on_disk.dig("last_slice", "classification")
    end
  end

  def test_a_halt_answered_to_a_probe_stops_the_probing_cleanly
    Dir.mktmpdir do |dir|
      stores[dir] << "101"
      asked, script = pc_upstream({ "101" => :halt }, default: :denied)
      report = fake_engine(dir: dir, ids: PC_IDS, script: script, spec: spec(slice: 2)).slice!
      assert_equal %w[102 103 101], asked
      assert_equal :clean_stop, report.classification, "a halted re-probe is a stop, not a wholesale block"
      assert_equal "101", report.halt[:id]
      assert_empty report.lookahead

      Dir.mktmpdir do |other|
        asked, script = pc_upstream({ "110" => :halt }, default: :denied)
        report = fake_engine(dir: other, ids: PC_IDS, script: script, spec: spec(slice: 2)).slice!
        assert_equal %w[101 102 104 106 110], asked, "the look-ahead stops at the halted probe"
        assert_equal :clean_stop, report.classification
        assert_equal([2, 4], report.lookahead.map { |probe| probe[:ahead] })
        assert_equal "110", report.halt[:id]
      end
    end
  end

  def test_a_halt_outcome_validates_its_shape
    halt = PC::Outcome.halt(reason: "429 Too Many Requests", evidence: { http_status: 429, retry_after: "60" })
    assert_equal :halt, halt.status
    assert_equal "429 Too Many Requests", halt.reason
    assert_equal({ http_status: 429, retry_after: "60" }, halt.evidence, "halt evidence is kept verbatim")
    assert_equal 429, halt.http_status
    refute_predicate halt, :ok?
    assert_predicate halt, :halt?
    assert_raises(ArgumentError) { PC::Outcome.new(status: :halt) }
    assert_raises(ArgumentError) { PC::Outcome.halt(reason: "") }
    assert_raises(ArgumentError) { PC::Outcome.new(status: :denied, reason: "x") }
    assert_raises(ArgumentError) { PC::Outcome.new(status: :halt, reason: "x", ledger_class: "denied") }
    assert_raises(ArgumentError) do
      PC::Spec.new(name: "x", ledger_file: ".x", classes: { halt: "h" }, delay: 0, slice: 1, schedule: nil)
    end
  end

  # ── the outage breaker ──

  def outage_spec(slice: 10, run: 3)
    spec(slice: slice, attempts: 1).with(outage_statuses: [:timeout], outage_run: run)
  end

  def ledger_now(dir, ids: PC_IDS)
    fake_engine(dir: dir, ids: ids, script: ->(_id) { flunk "no ask" }, spec: outage_spec).ledger
  end

  def test_staged_outage_failures_commit_when_a_later_id_answers
    Dir.mktmpdir do |dir|
      seen_at_recovery = nil
      asked, upstream = pc_upstream({ "101" => :timeout, "102" => :timeout, "104" => :timeout, "105" => :empty })
      script = lambda do |id|
        seen_at_recovery = ledger_now(dir) if id == "103"
        upstream.call(id)
      end
      report = fake_engine(dir: dir, ids: PC_IDS, script: script, spec: outage_spec(slice: 5)).slice!
      assert_equal %w[101 102 103 104 105], asked
      assert_empty seen_at_recovery["timeout-stuck"], "staged failures are not on disk before upstream answers"
      assert_equal({ "denied" => [], "empty" => %w[105], "timeout-stuck" => %w[101 102 104] }, ledger_now(dir),
                   "an ok and a non-outage refusal each commit the run before them")
      assert_equal %w[101 102 104], report.stuck
      assert_equal 3, report.refused["timeout-stuck"]
      assert_equal :yield, report.classification
      assert_nil report.outage
    end
  end

  def test_an_outage_run_aborts_the_slice_and_drops_the_run_unledgered
    Dir.mktmpdir do |dir|
      stores[dir] << "112"
      asked, script = pc_upstream({ "101" => :denied, "102" => :timeout, "103" => :timeout, "104" => :timeout })
      report = fake_engine(dir: dir, ids: PC_IDS, script: script, spec: outage_spec).slice!
      assert_equal %w[101 102 103 104], asked, "the third consecutive failure ends the slice — no probe after"
      assert_equal :outage_abort, report.classification
      assert_predicate report, :outage_aborted?
      assert_equal({ aborted: true, count: 3, ids: %w[102 103 104] }, report.outage.slice(:aborted, :count, :ids))
      assert_equal %w[104 timeout], report.outage[:last].values_at(:id, :status).map(&:to_s)
      assert_equal({ "denied" => %w[101], "empty" => [], "timeout-stuck" => [] }, ledger_now(dir),
                   "everything before the run stays; nothing from the run is ledgered")
      assert_equal({ "denied" => 1, "empty" => 0, "timeout-stuck" => 0 }, report.refused)
      assert_empty report.stuck
      assert_nil report.reprobe
      assert_empty report.lookahead
      assert_equal "102", report.frontier[:after]
      text = report.lines.join("\n")
      refute_match(/ZERO-YIELD/, text)
      assert_match(/OUTAGE ABORT: 3 consecutive outage answer\(s\) \(timeout\) at 102…104 — .*last: 104 timeout/,
                   text)

      resumed, resumed_script = pc_upstream
      fake_engine(dir: dir, ids: PC_IDS, script: resumed_script, spec: outage_spec(slice: 1)).slice!
      assert_equal %w[102], resumed, "the dropped run is re-asked next slice"
    end
  end

  def test_a_run_still_staged_when_the_slice_ends_stays_unledgered
    Dir.mktmpdir do |dir|
      _, script = pc_upstream({ "102" => :timeout })
      report = fake_engine(dir: dir, ids: PC_IDS, script: script, spec: outage_spec(slice: 2)).slice!
      assert_equal :yield, report.classification, "no FrozenFrontier for the staged id"
      assert_equal({ aborted: false, count: 1, ids: %w[102] }, report.outage.slice(:aborted, :count, :ids))
      refute_predicate report, :outage_aborted?
      assert_empty ledger_now(dir)["timeout-stuck"]
      assert_match(/OUTAGE STAGE: 1 outage answer\(s\) \(timeout\) at 102 uncommitted/, report.lines.join("\n"))
    end
  end

  def test_a_slice_killed_mid_stage_loses_only_the_staged_items
    Dir.mktmpdir do |dir|
      _, script = pc_upstream({ "101" => :denied, "102" => :timeout, "103" => :fatal })
      assert_raises(Nabu::FetchError) { fake_engine(dir: dir, ids: PC_IDS, script: script, spec: outage_spec).slice! }
      assert_equal({ "denied" => %w[101], "empty" => [], "timeout-stuck" => [] }, ledger_now(dir))
    end
  end

  def test_the_outage_knobs_validate
    assert_equal [[], nil], spec.to_h.values_at(:outage_statuses, :outage_run), "off by default"
    assert_equal [[:timeout], 3], outage_spec.to_h.values_at(:outage_statuses, :outage_run)
    assert_raises(ArgumentError) { spec.with(outage_statuses: [:ok], outage_run: 2) }
    assert_raises(ArgumentError) { spec.with(outage_statuses: [:halt], outage_run: 2) }
    assert_raises(ArgumentError) { spec.with(outage_statuses: [:timeout]) }
    assert_raises(ArgumentError) { spec.with(outage_run: 3) }
    assert_raises(ArgumentError) { spec.with(outage_statuses: [:timeout], outage_run: 0) }
    assert_raises(ArgumentError) do
      PC::Spec.new(name: "x", ledger_file: ".x", classes: { denied: "denied" }, delay: 0, slice: 1, schedule: nil,
                   outage_statuses: [:timeout], outage_run: 2)
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

# The whole conformance suite again over a lane that declares the outage
# breaker (timeouts staged, a run of three aborts) — so the OUTAGE LAW runs
# against the engine itself, and every other pin holds with the breaker on.
class PacedCrawlOutageLaneTest < Minitest::Test
  include PacedCrawlConformance

  PC = Nabu::PacedCrawl

  def stores = @stores ||= Hash.new { |hash, dir| hash[dir] = Set.new }

  def paced_crawl_engine(dir:, ids:, slice:, script:)
    store = stores[dir]
    lane = PC::Spec.new(
      name: "items", ledger_file: ".items-crawl.json",
      classes: { denied: "denied", empty: "empty", timeout: "timeout-stuck" },
      delay: 0, slice: slice, timeout_backoff: 0, outage_statuses: [:timeout], outage_run: 3,
      schedule: PC::Schedule.new(cadence: :per_phase, slices_per_phase: 2, stop_after_zero_slices: 3)
    )
    PC::Engine.new(
      spec: lane, dir: dir, universe: -> { ids }, held: ->(id) { store.include?(id) }, sleeper: ->(_) {},
      fetch_one: lambda do |id|
        case script.call(id)
        when :ok then (store << id) && PC::Outcome.from_body(:ok, http_status: 200, body: "{}")
        when :denied then PC::Outcome.from_body(:denied, http_status: 403, body: PC_REFUSAL_BODY)
        when :empty then PC::Outcome.from_body(:empty, http_status: 200, body: "{}")
        when :timeout then PC::Outcome.new(status: :timeout)
        when :fatal then raise Nabu::FetchError, "HTTP 500 for #{id}"
        end
      end
    )
  end

  def paced_crawl_hold!(dir, id) = stores[dir] << id
end
