# frozen_string_literal: true

require "test_helper"

# The sync summary line for a kind: module row: a module holds zero
# documents by invariant, so the document counters ("+0 added ~0 updated
# =0 skipped …") are suppressed and the line reports what moved — the ref,
# the changed files, and the seam census delta where the seam has one.
# Every sync report path (single, list, --all, quickstart sweeps) renders
# through CLI#format_sync_outcome, so this file pins the line there. The
# non-module line is pinned byte-for-byte: this is a rendering branch, not
# a reshaping of the ordinary report.
class SyncModuleLineTest < Minitest::Test
  OLD = "1111111111111111111111111111111111111111"
  NEW = "2222222222222222222222222222222222222222"

  def cli = Nabu::CLI.new

  def line(outcome) = cli.send(:format_sync_outcome, outcome)

  def zero_report
    Nabu::Store::LoadReport.new(added: 0, updated: 0, skipped: 0, withdrawn: 0, errored: 0, skipped_by_rule: 0)
  end

  def outcome(slug:, delta:, fetch_sha: NEW, report: zero_report)
    fetch = fetch_sha && Nabu::FetchReport.new(sha: fetch_sha, fetched_at: Time.now)
    Nabu::SyncRunner::Outcome.new(slug: slug, fetch_report: fetch, load_report: report, breaker: nil,
                                  indexed: nil, warnings: [], discovery: nil, module_delta: delta)
  end

  def delta(before:, after:, fetched: true, changed: nil, census: nil, previous: nil)
    Nabu::ModuleCensus::Delta.new(before: before, after: after, fetched: fetched, changed: changed,
                                  census: census, previous_census: previous)
  end

  def lects(anchors:, varieties:)
    [["anchors", anchors], ["stages", 125], ["varieties", varieties], ["codemap rows", 157]]
      .map { |label, count| Nabu::ModuleCensus::Count.new(label: label, count: count) }
  end

  def test_a_moved_nabu_lects_pull_reports_ref_files_and_census_delta
    moved = delta(before: OLD, after: NEW, changed: %w[CHANGELOG.md codemap.yml lects.yml],
                  census: lects(anchors: 248, varieties: 32), previous: lects(anchors: 246, varieties: 27))
    assert_equal "nabu-lects               111111111111..222222222222  3 files changed: CHANGELOG.md, " \
                 "codemap.yml, lects.yml  248 anchors (+2) · 125 stages · 32 varieties (+5) · 157 codemap rows",
                 line(outcome(slug: "nabu-lects", delta: moved))
  end

  def test_an_unchanged_module_says_so_with_its_census
    same = delta(before: NEW, after: NEW, census: lects(anchors: 246, varieties: 27))
    assert_equal "nabu-lects               unchanged at 222222222222  " \
                 "246 anchors · 125 stages · 27 varieties · 157 codemap rows",
                 line(outcome(slug: "nabu-lects", delta: same))
  end

  def test_a_census_less_module_falls_back_to_the_changed_files_honestly
    moved = delta(before: OLD, after: NEW, changed: ["places.yml"])
    assert_equal "nabu-places              111111111111..222222222222  1 file changed: places.yml",
                 line(outcome(slug: "nabu-places", delta: moved))
    same = delta(before: NEW, after: NEW)
    assert_equal "nabu-places              unchanged at 222222222222", line(outcome(slug: "nabu-places", delta: same))
  end

  def test_the_document_counters_never_print_for_a_module
    text = line(outcome(slug: "ucd", delta: delta(before: OLD, after: NEW)))
    refute_match(/added|updated|skipped|withdrawn|errored/, text)
  end

  def test_long_changed_lists_are_capped_with_an_honest_count
    files = (1..8).map { |i| "f#{i}.yml" }
    text = line(outcome(slug: "nabu-data", delta: delta(before: OLD, after: NEW, changed: files)))
    assert_match(/8 files changed: f1\.yml, f2\.yml, f3\.yml, f4\.yml, f5\.yml \+3 more\z/, text)
  end

  def test_fresh_clone_parse_only_and_sha_less_fetches
    cloned = delta(before: nil, after: NEW, census: lects(anchors: 246, varieties: 27))
    assert_match(/\Anabu-lects\s+cloned at 222222222222  246 anchors/, line(outcome(slug: "nabu-lects", delta: cloned)))
    parse_only = delta(before: NEW, after: nil, fetched: false)
    assert_equal "kr-gaiji                 parse-only at 222222222222",
                 line(outcome(slug: "kr-gaiji", delta: parse_only, fetch_sha: nil))
    sha_less = delta(before: nil, after: nil)
    assert_equal "trismegistos             fetched",
                 line(outcome(slug: "trismegistos", delta: sha_less, fetch_sha: nil))
  end

  def test_a_fetch_only_module_renders_the_module_line_too
    same = delta(before: NEW, after: NEW)
    assert_equal "nabu-places              unchanged at 222222222222",
                 line(outcome(slug: "nabu-places", delta: same, report: nil))
  end

  def test_the_non_module_line_is_byte_identical
    report = Nabu::Store::LoadReport.new(added: 3, updated: 1, skipped: 9, withdrawn: 2, errored: 1,
                                         skipped_by_rule: 0)
    assert_equal "perseus                  222222222222  +3 added  ~1 updated  =9 skipped  -2 withdrawn  !1 errored",
                 line(outcome(slug: "perseus", delta: nil, report: report))
    assert_equal "perseus                  222222222222  parse+load deferred (fetch-only)",
                 line(outcome(slug: "perseus", delta: nil, report: nil))
    assert_equal "perseus                  parse-only  +0 added  ~0 updated  =0 skipped  -0 withdrawn  !0 errored",
                 line(outcome(slug: "perseus", delta: nil, fetch_sha: nil))
  end

  def test_discovery_accounting_stays_silent_for_a_module
    module_outcome = outcome(slug: "nabu-lects", delta: delta(before: NEW, after: NEW))
    module_outcome = module_outcome.with(discovery: Nabu::Adapter::DiscoverySkips.new)
    out, = capture_io { cli.send(:print_discovery_accounting, module_outcome) }
    assert_empty out
    source_outcome = module_outcome.with(module_delta: nil)
    out, = capture_io { cli.send(:print_discovery_accounting, source_outcome) }
    assert_match(/discovery: 0 selected/, out, "non-module accounting unchanged")
  end

  def test_the_sync_all_path_renders_the_module_line
    same = delta(before: NEW, after: NEW)
    assert_equal "nabu-places              unchanged at 222222222222",
                 cli.send(:sync_all_line, "nabu-places", outcome(slug: "nabu-places", delta: same))
  end
end
