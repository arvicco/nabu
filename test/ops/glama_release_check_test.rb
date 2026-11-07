# frozen_string_literal: true

require_relative "../test_helper"
require "nabu/ops/glama_release_check"

# The post-release directory probe (release rail step 8): the Glama
# listing auto-rebuilds from every GitHub release, and a failure lands on
# THEIR builder where our CI never looks. The probe asserts the released
# version is visible on the public listing page and reports the badge
# grade. The fetcher is an injected seam — no network in tests, ever.
class GlamaReleaseCheckTest < Minitest::Test
  LISTING_URL = "https://glama.ai/mcp/servers/arvicco/nabu"
  BADGE_URL = "#{LISTING_URL}/badges/score.svg".freeze

  def fetcher(listing:, badge:)
    lambda do |url|
      case url
      when LISTING_URL then listing
      when BADGE_URL then badge
      else raise "unexpected fetch: #{url}"
      end
    end
  end

  def check(version: "1.7.0", **pages)
    Nabu::Ops::GlamaReleaseCheck.new(version: version, fetch: fetcher(**pages)).run
  end

  def test_released_version_visible_and_graded_is_clean
    report = check(listing: "<html>Recent Releases 1.7.0</html>",
                   badge: "<svg><title>Nabu – MCP server rated A on Glama</title></svg>")
    assert_predicate report, :clean?
    assert report.version_listed
    assert_equal "A", report.grade
  end

  def test_release_not_yet_visible_is_a_finding
    report = check(listing: "<html>No releases yet.</html>",
                   badge: "<svg><title>Nabu – MCP server rated A on Glama</title></svg>")
    refute_predicate report, :clean?
    assert_match(/1\.7\.0 not visible/, report.findings.first)
  end

  def test_missing_grade_reports_nil_but_stays_clean
    report = check(listing: "<html>Recent Releases 1.7.0</html>",
                   badge: "<svg><title>Nabu MCP server</title></svg>")
    assert_predicate report, :clean?, "a queued evaluation is not a release failure"
    assert_nil report.grade
  end

  def test_version_match_is_exact_not_substring
    report = check(version: "1.7.0",
                   listing: "<html>Recent Releases 11.7.01</html>",
                   badge: "<svg><title>rated A on Glama</title></svg>")
    refute_predicate report, :clean?
  end

  def test_fetch_failure_is_a_named_finding_never_a_pass
    failing = ->(_url) { raise Nabu::Ops::GlamaReleaseCheck::FetchError, "HTTP 503" }
    report = Nabu::Ops::GlamaReleaseCheck.new(version: "1.7.0", fetch: failing).run
    refute_predicate report, :clean?
    assert_match(/HTTP 503/, report.findings.first)
  end
end
