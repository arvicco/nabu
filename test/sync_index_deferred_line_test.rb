# frozen_string_literal: true

require "test_helper"

# The index_policy: deferred sync line (P168). A deferred source's sync
# loads its documents and skips the index (Outcome#indexed == :deferred);
# every sync report path renders through CLI#format_sync_outcome, so the
# deferral — and the command that pays it — rides each one, prominently.
class SyncIndexDeferredLineTest < Minitest::Test
  def outcome(indexed:)
    report = Nabu::Store::LoadReport.new(added: 616, updated: 0, skipped: 0, withdrawn: 0,
                                         errored: 0, skipped_by_rule: 0)
    Nabu::SyncRunner::Outcome.new(slug: "ndl-kotenseki", fetch_report: nil, load_report: report,
                                  breaker: nil, indexed: indexed, warnings: [], discovery: nil)
  end

  def cli = Nabu::CLI.new

  def test_deferred_sync_line_names_the_refresh_command
    line = cli.send(:format_sync_outcome, outcome(indexed: :deferred))
    assert_match(%r{  index DEFERRED — run bin/nabu index refresh ndl-kotenseki}, line)
    refute_match(/indexed \d+ passages/, line)
  end

  def test_sync_all_path_renders_the_same_fragment
    line = cli.send(:sync_all_line, "ndl-kotenseki", outcome(indexed: :deferred))
    assert_match(/index DEFERRED/, line)
  end

  def test_inline_counts_render_unchanged
    assert_match(/  indexed 12 passages \(ndl-kotenseki\)/, cli.send(:format_sync_outcome, outcome(indexed: 12)))
    refute_match(/index/, cli.send(:format_sync_outcome, outcome(indexed: nil)))
  end
end
