# frozen_string_literal: true

require "test_helper"

# Nabu::FileFetch (P12-2): the single-file HTTP fetch path — ZipFetch's
# sibling for upstreams that serve ONE plain file (OTA's 3009.xml), honoring
# the same contract: conditional GET on the stored Last-Modified (304 →
# untouched), sha256 body pin in a state file, attic retention with a
# GitFetch-format manifest for anything the fetch would delete, and the
# guard hook running BEFORE any tree mutation. No unzip, no staging tree —
# the "tree" is one file, so on the normal path nothing is ever doomed; a
# stale differently-named file (a FILENAME migration) is the one genuine
# attic case. No network: WebMock stubs throughout.
class FileFetchTest < Minitest::Test
  URL = "https://example.org/repository/3009.xml"
  MIRROR = "https://bitstream.mirror.example.net/content/3009.xml"
  LAST_MODIFIED = "Fri, 19 Jul 2019 12:07:26 GMT"
  FILENAME = "3009.xml"

  def setup
    @root = Dir.mktmpdir("file-fetch-test")
    @dir = File.join(@root, "aspr")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
    # webmock/minitest chains WebMock.reset! via alias_method :teardown — a
    # custom teardown MUST call super or the request registry accumulates
    # across tests (silently, until an assert_requested count lies).
    super
  end

  def stub_file(body, last_modified: LAST_MODIFIED)
    headers = { "Content-Type" => "text/xml" }
    headers["Last-Modified"] = last_modified if last_modified
    stub_request(:get, URL).to_return(status: 200, body: body, headers: headers)
  end

  def sync!(guard: nil)
    Nabu::FileFetch.sync!(url: URL, dir: @dir, filename: FILENAME, attic_dir: @attic, guard: guard)
  end

  def test_progress_messages_are_newline_terminated
    # Owner report 2026-07-19: multi-file sources printed "Downloading
    # X…Downloading Y…" as one unbroken line — the fetch_line contract is
    # RAW lines (git streams carry their own terminators), so synthetic
    # head-messages must self-terminate.
    stub_file("<TEI>alpha</TEI>")
    lines = []
    Nabu::FileFetch.sync!(url: URL, dir: @dir, filename: FILENAME, attic_dir: @attic,
                          progress: ->(line) { lines << line })
    downloading = lines.grep(/\ADownloading /)
    refute_empty downloading
    downloading.each { |line| assert line.end_with?("\n"), "synthetic fetch lines self-terminate: #{line.inspect}" }
  end

  def test_prepare_exposes_the_body_md5_beside_the_sha256_pin
    # P41-2: OpenITI's Zenodo artifacts publish md5 (not sha256) checksums;
    # the adapter verifies its hard md5 pin between prepare! and complete!.
    body = "<TEI>alpha</TEI>"
    stub_file(body)
    fetch = Nabu::FileFetch.new(url: URL, dir: @dir, filename: FILENAME, attic_dir: @attic)
    fetch.prepare!
    assert_equal Digest::MD5.hexdigest(body), fetch.md5
    fetch.complete!
    stub_request(:get, URL)
      .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
      .to_return(status: 304)
    replay = Nabu::FileFetch.new(url: URL, dir: @dir, filename: FILENAME, attic_dir: @attic)
    replay.prepare!
    assert_nil replay.md5, "no body on 304 → no md5; callers skip the pin check"
  end

  def test_fresh_fetch_writes_the_file_and_pins_the_body_sha256
    stub_file("<TEI>alpha</TEI>")
    result = sync!
    assert_equal "<TEI>alpha</TEI>", File.read(File.join(@dir, FILENAME))
    assert_equal Digest::SHA256.hexdigest("<TEI>alpha</TEI>"), result.sha
    assert_empty result.atticked
    refute result.not_modified
  end

  def test_state_file_records_last_modified_sha_and_url
    stub_file("<TEI>alpha</TEI>")
    sync!
    state = JSON.parse(File.read(File.join(@dir, Nabu::FileFetch::STATE_FILE)))
    assert_equal LAST_MODIFIED, state["last_modified"]
    assert_equal Digest::SHA256.hexdigest("<TEI>alpha</TEI>"), state["sha256"]
    assert_equal URL, state["url"]
  end

  def test_second_fetch_sends_if_modified_since_and_304_means_untouched
    stub_file("<TEI>alpha</TEI>")
    first = sync!

    stub_request(:get, URL)
      .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
      .to_return(status: 304)
    second = sync!

    assert second.not_modified
    assert_equal first.sha, second.sha, "a 304 keeps the previously pinned sha"
    assert_equal "<TEI>alpha</TEI>", File.read(File.join(@dir, FILENAME))
  end

  def test_a_wiped_tree_refetches_unconditionally
    stub_file("<TEI>alpha</TEI>")
    sync!
    FileUtils.rm(File.join(@dir, FILENAME))

    stub_file("<TEI>beta</TEI>") # unconditional stub: an If-Modified-Since GET would not match
    result = sync!
    refute result.not_modified
    assert_equal "<TEI>beta</TEI>", File.read(File.join(@dir, FILENAME))
  end

  def test_changed_body_updates_file_and_pin_without_atticking
    stub_file("<TEI>alpha</TEI>")
    sync!
    stub_file("<TEI>beta</TEI>", last_modified: "Sat, 20 Jul 2019 12:07:26 GMT")
    result = sync!
    assert_equal "<TEI>beta</TEI>", File.read(File.join(@dir, FILENAME))
    assert_equal Digest::SHA256.hexdigest("<TEI>beta</TEI>"), result.sha
    assert_empty result.atticked, "a revision is an update, not an attic-worthy deletion (the git precedent)"
  end

  def test_a_stale_differently_named_file_is_atticked_with_a_manifest
    stub_file("<TEI>old</TEI>")
    Nabu::FileFetch.sync!(url: URL, dir: @dir, filename: "old-name.xml", attic_dir: @attic)

    stub_file("<TEI>new</TEI>")
    result = sync!

    assert_equal ["old-name.xml"], result.atticked
    refute File.exist?(File.join(@dir, "old-name.xml")), "stale file → removed from the live tree"
    assert_equal "<TEI>old</TEI>", File.read(File.join(@attic, "old-name.xml")), "…but preserved in the attic"
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert_equal result.sha, manifest.fetch("old-name.xml"),
                 "the manifest records the body sha the file vanished at"
  end

  def test_guard_sees_doomed_paths_before_any_mutation_and_may_abort
    stub_file("<TEI>old</TEI>")
    Nabu::FileFetch.sync!(url: URL, dir: @dir, filename: "old-name.xml", attic_dir: @attic)

    stub_file("<TEI>new</TEI>")
    seen = nil
    error = Class.new(StandardError)
    assert_raises(error) do
      sync!(guard: lambda { |doomed|
        seen = doomed
        raise error
      })
    end

    assert_equal [File.join(@dir, "old-name.xml")], seen
    assert_equal "<TEI>old</TEI>", File.read(File.join(@dir, "old-name.xml")), "aborted → tree byte-unchanged"
    refute File.exist?(File.join(@dir, FILENAME)), "aborted → no new file written"
    refute Dir.exist?(@attic), "aborted → no attic writes"
  end

  def test_state_file_and_attic_are_never_reported_doomed
    stub_file("<TEI>alpha</TEI>")
    sync!
    FileUtils.mkdir_p(@attic)
    File.write(File.join(@attic, "retained.xml"), "retained")

    stub_file("<TEI>beta</TEI>", last_modified: "Sat, 20 Jul 2019 12:07:26 GMT")
    seen = nil
    sync!(guard: ->(doomed) { seen = doomed })
    assert_empty seen, "the state file and the attic must never read as upstream deletions"
  end

  def test_http_failure_raises_file_fetch_error
    stub_request(:get, URL).to_return(status: 500)
    assert_raises(Nabu::FileFetch::Error) { sync! }
  end

  def test_transport_failure_raises_file_fetch_error
    stub_request(:get, URL).to_raise(Faraday::ConnectionFailed.new("boom"))
    assert_raises(Nabu::FileFetch::Error) { sync! }
  end

  # -- redirects (the figshare/DSpace shape: downloads 302 to a mirror) -------

  def test_follows_a_302_to_the_mirror_and_keys_state_off_the_original_url
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => MIRROR })
    stub_request(:get, MIRROR)
      .to_return(status: 200, body: "<TEI>mirror</TEI>", headers: { "Last-Modified" => LAST_MODIFIED })
    result = sync!
    assert_equal "<TEI>mirror</TEI>", File.read(File.join(@dir, FILENAME))
    assert_equal Digest::SHA256.hexdigest("<TEI>mirror</TEI>"), result.sha,
                 "the pin is the sha of the FINAL body"
    assert_requested :get, MIRROR
    state = JSON.parse(File.read(File.join(@dir, Nabu::FileFetch::STATE_FILE)))
    assert_equal URL, state["url"], "state keys off the ORIGINAL url — mirror targets rotate"
  end

  def test_relative_redirect_location_resolves_against_the_current_url
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => "../content/3009.xml" })
    stub_request(:get, "https://example.org/content/3009.xml")
      .to_return(status: 200, body: "<TEI>relative</TEI>")
    sync!
    assert_equal "<TEI>relative</TEI>", File.read(File.join(@dir, FILENAME))
  end

  def test_redirect_loop_errors_honestly_at_the_hop_cap
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => URL })
    error = assert_raises(Nabu::FileFetch::Error) { sync! }
    assert_match(/more than 5 hops/, error.message, "the cap is named")
    assert_requested :get, URL, times: 6 # the original request + 5 followed hops
  end

  def test_redirect_without_location_is_an_honest_error
    stub_request(:get, URL).to_return(status: 302)
    error = assert_raises(Nabu::FileFetch::Error) { sync! }
    assert_match(/Location/, error.message)
  end

  def test_if_modified_since_rides_the_redirect_and_a_mirror_304_means_untouched
    stub_file("<TEI>alpha</TEI>")
    first = sync!

    stub_request(:get, URL)
      .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
      .to_return(status: 302, headers: { "Location" => MIRROR })
    stub_request(:get, MIRROR)
      .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
      .to_return(status: 304)
    second = sync!

    assert second.not_modified, "a 304 from the mirror (post-redirect) is honored"
    assert_equal first.sha, second.sha, "a 304 keeps the previously pinned sha"
    assert_equal "<TEI>alpha</TEI>", File.read(File.join(@dir, FILENAME))
  end

  def test_if_modified_since_rides_the_redirect_to_a_changed_mirror_body
    stub_file("<TEI>alpha</TEI>")
    sync!

    stub_request(:get, URL)
      .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
      .to_return(status: 302, headers: { "Location" => MIRROR })
    stub_request(:get, MIRROR)
      .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
      .to_return(status: 200, body: "<TEI>beta</TEI>",
                 headers: { "Last-Modified" => "Sat, 20 Jul 2019 12:07:26 GMT" })
    result = sync!

    refute result.not_modified
    assert_equal "<TEI>beta</TEI>", File.read(File.join(@dir, FILENAME))
    assert_equal Digest::SHA256.hexdigest("<TEI>beta</TEI>"), result.sha
  end

  def test_missing_last_modified_means_next_fetch_is_unconditional
    stub_file("<TEI>alpha</TEI>", last_modified: nil)
    sync!
    stub_file("<TEI>beta</TEI>", last_modified: nil)
    result = sync!
    refute result.not_modified
    assert_equal "<TEI>beta</TEI>", File.read(File.join(@dir, FILENAME))
  end

  def test_reuses_the_vendored_cert_default_http
    assert_same Nabu::ZipFetch.default_http, Nabu::FileFetch.default_http,
                "FileFetch rides ZipFetch's cert-hardened Faraday connection"
  end
end
