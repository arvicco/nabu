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

  def registry_of(*specs)
    entries = specs.map do |slug, klass, enabled|
      Nabu::SourceRegistry::Entry.new(
        slug: slug, adapter_class_name: klass, enabled: enabled || enabled.nil?, sync_policy: "manual"
      )
    end
    Nabu::SourceRegistry.new(entries)
  end

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
end
