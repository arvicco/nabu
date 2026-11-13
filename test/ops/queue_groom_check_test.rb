# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nabu/ops/queue_groom_check"

# The ship-time write-back machine half (the №I-49 class: two gates
# shipped queue items with zero queue write-back and a slate ranked
# against the stale board). The probe cross-checks the NEWEST
# phase-register row's named Q-ids against the work queue: a named id
# whose queue row carries no stamp dated at or after that row's merge
# date is presumed stale until groomed. The output line carries the
# queue row count + newest groom date so an ungroomed slate is visible
# in its own transcript.
class QueueGroomCheckTest < Minitest::Test
  REGISTER = <<~REG
    # Phase register

    ## P172 · The wave
    **Time: ~27h, PR #218 merged 2026-11-13.**
    - Q387 grant shape shipped whole; Q385 rode as a rider.

    ## P171 · Earlier
    **Time: 4h, PR #217 merged 2026-11-12.**
    - Q359's wave shipped.
  REG

  def with_board(queue:, register: REGISTER)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "phase-register.md"), register)
      File.write(File.join(dir, "work-queue.md"), queue)
      yield Nabu::Ops::QueueGroomCheck.new(boards_dir: dir).run
    end
  end

  def test_a_named_id_with_an_unstamped_queue_row_flags_as_stale
    queue = <<~Q
      # The work queue

      ## Q387 · Grant-provenance excision  [minted 2026-11-12 from the ruled privacy extension]
      Body still reads all-future.

      ## Q100 · Unrelated open work  [minted 2026-09-01]
      Untouched by the phase; never flags.
    Q
    with_board(queue: queue) do |report|
      refute_predicate report, :clean?
      assert_equal 1, report.findings.size
      assert_match(/Q387/, report.findings.first)
      assert_match(/2026-11-13/, report.findings.first, "the finding names the merge date the stamp must reach")
      refute_match(/Q100/, report.findings.join)
    end
  end

  def test_a_groomed_row_and_a_removed_row_both_pass
    queue = <<~Q
      # The work queue

      ## Executed post-P172 groom (2026-11-13)

      Q385 removed.

      ## Q387 · Grant-provenance excision  [MACHINERY SHIPPED P172 2026-11-13; minted 2026-11-12]
      Trimmed to the live remainder.
    Q
    with_board(queue: queue) do |report|
      assert_predicate report, :clean?, report.findings.join("\n")
    end
  end

  def test_the_summary_carries_row_count_and_newest_groom_date
    queue = <<~Q
      # The work queue

      ## Executed post-P172 groom (2026-11-13)

      ## Executed P170 groom (2026-11-12)

      ## Q387 · Row  [stamped 2026-11-13]
      Live.

      ## Q100 · Row  [minted 2026-09-01]
      Live.
    Q
    with_board(queue: queue) do |report|
      assert_equal 2, report.rows
      assert_equal Date.new(2026, 11, 13), report.newest_groom
      assert_match(/2 rows/, report.summary)
      assert_match(/2026-11-13/, report.summary)
    end
  end

  def test_a_register_without_a_dated_newest_row_skips_the_probe
    register = "# Phase register\n\n## P1 · Young\nNo merge stamp yet.\n"
    with_board(queue: "# Queue\n\n## Q387 · Row  [minted 2026-11-12]\nBody.\n", register: register) do |report|
      assert_predicate report, :clean?
    end
  end

  def test_missing_boards_dir_skips_cleanly
    report = Nabu::Ops::QueueGroomCheck.new(boards_dir: "/nonexistent-boards").run
    assert report.skipped
    assert_empty report.findings
  end
end
