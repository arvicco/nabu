# frozen_string_literal: true

require "test_helper"
require "digest"
require "json"
require "fileutils"
require "tmpdir"

# Named adapters the probe resolves via SourceRegistry::Entry#adapter_class.
# They exist only to carry a manifest (and, for the multi-repo case, override
# .upstream_repo_urls) — discover/parse/fetch are never called by the probe.
class ProbeGithubAdapter < Nabu::Adapter
  MANIFEST = Nabu::SourceManifest.new(
    id: "probe-github", name: "Probe GitHub", license: "MIT", license_class: "open",
    upstream_url: "https://github.com/acme/widget", parser_family: "plaintext"
  )
  def self.manifest = MANIFEST
end

class ProbeNonGithubAdapter < Nabu::Adapter
  MANIFEST = Nabu::SourceManifest.new(
    id: "probe-nongithub", name: "Probe GitLab", license: "MIT", license_class: "open",
    upstream_url: "https://gitlab.example/acme/widget", parser_family: "plaintext"
  )
  def self.manifest = MANIFEST
end

class ProbeMultiAdapter < Nabu::Adapter
  MANIFEST = Nabu::SourceManifest.new(
    id: "probe-multi", name: "Probe Multi", license: "MIT", license_class: "open",
    upstream_url: "https://github.com/acme", parser_family: "plaintext"
  )
  def self.manifest = MANIFEST
  def self.upstream_repo_urls = %w[https://github.com/acme/one https://github.com/acme/two]
end

# An HTTP-zip source (ORACC shape, P11-2): the probe HEADs each project zip
# and GETs each metadata.json instead of ls-remote. Two projects → multi-unit.
class ProbeHttpZipAdapter < Nabu::Adapter
  MANIFEST = Nabu::SourceManifest.new(
    id: "probe-http", name: "Probe HTTP-zip", license: "CC0", license_class: "open",
    upstream_url: "https://oracc.example", parser_family: "oracc-json"
  )
  def self.manifest = MANIFEST
  def self.remote_probe_strategy = :http_zip

  def self.http_probe_targets
    %w[alpha beta].map do |project|
      Nabu::Adapter::HttpProbeTarget.new(
        label: project,
        zip_url: "https://oracc.example/json/#{project}.zip",
        metadata_url: "https://oracc.example/#{project}/metadata.json",
        state_subdir: project
      )
    end
  end
end

# The single-file HTTP shape (P12-2, ASPR): one FileFetch-backed unit whose
# state pin is .file-fetch.json at the workdir root (state_subdir "") and
# whose license lives INSIDE the fetched file — no metadata endpoint at all
# (metadata_url nil).
class ProbeHttpFileAdapter < Nabu::Adapter
  MANIFEST = Nabu::SourceManifest.new(
    id: "probe-file", name: "Probe HTTP-file", license: "CC BY-SA 3.0", license_class: "attribution",
    upstream_url: "https://ota.example/bitstream/3009.xml", parser_family: "aspr"
  )
  def self.manifest = MANIFEST
  def self.remote_probe_strategy = :http_zip

  def self.http_probe_targets
    [Nabu::Adapter::HttpProbeTarget.new(
      label: "3009.xml", zip_url: MANIFEST.upstream_url, metadata_url: nil,
      state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
    )]
  end
end

class RemoteProbeTest < Minitest::Test
  include StoreTestDB

  def setup
    # P7-1: pins + license baselines live in the history LEDGER, not the
    # catalog — the probe needs no catalog at all.
    @ledger = ledger_test_db
  end

  # A fake Nabu::Shell: keyed on the ls-remote URL (argv[2]). A stored
  # exception is raised (a dead remote); a String is returned as ls-remote
  # stdout.
  class FakeShell
    def initialize(map) = @map = map

    def run(*argv)
      response = @map.fetch(argv[2]) { raise "unexpected ls-remote #{argv[2].inspect}" }
      raise response if response.is_a?(Exception)

      response
    end
  end

  def shell_error(stderr, status: 128)
    Nabu::Shell::Error.new("command failed (exit #{status}): git", status: status, stderr: stderr)
  end

  def registry_of(*specs, policy: "manual")
    entries = specs.map do |slug, klass, enabled|
      Nabu::SourceRegistry::Entry.new(
        slug: slug, adapter_class_name: klass, enabled: enabled || enabled.nil?, sync_policy: policy
      )
    end
    Nabu::SourceRegistry.new(entries)
  end

  # A synced run in the ledger — one of the two "has been synced before" signals
  # (the other is a canonical tree on disk) the honest no-pin split reads.
  def seed_run(slug:, status: "succeeded")
    Nabu::Store::Run.create(source_slug: slug, kind: "sync", started_at: Time.now, status: status)
  end

  # A non-empty canonical tree for +slug+ under +root+ (the second "synced
  # before" signal), and — with git: true — a real local git clone so the
  # backfill's `git -C … rev-parse HEAD` reads a genuine sha (no network).
  def seed_canonical(root, slug, git: false)
    dir = File.join(root, slug)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "doc.txt"), "hello")
    return dir unless git

    Nabu::Shell.run("git", "-C", dir, "init", "-q")
    Nabu::Shell.run("git", "-C", dir, "add", ".")
    Nabu::Shell.run("git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
    dir
  end

  def head_sha(dir) = Nabu::Shell.run("git", "-C", dir, "rev-parse", "HEAD").strip

  # One ledger pin (P7-1): the unified per-repo pin/baseline row, single- and
  # multi-repo sources alike.
  def seed_pin(slug:, repo_url:, last_sync_sha: nil, license_baseline_sha256: nil)
    Nabu::Store::Pin.create(
      source_slug: slug, repo_url: repo_url,
      last_sync_sha: last_sync_sha, license_baseline_sha256: license_baseline_sha256
    )
  end

  def probe(registry, shell, canonical_dir: nil)
    Nabu::Health::RemoteProbe.new(
      registry: registry, ledger: @ledger, shell: shell, canonical_dir: canonical_dir
    ).run
  end

  # A shell that must never be consulted — the HTTP-zip path does no
  # ls-remote (a call means the strategy branch is wrong).
  NO_SHELL = FakeShell.new({})

  # Write a project's .zip-fetch.json Last-Modified pin the way ZipFetch does,
  # under <canonical>/<source-slug>/<project>/.
  def write_zip_state(canonical_dir, slug, subdir, last_modified)
    dir = File.join(canonical_dir, slug, subdir)
    FileUtils.mkdir_p(dir)
    File.write(
      File.join(dir, Nabu::ZipFetch::STATE_FILE),
      JSON.generate("last_modified" => last_modified, "sha256" => "z", "url" => "u")
    )
  end

  NONGITHUB_URL = "https://gitlab.example/acme/widget"
  GITHUB_URL = "https://github.com/acme/widget"

  # -- liveness + drift ----------------------------------------------------

  def test_alive_and_current_when_head_matches_last_sync_sha
    seed_pin(slug: "src", repo_url: NONGITHUB_URL, last_sync_sha: "sha111")
    shell = FakeShell.new("https://gitlab.example/acme/widget" => "sha111\tHEAD\n")
    row = probe(registry_of(["src", "ProbeNonGithubAdapter", true]), shell).rows.first

    assert_equal :alive, row.liveness.status
    assert_equal :current, row.drift
    assert_equal :unchecked, row.license.status # non-github → never an error
  end

  def test_alive_and_behind_when_head_moved_past_last_sync_sha
    seed_pin(slug: "src", repo_url: NONGITHUB_URL, last_sync_sha: "old000")
    shell = FakeShell.new("https://gitlab.example/acme/widget" => "new999\tHEAD\n")
    row = probe(registry_of(["src", "ProbeNonGithubAdapter", true]), shell).rows.first

    assert_equal :alive, row.liveness.status
    assert_equal :behind, row.drift
  end

  def test_never_synced_when_no_row_or_no_last_sync_sha
    seed_pin(slug: "with-row", repo_url: NONGITHUB_URL, last_sync_sha: nil)
    shell = FakeShell.new(
      "https://gitlab.example/acme/widget" => "sha\tHEAD\n"
    )
    report = probe(registry_of(
                     ["with-row", "ProbeNonGithubAdapter", true],
                     ["no-row", "ProbeNonGithubAdapter", false]
                   ), shell)

    assert_equal :never_synced, report.rows[0].drift, "row present but last_sync_sha nil"
    assert_equal :never_synced, report.rows[1].drift, "no catalog row at all"
  end

  def test_gone_when_ls_remote_fails_and_sets_exit_flag
    seed_pin(slug: "src", repo_url: NONGITHUB_URL, last_sync_sha: "x")
    shell = FakeShell.new(
      "https://gitlab.example/acme/widget" => shell_error("remote: Repository not found.\nfatal: not found")
    )
    report = probe(registry_of(["src", "ProbeNonGithubAdapter", true]), shell)
    row = report.rows.first

    assert_equal :gone, row.liveness.status
    assert_match(/Repository not found/, row.liveness.detail)
    assert_equal :unknown, row.drift
    assert report.any_gone?
  end

  def test_moved_when_git_reports_a_redirect_not_a_plain_failure
    seed_pin(slug: "src", repo_url: NONGITHUB_URL, last_sync_sha: "x")
    shell = FakeShell.new(
      "https://gitlab.example/acme/widget" =>
        shell_error("fatal: unable to access '...': The requested URL returned error: 301 Moved Permanently")
    )
    report = probe(registry_of(["src", "ProbeNonGithubAdapter", true]), shell)

    assert_equal :moved, report.rows.first.liveness.status
    refute report.any_gone?, "moved is a soft signal, not a gone upstream"
  end

  # -- license drift (WebMock; never real network) -------------------------

  LICENSE_BODY = "MIT License\n\nCopyright (c) 2026\n"

  def stub_github_alive
    FakeShell.new("https://github.com/acme/widget" => "deadbeef\tHEAD\n")
  end

  def raw_url(name) = "https://raw.githubusercontent.com/acme/widget/deadbeef/#{name}"

  def test_license_baseline_recorded_on_first_probe
    seed_pin(slug: "gh", repo_url: GITHUB_URL, last_sync_sha: "deadbeef")
    stub_request(:get, raw_url("LICENSE")).to_return(status: 200, body: LICENSE_BODY)
    row = probe(registry_of(["gh", "ProbeGithubAdapter", true]), stub_github_alive).rows.first

    assert_equal :baseline_recorded, row.license.status
    stored = Nabu::Store::Pin.first(source_slug: "gh").license_baseline_sha256
    assert_equal Digest::SHA256.hexdigest(LICENSE_BODY), stored
  end

  def test_license_unchanged_when_hash_matches_stored_baseline
    seed_pin(slug: "gh", repo_url: GITHUB_URL, last_sync_sha: "deadbeef",
             license_baseline_sha256: Digest::SHA256.hexdigest(LICENSE_BODY))
    stub_request(:get, raw_url("LICENSE")).to_return(status: 200, body: LICENSE_BODY)
    row = probe(registry_of(["gh", "ProbeGithubAdapter", true]), stub_github_alive).rows.first

    assert_equal :unchanged, row.license.status
  end

  def test_license_changed_when_hash_differs_from_baseline
    seed_pin(slug: "gh", repo_url: GITHUB_URL, last_sync_sha: "deadbeef",
             license_baseline_sha256: "00baseline00")
    stub_request(:get, raw_url("LICENSE")).to_return(status: 200, body: LICENSE_BODY)
    row = probe(registry_of(["gh", "ProbeGithubAdapter", true]), stub_github_alive).rows.first

    assert_equal :changed, row.license.status
    assert_match(/review upstream/i, row.license.detail)
  end

  def test_license_falls_back_through_filenames_then_unchecked_when_absent
    seed_pin(slug: "gh", repo_url: GITHUB_URL, last_sync_sha: "deadbeef")
    Nabu::Health::RemoteProbe::LICENSE_FILENAMES.each do |name|
      stub_request(:get, raw_url(name)).to_return(status: 404)
    end
    row = probe(registry_of(["gh", "ProbeGithubAdapter", true]), stub_github_alive).rows.first

    assert_equal :unchecked, row.license.status
  end

  def test_license_uses_copying_when_that_is_the_only_file
    seed_pin(slug: "gh", repo_url: GITHUB_URL, last_sync_sha: "deadbeef")
    Nabu::Health::RemoteProbe::LICENSE_FILENAMES.each do |name|
      status = name == "COPYING" ? { status: 200, body: LICENSE_BODY } : { status: 404 }
      stub_request(:get, raw_url(name)).to_return(status)
    end
    row = probe(registry_of(["gh", "ProbeGithubAdapter", true]), stub_github_alive).rows.first

    assert_equal :baseline_recorded, row.license.status
  end

  # PerseusDL and First1KGreek name theirs lowercase "license.md" — found on
  # the live upstreams, so the list must carry the lowercase variants too.
  def test_license_finds_lowercase_license_md
    seed_pin(slug: "gh", repo_url: GITHUB_URL, last_sync_sha: "deadbeef")
    Nabu::Health::RemoteProbe::LICENSE_FILENAMES.each do |name|
      status = name == "license.md" ? { status: 200, body: LICENSE_BODY } : { status: 404 }
      stub_request(:get, raw_url(name)).to_return(status)
    end
    row = probe(registry_of(["gh", "ProbeGithubAdapter", true]), stub_github_alive).rows.first

    assert_equal :baseline_recorded, row.license.status
  end

  # -- license_watch (P16-5; WebMock, never real network) -------------------

  WATCH_URL = "https://repo.example/record/11356/1025"
  WATCH_BODY = "Licence: CC-BY 4.0\nAttribution: CCMH\n"

  # A non-github source (whose default license path is a silent :unchecked)
  # with a configured watch url — the escape hatch the key exists for.
  def watch_registry(adapter: "ProbeNonGithubAdapter")
    entry = Nabu::SourceRegistry::Entry.new(
      slug: "wsrc", adapter_class_name: adapter, enabled: true,
      sync_policy: "manual", license_watch: WATCH_URL
    )
    Nabu::SourceRegistry.new([entry])
  end

  def alive_nongithub_shell = FakeShell.new(NONGITHUB_URL => "sha\tHEAD\n")

  def test_license_watch_records_baseline_on_first_sight
    stub_request(:get, WATCH_URL).to_return(status: 200, body: WATCH_BODY)
    row = probe(watch_registry, alive_nongithub_shell).rows.first

    assert_equal :baseline_recorded, row.license.status
    pin = Nabu::Store::Pin.first(source_slug: "wsrc", repo_url: WATCH_URL)
    assert_equal Digest::SHA256.hexdigest(WATCH_BODY), pin.license_baseline_sha256
    assert_nil pin.last_sync_sha, "a watch pin is baseline-only — the drift check never reads it"
  end

  def test_license_watch_unchanged_when_hash_matches_baseline
    seed_pin(slug: "wsrc", repo_url: WATCH_URL,
             license_baseline_sha256: Digest::SHA256.hexdigest(WATCH_BODY))
    stub_request(:get, WATCH_URL).to_return(status: 200, body: WATCH_BODY)
    row = probe(watch_registry, alive_nongithub_shell).rows.first

    assert_equal :unchanged, row.license.status # renders "license: ok"
  end

  def test_license_watch_changed_names_the_watched_url
    seed_pin(slug: "wsrc", repo_url: WATCH_URL, license_baseline_sha256: "00stale00")
    stub_request(:get, WATCH_URL).to_return(status: 200, body: WATCH_BODY)
    row = probe(watch_registry, alive_nongithub_shell).rows.first

    assert_equal :changed, row.license.status # renders "license: CHANGED"
    assert_includes row.license.detail, WATCH_URL
  end

  # Best-effort contract: a non-200, or a transport error, reads :unchecked
  # (silent per P16-0) and never raises out of the probe.
  def test_license_watch_fetch_failure_reads_unchecked_never_raises
    seed_pin(slug: "wsrc", repo_url: WATCH_URL, license_baseline_sha256: "00baseline00")
    stub_request(:get, WATCH_URL).to_return(status: 500)
    assert_equal :unchecked, probe(watch_registry, alive_nongithub_shell).rows.first.license.status

    stub_request(:get, WATCH_URL).to_timeout
    row = probe(watch_registry, alive_nongithub_shell).rows.first
    assert_equal :unchecked, row.license.status
    assert_equal "00baseline00",
                 Nabu::Store::Pin.first(source_slug: "wsrc", repo_url: WATCH_URL).license_baseline_sha256,
                 "a failed fetch must not touch the stored baseline"
  end

  # The watch REPLACES the github license-file path: no raw.githubusercontent
  # GET is stubbed, so any attempt would fail the test under WebMock.
  def test_license_watch_overrides_the_github_license_file_path
    seed_pin(slug: "wsrc", repo_url: GITHUB_URL, last_sync_sha: "deadbeef")
    stub_request(:get, WATCH_URL).to_return(status: 200, body: WATCH_BODY)
    shell = FakeShell.new(GITHUB_URL => "deadbeef\tHEAD\n")
    row = probe(watch_registry(adapter: "ProbeGithubAdapter"), shell).rows.first

    assert_equal :baseline_recorded, row.license.status
  end

  # Same override on the http-zip strategy: the metadata.json GETs are not
  # stubbed, so reaching them would fail under WebMock.
  def test_license_watch_overrides_the_http_zip_metadata_path
    stub_zip_head(ALPHA_ZIP, last_modified: LM_OLD)
    stub_zip_head(BETA_ZIP, last_modified: LM_OLD)
    stub_request(:get, WATCH_URL).to_return(status: 200, body: WATCH_BODY)
    row = probe(watch_registry(adapter: "ProbeHttpZipAdapter"), NO_SHELL).rows.first

    assert_equal :baseline_recorded, row.license.status
  end

  def test_license_watch_without_a_ledger_reads_unchecked
    stub_request(:get, WATCH_URL).to_return(status: 200, body: WATCH_BODY)
    report = Nabu::Health::RemoteProbe.new(
      registry: watch_registry, ledger: nil, shell: alive_nongithub_shell
    ).run
    assert_equal :unchecked, report.rows.first.license.status
  end

  # -- multi-repo (UD shape) ----------------------------------------------

  # A multi-repo source with NO per-repo pins yet (never synced under P6-3)
  # still reads :multi / :unchecked — there is nothing per-repo to compare
  # against until the next sync records ledger pins.
  def test_multi_repo_all_alive_but_unpinned_marks_drift_multi
    shell = FakeShell.new(
      "https://github.com/acme/one" => "aaa\tHEAD\n",
      "https://github.com/acme/two" => "bbb\tHEAD\n"
    )
    row = probe(registry_of(["multi", "ProbeMultiAdapter", true]), shell).rows.first

    assert_equal :alive, row.liveness.status
    assert_equal :multi, row.drift
    assert_equal :unchecked, row.license.status
  end

  # Stub every license-filename lookup for owner/repo at +sha+ to 404, so a
  # drift-focused multi-repo test's license pass reaches :unchecked without
  # touching the network (each pinned github repo is still license-probed).
  def stub_no_license(owner, repo, sha)
    Nabu::Health::RemoteProbe::LICENSE_FILENAMES.each do |name|
      stub_request(:get, "https://raw.githubusercontent.com/#{owner}/#{repo}/#{sha}/#{name}").to_return(status: 404)
    end
  end

  # P6-3: with per-repo pins, drift is computed PER REPO — one behind, one
  # current → source-level :behind (worst wins), the behind repo named.
  def test_multi_repo_per_repo_drift_one_behind_one_current
    seed_pin(slug: "multi", repo_url: "https://github.com/acme/one", last_sync_sha: "aaa")
    seed_pin(slug: "multi", repo_url: "https://github.com/acme/two", last_sync_sha: "old")
    shell = FakeShell.new(
      "https://github.com/acme/one" => "aaa\tHEAD\n", # current
      "https://github.com/acme/two" => "new\tHEAD\n"  # behind (moved past pin)
    )
    stub_no_license("acme", "one", "aaa")
    stub_no_license("acme", "two", "new")
    row = probe(registry_of(["multi", "ProbeMultiAdapter", true]), shell).rows.first

    assert_equal :alive, row.liveness.status
    assert_equal :behind, row.drift
    assert_match(%r{acme/two}, row.drift_detail)
    refute_match(%r{acme/one}, row.drift_detail.to_s)
  end

  def test_multi_repo_all_repos_current_reads_current
    seed_pin(slug: "multi", repo_url: "https://github.com/acme/one", last_sync_sha: "aaa")
    seed_pin(slug: "multi", repo_url: "https://github.com/acme/two", last_sync_sha: "bbb")
    shell = FakeShell.new(
      "https://github.com/acme/one" => "aaa\tHEAD\n",
      "https://github.com/acme/two" => "bbb\tHEAD\n"
    )
    stub_no_license("acme", "one", "aaa")
    stub_no_license("acme", "two", "bbb")
    row = probe(registry_of(["multi", "ProbeMultiAdapter", true]), shell).rows.first

    assert_equal :current, row.drift
    assert_nil row.drift_detail
  end

  # Per-repo license baselines live on the ledger pins. One repo's
  # license changed vs its stored baseline → source-level :changed, named.
  def test_multi_repo_per_repo_license_one_changed
    seed_pin(slug: "multi", repo_url: "https://github.com/acme/one", last_sync_sha: "aaa",
             license_baseline_sha256: Digest::SHA256.hexdigest(LICENSE_BODY))
    seed_pin(slug: "multi", repo_url: "https://github.com/acme/two", last_sync_sha: "bbb",
             license_baseline_sha256: "00stale00")
    shell = FakeShell.new(
      "https://github.com/acme/one" => "aaa\tHEAD\n",
      "https://github.com/acme/two" => "bbb\tHEAD\n"
    )
    stub_request(:get, "https://raw.githubusercontent.com/acme/one/aaa/LICENSE")
      .to_return(status: 200, body: LICENSE_BODY)
    stub_request(:get, "https://raw.githubusercontent.com/acme/two/bbb/LICENSE")
      .to_return(status: 200, body: LICENSE_BODY) # differs from "00stale00" → changed
    row = probe(registry_of(["multi", "ProbeMultiAdapter", true]), shell).rows.first

    assert_equal :changed, row.license.status
    assert_match(%r{acme/two}, row.license.detail)
  end

  # A newly-recorded baseline on any repo (none changed) reads :baseline_recorded
  # and the sha lands on that repo's row.
  def test_multi_repo_per_repo_license_baseline_recorded
    seed_pin(slug: "multi", repo_url: "https://github.com/acme/one", last_sync_sha: "aaa",
             license_baseline_sha256: Digest::SHA256.hexdigest(LICENSE_BODY))
    seed_pin(slug: "multi", repo_url: "https://github.com/acme/two", last_sync_sha: "bbb") # no baseline yet
    shell = FakeShell.new(
      "https://github.com/acme/one" => "aaa\tHEAD\n",
      "https://github.com/acme/two" => "bbb\tHEAD\n"
    )
    stub_request(:get, "https://raw.githubusercontent.com/acme/one/aaa/LICENSE")
      .to_return(status: 200, body: LICENSE_BODY)
    stub_request(:get, "https://raw.githubusercontent.com/acme/two/bbb/LICENSE")
      .to_return(status: 200, body: LICENSE_BODY)
    row = probe(registry_of(["multi", "ProbeMultiAdapter", true]), shell).rows.first

    assert_equal :baseline_recorded, row.license.status
    stored = Nabu::Store::Pin.first(repo_url: "https://github.com/acme/two").license_baseline_sha256
    assert_equal Digest::SHA256.hexdigest(LICENSE_BODY), stored
  end

  def test_multi_repo_one_gone_makes_the_source_gone
    shell = FakeShell.new(
      "https://github.com/acme/one" => "aaa\tHEAD\n",
      "https://github.com/acme/two" => shell_error("remote: Repository not found.")
    )
    report = probe(registry_of(["multi", "ProbeMultiAdapter", true]), shell)

    assert_equal :gone, report.rows.first.liveness.status
    assert report.any_gone?
    assert_match(%r{acme/two}, report.rows.first.liveness.detail)
  end

  # -- disabled sources are probed too ------------------------------------

  def test_disabled_source_is_still_probed
    seed_pin(slug: "src", repo_url: NONGITHUB_URL, last_sync_sha: "sha")
    shell = FakeShell.new("https://gitlab.example/acme/widget" => "sha\tHEAD\n")
    row = probe(registry_of(["src", "ProbeNonGithubAdapter", false]), shell).rows.first

    refute row.enabled
    assert_equal :alive, row.liveness.status
  end

  def test_upstream_repo_urls_defaults_to_manifest_url
    assert_equal ["https://github.com/acme/widget"], ProbeGithubAdapter.upstream_repo_urls
  end

  # -- HTTP-zip probe (P11-2; ORACC shape) --------------------------------
  #
  # Honest live shapes recorded 2026-07-09 against oracc.museum.upenn.edu and
  # replayed here as stubs: a live project zip HEADs 200 + Last-Modified (e.g.
  # rimanum.zip → "Fri, 28 Jun 2024 12:46:37 GMT"); an unknown project HEADs
  # 500 (not 404); the standalone /<project>/metadata.json GETs 200 but with
  # an EMPTY body over HTTP (the real license lives inside the zip), so the
  # license check degrades to :unchecked live — proven by
  # test_http_zip_license_unchecked_when_metadata_body_empty. The metadata
  # JSON shape used below (license field verbatim) is the ORACC build's, per
  # the Oracc adapter class note and P9-5a scouting.

  ALPHA_ZIP = "https://oracc.example/json/alpha.zip"
  BETA_ZIP = "https://oracc.example/json/beta.zip"
  ALPHA_META = "https://oracc.example/alpha/metadata.json"
  BETA_META = "https://oracc.example/beta/metadata.json"
  LM_OLD = "Fri, 28 Jun 2024 12:46:37 GMT"
  LM_NEW = "Wed, 14 Aug 2024 14:47:17 GMT"
  CC0_STRING = "This data is released under the CC0 license"
  META_CC0 = JSON.generate(
    "license" => CC0_STRING,
    "license-url" => "https://creativecommons.org/publicdomain/zero/1.0/"
  )

  def http_registry = registry_of(["orx", "ProbeHttpZipAdapter", true])

  def stub_zip_head(url, last_modified: LM_OLD, status: 200)
    headers = last_modified ? { "Last-Modified" => last_modified } : {}
    stub_request(:head, url).to_return(status: status, headers: headers)
  end

  def test_http_zip_reachable_and_current_when_last_modified_matches
    Dir.mktmpdir do |root|
      write_zip_state(root, "orx", "alpha", LM_OLD)
      write_zip_state(root, "orx", "beta", LM_OLD)
      stub_zip_head(ALPHA_ZIP, last_modified: LM_OLD)
      stub_zip_head(BETA_ZIP, last_modified: LM_OLD)
      row = probe(http_registry, NO_SHELL, canonical_dir: root).rows.first

      assert_equal :alive, row.liveness.status
      assert_equal :current, row.drift
      assert_nil row.drift_detail
    end
  end

  def test_http_zip_behind_when_upstream_last_modified_moved
    Dir.mktmpdir do |root|
      write_zip_state(root, "orx", "alpha", LM_OLD)
      write_zip_state(root, "orx", "beta", LM_OLD)
      stub_zip_head(ALPHA_ZIP, last_modified: LM_NEW) # upstream moved
      stub_zip_head(BETA_ZIP, last_modified: LM_OLD)  # current
      row = probe(http_registry, NO_SHELL, canonical_dir: root).rows.first

      assert_equal :alive, row.liveness.status
      assert_equal :behind, row.drift
      assert_match(/alpha/, row.drift_detail)
      refute_match(/beta/, row.drift_detail.to_s)
    end
  end

  # Acceptance: an unsynced project is reported never-synced, NOT gone and NOT
  # false drift. No pins, no state files → no metadata GET is even issued.
  def test_http_zip_never_synced_reads_never_synced_not_gone
    Dir.mktmpdir do |root|
      stub_zip_head(ALPHA_ZIP, last_modified: LM_NEW)
      stub_zip_head(BETA_ZIP, last_modified: LM_NEW)
      report = probe(http_registry, NO_SHELL, canonical_dir: root)
      row = report.rows.first

      assert_equal :alive, row.liveness.status
      assert_equal :never_synced, row.drift
      assert_equal :unchecked, row.license.status
      refute report.any_gone?
    end
  end

  def test_http_zip_gone_when_a_project_head_returns_server_error
    Dir.mktmpdir do |root|
      stub_zip_head(ALPHA_ZIP, last_modified: LM_OLD)
      stub_zip_head(BETA_ZIP, status: 500, last_modified: nil) # ORACC's unknown-project shape
      report = probe(http_registry, NO_SHELL, canonical_dir: root)
      row = report.rows.first

      assert_equal :gone, row.liveness.status
      assert_match(/beta\.zip/, row.liveness.detail)
      assert report.any_gone?
    end
  end

  def test_http_zip_license_baseline_recorded_and_hash_stored_on_pin
    Dir.mktmpdir do |root|
      seed_pin(slug: "orx", repo_url: ALPHA_ZIP, last_sync_sha: "s1")
      seed_pin(slug: "orx", repo_url: BETA_ZIP, last_sync_sha: "s2")
      write_zip_state(root, "orx", "alpha", LM_OLD)
      write_zip_state(root, "orx", "beta", LM_OLD)
      stub_zip_head(ALPHA_ZIP, last_modified: LM_OLD)
      stub_zip_head(BETA_ZIP, last_modified: LM_OLD)
      stub_request(:get, ALPHA_META).to_return(status: 200, body: META_CC0)
      stub_request(:get, BETA_META).to_return(status: 200, body: META_CC0)
      row = probe(http_registry, NO_SHELL, canonical_dir: root).rows.first

      assert_equal :baseline_recorded, row.license.status
      stored = Nabu::Store::Pin.first(repo_url: ALPHA_ZIP).license_baseline_sha256
      assert_equal Digest::SHA256.hexdigest(CC0_STRING), stored
    end
  end

  def test_http_zip_license_unchanged_when_field_matches_baseline
    seed_pin(slug: "orx", repo_url: ALPHA_ZIP, last_sync_sha: "s1",
             license_baseline_sha256: Digest::SHA256.hexdigest(CC0_STRING))
    seed_pin(slug: "orx", repo_url: BETA_ZIP, last_sync_sha: "s2",
             license_baseline_sha256: Digest::SHA256.hexdigest(CC0_STRING))
    stub_zip_head(ALPHA_ZIP)
    stub_zip_head(BETA_ZIP)
    stub_request(:get, ALPHA_META).to_return(status: 200, body: META_CC0)
    stub_request(:get, BETA_META).to_return(status: 200, body: META_CC0)
    row = probe(http_registry, NO_SHELL).rows.first

    assert_equal :unchanged, row.license.status
  end

  def test_http_zip_license_changed_when_field_differs_from_baseline
    seed_pin(slug: "orx", repo_url: ALPHA_ZIP, last_sync_sha: "s1",
             license_baseline_sha256: "00stale00")
    seed_pin(slug: "orx", repo_url: BETA_ZIP, last_sync_sha: "s2",
             license_baseline_sha256: Digest::SHA256.hexdigest(CC0_STRING))
    stub_zip_head(ALPHA_ZIP)
    stub_zip_head(BETA_ZIP)
    stub_request(:get, ALPHA_META).to_return(status: 200, body: META_CC0)
    stub_request(:get, BETA_META).to_return(status: 200, body: META_CC0)
    row = probe(http_registry, NO_SHELL).rows.first

    assert_equal :changed, row.license.status
    assert_match(/alpha/, row.license.detail)
  end

  # Live reality: the standalone metadata.json returns 200 with an EMPTY body,
  # so the license field is unreadable without the zip → best-effort :unchecked
  # (never an error). Same outcome for a 304, which the plain HEAD never asks
  # for and the GET path treats as non-200.
  def test_http_zip_license_unchecked_when_metadata_body_empty
    seed_pin(slug: "orx", repo_url: ALPHA_ZIP, last_sync_sha: "s1")
    seed_pin(slug: "orx", repo_url: BETA_ZIP, last_sync_sha: "s2")
    stub_zip_head(ALPHA_ZIP)
    stub_zip_head(BETA_ZIP)
    stub_request(:get, ALPHA_META).to_return(status: 200, body: "")
    stub_request(:get, BETA_META).to_return(status: 200, body: "")
    row = probe(http_registry, NO_SHELL).rows.first

    assert_equal :unchecked, row.license.status
  end

  # -- HTTP single-file probe (P12-2; ASPR shape) --------------------------

  FILE_URL = "https://ota.example/bitstream/3009.xml"

  def file_registry = registry_of(["asx", "ProbeHttpFileAdapter", false])

  # The FileFetch pin (.file-fetch.json at the workdir ROOT — state_subdir
  # "") drives drift exactly as a zip unit's does.
  def test_http_file_current_when_file_fetch_pin_matches
    Dir.mktmpdir do |root|
      dir = File.join(root, "asx")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, Nabu::FileFetch::STATE_FILE),
                 JSON.generate("last_modified" => LM_OLD, "sha256" => "f", "url" => FILE_URL))
      stub_zip_head(FILE_URL, last_modified: LM_OLD)
      row = probe(file_registry, NO_SHELL, canonical_dir: root).rows.first

      assert_equal :alive, row.liveness.status
      assert_equal :current, row.drift
    end
  end

  # metadata_url nil (the license lives in the fetched file) → the license
  # row is honestly unchecked and NO metadata GET is issued (WebMock would
  # fail the test on any unstubbed request).
  def test_http_file_license_unchecked_without_a_metadata_get
    seed_pin(slug: "asx", repo_url: FILE_URL, last_sync_sha: "s1")
    stub_zip_head(FILE_URL, last_modified: LM_OLD)
    row = probe(file_registry, NO_SHELL).rows.first

    assert_equal :alive, row.liveness.status
    assert_equal :unchecked, row.license.status
  end

  # The whole point: the REAL Oracc adapter, registered as a source, is probed
  # over HTTP and reads alive (never-synced), NOT the pre-P11-2 false "gone".
  def test_real_oracc_adapter_probes_over_http_and_is_not_gone
    Dir.mktmpdir do |root|
      Nabu::Adapters::Oracc::PROJECTS.each do |project|
        stub_zip_head("https://oracc.museum.upenn.edu/json/#{project.tr('/', '-')}.zip", last_modified: LM_OLD)
      end
      report = probe(registry_of(["oracc", "Nabu::Adapters::Oracc", true]), NO_SHELL, canonical_dir: root)
      row = report.rows.first

      assert_equal :alive, row.liveness.status
      assert_equal :never_synced, row.drift
      refute report.any_gone?
    end
  end

  # -- P14-12: probe-verdict persistence (the status upstream cache) --------

  # Every run writes one source_probes row per source with the drift/license
  # verdicts and a checked_at, so `nabu status` can render up=… with no probe.
  def test_persists_a_probe_row_per_source
    seed_pin(slug: "src", repo_url: NONGITHUB_URL, last_sync_sha: "sha111")
    before = Time.now - 1
    probe(registry_of(["src", "ProbeNonGithubAdapter", true]),
          FakeShell.new(NONGITHUB_URL => "sha111\tHEAD\n"))

    row = Nabu::Store::Probe.first(source_slug: "src")
    refute_nil row, "a probe row must be persisted"
    assert_equal "current", row.drift
    assert_equal "unchecked", row.license # non-github → best-effort unchecked
    assert_operator row.checked_at, :>=, before, "checked_at is recorded"
  end

  # The cache is one row per source, upserted — a second run overwrites the
  # verdict and checked_at, never duplicates the row.
  def test_persist_upserts_one_row_per_source
    seed_pin(slug: "src", repo_url: NONGITHUB_URL, last_sync_sha: "sha111")
    reg = registry_of(["src", "ProbeNonGithubAdapter", true])
    probe(reg, FakeShell.new(NONGITHUB_URL => "sha111\tHEAD\n")) # current

    # Move our pin behind upstream, re-probe: same row, new verdict.
    Nabu::Store::Pin.first(source_slug: "src").update(last_sync_sha: "old000")
    probe(reg, FakeShell.new(NONGITHUB_URL => "new999\tHEAD\n")) # behind

    rows = Nabu::Store::Probe.where(source_slug: "src").all
    assert_equal 1, rows.size, "upsert keeps exactly one row per source"
    assert_equal "behind", rows.first.drift
  end

  # A not-alive source persists the liveness reason in detail (the status
  # column's trailing context) with an indeterminate (unknown) drift.
  def test_persists_detail_from_a_gone_upstream
    seed_pin(slug: "src", repo_url: NONGITHUB_URL, last_sync_sha: "x")
    probe(registry_of(["src", "ProbeNonGithubAdapter", true]),
          FakeShell.new(NONGITHUB_URL => shell_error("remote: Repository not found.")))

    row = Nabu::Store::Probe.first(source_slug: "src")
    assert_equal "unknown", row.drift
    assert_match(/Repository not found/, row.detail)
  end

  # No ledger (fresh machine / unit run without one) → persistence is silently
  # skipped, the probe still returns its report.
  def test_persistence_skipped_without_a_ledger
    shell = FakeShell.new(NONGITHUB_URL => "sha\tHEAD\n")
    report = Nabu::Health::RemoteProbe.new(
      registry: registry_of(["src", "ProbeNonGithubAdapter", true]), ledger: nil, shell: shell
    ).run
    assert_equal :alive, report.rows.first.liveness.status
  end

  # -- P15-7: honest no-pin labels (unpinned vs never-synced) --------------

  # No pin, but a canonical tree exists → the source WAS synced before the pins
  # ledger existed (P7): :unpinned, with the honest pre-ledger hint — NOT the
  # false "never-synced" of the owner defect (proiel/torot/papyri-ddbdp).
  def test_no_pin_reads_unpinned_when_a_canonical_tree_exists
    Dir.mktmpdir do |root|
      seed_canonical(root, "src")
      shell = FakeShell.new(NONGITHUB_URL => "sha111\tHEAD\n")
      row = probe(registry_of(["src", "ProbeNonGithubAdapter", true]), shell, canonical_dir: root).rows.first

      assert_equal :unpinned, row.drift
      assert_match(/synced pre-ledger/, row.drift_detail)
      assert_match(/health --backfill-pins/, row.drift_detail)
    end
  end

  # The other "synced before" signal: a run in the ledger, no canonical dir.
  def test_no_pin_reads_unpinned_when_a_run_is_in_the_ledger
    seed_run(slug: "src")
    shell = FakeShell.new(NONGITHUB_URL => "sha111\tHEAD\n")
    row = probe(registry_of(["src", "ProbeNonGithubAdapter", true]), shell).rows.first

    assert_equal :unpinned, row.drift
  end

  # Truly untouched: no pin, no run, no canonical tree → :never_synced stays.
  def test_no_pin_reads_never_synced_without_a_run_or_tree
    Dir.mktmpdir do |root|
      shell = FakeShell.new(NONGITHUB_URL => "sha111\tHEAD\n")
      row = probe(registry_of(["src", "ProbeNonGithubAdapter", true]), shell, canonical_dir: root).rows.first

      assert_equal :never_synced, row.drift
      assert_nil row.drift_detail
    end
  end

  # The unpinned verdict + hint are cached (the status up= detail "follows
  # suit" — MCP/status read the cached row).
  def test_persists_unpinned_verdict_and_hint
    seed_run(slug: "src")
    probe(registry_of(["src", "ProbeNonGithubAdapter", true]),
          FakeShell.new(NONGITHUB_URL => "sha111\tHEAD\n"))

    row = Nabu::Store::Probe.first(source_slug: "src")
    assert_equal "unpinned", row.drift
    assert_match(/synced pre-ledger/, row.detail)
  end

  # -- P15-7: frozen-policy agreement --------------------------------------

  # A frozen-policy source reads drift :frozen in health --remote, agreeing
  # with status's up=frozen (P14-12) — even when a pin sits behind upstream,
  # the frozen verdict overrides (we deliberately don't re-sync it).
  def test_frozen_policy_source_reads_frozen_drift
    seed_pin(slug: "src", repo_url: NONGITHUB_URL, last_sync_sha: "old000")
    shell = FakeShell.new(NONGITHUB_URL => "new999\tHEAD\n") # would be :behind if not frozen
    row = probe(registry_of(["src", "ProbeNonGithubAdapter", true], policy: "frozen"), shell).rows.first

    assert_equal :alive, row.liveness.status, "liveness is still probed"
    assert_equal :frozen, row.drift
  end

  def test_frozen_verdict_is_persisted_to_the_probe_cache
    shell = FakeShell.new(NONGITHUB_URL => "new999\tHEAD\n")
    probe(registry_of(["src", "ProbeNonGithubAdapter", true], policy: "frozen"), shell)

    assert_equal "frozen", Nabu::Store::Probe.first(source_slug: "src").drift
  end

  # -- P15-7: pin backfill --------------------------------------------------

  def backfiller(registry, shell: Nabu::Shell, canonical_dir: nil)
    Nabu::Health::RemoteProbe.new(
      registry: registry, ledger: @ledger, shell: shell, canonical_dir: canonical_dir
    )
  end

  # A git source with a canonical clone but no pin → the clone's HEAD is
  # recorded as last_sync_sha, keyed by the source's one declared repo URL.
  def test_backfill_records_pin_from_a_git_clone
    Dir.mktmpdir do |root|
      dir = seed_canonical(root, "gh", git: true)
      recorded = backfiller(registry_of(["gh", "ProbeGithubAdapter", true]), canonical_dir: root).backfill_pins

      assert_equal 1, recorded.size
      assert_equal :git_clone, recorded.first.origin
      pin = Nabu::Store::Pin.first(source_slug: "gh", repo_url: GITHUB_URL)
      assert_equal head_sha(dir), pin.last_sync_sha
    end
  end

  # A non-git ZipFetch source: each project's .zip-fetch.json sha256 pin is
  # recorded, keyed by the project zip URL.
  def test_backfill_records_pins_from_zip_state_files
    Dir.mktmpdir do |root|
      write_zip_sha_state(root, "orx", "alpha", "shaA")
      write_zip_sha_state(root, "orx", "beta", "shaB")
      recorded = backfiller(http_registry, shell: NO_SHELL, canonical_dir: root).backfill_pins

      assert_equal %i[state_file state_file], recorded.map(&:origin)
      assert_equal "shaA", Nabu::Store::Pin.first(source_slug: "orx", repo_url: ALPHA_ZIP).last_sync_sha
      assert_equal "shaB", Nabu::Store::Pin.first(source_slug: "orx", repo_url: BETA_ZIP).last_sync_sha
    end
  end

  # A single-file FileFetch source (.file-fetch.json at the workdir root).
  def test_backfill_records_pin_from_a_file_state_file
    Dir.mktmpdir do |root|
      dir = File.join(root, "asx")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, Nabu::FileFetch::STATE_FILE),
                 JSON.generate("last_modified" => LM_OLD, "sha256" => "shaF", "url" => FILE_URL))
      recorded = backfiller(file_registry, shell: NO_SHELL, canonical_dir: root).backfill_pins

      assert_equal 1, recorded.size
      assert_equal "shaF", Nabu::Store::Pin.first(source_slug: "asx", repo_url: FILE_URL).last_sync_sha
    end
  end

  # Idempotent: a second backfill records nothing and does not change the pin.
  def test_backfill_is_idempotent
    Dir.mktmpdir do |root|
      seed_canonical(root, "gh", git: true)
      reg = registry_of(["gh", "ProbeGithubAdapter", true])
      first = backfiller(reg, canonical_dir: root).backfill_pins
      sha = Nabu::Store::Pin.first(source_slug: "gh").last_sync_sha

      second = backfiller(reg, canonical_dir: root).backfill_pins
      assert_equal 1, first.size
      assert_empty second, "already-pinned source is skipped"
      assert_equal 1, Nabu::Store::Pin.where(source_slug: "gh").count, "no duplicate pin row"
      assert_equal sha, Nabu::Store::Pin.first(source_slug: "gh").last_sync_sha
    end
  end

  # An existing pin (non-blank sha) is never overwritten by backfill.
  def test_backfill_skips_an_already_pinned_source
    Dir.mktmpdir do |root|
      seed_pin(slug: "gh", repo_url: GITHUB_URL, last_sync_sha: "kept0000")
      seed_canonical(root, "gh", git: true)
      recorded = backfiller(registry_of(["gh", "ProbeGithubAdapter", true]), canonical_dir: root).backfill_pins

      assert_empty recorded
      assert_equal "kept0000", Nabu::Store::Pin.first(source_slug: "gh").last_sync_sha
    end
  end

  # No canonical clone / no state file → nothing to backfill.
  def test_backfill_records_nothing_without_a_local_clone
    Dir.mktmpdir do |root|
      recorded = backfiller(registry_of(["gh", "ProbeGithubAdapter", true]), canonical_dir: root).backfill_pins
      assert_empty recorded
      assert_nil Nabu::Store::Pin.first(source_slug: "gh")
    end
  end

  # A .zip-fetch.json carrying the sha256 body pin, the way ZipFetch writes it.
  def write_zip_sha_state(canonical_dir, slug, subdir, sha256)
    dir = File.join(canonical_dir, slug, subdir)
    FileUtils.mkdir_p(dir)
    File.write(
      File.join(dir, Nabu::ZipFetch::STATE_FILE),
      JSON.generate("last_modified" => LM_OLD, "sha256" => sha256, "url" => "u")
    )
  end
end
