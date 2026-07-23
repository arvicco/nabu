# frozen_string_literal: true

require "test_helper"

# GrantGate (P42-r1): the fetch-grant gate's POLICY and ledger record. The
# interactive IO lives in the CLI (exercised in cli_test); here we prove the
# acknowledgment record (idempotent, table-guarded), the blocked? predicate,
# the answer check, and the pure notice/skip/abort text.
class GrantGateTest < Minitest::Test
  include StoreTestDB

  def setup
    @ledger = ledger_test_db
  end

  def grant_entry(slug: "starling", grant_required: true)
    Nabu::SourceRegistry::Entry.new(
      slug: slug, adapter_class_name: "TestAdapter", enabled: true, sync_policy: "manual",
      grant_required: grant_required, grant: (grant_required ? sample_grant : nil)
    )
  end

  def sample_grant
    Nabu::SourceRegistry::Grant.new(
      grantor: "G. Starostin", date: "2026-07-15", terms: "any use, per-base attribution required",
      thread: "№1", request_hint: "write to George Starostin for your own grant"
    )
  end

  def test_unacknowledged_source_is_blocked
    gate = Nabu::GrantGate.new(ledger: @ledger)
    assert gate.blocked?(grant_entry)
    refute gate.acknowledged?("starling")
  end

  def test_a_non_grant_source_is_never_blocked
    gate = Nabu::GrantGate.new(ledger: @ledger)
    refute gate.blocked?(grant_entry(grant_required: false))
  end

  def test_record_then_acknowledged_and_no_longer_blocked
    gate = Nabu::GrantGate.new(ledger: @ledger)
    gate.record!(slug: "starling", terms: "any use, per-base attribution required", how: "typed")
    assert gate.acknowledged?("starling")
    refute gate.blocked?(grant_entry)
    row = @ledger[:grant_acknowledgments].where(source_slug: "starling").first
    assert_equal "typed", row[:how]
    assert_equal "any use, per-base attribution required", row[:terms]
  end

  def test_record_is_idempotent
    gate = Nabu::GrantGate.new(ledger: @ledger)
    gate.record!(slug: "starling", terms: "t", how: "typed")
    gate.record!(slug: "starling", terms: "t", how: "flag")
    assert_equal 1, @ledger[:grant_acknowledgments].where(source_slug: "starling").count,
                 "a second record! is a no-op — re-syncing never appends"
  end

  def test_acknowledged_answer_is_the_typed_word_case_insensitive
    assert Nabu::GrantGate.acknowledged_answer?("granted\n")
    assert Nabu::GrantGate.acknowledged_answer?("  GRANTED ")
    refute Nabu::GrantGate.acknowledged_answer?("y")
    refute Nabu::GrantGate.acknowledged_answer?("")
    refute Nabu::GrantGate.acknowledged_answer?(nil)
  end

  def test_notice_carries_terms_criterion_and_request_scaffold
    notice = Nabu::GrantGate.notice(grant_entry)
    assert_match(/any use, per-base attribution required/, notice, "terms verbatim")
    assert_match(/granted personally to the project author — you need your own/, notice, "the criterion")
    assert_match(/write to George Starostin/, notice, "the request scaffold")
    assert_match(/G\. Starostin, 2026-07-15/, notice)
  end

  def test_abort_message_includes_the_scaffold_pointer
    msg = Nabu::GrantGate.abort_message(grant_entry)
    assert_match(/write to George Starostin/, msg, "the on-ramp, not a bare wall")
    assert_match(/--grant-acknowledged/, msg)
    assert_match(/Nothing was fetched/, msg)
  end

  def test_skip_line_points_at_the_review_command
    assert_equal "skipped (grant required): starling — run `nabu sync starling` to review the terms",
                 Nabu::GrantGate.skip_line("starling")
  end

  def test_a_ledger_without_the_table_reads_as_unacknowledged
    bare = Nabu::Store::Ledger.connect("sqlite::memory:") # no migrations → no table
    gate = Nabu::GrantGate.new(ledger: bare)
    refute gate.acknowledged?("starling"), "a pre-P42 ledger reads as un-acknowledged, never raises"
  ensure
    bare&.disconnect
  end
end
