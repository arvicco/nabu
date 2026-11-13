# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "nabu/ops/docs_verify"

# The executor half of `rake docs:verify`: runs a plan's steps against a
# sandbox root and prints one verdict line per claim. These tests drive it
# with a stub flow (a tiny page + plan in a tmpdir) — the full sandbox run
# over the real pages is the rake task's job, never the suite's.
class DocsVerifyTest < Minitest::Test
  Result = Nabu::Shell::Capture

  PAGE = <<~MD
    # Walkthrough

    ```
    tool --version      # prints the version
    tool fetch thing    # downloads the thing
    ```

    The profile lives at `profile.yml`. `bin/nabu ping` answers pong.

    ```
    $ tool show one
    one — the first
      body line
    …
    ```

    ```json
    {"server": {"command": "tool"}}
    ```
  MD

  def plan_hash
    {
      "pages" => [{ "path" => "walk.md" }],
      "forbid_output" => ["warning: "],
      "steps" => [
        { "id" => "version", "run" => "tool --version",
          "claim" => { "page" => "walk.md", "quote" => "prints the version" },
          "expect" => { "exit" => 0, "output_includes" => ["tool 1."], "max_seconds" => 5 } },
        { "id" => "fetch", "run" => "tool fetch thing", "mode" => "network", "expect" => { "exit" => 0 } },
        { "id" => "ping", "run" => "bin/nabu ping", "expect" => { "output_matches" => ["\\Apong"] } },
        { "id" => "show", "run" => "tool show one", "expect" => { "transcript" => "walk.md" } },
        { "id" => "profile", "run" => "tool init", "covers" => [],
          "claim" => { "page" => "walk.md", "quote" => "The profile lives at `profile.yml`." },
          "expect" => { "path_exists" => "profile.yml" } },
        { "id" => "config", "run" => "true", "covers" => [],
          "blocks" => [{ "page" => "walk.md", "contains" => "\"server\"" }],
          "expect" => { "json_file_equals_block" => { "path" => "server.json", "page" => "walk.md",
                                                      "contains" => "\"server\"" } } }
      ],
      "ignore" => []
    }
  end

  def with_root(files = {})
    Dir.mktmpdir do |root|
      File.write(File.join(root, "walk.md"), PAGE)
      files.each { |name, body| File.write(File.join(root, name), body) }
      yield root
    end
  end

  def stub_runner(outcomes)
    calls = []
    runner = lambda do |command, stdin:|
      calls << [command, stdin]
      outcome = outcomes.fetch(command)
      outcome.respond_to?(:call) ? outcome.call : outcome
    end
    [runner, calls]
  end

  def run_verify(root, outcomes, mode: :offline, plan: plan_hash, clock: nil)
    runner, calls = stub_runner(outcomes)
    out = StringIO.new
    verify = Nabu::Ops::DocsVerify.new(plan: Nabu::Ops::DocsVerify::Plan.from_h(plan), root: root,
                                       mode: mode, runner: runner, out: out, clock: clock)
    [verify.run.clean?, out.string, calls]
  end

  def good_outcomes
    {
      "tool --version" => Result.new(output: "tool 1.2\n", status: 0),
      "tool fetch thing" => Result.new(output: "fetched\n", status: 0),
      "bin/nabu ping" => Result.new(output: "pong\n", status: 0),
      "tool show one" => Result.new(output: "one — the first\n  body   line\nextra\n", status: 0),
      "tool init" => Result.new(output: "", status: 0),
      "true" => Result.new(output: "", status: 0)
    }
  end

  def test_offline_mode_runs_offline_steps_and_names_the_network_ones
    with_root("profile.yml" => "x", "server.json" => %({"server":{"command":"tool"}})) do |root|
      ok, out, calls = run_verify(root, good_outcomes)

      assert ok, out
      refute_includes calls.map(&:first), "tool fetch thing"
      assert_match(/^OK    version: tool --version \(/, out)
      assert_match(/^NET   fetch: tool fetch thing — network step; run rake "docs:verify\[network\]"$/, out)
      assert_match(/^OK    show: tool show one/, out)
      assert_match(/^OK    config: true/, out)
      assert_match(/docs:verify \(offline\) — 5 OK, 0 FAIL, 1 network-only$/, out)
    end
  end

  def test_network_mode_runs_every_step_in_plan_order
    with_root("profile.yml" => "x", "server.json" => %({"server":{"command":"tool"}})) do |root|
      ok, out, calls = run_verify(root, good_outcomes, mode: :network)

      assert ok, out
      assert_equal ["tool --version", "tool fetch thing", "bin/nabu ping", "tool show one", "tool init", "true"],
                   calls.map(&:first)
      assert_match(/docs:verify \(network\) — 6 OK, 0 FAIL$/, out)
    end
  end

  def test_a_failed_claim_prints_what_the_doc_says_against_what_happened
    with_root("server.json" => %({"server":{"command":"other"}})) do |root|
      outcomes = good_outcomes.merge(
        "tool --version" => Result.new(output: "tool 2.0\nwarning: deprecated\n", status: 1),
        "tool show one" => Result.new(output: "one — the first\n", status: 0)
      )
      ok, out, = run_verify(root, outcomes)

      refute ok
      line = out.lines.find { |l| l.start_with?("FAIL  version") }
      assert_includes line, %(doc (walk.md) says "prints the version")
      assert_includes line, "exit 0 expected, got 1"
      assert_includes line, %(output lacks "tool 1.")
      assert_includes line, %(forbidden output "warning: ")
      assert_match(/^FAIL  show: .*documented output line missing: "body line"/, out)
      assert_match(/^FAIL  profile: .*profile\.yml does not exist/, out)
      assert_match(/^FAIL  config: .*server\.json differs from the documented block/, out)
      assert_match(/— 1 OK, 4 FAIL, 1 network-only$/, out)
    end
  end

  def test_timing_budgets_are_claims_too
    with_root("profile.yml" => "x", "server.json" => %({"server":{"command":"tool"}})) do |root|
      ticks = [0.0, 9.5, 10.0, 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7, 10.8, 10.9].each
      ok, out, = run_verify(root, good_outcomes, clock: -> { ticks.next })

      refute ok
      assert_match(/^FAIL  version: .*took 9\.5s, budget 5s/, out)
    end
  end

  def test_nonzero_exit_expectations_check_refusal_paths
    plan = plan_hash.merge("steps" => [{ "id" => "refuse", "run" => "tool fetch thing",
                                         "expect" => { "exit" => "nonzero",
                                                       "output_includes" => ["enable thing"] } }])
    with_root do |root|
      ok, out, = run_verify(root, { "tool fetch thing" => Result.new(output: "run enable thing\n", status: 1) },
                            plan: plan)
      assert ok, out

      ok, out, = run_verify(root, { "tool fetch thing" => Result.new(output: "fetched\n", status: 0) },
                            plan: plan)
      refute ok
      assert_match(/nonzero exit expected, got 0/, out)
    end
  end

  def test_root_placeholder_and_stdin_reach_the_runner
    plan = plan_hash.merge("steps" => [{ "id" => "abs", "run" => "cd / && {root}/bin/tool", "stdin" => "hello\n",
                                         "covers" => [], "expect" => { "exit" => 0 } }])
    with_root do |root|
      _, _, calls = run_verify(root, { "cd / && #{root}/bin/tool" => Result.new(output: "", status: 0) }, plan: plan)

      assert_equal [["cd / && #{root}/bin/tool", "hello\n"]], calls
    end
  end

  def test_mcp_tool_count_reads_the_tools_list_response
    plan = plan_hash.merge("steps" => [{ "id" => "mcp", "run" => "serve", "covers" => [],
                                         "expect" => { "mcp_tools" => 2 } }])
    reply = [{ jsonrpc: "2.0", id: 1, result: {} }, { jsonrpc: "2.0", id: 2, result: { tools: [{}, {}] } }]
            .map { |r| JSON.generate(r) }.join("\n")
    with_root do |root|
      ok, out, = run_verify(root, { "serve" => Result.new(output: "#{reply}\n", status: 0) }, plan: plan)
      assert ok, out

      ok, out, = run_verify(root, { "serve" => Result.new(output: "boom\n", status: 1) }, plan: plan)
      refute ok
      assert_match(%r{tools/list answered 0 tools, doc says 2}, out)
    end
  end

  # The drift guard's machine half: every documented command and content
  # block is covered by a step or an ignore entry, every claim quote still
  # appears in its page, and no plan entry names a command the pages lost.
  def test_coverage_gaps_name_uncovered_commands_stale_quotes_and_dead_entries
    with_root do |root|
      plan = plan_hash
      plan["steps"] = plan["steps"].reject { |s| s["id"] == "ping" }
      plan["steps"].first["claim"]["quote"] = "prints the release"
      plan["ignore"] = [{ "command" => "tool vanished", "reason" => "gone" }]
      verify = Nabu::Ops::DocsVerify.new(plan: Nabu::Ops::DocsVerify::Plan.from_h(plan), root: root)
      gaps = verify.coverage_gaps

      assert_includes gaps, "walk.md:8: `bin/nabu ping` is neither verified by a step nor ignored"
      assert_includes gaps, %(step version: claim quote not found in walk.md: "prints the release")
      assert_includes gaps, "ignore entry `tool vanished` matches no documented command"
      assert_equal 3, gaps.size, gaps.inspect
    end
  end

  def test_a_clean_plan_has_no_coverage_gaps
    with_root do |root|
      verify = Nabu::Ops::DocsVerify.new(plan: Nabu::Ops::DocsVerify::Plan.from_h(plan_hash), root: root)

      assert_empty verify.coverage_gaps
    end
  end

  def test_ignore_entries_require_a_reason
    plan = plan_hash.merge("ignore" => [{ "command" => "tool fetch thing" }])

    error = assert_raises(Nabu::Error) { Nabu::Ops::DocsVerify::Plan.from_h(plan) }
    assert_match(/reason/, error.message)
  end

  # The sandbox is a fresh clone of the local repo (HEAD, committed state)
  # in a tmpdir — never the working tree itself.
  def test_sandbox_clones_the_committed_repo_into_a_throwaway_dir
    Dir.mktmpdir do |repo|
      Nabu::Shell.run("git", "-C", repo, "init", "--quiet")
      File.write(File.join(repo, "walk.md"), PAGE)
      Nabu::Shell.run("git", "-C", repo, "add", "walk.md")
      Nabu::Shell.run("git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@example.org",
                      "commit", "--quiet", "--no-verify", "-m", "seed")
      File.write(File.join(repo, "dirty.md"), "uncommitted")
      seen = nil
      Nabu::Ops::DocsVerify.sandbox(repo: repo) do |root, sha|
        seen = root
        assert File.file?(File.join(root, "walk.md"))
        refute File.exist?(File.join(root, "dirty.md"))
        assert_match(/\A\h{40}\z/, sha)
      end
      refute File.exist?(seen)
    end
  end

  # The real runner: a clean environment (no inherited Bundler/Ruby/Nabu
  # variables) and, offline, an unroutable proxy so an accidental fetch
  # fails fast instead of downloading.
  def test_runner_environment_strips_bundler_and_guards_the_network_offline
    env = Nabu::Ops::DocsVerify.runner_env(mode: :offline, base: { "BUNDLE_GEMFILE" => "/x/Gemfile",
                                                                   "RUBYOPT" => "-rbundler/setup",
                                                                   "NABU_TEST_WORKERS" => "4", "PATH" => "/bin" })

    assert_nil env.fetch("BUNDLE_GEMFILE")
    assert_nil env.fetch("RUBYOPT")
    assert_nil env.fetch("NABU_TEST_WORKERS")
    refute env.key?("PATH")
    assert_equal Nabu::Ops::DocsVerify::OFFLINE_PROXY, env.fetch("https_proxy")
    refute Nabu::Ops::DocsVerify.runner_env(mode: :network, base: {}).key?("https_proxy")
  end
end
