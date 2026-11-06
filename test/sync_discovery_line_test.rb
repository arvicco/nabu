# frozen_string_literal: true

require "test_helper"

# The sync epilogue's discovery accounting line. Its not-ingested bucket
# once folded three different fates into one "unrecognized" count — files
# the adapter raised ParseError on (quarantined as damage), documents
# rejected keep-first by the within-pass collision guard, and files that
# matched no content pattern at all — so an operator could not tell from
# the line whether a sync left true quarantines behind. Each fate now reads
# as its own bucket; any of them positive still renders the line loudly.
class SyncDiscoveryLineTest < Minitest::Test
  def cli = Nabu::CLI.new

  def outcome(errored: 0, collided: 0, unrecognized: 0, skipped_by_rule: 0)
    report = Nabu::Store::LoadReport.new(added: 4, updated: 1, skipped: 2, withdrawn: 0, errored: errored,
                                         skipped_by_rule: 1, collided: collided)
    discovery = Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped_by_rule, unrecognized: unrecognized)
    Nabu::SyncRunner::Outcome.new(slug: "perseus", fetch_report: nil, load_report: report, breaker: nil,
                                  indexed: nil, warnings: [], discovery: discovery, module_delta: nil)
  end

  def discovery_line(outcome)
    out, = capture_io { cli.send(:print_discovery_accounting, outcome) }
    out.lines.first.to_s.strip
  end

  def test_a_clean_sync_reads_zero_quarantined_and_zero_unrecognized
    assert_equal "discovery: 7 selected · 1 skipped-by-rule · 0 quarantined · 0 unrecognized",
                 discovery_line(outcome)
  end

  def test_quarantined_documents_are_their_own_bucket
    assert_equal "discovery: 7 selected · 3 skipped-by-rule · 2 quarantined · 0 unrecognized",
                 discovery_line(outcome(errored: 2, skipped_by_rule: 2))
  end

  def test_unrecognized_counts_only_pattern_misses
    assert_equal "discovery: 7 selected · 1 skipped-by-rule · 0 quarantined · 5 unrecognized",
                 discovery_line(outcome(unrecognized: 5))
  end

  def test_collided_documents_appear_as_their_own_bucket_only_when_present
    assert_equal "discovery: 7 selected · 1 skipped-by-rule · 1 quarantined · 2 unrecognized · 3 collided",
                 discovery_line(outcome(errored: 1, unrecognized: 2, collided: 3))
  end

  def test_any_not_ingested_bucket_renders_the_line_loudly
    loud = []
    probe = cli
    probe.define_singleton_method(:say) { |_text, color = nil| loud << color }
    probe.send(:print_discovery_accounting, outcome)
    probe.send(:print_discovery_accounting, outcome(errored: 1))
    probe.send(:print_discovery_accounting, outcome(collided: 1))
    probe.send(:print_discovery_accounting, outcome(unrecognized: 1))
    assert_equal [nil, :yellow, :yellow, :yellow], loud
  end
end
