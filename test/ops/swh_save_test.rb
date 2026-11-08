# frozen_string_literal: true

require_relative "../test_helper"
require "nabu/ops/swh_save"

# The Software Heritage save round (`rake outreach:swh`): one owner-fired
# command that asks SWH to archive every family repo and reads back the
# snapshot SWHIDs already on record. The HTTP seam is injected — no
# network in tests, ever.
class SwhSaveTest < Minitest::Test
  def client(responses)
    lambda do |method, url|
      key = [method, url]
      raise "unexpected #{method} #{url}" unless responses.key?(key)

      responses[key]
    end
  end

  def save_url(repo)
    "https://archive.softwareheritage.org/api/1/origin/save/git/url/https://github.com/arvicco/#{repo}/"
  end

  def visit_url(repo)
    "https://archive.softwareheritage.org/api/1/origin/https://github.com/arvicco/#{repo}/visit/latest/" \
      "?require_snapshot=true"
  end

  def test_accepted_save_and_recorded_snapshot_report_cleanly
    runner = Nabu::Ops::SwhSave.new(
      repos: ["nabu"],
      http: client({
                     ["POST", save_url("nabu")] => '{"save_request_status":"accepted","save_task_status":"pending"}',
                     ["GET", visit_url("nabu")] => '{"snapshot":"abc123","date":"2026-11-01T00:00:00+00:00"}'
                   })
    )
    report = runner.run
    row = report.rows.fetch(0)
    assert_equal "accepted", row.request_status
    assert_equal "swh:1:snp:abc123", row.snapshot_swhid
    assert_predicate report, :clean?
  end

  def test_rejected_save_is_a_finding
    runner = Nabu::Ops::SwhSave.new(
      repos: ["nabu"],
      http: client({
                     ["POST", save_url("nabu")] => '{"save_request_status":"rejected","note":"blocklisted"}',
                     ["GET", visit_url("nabu")] => Nabu::Ops::SwhSave::NOT_FOUND
                   })
    )
    report = runner.run
    refute_predicate report, :clean?
    assert_match(/rejected/, report.findings.join)
    assert_nil report.rows.fetch(0).snapshot_swhid
  end

  def test_no_visit_yet_is_not_a_finding
    runner = Nabu::Ops::SwhSave.new(
      repos: ["nabu"],
      http: client({
                     ["POST", save_url("nabu")] => '{"save_request_status":"accepted"}',
                     ["GET", visit_url("nabu")] => Nabu::Ops::SwhSave::NOT_FOUND
                   })
    )
    report = runner.run
    assert_predicate report, :clean?
    assert_nil report.rows.fetch(0).snapshot_swhid
  end

  def test_default_repos_cover_the_family
    assert_includes Nabu::Ops::SwhSave::REPOS, "nabu"
    assert_includes Nabu::Ops::SwhSave::REPOS, "nabu-lects"
    assert_includes Nabu::Ops::SwhSave::REPOS, "nabu-data"
    assert_includes Nabu::Ops::SwhSave::REPOS, "nabu-skill"
  end
end
