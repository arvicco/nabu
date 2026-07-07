# frozen_string_literal: true

require "digest"
require "faraday"

module Nabu
  # Source-health probes (docs/backlog.md Phase 5). The remote probe here is
  # the network-facing half; the local, run-history half arrives with P5-5.
  module Health
    # `nabu health --remote` — a no-clone, no-corpus-fetch upstream probe run
    # for EVERY registered source (enabled or not: a disabled source's upstream
    # can still die and the owner wants to know). It answers three questions per
    # source and returns data; the CLI does all formatting.
    #
    #   1. Liveness — `git ls-remote <url> HEAD` (through the injected Shell).
    #      Success → :alive with the remote HEAD sha. Shell::Error → :gone, or
    #      :moved when git's own output looks like a redirect/rename (some hosts
    #      surface a moved repo as a 301 rather than following it; in practice
    #      git follows GitHub's redirect silently, so a rename usually reads as
    #      :alive against the new location — :moved is the best-effort case where
    #      git reports the redirect as the failure). Only :gone sets the exit-1
    #      flag; :moved is a soft "your stored URL is stale" signal.
    #
    #   2. Drift — remote HEAD vs the repo's ledger pin (Store::Pin, P7-1):
    #      :current, :behind (upstream has new commits), or :never_synced (no
    #      pin / no sha). Not alive → :unknown (nothing to compare).
    #
    #   3. License drift (best-effort, no clone) — for github.com upstreams,
    #      fetch the license file via raw.githubusercontent.com at the remote
    #      HEAD sha (LICENSE, LICENSE.md, COPYING in order) and compare its
    #      sha256 to a per-repo baseline stored on the ledger pin. First
    #      sight records the baseline (:baseline_recorded, not a false alarm);
    #      a differing hash is :changed; a match is :unchanged. Non-github, no
    #      license file, an unreachable upstream, or a fetch error → :unchecked
    #      (never an error — this is best-effort). Baselines and pins live in
    #      the history ledger (db/history.sqlite3), NOT the catalog, so they
    #      survive `nabu rebuild` — the drift blindspot the pre-P7-1 layout
    #      had (rebuild wiped the baseline; the next probe silently re-recorded
    #      whatever upstream had become) is closed.
    #
    # == Multi-repo sources (the UD decision, per-repo pinning — P6-3)
    #
    # Most adapters pull one git repo (the manifest URL). UD is one repo PER
    # treebank and its manifest URL is the GitHub *org* — un-probeable as a repo,
    # so probing it literally would be a permanent false "gone". Decision: probe
    # EVERY repo an adapter declares (Adapter.upstream_repo_urls; UD overrides
    # with its treebank repos) for LIVENESS — a single dead treebank is caught.
    # A multi-repo source is :alive only if all its repos are; :gone/:moved if
    # any is (the offending repos named in the detail).
    #
    # DRIFT and LICENSE are computed PER REPO against the ledger pins (P6-3,
    # moved to the ledger by P7-1), which the sync path records one row per
    # repo into — single-repo sources included (their one declared repo gets a
    # pin too). For each repo: drift = its ls-remote HEAD vs its pin
    # (:current/:behind/:never_synced/:unknown), and the source-level drift is
    # the WORST of them (offending :behind repos named in +drift_detail+, as
    # liveness names its offenders); license = the same
    # raw.githubusercontent.com fetch for every pinned github repo, baseline
    # on the pin, and the source-level license is :changed if ANY repo changed
    # (offenders named), else :baseline_recorded if any was newly recorded,
    # else :unchanged, else :unchecked. A multi-repo source with NO pins yet
    # (never synced under P6-3) still reads drift → :multi and license →
    # :unchecked("multi-repo") — there is nothing per-repo to compare against
    # until the next sync records pins.
    class RemoteProbe
      # Tried in order at the remote HEAD sha; first 200 wins. Lowercase
      # variants are real: PerseusDL and First1KGreek ship "license.md".
      LICENSE_FILENAMES = %w[LICENSE LICENSE.md LICENSE.txt license.md license.txt COPYING].freeze
      RAW_HOST = "https://raw.githubusercontent.com"

      # owner/repo out of an https or ssh github URL, tolerant of a .git suffix
      # and a trailing slash. Requires BOTH path segments, so an org-only URL
      # (github.com/UniversalDependencies) does not match — it reads as
      # non-github and the license check stays :unchecked rather than erroring.
      GITHUB_URL = %r{github\.com[/:](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?\z}i

      # status: :alive | :moved | :gone
      Liveness = Data.define(:status, :detail)
      # status: :baseline_recorded | :unchanged | :changed | :unchecked
      License = Data.define(:status, :detail)
      # status: :current | :behind | :never_synced | :unknown | :multi.
      # +detail+ names the offending repos for a multi-repo :behind (nil
      # otherwise); the single-repo path always leaves it nil.
      Drift = Data.define(:status, :detail)
      # drift is the Drift#status symbol (single-repo behavior unchanged);
      # drift_detail is Drift#detail — the multi-repo offender line, else nil.
      SourceHealth = Data.define(:slug, :enabled, :upstream, :liveness, :drift, :drift_detail, :license)

      Report = Data.define(:rows) do
        # The exit-code gate: any upstream fully gone fails the probe (exit 1).
        def any_gone? = rows.any? { |row| row.liveness.status == :gone }
      end

      # +ledger+ is the history db holding the pins (Store::Ledger bound); it
      # may be nil (fresh machine, no ledger yet): every source then reads as
      # never-synced and no baseline is recorded. +shell+ is injectable so unit
      # tests can feed canned ls-remote output/failures without a network.
      def initialize(registry:, ledger:, shell: Nabu::Shell)
        @registry = registry
        @ledger = ledger
        @shell = shell
      end

      def run
        Report.new(rows: @registry.each_source.map { |entry| probe_source(entry) })
      end

      private

      # One RepoProbe per upstream repo: its url, liveness, and HEAD sha (nil
      # when not alive).
      RepoProbe = Data.define(:url, :liveness, :head)
      private_constant :RepoProbe

      def probe_source(entry)
        urls = entry.adapter_class.upstream_repo_urls
        pins = pins_for(entry.slug)
        probes = urls.map { |url| probe_repo(url) }
        multi = probes.size > 1
        drift = drift_status(probes, pins, multi: multi)
        SourceHealth.new(
          slug: entry.slug, enabled: entry.enabled,
          upstream: multi ? "#{urls.size} repos" : urls.first,
          liveness: aggregate_liveness(probes),
          drift: drift.status, drift_detail: drift.detail,
          license: license_status(probes, pins, multi: multi)
        )
      end

      def probe_repo(url)
        out = @shell.run("git", "ls-remote", url, "HEAD")
        RepoProbe.new(url: url, liveness: Liveness.new(status: :alive, detail: nil), head: parse_head(out))
      rescue Nabu::Shell::Error => e
        RepoProbe.new(url: url, liveness: Liveness.new(status: classify_error(e), detail: error_detail(e)), head: nil)
      end

      def parse_head(out)
        out.to_s.lines.first&.split(/\s+/)&.first
      end

      def classify_error(error)
        "#{error.stderr} #{error.message}".match?(/moved|redirect|permanently|\b301\b/i) ? :moved : :gone
      end

      def error_detail(error)
        line = error.stderr.to_s.lines.map(&:strip).reject(&:empty?).first
        "git: #{line || error.message}"
      end

      # Single repo → its liveness verbatim. Multi → worst status wins (gone >
      # moved > alive), naming the offending repos so the row points at them.
      def aggregate_liveness(probes)
        return probes.first.liveness if probes.size == 1

        offenders = ->(status) { probes.select { |p| p.liveness.status == status }.map(&:url).join(", ") }
        if probes.any? { |p| p.liveness.status == :gone }
          Liveness.new(status: :gone, detail: "gone: #{offenders.call(:gone)}")
        elsif probes.any? { |p| p.liveness.status == :moved }
          Liveness.new(status: :moved, detail: "moved: #{offenders.call(:moved)}")
        else
          Liveness.new(status: :alive, detail: "#{probes.size} repos")
        end
      end

      # Worst-wins ordering for a multi-repo source's per-repo drift.
      DRIFT_SEVERITY = { behind: 3, never_synced: 2, unknown: 1, current: 0 }.freeze
      private_constant :DRIFT_SEVERITY

      def drift_status(probes, pins, multi:)
        return single_repo_drift(probes.first, pins) unless multi

        multi_repo_drift(probes, pins)
      end

      # repo_drift already yields :unknown (not alive) / :never_synced (no pin)
      # / :current / :behind — the single-repo status verbatim.
      def single_repo_drift(probe, pins)
        Drift.new(status: repo_drift(probe, pins[probe.url]), detail: nil)
      end

      # No per-repo pins yet → :multi (nothing to compare against until the next
      # sync records rows). Otherwise the worst per-repo drift wins, with the
      # :behind repos named in the detail.
      def multi_repo_drift(probes, pins)
        return Drift.new(status: :multi, detail: "no per-repo pins yet — sync to record") if pins.empty?

        per_repo = probes.map { |probe| [probe, repo_drift(probe, pins[probe.url])] }
        worst = per_repo.map { |_probe, status| status }.max_by { |status| DRIFT_SEVERITY.fetch(status) }
        behind = per_repo.select { |_probe, status| status == :behind }.map { |probe, _status| probe.url }
        Drift.new(status: worst, detail: behind.empty? ? nil : "behind: #{behind.join(', ')}")
      end

      def repo_drift(probe, pin)
        return :unknown unless probe.liveness.status == :alive && probe.head
        return :never_synced if pin.nil? || pin.last_sync_sha.nil? || pin.last_sync_sha.empty?

        pin.last_sync_sha == probe.head ? :current : :behind
      end

      def license_status(probes, pins, multi:)
        return repo_license(probes.first, pins[probes.first.url]) unless multi

        multi_repo_license(probes, pins)
      end

      # Per-repo license baselines stored on the ledger pins. Source-level
      # status: :changed if ANY repo changed (offenders named), else
      # :baseline_recorded if any was newly recorded, else :unchanged if any
      # matched, else :unchecked (no pins / nothing checkable).
      def multi_repo_license(probes, pins)
        return unchecked("multi-repo") if pins.empty?

        results = probes.map { |probe| [probe, repo_license(probe, pins[probe.url])] }
        changed = results.select { |_probe, lic| lic.status == :changed }.map { |probe, _lic| probe.url }
        return License.new(status: :changed, detail: license_changed_detail(changed)) unless changed.empty?

        statuses = results.map { |_probe, lic| lic.status }
        return License.new(status: :baseline_recorded, detail: nil) if statuses.include?(:baseline_recorded)
        return License.new(status: :unchanged, detail: nil) if statuses.include?(:unchanged)

        unchecked("multi-repo")
      end

      def license_changed_detail(urls)
        "license file changed — review upstream: #{urls.join(', ')}"
      end

      # Compare (and record) the license baseline for one repo against +row+
      # (its Store::Pin in the ledger). +row+ nil means the repo has no pin
      # yet (never synced), so nothing is checkable — the probe never mints
      # pins itself; baselines attach to pins the sync path created.
      def repo_license(probe, row)
        return unchecked("upstream unreachable") unless probe.liveness.status == :alive && probe.head

        owner_repo = github_owner_repo(probe.url)
        return unchecked("non-github") unless owner_repo
        return unchecked("never synced") unless row

        sha = license_sha256(*owner_repo, probe.head)
        return unchecked("no license file") unless sha

        compare_license(row, sha)
      end

      def compare_license(row, sha)
        baseline = row.license_baseline_sha256
        if baseline.nil? || baseline.empty?
          row.update(license_baseline_sha256: sha)
          License.new(status: :baseline_recorded, detail: nil)
        elsif baseline == sha
          License.new(status: :unchanged, detail: nil)
        else
          License.new(status: :changed, detail: "license file changed — review upstream")
        end
      end

      def unchecked(detail) = License.new(status: :unchecked, detail: detail)

      def license_sha256(owner, repo, sha)
        LICENSE_FILENAMES.each do |name|
          body = fetch_raw("#{RAW_HOST}/#{owner}/#{repo}/#{sha}/#{name}")
          return Digest::SHA256.hexdigest(body) if body
        end
        nil
      end

      # Best-effort: any transport error is "no license here", never a probe
      # failure.
      def fetch_raw(url)
        response = Faraday.get(url)
        response.status == 200 ? response.body : nil
      rescue Faraday::Error
        nil
      end

      def github_owner_repo(url)
        match = GITHUB_URL.match(url.to_s)
        match && [match[:owner], match[:repo]]
      end

      # { repo_url => Store::Pin } for a source's ledger pins. Empty when
      # there is no ledger yet (fresh machine) or the source was never synced
      # (no pins recorded yet).
      def pins_for(slug)
        return {} unless @ledger

        Nabu::Store::Pin.where(source_slug: slug).to_hash(:repo_url)
      end
    end
  end
end
