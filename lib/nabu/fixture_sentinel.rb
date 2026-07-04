# frozen_string_literal: true

require "yaml"
require "date"
require "fileutils"
require "tmpdir"
require "faraday"

module Nabu
  # The fixture sentinel (P5-4, maintenance §6). Guards the checked-in test
  # fixtures against upstream drift WITHOUT ever mutating them on `check`:
  #
  #   check(source)  — for every refetchable manifest entry, GET the upstream
  #                    raw URL into a tmp dir and (a) byte-diff it against the
  #                    checked-in fixture (whole files only — a trim can never
  #                    byte-match its source, so trimmed entries are fetched for
  #                    URL-liveness only), then (b) re-run the source's adapter
  #                    test against the FRESH copies via NABU_FIXTURE_DIR. Never
  #                    overwrites. Failing adapter tests ARE the drift report.
  #
  #   refresh(source) — explicit adoption: re-fetch and OVERWRITE the checked-in
  #                    fixtures for refetchable entries, bump the manifest's
  #                    retrieval dates, and hand back a reminder to re-run the
  #                    suite and eyeball the diff. Refuses without a source.
  #
  # Both are network-CAPABLE and human-initiated only; the suite never runs them
  # for real (HTTP is injected — Faraday by default — and the adapter-test
  # shell-out goes through an injected Nabu::Shell). Local-trim entries (the
  # papyri-ddbdp quarantine exemplars, copied from a canonical sync rather than
  # fetched) are refetchable: false and skipped by both, with the reason
  # printed — re-acquiring them means a full corpus sync, not a raw GET.
  class FixtureSentinel
    # Raised internally when a single upstream fetch fails; caught per-entry so
    # one dead URL is reported, not fatal to the whole run.
    class FetchFailure < Nabu::Error; end

    # One checked-in fixture file, as declared in a manifest.
    Entry = Data.define(:path, :url, :whole, :refetchable, :provenance, :reason, :trim) do
      def refetchable? = refetchable
      def whole? = whole
    end

    # A parsed manifest.yml for one fixture directory.
    Manifest = Data.define(:source, :dir, :adapter_test, :retrieved, :entries) do
      def file_path(entry) = File.join(dir, entry.path)
      def path = File.join(dir, "manifest.yml")
    end

    # Per-file outcome of a check. status:
    #   :identical    whole file, fresh fetch byte-matches the fixture (clean)
    #   :differs      whole file, fresh fetch differs (DRIFT — flags nonzero)
    #   :fetched      trimmed file, upstream fetched OK (not byte-compared)
    #   :fetch_failed the URL did not return 200 / transport error (flags nonzero)
    #   :skipped      not refetchable (local-trim) — reported, never a failure
    FileResult = Data.define(:path, :status, :detail)

    # Outcome of the "re-run the adapter test against fresh copies" step.
    AdapterTestResult = Data.define(:ran, :command, :env, :passed, :detail)

    CheckResult = Data.define(:source, :files, :adapter_test) do
      # Clean iff nothing drifted, nothing failed to fetch, and (if it ran) the
      # adapter test passed against the fresh copies.
      def ok?
        files.none? { |f| %i[differs fetch_failed].include?(f.status) } &&
          !(adapter_test&.ran && adapter_test.passed == false)
      end
    end

    RefreshResult = Data.define(:source, :updated, :skipped, :reminder)

    DEFAULT_FIXTURES_ROOT = File.expand_path("../../test/fixtures", __dir__)
    DEFAULT_REPO_ROOT = File.expand_path("../..", __dir__)

    def initialize(fixtures_root: DEFAULT_FIXTURES_ROOT, repo_root: DEFAULT_REPO_ROOT,
                   http: Faraday, shell: Nabu::Shell, clock: -> { Date.today })
      @fixtures_root = fixtures_root
      @repo_root = repo_root
      @http = http
      @shell = shell
      @clock = clock
    end

    # Sorted list of every fixture dir carrying a manifest.yml (the no-arg
    # `check` iterates these).
    def sources
      Dir.children(@fixtures_root)
         .select { |name| File.file?(File.join(@fixtures_root, name, "manifest.yml")) }
         .sort
    end

    def check(source)
      manifest = load_manifest(source)
      Dir.mktmpdir("nabu-fixtures-check") do |tmp|
        files = manifest.entries.map { |entry| check_entry(manifest, entry, tmp) }
        adapter = run_adapter_test(manifest, tmp, files)
        CheckResult.new(source: source, files: files, adapter_test: adapter)
      end
    end

    def refresh(source)
      self.class.demand_source(source)
      manifest = load_manifest(source)
      updated = []
      skipped = []
      manifest.entries.each do |entry|
        if entry.refetchable?
          File.binwrite(manifest.file_path(entry), fetch(entry.url))
          updated << entry.path
        else
          skipped << entry.path
        end
      end
      bump_retrieved_dates(manifest) unless updated.empty?
      RefreshResult.new(source: source, updated: updated, skipped: skipped,
                        reminder: refresh_reminder(manifest, updated))
    end

    # Refresh overwrites checked-in fixtures, so it refuses to run "for all
    # sources" — the operator must name exactly one.
    def self.demand_source(source)
      return source unless source.nil? || source.to_s.strip.empty?

      raise ArgumentError,
            "usage: rake fixtures:refresh[<source>] — refresh needs an explicit source. " \
            "It re-fetches and OVERWRITES checked-in fixtures, so it never refreshes every source at once."
    end

    def load_manifest(source)
      dir = File.join(@fixtures_root, source)
      file = File.join(dir, "manifest.yml")
      raise Nabu::Error, "no manifest.yml in #{dir}" unless File.file?(file)

      raw = YAML.safe_load_file(file, permitted_classes: [Date])
      Manifest.new(
        source: raw.fetch("source"),
        dir: dir,
        adapter_test: presence(raw["adapter_test"]),
        retrieved: raw["retrieved"],
        entries: Array(raw["files"]).map { |f| build_entry(f) }
      )
    end

    private

    def build_entry(hash)
      Entry.new(
        path: hash.fetch("path"),
        url: hash["url"],
        whole: hash.fetch("whole", true),
        refetchable: hash.fetch("refetchable", true),
        provenance: hash["provenance"] || "raw-get",
        reason: hash["reason"],
        trim: hash["trim"]
      )
    end

    def check_entry(manifest, entry, tmp)
      unless entry.refetchable?
        return FileResult.new(path: entry.path, status: :skipped,
                              detail: "not refetchable (#{entry.provenance}): #{entry.reason}")
      end

      body = fetch(entry.url)
      stage(tmp, manifest.source, entry.path, body)
      diff_entry(manifest, entry, body)
    rescue FetchFailure => e
      FileResult.new(path: entry.path, status: :fetch_failed, detail: e.message)
    end

    def diff_entry(manifest, entry, body)
      unless entry.whole?
        return FileResult.new(path: entry.path, status: :fetched,
                              detail: "trimmed fixture — upstream fetched (#{body.bytesize} B), not byte-compared")
      end

      checked_in = File.binread(manifest.file_path(entry))
      if checked_in == body
        FileResult.new(path: entry.path, status: :identical, detail: nil)
      else
        FileResult.new(path: entry.path, status: :differs,
                       detail: "fresh #{body.bytesize} B vs checked-in #{checked_in.bytesize} B")
      end
    end

    # Write a fresh copy into the tmp mirror (<tmp>/<source>/<path>) so the
    # adapter test can run against it via NABU_FIXTURE_DIR=<tmp>.
    def stage(tmp, source, path, body)
      dest = File.join(tmp, source, path)
      FileUtils.mkdir_p(File.dirname(dest))
      File.binwrite(dest, body)
    end

    def run_adapter_test(manifest, tmp, files)
      return skipped_test("no adapter_test in manifest") if manifest.adapter_test.nil?
      if files.any? { |f| f.status == :fetch_failed }
        return skipped_test("a fixture failed to fetch — not re-running against a partial tree")
      end

      # NABU_FIXTURE_DIR replaces the fixtures ROOT; <root>/<source>/... mirrors
      # the checked-in layout, so the source's adapter test resolves its fixtures
      # to the freshly fetched copies.
      env = { "NABU_FIXTURE_DIR" => tmp }
      command = ["bundle", "exec", "rake", "test", "TEST=#{manifest.adapter_test}"]
      invoke_adapter_test(env, command)
    end

    def invoke_adapter_test(env, command)
      @shell.run(env, *command, chdir: @repo_root)
      AdapterTestResult.new(ran: true, command: command, env: env, passed: true, detail: nil)
    rescue Nabu::Shell::Error => e
      AdapterTestResult.new(ran: true, command: command, env: env, passed: false,
                            detail: "adapter test FAILED against fresh upstream (exit #{e.status}) — the drift report")
    end

    def skipped_test(detail)
      AdapterTestResult.new(ran: false, command: nil, env: nil, passed: nil, detail: detail)
    end

    def fetch(url)
      response = @http.get(url)
      raise FetchFailure, "HTTP #{response.status} for #{url}" unless response.status == 200

      response.body.to_s
    rescue Faraday::Error => e
      raise FetchFailure, "transport error for #{url}: #{e.message}"
    end

    # Bump every `retrieved:` value line to today, preserving comments and the
    # rest of the YAML (Psych round-tripping would drop the documented header).
    def bump_retrieved_dates(manifest)
      today = @clock.call.to_s
      text = File.read(manifest.path)
      text = text.gsub(/^(\s*)retrieved:[ \t]*\S.*$/) { "#{Regexp.last_match(1)}retrieved: #{today}" }
      File.write(manifest.path, text)
    end

    def refresh_reminder(manifest, updated)
      trimmed = manifest.entries.select { |e| e.refetchable? && !e.whole? }.map(&:path)
      lines = ["Overwrote #{updated.size} checked-in fixture(s) with fresh upstream copies.",
               "Re-run `bundle exec rake test` and eyeball `git diff` before committing."]
      unless trimmed.empty?
        lines << "TRIMMED fixtures were replaced by the FULL upstream files: " \
                 "#{trimmed.join(', ')} — re-apply the README trim procedure or the suite will fail."
      end
      lines.join(" ")
    end

    def presence(value)
      return nil if value.nil? || value.to_s.strip.empty?

      value
    end
  end
end
