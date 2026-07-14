# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

# ReviewHook (P18-7): the JSON brief's shape and the subprocess boundary's
# non-fatality. The "hook" here is a stub shell command — no network, no AI,
# exactly the tool-agnostic contract.
class ReviewHookTest < Minitest::Test
  include StoreTestDB

  def setup
    @ledger = ledger_test_db
    @db = store_test_db
  end

  # -- the brief ---------------------------------------------------------------

  def test_brief_shape_carries_counts_quarantine_discovery_and_samples
    outcome = seed_synced_outcome
    brief = Nabu::ReviewHook.brief(outcome: outcome, db: @db, ledger: @ledger)

    assert_equal "nabu.sync-review/1", brief[:schema]
    assert_equal "corpus", brief[:source]
    assert_equal "abc123", brief[:fetched_sha]
    assert_equal({ added: 2, updated: 0, skipped: 0, withdrawn: 0, errored: 1, indexed: 2 },
                 brief[:counts])
    assert_equal({ errored: 1, baseline: 1, anchor: 1 }, brief[:quarantine])
    assert_equal({ skipped_by_rule: 3, unrecognized: 1, notes: ["one gap"] }, brief[:discovery])
    assert_equal ["quarantined 1 — baseline recorded; future runs warn on change only"], brief[:warnings]
    assert_equal %w[urn:t:corpus:2:p urn:t:corpus:1:p], brief[:sample_urns],
                 "fresh (provenance-journaled) passages, most recent first"
    JSON.generate(brief) # must be serializable as-is
  end

  def test_brief_quarantine_degrades_on_a_pre_005_ledger
    @ledger.drop_table(:quarantine_baselines)
    brief = Nabu::ReviewHook.brief(outcome: seed_synced_outcome(record_baseline: false),
                                   db: @db, ledger: @ledger)
    assert_equal({ errored: 1, baseline: nil, anchor: nil }, brief[:quarantine])
  end

  # -- the subprocess boundary --------------------------------------------------

  def test_run_pipes_the_brief_to_stdin_and_reports_exit_zero
    Dir.mktmpdir("nabu-hook") do |dir|
      sink = File.join(dir, "received.json")
      result = Nabu::ReviewHook.run(command: "cat > #{sink} && echo reviewed", brief: { schema: "x", n: 1 })

      assert_predicate result, :ok?
      assert_equal 0, result.status
      assert_equal "reviewed\n", result.output
      assert_equal({ "schema" => "x", "n" => 1 }, JSON.parse(File.read(sink)))
    end
  end

  # The hook's failure is REPORTED, never raised — the caller decides what to
  # print; nothing here can fail a sync.
  def test_run_reports_a_nonzero_exit_honestly_without_raising
    result = Nabu::ReviewHook.run(command: "cat >/dev/null; echo boom >&2; exit 3", brief: {})
    refute_predicate result, :ok?
    assert_equal 3, result.status
    assert_match(/boom/, result.output)
  end

  def test_run_survives_an_unstartable_command
    result = Nabu::ReviewHook.run(command: "/definitely/not/a/command-#{object_id}", brief: {})
    refute_predicate result, :ok?
    # Depending on shell involvement this is a spawn failure (status nil) or a
    # shell 127 — either way: reported, not raised.
    assert(result.status.nil? || result.status == 127)
  end

  private

  # A source with two loaded documents (provenance-journaled), a recorded
  # baseline, and a plausible sync Outcome around them.
  def seed_synced_outcome(record_baseline: true)
    source_id = @db[:sources].insert(slug: "corpus", name: "c", adapter_class: "X",
                                     license_class: "open", enabled: true)
    [1, 2].each do |i|
      doc_id = @db[:documents].insert(source_id: source_id, urn: "urn:t:corpus:#{i}",
                                      content_sha256: "x", withdrawn: false)
      @db[:passages].insert(document_id: doc_id, urn: "urn:t:corpus:#{i}:p", sequence: 0,
                            language: "grc", text: "α", text_normalized: "α",
                            content_sha256: "x", withdrawn: false)
      @db[:provenance].insert(document_id: doc_id, event: "loaded", at: Time.now + i)
    end
    Nabu::Health::QuarantineBaseline.record!(@ledger, "corpus", errored: 1) if record_baseline

    report = Nabu::Store::LoadReport.new(added: 2, updated: 0, skipped: 0, withdrawn: 0,
                                         errored: 1, skipped_by_rule: 0)
    Nabu::SyncRunner::Outcome.new(
      slug: "corpus",
      fetch_report: Nabu::FetchReport.new(sha: "abc123", fetched_at: Time.now, notes: nil),
      load_report: report, breaker: nil, indexed: 2,
      warnings: [Nabu::Health::TrendRules.quarantine_delta(errored: 1, baseline: nil)].compact,
      discovery: Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: 3, unrecognized: 1, notes: ["one gap"])
    )
  end
end
