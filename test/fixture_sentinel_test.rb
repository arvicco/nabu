# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"

# Fixture-sentinel logic (P5-4), tested with WebMock + tmp fixture dirs and an
# injected shell — never the real network, never the checked-in fixtures, never
# a real adapter-test shell-out. The "re-run the adapter test against fresh
# copies" step is asserted at the command/env level (the shell is stubbed).
class FixtureSentinelTest < Minitest::Test
  BASE = "https://example.test/fix"

  # Records shell-outs instead of executing them; optionally simulates a failing
  # adapter test (the drift signal).
  class FakeShell
    attr_reader :calls

    def initialize(fail: false)
      @calls = []
      @fail = fail
    end

    def run(*args, **opts)
      @calls << { args: args, opts: opts }
      raise Nabu::Shell::Error.new("adapter test failed", status: 1, stderr: "") if @fail

      ""
    end
  end

  # --- check --------------------------------------------------------------

  def test_identical_fetch_is_clean_and_reruns_the_adapter_test
    Dir.mktmpdir do |root|
      build_source(root, "demo", adapter_test: "test/adapters/demo_test.rb",
                                 files: [file("a.xml", disk: "hello", url: "#{BASE}/a.xml")])
      stub_request(:get, "#{BASE}/a.xml").to_return(status: 200, body: "hello")

      shell = FakeShell.new
      result = sentinel(root, shell).check("demo")

      assert result.ok?, "identical fetch should be clean"
      assert_equal :identical, result.files.first.status
      assert result.adapter_test.ran
      assert result.adapter_test.passed
      assert_equal ["bundle", "exec", "rake", "test", "TEST=test/adapters/demo_test.rb"],
                   result.adapter_test.command
      assert result.adapter_test.env.key?("NABU_FIXTURE_DIR")
      assert_equal 1, shell.calls.size, "adapter test should be shelled out exactly once"
    end
  end

  def test_changed_body_is_drift_and_flags_nonzero
    Dir.mktmpdir do |root|
      build_source(root, "demo", files: [file("a.xml", disk: "hello", url: "#{BASE}/a.xml")])
      stub_request(:get, "#{BASE}/a.xml").to_return(status: 200, body: "HELLO-changed")

      result = sentinel(root).check("demo")

      refute result.ok?, "a changed upstream body is drift"
      assert_equal :differs, result.files.first.status
    end
  end

  def test_404_is_reported_as_fetch_failure_and_skips_adapter_test
    Dir.mktmpdir do |root|
      build_source(root, "demo", adapter_test: "test/adapters/demo_test.rb",
                                 files: [file("a.xml", disk: "hello", url: "#{BASE}/a.xml")])
      stub_request(:get, "#{BASE}/a.xml").to_return(status: 404, body: "nope")

      shell = FakeShell.new
      result = sentinel(root, shell).check("demo")

      refute result.ok?
      assert_equal :fetch_failed, result.files.first.status
      refute result.adapter_test.ran, "must not run the adapter test against a partial tree"
      assert_empty shell.calls
    end
  end

  def test_non_refetchable_entries_are_skipped_with_a_note_and_never_fetched
    Dir.mktmpdir do |root|
      build_source(root, "demo", files: [
                     local_trim("a.xml", disk: "kept", reason: "full corpus sync only")
                   ])
      # No stub: any HTTP attempt would raise WebMock::NetConnectNotAllowedError.
      result = sentinel(root).check("demo")

      assert result.ok?, "a skipped local-trim entry is not a failure"
      skipped = result.files.first
      assert_equal :skipped, skipped.status
      assert_match(/full corpus sync only/, skipped.detail)
    end
  end

  def test_trimmed_entry_is_fetched_but_not_byte_compared
    Dir.mktmpdir do |root|
      build_source(root, "demo",
                   files: [file("a.conllu", disk: "trimmed-50", url: "#{BASE}/a.conllu", whole: false)])
      stub_request(:get, "#{BASE}/a.conllu").to_return(status: 200, body: "the-full-upstream-file")

      result = sentinel(root).check("demo")

      assert result.ok?, "a trimmed entry differing from upstream is expected, not drift"
      assert_equal :fetched, result.files.first.status
    end
  end

  def test_failing_adapter_test_against_fresh_upstream_is_the_drift_report
    Dir.mktmpdir do |root|
      build_source(root, "demo", adapter_test: "test/adapters/demo_test.rb",
                                 files: [file("a.xml", disk: "hello", url: "#{BASE}/a.xml")])
      stub_request(:get, "#{BASE}/a.xml").to_return(status: 200, body: "hello")

      result = sentinel(root, FakeShell.new(fail: true)).check("demo")

      refute result.ok?, "a failing fresh-copy adapter test flags drift"
      assert result.adapter_test.ran
      refute result.adapter_test.passed
    end
  end

  def test_sources_lists_only_dirs_carrying_a_manifest
    Dir.mktmpdir do |root|
      build_source(root, "b", files: [file("x", disk: "1", url: "#{BASE}/x")])
      build_source(root, "a", files: [file("x", disk: "1", url: "#{BASE}/x")])
      FileUtils.mkdir_p(File.join(root, "no-manifest"))

      assert_equal %w[a b], sentinel(root).sources
    end
  end

  # --- refresh ------------------------------------------------------------

  def test_refresh_overwrites_fixtures_and_bumps_retrieval_dates
    Dir.mktmpdir do |root|
      src = build_source(root, "demo", retrieved: "2026-07-03",
                                       files: [file("a.xml", disk: "old", url: "#{BASE}/a.xml")])
      stub_request(:get, "#{BASE}/a.xml").to_return(status: 200, body: "new-upstream")

      clock = -> { Date.new(2026, 12, 25) }
      result = sentinel(root, FakeShell.new, clock: clock).refresh("demo")

      assert_equal ["a.xml"], result.updated
      assert_equal "new-upstream", File.binread(File.join(src, "a.xml"))
      manifest = File.read(File.join(src, "manifest.yml"))
      assert_match(/^retrieved: 2026-12-25$/, manifest)
      refute_match(/2026-07-03/, manifest)
    end
  end

  def test_refresh_skips_non_refetchable_entries
    Dir.mktmpdir do |root|
      src = build_source(root, "demo", files: [
                           local_trim("a.xml", disk: "kept", reason: "corpus sync only")
                         ])
      result = sentinel(root).refresh("demo")

      assert_empty result.updated
      assert_equal ["a.xml"], result.skipped
      assert_equal "kept", File.binread(File.join(src, "a.xml")), "non-refetchable file untouched"
    end
  end

  def test_refresh_reminder_warns_about_trimmed_fixtures
    Dir.mktmpdir do |root|
      build_source(root, "demo",
                   files: [file("a.conllu", disk: "trim", url: "#{BASE}/a.conllu", whole: false)])
      stub_request(:get, "#{BASE}/a.conllu").to_return(status: 200, body: "full")

      result = sentinel(root).refresh("demo")
      assert_match(/re-apply the README trim/i, result.reminder)
    end
  end

  def test_no_arg_refresh_is_refused
    assert_raises(ArgumentError) { Nabu::FixtureSentinel.demand_source(nil) }
    assert_raises(ArgumentError) { Nabu::FixtureSentinel.demand_source("") }
    assert_equal "perseus", Nabu::FixtureSentinel.demand_source("perseus")

    Dir.mktmpdir do |root|
      assert_raises(ArgumentError) { sentinel(root).refresh(nil) }
    end
  end

  private

  def sentinel(root, shell = FakeShell.new, clock: -> { Date.today })
    Nabu::FixtureSentinel.new(fixtures_root: root, repo_root: root, http: Faraday, shell: shell, clock: clock)
  end

  def file(path, disk:, url:, whole: true)
    { disk: disk, manifest: { "path" => path, "url" => url, "whole" => whole, "trim" => "n/a" } }
  end

  def local_trim(path, disk:, reason:)
    { disk: disk,
      manifest: { "path" => path, "refetchable" => false, "provenance" => "local-trim",
                  "reason" => reason, "whole" => true } }
  end

  def build_source(root, name, files:, adapter_test: nil, retrieved: nil)
    dir = File.join(root, name)
    FileUtils.mkdir_p(dir)
    files.each do |f|
      dest = File.join(dir, f[:manifest]["path"])
      FileUtils.mkdir_p(File.dirname(dest))
      File.binwrite(dest, f[:disk])
    end
    manifest = { "source" => name, "adapter_test" => adapter_test,
                 "files" => files.map { |f| f[:manifest] } }
    manifest["retrieved"] = retrieved if retrieved
    File.write(File.join(dir, "manifest.yml"), YAML.dump(manifest))
    dir
  end
end
