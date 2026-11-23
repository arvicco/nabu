# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nabu/ops/outreach_probe"

module Ops
  # Nabu::Ops::OutreachProbe (`rake outreach:probe`): the probe list is a
  # gitignored board file; http + registry kinds run over WebMock stubs,
  # the gh kinds over an injected command runner. Example rows only —
  # never the real boards.
  class OutreachProbeTest < Minitest::Test
    PROBE = Nabu::Ops::OutreachProbe

    # Trimmed from a real v0 registry search response (2026-11-23).
    REGISTRY_BODY = <<~JSON
      {"servers":[{"server":{"name":"io.github.example/demo","version":"1.7.0"},
        "_meta":{"io.modelcontextprotocol.registry/official":{"status":"active","isLatest":false}}},
       {"server":{"name":"io.github.example/demo","version":"1.8.0"},
        "_meta":{"io.modelcontextprotocol.registry/official":{"status":"active","isLatest":true}}}],
       "metadata":{"count":2}}
    JSON

    def setup
      @dir = Dir.mktmpdir
      FileUtils.mkdir_p(File.join(@dir, "outreach"))
      @calls = []
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def write_probes(rows)
      File.write(File.join(@dir, PROBE::FILE), YAML.dump("probes" => rows))
    end

    def runner(outputs)
      lambda do |*argv|
        @calls << argv
        out = outputs.fetch(argv[1..3].join(" "))
        raise out if out.is_a?(Exception)

        out
      end
    end

    def run_probe(outputs = {})
      PROBE.new(boards_dir: @dir, runner: runner(outputs)).run
    end

    def test_absent_probe_list_is_an_announced_skip
      report = PROBE.new(boards_dir: File.join(@dir, "nowhere")).run
      assert report.skipped
      assert_empty report.results
    end

    def test_http_status_expectation
      stub_request(:get, "https://dir.example/servers/demo").to_return(status: 200, body: "<html/>")
      stub_request(:get, "https://dir.example/servers/gone").to_return(status: 404)
      write_probes([{ "name" => "listed", "kind" => "http", "url" => "https://dir.example/servers/demo",
                      "expect" => 200 },
                    { "name" => "gone", "kind" => "http", "url" => "https://dir.example/servers/gone",
                      "expect" => 200 }])
      listed, gone = run_probe.results
      assert_equal "listed · HTTP 200 · expectation met · first run", listed.line
      assert_equal false, gone.met
      assert_match(/HTTP 404 · expectation NOT met/, gone.line)
    end

    def test_http_substring_expectation_is_case_insensitive
      stub_request(:get, "https://skills.example/search?q=demo").to_return(status: 200, body: "<b>Demo</b> skill")
      stub_request(:get, "https://skills.example/search?q=none").to_return(status: 200, body: "no results")
      write_probes([{ "name" => "hit", "kind" => "http", "url" => "https://skills.example/search?q=demo",
                      "expect" => "demo" },
                    { "name" => "miss", "kind" => "http", "url" => "https://skills.example/search?q=none",
                      "expect" => "demo" }])
      hit, miss = run_probe.results
      assert hit.met
      assert_equal false, miss.met
      assert_match(/no "demo"/, miss.state)
    end

    def test_http_follows_redirects_and_reports_unreachable_as_a_state
      stub_request(:get, "https://dir.example/a").to_return(status: 301, headers: { "Location" => "/b" })
      stub_request(:get, "https://dir.example/b").to_return(status: 200, body: "ok")
      stub_request(:get, "https://down.example/").to_raise(SocketError)
      write_probes([{ "name" => "moved", "kind" => "http", "url" => "https://dir.example/a", "expect" => 200 },
                    { "name" => "down", "kind" => "http", "url" => "https://down.example/", "expect" => 200 }])
      moved, down = run_probe.results
      assert moved.met
      assert_equal false, down.met
      assert_match(/unreachable: SocketError/, down.state)
    end

    def test_registry_reports_latest_version_of_the_matching_server
      stub_request(:get, "#{PROBE::REGISTRY}?search=example").to_return(status: 200, body: REGISTRY_BODY)
      write_probes([{ "name" => "registry", "kind" => "registry", "q" => "example" }])
      result = run_probe.results.first
      assert_equal "io.github.example/demo 1.8.0", result.state
      assert result.met
    end

    def test_registry_without_a_match_is_unmet
      stub_request(:get, "#{PROBE::REGISTRY}?search=nobody")
        .to_return(status: 200, body: '{"servers":[],"metadata":{"count":0}}')
      write_probes([{ "name" => "registry", "kind" => "registry", "q" => "nobody" }])
      assert_equal false, run_probe.results.first.met
    end

    def test_gh_kinds_report_state_and_last_comment_date
      pr = { "state" => "MERGED", "comments" => [{ "createdAt" => "2026-11-01T10:00:00Z" },
                                                 { "createdAt" => "2026-11-17T02:56:55Z" }] }
      issue = { "state" => "OPEN", "comments" => [] }
      write_probes([{ "name" => "pr", "kind" => "gh_pr", "repo" => "example/list", "number" => 12,
                      "expect" => "merged" },
                    { "name" => "issue", "kind" => "gh_issue", "repo" => "example/catalog", "number" => 34 }])
      pr_result, issue_result = run_probe("pr view 12" => JSON.dump(pr), "issue view 34" => JSON.dump(issue)).results
      assert_equal "MERGED · last comment 2026-11-17", pr_result.state
      assert pr_result.met
      assert_equal "OPEN · no comments", issue_result.state
      assert_nil issue_result.met
      assert_match(/no expectation/, issue_result.line)
      assert_equal %w[gh pr view 12 --repo example/list --json state,comments], @calls.first
    end

    def test_gh_failure_is_an_announced_skip_never_a_crash
      missing = Nabu::Shell::Error.new("command not found: gh", status: nil, stderr: "")
      write_probes([{ "name" => "pr", "kind" => "gh_pr", "repo" => "example/list", "number" => 12 }])
      result = run_probe("pr view 12" => missing).results.first
      assert result.skipped
      assert_equal "pr · SKIP · gh unavailable or failed (command not found: gh)", result.line
    end

    def test_delta_against_the_previous_run
      issue = ->(date) { JSON.dump("state" => "OPEN", "comments" => [{ "createdAt" => date }]) }
      write_probes([{ "name" => "issue", "kind" => "gh_issue", "repo" => "example/catalog", "number" => 34 }])
      run_probe("issue view 34" => issue.call("2026-11-01T00:00:00Z"))
      assert_match(/unchanged\z/, run_probe("issue view 34" => issue.call("2026-11-01T00:00:00Z")).results.first.line)

      report = run_probe("issue view 34" => issue.call("2026-11-20T00:00:00Z"))
      assert_equal 1, report.changed
      assert_match(/CHANGED \(was OPEN · last comment 2026-11-01\)/, report.results.first.line)
    end

    def test_a_skipped_row_keeps_its_earlier_observation
      ok = JSON.dump("state" => "OPEN", "comments" => [])
      write_probes([{ "name" => "issue", "kind" => "gh_issue", "repo" => "example/catalog", "number" => 34 }])
      run_probe("issue view 34" => ok)
      run_probe("issue view 34" => Nabu::Shell::Error.new("gh: HTTP 502", status: 1, stderr: ""))
      assert_match(/unchanged\z/, run_probe("issue view 34" => ok).results.first.line)
    end

    def test_malformed_rows_are_named
      write_probes([{ "name" => "odd", "kind" => "ftp" }])
      error = assert_raises(PROBE::ProbeError) { run_probe }
      assert_match(/odd: unknown kind "ftp"/, error.message)
    end
  end
end
