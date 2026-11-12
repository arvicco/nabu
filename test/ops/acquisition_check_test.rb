# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "nabu/ops/acquisition_check"

# The acquisition segment's machine check (the P169–P171 rail-slice
# omission class): the CURRENT phase plan doc must carry its alternating
# segment (odd = acquisition, even = outreach) or an explicit
# carries-none justification, and no rail source may sit untouched since
# before the previous phase's merge.
class AcquisitionCheckTest < Minitest::Test
  MERGED_ROWS = <<~REG
    # Phase register

    ## P172 · Something
    **Time: 1h, PR #218 merged 2026-11-20.**

    ## P171 · Something else
    **Time: 4h, PR #217 merged 2026-11-12.**
  REG

  def with_board(plan_name:, plan_text:, register: MERGED_ROWS)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, plan_name), plan_text)
      File.write(File.join(dir, "phase-register.md"), register)
      adapters = File.join(dir, "adapters")
      FileUtils.mkdir_p(adapters)
      File.write(File.join(adapters, "wellcome.rb"),
                 "ZIP = Spec.new(schedule: Nabu::PacedCrawl::Schedule.new(cadence: :per_phase))\n")
      ledger = File.join(dir, "history.sqlite3")
      db = Sequel.sqlite(ledger)
      db.create_table(:runs) do
        primary_key :id
        String :source_slug
        Time :started_at
        String :status
      end
      yield dir, adapters, ledger, db
    end
  end

  def check(dir, adapters, ledger)
    Nabu::Ops::AcquisitionCheck.new(boards_dir: dir, adapters_dir: adapters, ledger_path: ledger).run
  end

  def test_an_odd_phase_plan_without_an_acquisition_segment_flags
    with_board(plan_name: "p173-plan.md", plan_text: "# P173\nPackets only.\n") do |dir, adapters, ledger, db|
      db[:runs].insert(source_slug: "wellcome", started_at: Time.now, status: "succeeded")
      report = check(dir, adapters, ledger)

      refute_predicate report, :clean?
      assert_match(/p173-plan\.md.*acquisition segment/i, report.findings.join("\n"))
    end
  end

  def test_a_justified_empty_passes_and_an_even_phase_wants_outreach
    odd = "# P173\nThis phase carries no acquisition segment: the rail is cone-complete and no scout fits.\n"
    with_board(plan_name: "p173-plan.md", plan_text: odd) do |dir, adapters, ledger, db|
      db[:runs].insert(source_slug: "wellcome", started_at: Time.now, status: "succeeded")
      assert_predicate check(dir, adapters, ledger), :clean?
    end

    with_board(plan_name: "p174-plan.md", plan_text: "# P174\nNo segments here.\n") do |dir, adapters, ledger, db|
      db[:runs].insert(source_slug: "wellcome", started_at: Time.now, status: "succeeded")
      report = check(dir, adapters, ledger)

      refute_predicate report, :clean?
      assert_match(/outreach segment/i, report.findings.join("\n"))
    end
  end

  def test_a_rail_source_untouched_since_before_the_previous_merge_flags
    plan = "# P173\nAcquisition segment: slices below.\n"
    with_board(plan_name: "p173-plan.md", plan_text: plan) do |dir, adapters, ledger, db|
      db[:runs].insert(source_slug: "wellcome", started_at: Time.utc(2026, 11, 1), status: "succeeded")
      report = check(dir, adapters, ledger)

      refute_predicate report, :clean?
      assert_match(/wellcome.*2026-11-01.*owes/i, report.findings.join("\n"))
    end
  end

  def test_missing_boards_or_ledger_skip_cleanly
    Dir.mktmpdir do |dir|
      report = Nabu::Ops::AcquisitionCheck.new(boards_dir: File.join(dir, "none"),
                                               adapters_dir: dir, ledger_path: File.join(dir, "no.sqlite3")).run

      assert_predicate report, :skipped
      assert_predicate report, :clean?
    end
  end
end
