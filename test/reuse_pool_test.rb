# frozen_string_literal: true

require "test_helper"

# Nabu::ReusePool — the reuse engine's in-order fork map. The serial path
# (workers ≤ 1) is the reference; the forked path must deliver the same
# results in the same order, carry per-worker finals, and fail loudly.
class ReusePoolTest < Minitest::Test
  def pool(workers, work: ->(state, task) { [state[:index], task * task] })
    Nabu::ReusePool.new(workers: workers, setup: ->(index) { { index: index, seen: 0 } },
                        work: lambda { |state, task|
                          state[:seen] += 1
                          work.call(state, task)
                        },
                        finish: ->(state) { state[:seen] })
  end

  def test_serial_and_forked_deliver_identical_results_in_task_order
    serial = []
    finals = pool(1).map(1..20) { |result| serial << result.last }
    assert_equal (1..20).map { |n| n * n }, serial
    assert_equal [20], finals

    forked = []
    workers = []
    finals = pool(3).map(1..20) do |result|
      workers << result.first
      forked << result.last
    end
    assert_equal serial, forked, "delivery is in task order whatever the finishing order"
    assert_equal 20, finals.sum, "every task ran exactly once across the workers"
    assert_equal 3, finals.size
    assert_operator workers.uniq.size, :>, 1, "tasks really spread across workers"
  end

  def test_large_payloads_cross_without_deadlock
    big = "x" * 300_000
    out = []
    pool(2, work: ->(_state, task) { task + big }).map(Array.new(6) { big }) { |result| out << result.bytesize }
    assert_equal [600_000] * 6, out
  end

  def test_a_worker_exception_raises_at_its_slot
    delivered = []
    error = assert_raises(Nabu::ReusePool::WorkerError) do
      pool(2, work: ->(_state, task) { task == 5 ? raise(ArgumentError, "bad five") : task })
        .map(1..9) { |result| delivered << result }
    end
    assert_match(/ArgumentError: bad five/, error.message)
    assert_equal [1, 2, 3, 4], delivered.first(4), "every earlier slot was delivered first"
    refute_includes delivered, 5
  end

  def test_a_dying_worker_raises
    assert_raises(Nabu::ReusePool::WorkerError) do
      pool(2, work: ->(_state, task) { task == 3 ? exit!(3) : task }).map(1..6) { |_result| nil }
    end
  end
end
