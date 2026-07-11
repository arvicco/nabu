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
  LAST_MODIFIED = "Fri, 19 Jul 2019 12:07:26 GMT"
  FILENAME = "3009.xml"

  def setup
    @root = Dir.mktmpdir("file-fetch-test")
    @dir = File.join(@root, "aspr")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def stub_file(body, last_modified: LAST_MODIFIED)
    headers = { "Content-Type" => "text/xml" }
    headers["Last-Modified"] = last_modified if last_modified
    stub_request(:get, URL).to_return(status: 200, body: body, headers: headers)
  end

  def sync!(guard: nil)
    Nabu::FileFetch.sync!(url: URL, dir: @dir, filename: FILENAME, attic_dir: @attic, guard: guard)
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
