# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nabu/ops/embed_staleness_check"

# The embed-staleness probe (`rake boards:check`, informational): the
# vectors file is maintained only by owner-fired `nabu embed` runs, so it
# can lag the library indefinitely with nothing saying so. The probe holds
# the newest embed stamp (embed_meta.updated_at) against the newest source
# addition (each source's first succeeded run in the ledger — the ledger,
# not the catalog, because a rebuild re-mints every catalog timestamp) and
# prints one honest line when the gap exceeds the threshold.
class EmbedStalenessCheckTest < Minitest::Test
  CHECK = Nabu::Ops::EmbedStalenessCheck

  def with_setup(stamps: [], runs: [], vectors: true, ledger: true, embed_slugs: %w[core])
    Dir.mktmpdir do |dir|
      vectors_path = File.join(dir, "vectors.sqlite3")
      ledger_path = File.join(dir, "history.sqlite3")
      seed_vectors(vectors_path, stamps) if vectors
      seed_ledger(ledger_path, runs) if ledger
      yield CHECK.new(vectors_path: vectors_path, ledger_path: ledger_path, embed_slugs: embed_slugs)
    end
  end

  def seed_vectors(path, stamps)
    db = Sequel.connect("sqlite://#{path}")
    Nabu::Embed.ensure_schema!(db)
    stamps.each_with_index do |stamp, i|
      db[Nabu::Embed::META_TABLE].insert(model: "model-#{i}", dim: 4, encoding: "i8", worker_version: "t",
                                         updated_at: stamp)
    end
  ensure
    db&.disconnect
  end

  def seed_ledger(path, runs)
    db = Sequel.connect("sqlite://#{path}")
    db.create_table(:runs) do
      primary_key :id
      String :source_slug
      DateTime :started_at
      String :status
    end
    runs.each do |slug, started, status|
      db[:runs].insert(source_slug: slug, started_at: Time.parse(started).localtime, status: status || "succeeded")
    end
  ensure
    db&.disconnect
  end

  def test_sources_added_past_the_threshold_produce_one_named_finding
    runs = [["core", "2026-08-01T12:00:00Z"], ["newer", "2026-10-01T12:00:00Z"],
            ["newest", "2026-11-20T12:00:00Z"], ["newest", "2026-11-21T12:00:00Z"],
            ["core", "2026-11-22T12:00:00Z"]] # a re-sync is not an addition
    with_setup(stamps: %w[2026-09-01T12:00:00Z 2026-09-04T12:00:00Z], runs: runs) do |check|
      report = check.run
      refute report.skipped
      refute report.clean?
      assert_match(/newest embed stamp 2026-09-04/, report.finding)
      assert_match(/2 source\(s\) first synced since/, report.finding)
      assert_match(/newest: newest 2026-11-20, 77 days later/, report.finding)
      assert_match(/0 of them embed-flagged/, report.finding)
    end
  end

  def test_additions_inside_the_threshold_are_clean
    runs = [["core", "2026-08-01T12:00:00Z"], ["fresh", "2026-09-08T12:00:00Z"]]
    with_setup(stamps: %w[2026-09-04T12:00:00Z], runs: runs) do |check|
      report = check.run
      assert report.clean?
      assert_equal Date.new(2026, 9, 4), report.stamp.to_date
      assert_equal "fresh", report.newest_slug
    end
  end

  def test_failed_first_runs_are_not_additions
    runs = [["core", "2026-08-01T12:00:00Z"], ["broken", "2026-11-01T12:00:00Z", "failed"]]
    with_setup(stamps: %w[2026-09-04T12:00:00Z], runs: runs) do |check|
      assert check.run.clean?
    end
  end

  def test_an_embed_flagged_addition_is_counted
    runs = [["core", "2026-11-01T12:00:00Z"]]
    with_setup(stamps: %w[2026-09-04T12:00:00Z], runs: runs) do |check|
      assert_match(/1 of them embed-flagged/, check.run.finding)
    end
  end

  def test_skips_without_a_vectors_file_a_stamp_or_a_ledger
    with_setup(vectors: false) { |check| assert_match(/no vectors/, check.run.skip_reason) }
    with_setup(stamps: []) { |check| assert_match(/no embed stamp/, check.run.skip_reason) }
    with_setup(stamps: %w[2026-09-04T12:00:00Z], ledger: false) do |check|
      report = check.run
      assert report.skipped
      assert report.clean?
      assert_match(/no ledger/, report.skip_reason)
    end
  end
end
