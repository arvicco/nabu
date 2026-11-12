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

  def grant_entry(slug: "starling", grant_required: true, grant: sample_grant)
    Nabu::SourceRegistry::Entry.new(
      slug: slug, adapter_class_name: "TestAdapter", wired: true, sync_policy: "manual",
      grant_required: grant_required, grant: (grant_required ? grant : nil)
    )
  end

  # The PUBLIC grant (what config/sources.yml carries on every clone).
  def sample_grant
    Nabu::SourceRegistry::Grant.new(
      terms: "any use, per-base attribution required",
      request_hint: "contact the source (example.org) for a license grant"
    )
  end

  # The same grant with this box's instance provenance merged in.
  def provenanced_grant
    sample_grant.with(grantor: "A. Grantor", date: "2026-01-02", thread: "a written grant")
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

  # A public clone (no provenance file): terms, the criterion and the
  # on-ramp — and NO provenance line at all.
  def test_notice_carries_terms_criterion_and_request_scaffold
    notice = Nabu::GrantGate.notice(grant_entry)
    assert_match(/any use, per-base attribution required/, notice, "terms verbatim")
    assert_match(/not conveyed by a public license — you need your own grant/, notice, "the criterion")
    assert_match(/request your own: contact the source/, notice, "the request scaffold")
    refute_match(/on this box/, notice, "no provenance line without the instance file")
    assert_equal 4, notice.lines.size
  end

  # The owner's box (provenance file present): one extra line, after terms.
  def test_notice_renders_the_provenance_line_only_when_the_box_holds_it
    notice = Nabu::GrantGate.notice(grant_entry(grant: provenanced_grant))
    assert_match(/^  on this box: granted by A\. Grantor, 2026-01-02 · a written grant$/, notice)
    assert_equal 5, notice.lines.size
  end

  def test_a_partial_provenance_row_renders_what_it_has
    partial = sample_grant.with(grantor: "A. Grantor")
    assert_match(/^  on this box: granted by A\. Grantor$/, Nabu::GrantGate.notice(grant_entry(grant: partial)))
  end

  def test_abort_message_includes_the_scaffold_pointer
    msg = Nabu::GrantGate.abort_message(grant_entry)
    assert_match(/contact the source/, msg, "the on-ramp, not a bare wall")
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
