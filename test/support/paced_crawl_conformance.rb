# frozen_string_literal: true

require "json"
require "tmpdir"

# Shared conformance suite for paced-crawl lanes (architecture §19). Every
# lane built on Nabu::PacedCrawl includes this module into its test — the
# engine's own test drives it with an in-memory fake; an adapter drives it
# through its REAL wiring (its census file, its held-on-disk rule, its
# transport stubbed by WebMock).
#
# Hooks the including test provides:
#
#   paced_crawl_engine(dir:, ids:, slice:, script:) -> a Nabu::PacedCrawl::Engine
#       over +dir+ whose universe is exactly +ids+ (in that order), whose
#       slice budget is +slice+, with no pacing delay and no backoff. Called
#       several times on the same +dir+ (a resumed crawl is a new engine
#       over the same disk). +script+ is the upstream: ->(id) answering one
#       of :ok / :denied / :empty / :timeout / :fatal, which the factory
#       translates into its own transport — :ok a servable payload the lane
#       stores, :denied an HTTP 403 "This PID is not allowed", :empty an
#       empty-but-valid payload, :timeout a transport timeout, :fatal a
#       non-terminal failure (HTTP 500) that must abort the slice.
#   paced_crawl_hold!(dir, id) -> place +id+'s payload as already held.
#
# Pins (one test method each): held never re-fetched; the one budget —
# every asked id spends a unit whatever it answers; ledgered never retried
# (and timeouts retried timeout_attempts times, then ledgered); resume from
# a kill mid-slice; an idempotent re-slice at the end of the cone; every
# zero-yield class (all-refused with its re-probe and look-ahead,
# upstream-refusing, cone-exhausted, selection-empty raises); the frozen
# frontier raises; the report shape incl. the reconciliation triple, its
# loud mismatch, and the persisted last_slice; the offline diagnose; the
# declared schedule.
module PacedCrawlConformance
  PC_IDS = (101..112).map(&:to_s).freeze
  PC_REFUSAL_BODY = "This PID is not allowed"

  def paced_crawl_engine(dir:, ids:, slice:, script:) # rubocop:disable Lint/UnusedMethodArgument
    flunk "#{self.class} must define #paced_crawl_engine(dir:, ids:, slice:, script:) returning an Engine"
  end

  def paced_crawl_hold!(_dir, _id)
    flunk "#{self.class} must define #paced_crawl_hold!(dir, id) placing the id's payload as held"
  end

  # A recording upstream: answers[id] or +default+; every ask lands in
  # the returned array.
  def pc_upstream(answers = {}, default: :ok)
    asked = []
    [asked, lambda do |id|
      asked << id
      answers.fetch(id, default)
    end]
  end

  def pc_engine(dir, slice:, answers: {}, default: :ok, ids: PC_IDS)
    asked, script = pc_upstream(answers, default: default)
    [paced_crawl_engine(dir: dir, ids: ids, slice: slice, script: script), asked]
  end

  def pc_ledger_on_disk(engine) = JSON.parse(File.read(engine.ledger_path))

  def pc_class(engine, status) = engine.spec.classes.fetch(status)

  def test_paced_crawl_held_ids_are_never_fetched
    Dir.mktmpdir do |dir|
      paced_crawl_hold!(dir, "101")
      paced_crawl_hold!(dir, "102")
      engine, asked = pc_engine(dir, slice: 3)
      report = engine.slice!
      assert_equal %w[103 104 105], asked, "held ids are skipped, the slice takes the next three in order"
      assert_equal 3, report.ok
      assert_equal [2, 5], report.held.values_at(:before, :after)
    end
  end

  def test_paced_crawl_every_asked_id_spends_one_unit_of_the_one_budget
    Dir.mktmpdir do |dir|
      engine, asked = pc_engine(dir, slice: 3, answers: { "101" => :denied, "103" => :empty })
      report = engine.slice!
      assert_equal %w[101 102 103], asked, "refusals burn the budget exactly like yields"
      assert_equal [3, 1], [report.attempted, report.ok]
      assert_equal 1, report.refused.fetch(pc_class(engine, :denied))
      assert_equal 1, report.refused.fetch(pc_class(engine, :empty))
      assert_equal ["101", "104", 3], report.frontier.values_at(:before, :after, :moved)
      assert_equal 3, report.requests, "a yielding slice spends no probe"
      refute_predicate report, :zero_yield?
    end
  end

  def test_paced_crawl_ledgered_ids_are_never_retried
    Dir.mktmpdir do |dir|
      engine, asked = pc_engine(dir, slice: 4, answers: { "101" => :denied, "102" => :empty, "103" => :timeout })
      report = engine.slice!
      attempts = engine.spec.timeout_attempts
      assert_equal attempts, asked.count("103"), "a timeout is retried timeout_attempts times, then ledgered"
      assert_equal ["103"], report.stuck
      assert_equal ["101"], pc_ledger_on_disk(engine).fetch(pc_class(engine, :denied))
      assert_equal ["102"], pc_ledger_on_disk(engine).fetch(pc_class(engine, :empty))
      assert_equal ["103"], pc_ledger_on_disk(engine).fetch(pc_class(engine, :timeout))

      resumed, asked_again = pc_engine(dir, slice: 4)
      resumed.slice!
      assert_equal %w[105 106 107 108], asked_again, "neither a refusal nor a stuck id is ever re-asked"
    end
  end

  def test_paced_crawl_resumes_from_a_kill_mid_slice
    Dir.mktmpdir do |dir|
      engine, = pc_engine(dir, slice: 5, answers: { "101" => :denied, "102" => :denied, "103" => :fatal })
      assert_raises(Nabu::Error) { engine.slice! }
      assert_equal %w[101 102], pc_ledger_on_disk(engine).fetch(pc_class(engine, :denied)),
                   "the ledger holds what the slice learned before it died"

      resumed, asked = pc_engine(dir, slice: 2)
      resumed.slice!
      assert_equal %w[103 104], asked, "the resumed crawl starts at the id that died"
    end
  end

  def test_paced_crawl_re_slicing_an_exhausted_cone_is_idempotent
    Dir.mktmpdir do |dir|
      engine, = pc_engine(dir, slice: 50, answers: { "112" => :denied })
      assert_equal 11, engine.slice!.ok
      ledger = engine.ledger

      again, asked = pc_engine(dir, slice: 50)
      report = again.slice!
      assert_empty asked, "an exhausted cone asks nothing"
      assert_equal :cone_exhausted, report.classification
      assert_equal ledger, again.ledger
      assert_equal [11, 11], report.held.values_at(:before, :after)
      assert(report.lines.any? { |line| line.include?("ZERO-YIELD SLICE [cone-exhausted]") }, report.lines.inspect)
      refute_predicate report, :progressed?
    end
  end

  def test_paced_crawl_an_all_refused_slice_reprobes_a_held_id_and_looks_ahead
    Dir.mktmpdir do |dir|
      paced_crawl_hold!(dir, "101")
      denied = %w[102 103 104 105].to_h { |id| [id, :denied] }
      engine, asked = pc_engine(dir, slice: 4, answers: denied)
      report = engine.slice!
      assert_equal :all_refused, report.classification
      assert_predicate report, :zero_yield?
      assert_predicate report, :progressed?, "a refusal stripe crossed is progress — the frontier moved"
      assert_equal 1, asked.count("101"), "exactly ONE re-probe of the held id"
      assert_equal({ id: "101", status: :ok }, report.reprobe.slice(:id, :status))
      assert_equal [[4, "109"], [7, "112"]], report.lookahead.map { |probe| probe.values_at(:ahead, :id) },
                   "slice × 2^k past the frontier, clamped to the remaining cone"
      assert_equal 4 + 1 + 2, report.requests, "the probes count in the request tally"
      assert_equal 4, report.attempted, "…but never against the slice budget"
      sample = report.samples.first
      assert_equal ["102", :denied, 403], sample.values_at(:id, :status, :http_status)
      assert_equal PC_REFUSAL_BODY, sample[:body_head], "refusal evidence is quoted verbatim"
      text = report.lines.join("\n")
      assert_match(%r{ZERO-YIELD SLICE \[all-refused\]: 4/4 asked refused \(HTTP 403 ×4, uniform\)}, text)
      assert_match(/re-probe of held 101: ok HTTP 200 — upstream alive/, text)
      assert_match(/look-ahead: .* servable text answers 4 id\(s\) past the frontier/, text)
      assert_empty report.stuck
    end
  end

  def test_paced_crawl_a_refused_reprobe_classifies_upstream_refusing
    Dir.mktmpdir do |dir|
      paced_crawl_hold!(dir, "101")
      engine, = pc_engine(dir, slice: 3, default: :denied)
      report = engine.slice!
      assert_equal :upstream_refusing, report.classification
      assert_equal :denied, report.reprobe[:status]
      assert_empty report.lookahead, "no look-ahead into a wholesale block"
      assert_equal 3 + 1, report.requests
      assert(report.lines.any? { |line| line.include?("ZERO-YIELD SLICE [upstream-refusing]") }, report.lines.inspect)
    end
  end

  def test_paced_crawl_selection_empty_with_ids_remaining_raises
    Dir.mktmpdir do |dir|
      engine, = pc_engine(dir, slice: 3)
      seen = Hash.new(0)
      lying = engine.rewire(held: lambda do |id, original|
        seen[id] += 1
        seen[id] > 1 || original.call(id)
      end)
      assert_raises(Nabu::PacedCrawl::SelectionEmptyError) { lying.slice! }
    end
  end

  def test_paced_crawl_a_frozen_frontier_raises
    Dir.mktmpdir do |dir|
      engine, = pc_engine(dir, slice: 3)
      storing_nothing = engine.rewire(fetch_one: ->(_id, _original) { Nabu::PacedCrawl::Outcome.new(status: :ok) })
      error = assert_raises(Nabu::PacedCrawl::FrozenFrontierError) { storing_nothing.slice! }
      assert_match(/frontier frozen — 3 asked id\(s\) still selectable/, error.message)
    end
  end

  def test_paced_crawl_report_shape_and_the_persisted_last_slice
    Dir.mktmpdir do |dir|
      paced_crawl_hold!(dir, "101")
      engine, = pc_engine(dir, slice: 3)
      report = engine.slice!
      assert_kind_of Nabu::PacedCrawl::Report, report
      assert_predicate report, :reconciles?
      assert_equal 12, report.census
      assert_equal [[1, 4], [11, 8]], [report.held.values_at(:before, :after),
                                       report.remaining.values_at(:before, :after)]
      assert_equal ["102", "105", 3], report.frontier.values_at(:before, :after, :moved)
      name = engine.spec.name
      assert(report.lines.all? { |line| line.start_with?("#{name}: ") }, report.lines.inspect)
      text = report.lines.join("\n")
      assert_match(/census 12 = held 4 \(\+3\) \+ ledgered 0 \(\+0\) \[[^\]]*\] \+ remaining 8 — reconciles/, text)
      assert_match(/frontier 102 → 105 \(advanced 3 of 12 position\(s\)\)/, text)
      assert_match(%r{slice \+3 ok of 3/3 asked}, text)
      assert_match(/3 request\(s\) in .*; ~3 slice\(s\) of 3 to the end of the cone/, text)
      last = pc_ledger_on_disk(engine).fetch(Nabu::PacedCrawl::LAST_SLICE)
      assert_equal %w[yield 3 3], [last["classification"], last["ok"].to_s, last["attempted"].to_s]
      assert_equal engine.spec.class_names.sort, (pc_ledger_on_disk(engine).keys - [Nabu::PacedCrawl::LAST_SLICE]).sort,
                   "the ledger keeps its shape: one array of ids per class, beside last_slice"
    end
  end

  def test_paced_crawl_a_reconciliation_mismatch_is_loud
    Dir.mktmpdir do |dir|
      paced_crawl_hold!(dir, "101")
      engine, = pc_engine(dir, slice: 1)
      File.write(engine.ledger_path, JSON.generate({ pc_class(engine, :denied) => ["101"] }))
      report = engine.slice!
      refute_predicate report, :reconciles?
      assert(report.lines.any? { |line| line.include?("RECONCILIATION MISMATCH: census 12") }, report.lines.inspect)
    end
  end

  def test_paced_crawl_diagnose_is_offline_set_arithmetic
    Dir.mktmpdir do |dir|
      engine, = pc_engine(dir, slice: 2, answers: { "101" => :denied })
      engine.slice!
      offline, asked = pc_engine(dir, slice: 2)
      diagnosis = offline.diagnose
      assert_empty asked, "diagnose never asks upstream"
      assert_predicate diagnosis, :reconciles?
      assert_equal [12, 1, 10], [diagnosis.census, diagnosis.held_count, diagnosis.remaining_count]
      assert_equal ["103", 2], [diagnosis.frontier, diagnosis.frontier_position]
      assert_equal "yield", diagnosis.last_slice["classification"]
      text = diagnosis.lines.join("\n")
      assert_match(/census 12 = held 1 \+ ledgered 1 \[[^\]]*\] \+ remaining 10 — reconciles/, text)
      assert_match(/last slice .*: yield, \+1 ok of 2 asked/, text)
    end
  end

  def test_paced_crawl_lane_declares_its_schedule
    Dir.mktmpdir do |dir|
      engine, = pc_engine(dir, slice: 1)
      schedule = engine.spec.schedule
      assert_kind_of Nabu::PacedCrawl::Schedule, schedule
      refute_nil schedule.cadence
      assert_operator schedule.slices_per_phase, :>=, 1
      assert_operator schedule.stop_after_zero_slices, :>=, 1
    end
  end
end
