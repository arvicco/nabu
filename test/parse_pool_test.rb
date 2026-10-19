# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The forked parse-worker pool: N children run Adapter#parse, the parent
# receives every result IN INPUT ORDER (whatever order the workers finish
# in), a parse exception re-raises at its own slot with its own class, and
# a worker that dies takes the load down honestly at the slot it held.
class ParsePoolTest < Minitest::Test
  # A deterministic synthetic adapter: one document per ref, its passages
  # derived from the ref id; jittered so workers finish out of order; a
  # few ids trip the failure shapes the pool must carry across the fork.
  class JitterAdapter < Nabu::Adapter
    def parse(ref)
      n = Integer(ref.metadata.fetch("n"))
      sleep(((n * 7919) % 5) / 1000.0) # out-of-order completion
      case ref.metadata["trip"]
      when "parse" then raise Nabu::ParseError, "bad #{ref.id}"
      when "skip" then raise Nabu::DocumentSkipped.new("rule #{ref.id}", reason: "catalog-only")
      when "crash" then raise ArgumentError, "adapter bug at #{ref.id}"
      when "die" then Process.kill(:KILL, Process.pid)
      end
      document = Nabu::Document.new(urn: ref.id, language: "grc", title: "T#{n}", canonical_path: ref.path,
                                    metadata: { "n" => n })
      (n % 4).succ.times do |i|
        document << Nabu::Passage.new(urn: "#{ref.id}:#{i}", language: "grc", text: "λόγος #{n} #{i}",
                                      annotations: { "i" => i }, sequence: i)
      end
      document
    end
  end

  def refs(count, trips = {})
    Array.new(count) do |n|
      metadata = { "n" => n.to_s }
      metadata["trip"] = trips[n] if trips.key?(n)
      Nabu::DocumentRef.new(source_id: "jitter", id: "urn:nabu:jitter:#{n}", path: "/canonical/jitter/#{n}",
                            metadata: metadata)
    end
  end

  def serial(adapter, list)
    list.map do |ref|
      adapter.parse(ref)
    rescue Nabu::Error => e
      e
    end
  end

  def test_results_arrive_in_input_order_and_equal_the_serial_parse
    adapter = JitterAdapter.new
    list = refs(60)
    pool = Nabu::ParsePool.new(adapter: adapter, workers: 4)
    seen = []
    pool.each(list) { |result| seen << [result.ref, result.value!] }

    assert_equal list, seen.map(&:first), "results are delivered in input order"
    expected = serial(adapter, list)
    seen.map(&:last).zip(expected).each do |got, want|
      assert_equal [want.urn, want.title, want.metadata, want.canonical_path], [got.urn, got.title, got.metadata,
                                                                                got.canonical_path]
      assert_equal want.passages, got.passages, "passages cross the fork as equal value objects"
    end
    assert_equal 4, pool.pids.size
  end

  # A byte budget smaller than any one document still makes progress —
  # one document in flight at a time — and still delivers in order.
  def test_a_starved_byte_budget_still_completes_in_order
    list = refs(30)
    seen = []
    Nabu::ParsePool.new(adapter: JitterAdapter.new, workers: 3, buffer_bytes: 1).each(list) do |result|
      seen << result.value!.urn
    end
    assert_equal list.map(&:id), seen
  end

  def test_parse_exceptions_reraise_at_their_slot_with_their_class
    list = refs(12, 3 => "parse", 7 => "skip")
    outcomes = []
    Nabu::ParsePool.new(adapter: JitterAdapter.new, workers: 3).each(list) do |result|
      outcomes << begin
        result.value!.urn
      rescue Nabu::DocumentSkipped => e
        [:skipped, e.reason, e.message]
      rescue Nabu::ParseError => e
        [:quarantined, e.message]
      end
    end

    assert_equal [:quarantined, "bad urn:nabu:jitter:3"], outcomes[3]
    assert_equal [:skipped, "catalog-only", "rule urn:nabu:jitter:7"], outcomes[7]
    assert_equal "urn:nabu:jitter:11", outcomes[11]
    assert_equal 12, outcomes.size
  end

  def test_an_adapter_bug_aborts_at_its_slot_after_every_earlier_result
    delivered = []
    error = assert_raises(ArgumentError) do
      Nabu::ParsePool.new(adapter: JitterAdapter.new, workers: 3).each(refs(20, 9 => "crash")) do |result|
        delivered << result.value!.urn
      end
    end
    assert_equal "adapter bug at urn:nabu:jitter:9", error.message
    assert_equal Array.new(9) { |n| "urn:nabu:jitter:#{n}" }, delivered,
                 "everything before the failing slot is delivered, nothing after it"
  end

  def test_a_dead_worker_aborts_the_load_honestly_and_every_child_is_reaped
    pool = Nabu::ParsePool.new(adapter: JitterAdapter.new, workers: 3)
    delivered = []
    error = assert_raises(Nabu::ParseWorkerError) do
      pool.each(refs(20, 5 => "die")) { |result| delivered << result.value!.urn }
    end
    assert_match(/urn:nabu:jitter:5/, error.message)
    assert_match(/died/, error.message)
    assert_equal 5, delivered.size
    assert_all_reaped(pool)
  end

  def test_children_are_reaped_after_a_writer_side_abort
    pool = Nabu::ParsePool.new(adapter: JitterAdapter.new, workers: 3)
    assert_raises(Nabu::Error) do
      pool.each(refs(40)) { |result| raise Nabu::Error, "writer failed" if result.ref.id.end_with?(":4") }
    end
    assert_all_reaped(pool)
  end

  def test_children_are_reaped_after_a_clean_run
    pool = Nabu::ParsePool.new(adapter: JitterAdapter.new, workers: 2)
    pool.each(refs(5)) { |result| result }
    assert_all_reaped(pool)
  end

  def test_an_empty_ref_list_forks_nothing
    pool = Nabu::ParsePool.new(adapter: JitterAdapter.new, workers: 4)
    pool.each([]) { flunk "nothing to yield" }
    assert_empty pool.pids
  end

  # Inherited writable SQLite handles: the sqlite3 gem discards them in
  # the child (never closing the parent's file) — the pool forks with its
  # inherited-connection warning silenced, and the parent's handle keeps
  # working afterwards.
  def test_forking_beside_an_open_writable_catalog_is_quiet_and_safe
    Dir.mktmpdir do |dir|
      db = Nabu::Store.connect(File.join(dir, "catalog.sqlite3"))
      db.create_table(:t) { Integer :n }
      db[:t].insert(n: 1)
      _out, err = capture_subprocess_io do
        Nabu::ParsePool.new(adapter: JitterAdapter.new, workers: 2).each(refs(4)) { |result| result }
      end
      refute_match(/inherited from a forked process/, err)
      db[:t].insert(n: 2)
      assert_equal [1, 2], db[:t].order(:n).select_map(:n)
      db.disconnect
    end
  end

  def test_the_writer_side_cost_is_measured
    pool = Nabu::ParsePool.new(adapter: JitterAdapter.new, workers: 2)
    pool.each(refs(10)) { |result| result }
    assert_operator pool.ipc_bytes, :>, 0
    assert_operator pool.decode_seconds, :>=, 0.0
    assert_operator pool.wait_seconds, :>=, 0.0
    assert_operator pool.worker_parse_seconds, :>, 0.0
  end

  def test_default_workers_is_cores_minus_one_capped
    assert_equal 1, Nabu::ParsePool.default_workers(nprocessors: 1)
    assert_equal 1, Nabu::ParsePool.default_workers(nprocessors: 2)
    assert_equal 3, Nabu::ParsePool.default_workers(nprocessors: 4)
    assert_equal Nabu::ParsePool::DEFAULT_CAP, Nabu::ParsePool.default_workers(nprocessors: 64)
  end

  def test_fewer_than_one_worker_is_refused
    assert_raises(ArgumentError) { Nabu::ParsePool.new(adapter: JitterAdapter.new, workers: 0) }
  end

  private

  def assert_all_reaped(pool)
    refute_empty pool.pids
    pool.pids.each do |pid|
      assert_raises(Errno::ECHILD, "worker #{pid} must already be reaped") { Process.waitpid(pid, Process::WNOHANG) }
    end
  end
end
