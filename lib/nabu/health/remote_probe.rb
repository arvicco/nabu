# frozen_string_literal: true

require "digest"
require "json"
require "faraday"
require_relative "../zip_fetch"

module Nabu
  # Source-health probes (docs/backlog.md Phase 5). The remote probe here is
  # the network-facing half; the local, run-history half arrives with P5-5.
  module Health
    # `nabu health --remote` — a no-clone, no-corpus-fetch upstream probe run
    # for EVERY registered source (enabled or not: a disabled source's upstream
    # can still die and the owner wants to know). It answers three questions per
    # source and returns data; the CLI does all formatting.
    #
    # == Per-source probe strategy (P11-2)
    #
    # The strategy is keyed off the adapter (Adapter.remote_probe_strategy):
    # :git (default) → the ls-remote path below; :http_zip (ORACC, the
    # non-git ZipFetch path) → HEAD each project zip (reachability +
    # Last-Modified drift vs the on-disk .zip-fetch.json pin) and GET each
    # project metadata.json for license drift. The HTTP-zip half fills the
    # same SourceHealth shape (liveness/drift/license), aggregated identically
    # (worst-wins liveness/drift, any-changed license), and reuses the ledger
    # pins + compare_license baseline mechanism — see probe_http_source. Both
    # halves render through the one CLI table.
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
    #      :current, :behind (upstream has new commits), :unpinned (no pin yet
    #      but the source HAS been synced — a run in the ledger or a canonical
    #      tree on disk — so it last fetched before the pins ledger existed,
    #      P7; NOT "never synced"), or :never_synced (no pin AND no run AND no
    #      canonical tree — genuinely untouched). Not alive → :unknown (nothing
    #      to compare). A frozen-policy source short-circuits to :frozen (no
    #      drift expected), agreeing with status's up=frozen column (P14-12).
    #      The honest split (P15-7) closes the owner defect where sources
    #      synced pre-P7 read a false "never-synced".
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
      # status: :current | :behind | :unpinned | :never_synced | :unknown |
      # :multi | :frozen. +detail+ names the offending repos for a multi-repo
      # :behind, or carries UNPINNED_HINT for a single-unit :unpinned (nil
      # otherwise).
      Drift = Data.define(:status, :detail)

      # The single-unit :unpinned hint — an honest "you synced this before the
      # pins ledger existed" note, pointing at the two ways to record the pin.
      UNPINNED_HINT = "synced pre-ledger — next sync records the pin, or run health --backfill-pins"
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
      # +canonical_dir+ (P11-2) is the corpus root the HTTP-zip probe reads the
      # per-project .zip-fetch.json Last-Modified pins from
      # (<canonical_dir>/<source-slug>/<project>/.zip-fetch.json). nil (the git
      # unit tests) → every http-zip project reads as never-synced.
      def initialize(registry:, ledger:, shell: Nabu::Shell, canonical_dir: nil)
        @registry = registry
        @ledger = ledger
        @shell = shell
        @canonical_dir = canonical_dir
      end

      def run
        checked_at = Time.now
        rows = @registry.each_source.map do |entry|
          health = probe_source(entry)
          persist(health, checked_at)
          health
        end
        Report.new(rows: rows)
      end

      # One backfilled pin: the source, the repo/zip URL it keys, the recorded
      # sha, and where it came from (:git_clone | :state_file).
      Backfilled = Data.define(:slug, :repo_url, :sha, :origin)

      # `nabu health --backfill-pins` (P15-7): record ledger pins for sources
      # that were synced before the pins ledger existed (P7) and so read as
      # "unpinned". READ-ONLY on canonical/ (a local `git rev-parse HEAD` or a
      # state-file read) and on the network (none); writes ONLY the ledger
      # pins. Idempotent — a source that already carries a non-blank pin is
      # skipped, so re-running records nothing. Returns the Backfilled rows
      # actually written (empty without a ledger, or when nothing needs it).
      def backfill_pins
        return [] unless @ledger

        @registry.each_source.flat_map { |entry| backfill_source(entry) }
      end

      private

      def backfill_source(entry)
        case entry.adapter_class.remote_probe_strategy
        when :http_zip then backfill_http_source(entry)
        else backfill_git_source(entry)
        end
      end

      # Single-repo git sources only: canonical/<slug> is the one clone, so its
      # `git rev-parse HEAD` maps onto the source's one declared repo URL. A
      # multi-repo source (UD) keeps its per-repo clones under adapter-private
      # subdirs — one canonical/<slug> HEAD can't stand in for several pins, so
      # those are left for the next real sync to record.
      def backfill_git_source(entry)
        urls = entry.adapter_class.upstream_repo_urls
        return [] unless urls.size == 1

        url = urls.first
        return [] if pinned?(entry.slug, url)

        sha = local_head(entry.slug)
        return [] unless sha

        record_pin(entry.slug, url, sha)
        [Backfilled.new(slug: entry.slug, repo_url: url, sha: sha, origin: :git_clone)]
      end

      # Non-git sources (ZipFetch/FileFetch): each fetched unit's state file
      # carries the body sha256 pin. Backfill from it (per unit, keyed by the
      # unit's URL) where the state file exists and the unit is not already
      # pinned.
      def backfill_http_source(entry)
        entry.adapter_class.http_probe_targets.filter_map do |target|
          next if pinned?(entry.slug, target.zip_url)

          sha = state_file_sha(entry.slug, target)
          next unless sha

          record_pin(entry.slug, target.zip_url, sha)
          Backfilled.new(slug: entry.slug, repo_url: target.zip_url, sha: sha, origin: :state_file)
        end
      end

      # A source unit counts as pinned only when its row carries a non-blank
      # last_sync_sha — a baseline-only row (license baseline, no sha) is still
      # backfillable, and record_pin then updates that row in place.
      def pinned?(slug, repo_url)
        pin = Nabu::Store::Pin.first(source_slug: slug, repo_url: repo_url)
        pin && !blank?(pin.last_sync_sha)
      end

      def record_pin(slug, repo_url, sha)
        pin = Nabu::Store::Pin.first(source_slug: slug, repo_url: repo_url)
        if pin
          pin.update(last_sync_sha: sha)
        else
          Nabu::Store::Pin.create(source_slug: slug, repo_url: repo_url, last_sync_sha: sha)
        end
      end

      # `git -C canonical/<slug> rev-parse HEAD`, read-only. nil when there is
      # no canonical dir, no clone, or the dir is not a git repo (rev-parse
      # fails → Shell::Error).
      def local_head(slug)
        return nil unless @canonical_dir

        dir = File.join(@canonical_dir, slug)
        return nil unless Dir.exist?(dir)

        sha = @shell.run("git", "-C", dir, "rev-parse", "HEAD").to_s.strip
        sha.empty? ? nil : sha
      rescue Nabu::Shell::Error
        nil
      end

      # The body-sha pin a ZipFetch/FileFetch state file recorded, at the same
      # <canonical_dir>/<slug>/<state_subdir>/<state_file> the drift probe reads
      # its Last-Modified from. nil when the state file is absent or its sha is
      # blank/unparseable.
      def state_file_sha(slug, target)
        return nil unless @canonical_dir

        path = File.join(@canonical_dir, slug, target.state_subdir, target.state_file)
        return nil unless File.file?(path)

        sha = JSON.parse(File.read(path))["sha256"]
        blank?(sha) ? nil : sha
      rescue JSON::ParserError
        nil
      end

      # P14-12: persist this run's verdict into the ledger's probe cache (one
      # upserted row per source), so `nabu status` can render the upstream
      # `up=…` column with no live network call — the informed-update signal.
      # No ledger (fresh machine, unit tests without one) → nothing to write.
      def persist(health, checked_at)
        return unless @ledger

        attrs = {
          checked_at: checked_at, drift: health.drift.to_s,
          license: health.license.status.to_s, detail: probe_detail(health)
        }
        row = Nabu::Store::Probe.first(source_slug: health.slug)
        row ? row.update(attrs) : Nabu::Store::Probe.create(attrs.merge(source_slug: health.slug))
      end

      # The one compact detail line the cache carries, mirroring what the CLI's
      # health_detail shows: a not-alive reason, the behind-repo offenders, or a
      # changed-license note — whichever is most salient; nil when the row is
      # clean. Kept short (it rides the terse status column's trailing context).
      def probe_detail(health)
        return health.liveness.detail if health.liveness.status != :alive && health.liveness.detail
        return health.drift_detail if %i[behind unpinned].include?(health.drift) && health.drift_detail
        return health.license.detail if health.license.status == :changed && health.license.detail

        nil
      end

      # HTTP client for the HTTP-zip probe: the SAME verified path ZipFetch
      # fetches through (system trust store PLUS the vendored InCommon
      # intermediate), because oracc.museum.upenn.edu serves an incomplete TLS
      # chain — a bare Faraday would fail verification exactly as sync did.
      def http_client = @http_client ||= Nabu::ZipFetch.default_http

      # One RepoProbe per upstream repo: its url, liveness, and HEAD sha (nil
      # when not alive).
      RepoProbe = Data.define(:url, :liveness, :head)
      private_constant :RepoProbe

      def probe_source(entry)
        case entry.adapter_class.remote_probe_strategy
        when :http_zip then probe_http_source(entry)
        else probe_git_source(entry)
        end
      end

      def probe_git_source(entry)
        urls = entry.adapter_class.upstream_repo_urls
        pins = pins_for(entry.slug)
        probes = urls.map { |url| probe_repo(url) }
        multi = probes.size > 1
        drift = source_drift(entry) { drift_status(probes, pins, multi: multi, no_pin: no_pin_verdict(entry)) }
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

      # Worst-wins ordering for a multi-repo source's per-repo drift. :unpinned
      # and :never_synced share a rank (both mean "no pin to compare"): the
      # verdict chosen for the no-pin case is decided by +no_pin_verdict+, not
      # by severity.
      DRIFT_SEVERITY = { behind: 3, unpinned: 2, never_synced: 2, unknown: 1, current: 0 }.freeze
      private_constant :DRIFT_SEVERITY

      # A frozen-policy source has no meaningful drift (we deliberately don't
      # re-sync it): short-circuit to :frozen so `health --remote` agrees with
      # `status`'s up=frozen column (P14-12/P15-7). Otherwise yield the computed
      # drift. Liveness and license are still probed as normal.
      def source_drift(entry)
        return Drift.new(status: :frozen, detail: nil) if frozen?(entry)

        yield
      end

      def frozen?(entry) = entry.sync_policy == "frozen"

      # The verdict a git/zip unit gets when it has no pin. Honest split
      # (P15-7): a source that HAS been synced (a run in the ledger, or a
      # canonical tree on disk) but carries no pin was fetched before the pins
      # ledger existed → :unpinned. One with no run AND no canonical tree is
      # genuinely :never_synced.
      def no_pin_verdict(entry)
        synced_before?(entry.slug) ? :unpinned : :never_synced
      end

      def synced_before?(slug)
        any_runs?(slug) || canonical_tree?(slug)
      end

      def any_runs?(slug)
        return false unless @ledger&.table_exists?(:runs)

        !Nabu::Store::Run.where(source_slug: slug).empty?
      end

      def canonical_tree?(slug)
        return false unless @canonical_dir

        dir = File.join(@canonical_dir, slug)
        Dir.exist?(dir) && !Dir.empty?(dir)
      end

      def drift_status(probes, pins, multi:, no_pin:)
        return single_repo_drift(probes.first, pins, no_pin) unless multi

        multi_repo_drift(probes, pins, no_pin)
      end

      # repo_drift already yields :unknown (not alive) / the no_pin verdict (no
      # pin) / :current / :behind — the single-repo status verbatim. An
      # :unpinned unit carries the honest pre-ledger hint.
      def single_repo_drift(probe, pins, no_pin)
        status = repo_drift(probe, pins[probe.url], no_pin)
        Drift.new(status: status, detail: status == :unpinned ? UNPINNED_HINT : nil)
      end

      # No per-repo pins yet → :multi (nothing to compare against until the next
      # sync records rows). Otherwise the worst per-repo drift wins, with the
      # :behind repos named in the detail.
      def multi_repo_drift(probes, pins, no_pin)
        return Drift.new(status: :multi, detail: "no per-repo pins yet — sync to record") if pins.empty?

        per_repo = probes.map { |probe| [probe, repo_drift(probe, pins[probe.url], no_pin)] }
        worst = per_repo.map { |_probe, status| status }.max_by { |status| DRIFT_SEVERITY.fetch(status) }
        behind = per_repo.select { |_probe, status| status == :behind }.map { |probe, _status| probe.url }
        Drift.new(status: worst, detail: behind.empty? ? nil : "behind: #{behind.join(', ')}")
      end

      def repo_drift(probe, pin, no_pin)
        return :unknown unless probe.liveness.status == :alive && probe.head
        return no_pin if pin.nil? || pin.last_sync_sha.nil? || pin.last_sync_sha.empty?

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

      # == HTTP-zip probe (P11-2) ============================================
      #
      # Mirrors the git path's SourceHealth shape from HEAD/GET instead of
      # ls-remote. One ZipProbe per project (its zip URL — also the ledger-pin
      # key), the HEAD reachability + Last-Modified, and the stored
      # .zip-fetch.json Last-Modified to diff against.
      ZipProbe = Data.define(:url, :label, :liveness, :remote_last_modified, :stored_last_modified, :metadata_url)
      private_constant :ZipProbe

      def probe_http_source(entry)
        targets = entry.adapter_class.http_probe_targets
        pins = pins_for(entry.slug)
        probes = targets.map { |target| probe_zip(entry.slug, target) }
        multi = probes.size > 1
        drift = source_drift(entry) { zip_drift(probes, multi: multi, no_pin: no_pin_verdict(entry)) }
        SourceHealth.new(
          slug: entry.slug, enabled: entry.enabled,
          upstream: multi ? "#{targets.size} projects" : targets.first&.zip_url,
          liveness: aggregate_liveness(probes),
          drift: drift.status, drift_detail: drift.detail,
          license: zip_license(probes, pins, multi: multi)
        )
      end

      def probe_zip(slug, target)
        stored = stored_last_modified(slug, target)
        liveness, last_modified = head_liveness(target.zip_url)
        ZipProbe.new(
          url: target.zip_url, label: target.label, liveness: liveness,
          remote_last_modified: last_modified, stored_last_modified: stored,
          metadata_url: target.metadata_url
        )
      end

      # HEAD the zip: 200 → alive (with its Last-Modified); a redirect →
      # :moved (a soft "your URL is stale" signal, like git's); anything else
      # (404/500/transport error) → :gone. ORACC serves 200 + Last-Modified
      # for a live project and 500 (not 404) for an unknown one (live
      # 2026-07-09), so any non-200/non-redirect is treated as gone.
      def head_liveness(url)
        response = http_client.head(url)
        case response.status
        when 200
          [Liveness.new(status: :alive, detail: nil), response.headers["last-modified"]]
        when 301, 302, 303, 307, 308
          [Liveness.new(status: :moved, detail: "http: #{response.status} #{url}"), nil]
        else
          [Liveness.new(status: :gone, detail: "http: #{response.status} #{url}"), nil]
        end
      rescue Faraday::Error => e
        [Liveness.new(status: :gone, detail: "http: #{e.message}"), nil]
      end

      # Per-project drift = HEAD Last-Modified vs the stored .zip-fetch.json
      # pin. No stored pin (never fetched) → :never_synced, reported as such,
      # not as drift. Not alive, or a HEAD that carried no Last-Modified →
      # :unknown (nothing to compare). Aggregated worst-wins like the git
      # multi-repo path; single-project sources leave the detail nil.
      def zip_drift(probes, multi:, no_pin:)
        return Drift.new(status: :unknown, detail: nil) if probes.empty?

        per_repo = probes.map { |probe| [probe, zip_repo_drift(probe, no_pin)] }
        worst = per_repo.map { |_probe, status| status }.max_by { |status| DRIFT_SEVERITY.fetch(status) }
        behind = per_repo.select { |_probe, status| status == :behind }.map { |probe, _status| probe.label }
        Drift.new(status: worst, detail: zip_drift_detail(worst, behind, multi: multi))
      end

      # Multi-unit: name the behind projects. Single-unit :unpinned: the honest
      # pre-ledger hint, exactly as the git single-repo path.
      def zip_drift_detail(worst, behind, multi:)
        return "behind: #{behind.join(', ')}" if multi && !behind.empty?
        return UNPINNED_HINT if !multi && worst == :unpinned

        nil
      end

      def zip_repo_drift(probe, no_pin)
        return :unknown unless probe.liveness.status == :alive
        return no_pin if blank?(probe.stored_last_modified)
        return :unknown if blank?(probe.remote_last_modified)

        probe.stored_last_modified == probe.remote_last_modified ? :current : :behind
      end

      # License drift, per project, aggregated exactly like multi_repo_license:
      # :changed if ANY project changed (offenders named), else
      # :baseline_recorded if any was newly recorded, else :unchanged if any
      # matched, else :unchecked. Baselines live on the ledger pins keyed by
      # zip URL — the SAME column and mechanism the git sources use.
      def zip_license(probes, pins, multi:)
        results = probes.map { |probe| [probe, zip_repo_license(probe, pins[probe.url])] }
        changed = results.select { |_probe, lic| lic.status == :changed }.map { |probe, _lic| probe.label }
        return License.new(status: :changed, detail: license_changed_detail(changed)) unless changed.empty?

        statuses = results.map { |_probe, lic| lic.status }
        return License.new(status: :baseline_recorded, detail: nil) if statuses.include?(:baseline_recorded)
        return License.new(status: :unchanged, detail: nil) if statuses.include?(:unchanged)

        unchecked(multi ? "http-zip" : "no license metadata")
      end

      # +row+ nil → never synced (no pin), so nothing is checkable — the probe
      # never mints pins itself. GET the small metadata.json and compare its
      # license field (hashed, mirroring the git license baseline) via the
      # shared compare_license, which records/updates the baseline on the pin.
      # Best-effort throughout: an unreachable upstream, an empty/non-JSON body
      # (ORACC's standalone metadata.json returns 200 with NO body live —
      # 2026-07-09), or a missing license field → :unchecked, never an error.
      def zip_repo_license(probe, row)
        return unchecked("upstream unreachable") unless probe.liveness.status == :alive
        return unchecked("never synced") unless row
        # No metadata endpoint at all (ASPR: the license lives inside the
        # fetched file) → honestly unchecked, no GET issued.
        return unchecked("no license metadata") unless probe.metadata_url

        license = fetch_license_field(probe.metadata_url)
        return unchecked("no license metadata") unless license

        compare_license(row, Digest::SHA256.hexdigest(license))
      end

      def fetch_license_field(url)
        response = http_client.get(url)
        return nil unless response.status == 200

        value = JSON.parse(response.body.to_s)["license"]
        blank?(value) ? nil : value.to_s
      rescue Faraday::Error, JSON::ParserError
        nil
      end

      # The stored Last-Modified pin for one probe target:
      # <canonical_dir>/<source-slug>/<state_subdir>/<state_file> — the
      # target names its state file (.zip-fetch.json for zip units,
      # .file-fetch.json for a FileFetch single-file source). Missing dir /
      # file / key (never synced) → nil.
      def stored_last_modified(slug, target)
        return nil unless @canonical_dir

        path = File.join(@canonical_dir, slug, target.state_subdir, target.state_file)
        return nil unless File.file?(path)

        JSON.parse(File.read(path))["last_modified"]
      rescue JSON::ParserError
        nil
      end

      def blank?(value) = value.nil? || value.to_s.empty?

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
