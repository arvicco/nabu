# frozen_string_literal: true

require "test_helper"

# Nabu::ZipFetch (P10-1): the first NON-git fetch path — download a zip over
# HTTP, unpack, and honor the same retention contract as Nabu::GitFetch
# (upstream-dropped files land in the attic with a sha manifest, first copy
# wins, guard runs BEFORE any tree mutation). No network: HTTP responses are
# WebMock stubs whose zip bodies are assembled here with the system `zip`
# (the payload files are trivial — the REAL-data zip round-trip is covered by
# the Oracc adapter fetch tests, which zip the checked-in fixtures).
class ZipFetchTest < Minitest::Test
  URL = "https://example.org/json/proj.zip"
  LAST_MODIFIED = "Sat, 01 Mar 2026 10:00:00 GMT"

  def setup
    @root = Dir.mktmpdir("zip-fetch-test")
    @dir = File.join(@root, "proj")
    @attic = File.join(@root, ".attic", "proj")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # Build a zip whose single top-level dir is proj/ containing +files+
  # (relative path => content), and stub URL with it.
  def stub_zip(files, last_modified: LAST_MODIFIED)
    Dir.mktmpdir("zip-fetch-upstream") do |staging|
      files.each do |rel, content|
        path = File.join(staging, "proj", rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
      zip = File.join(staging, "proj.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip, "proj", chdir: staging)
      headers = { "Content-Type" => "application/zip" }
      headers["Last-Modified"] = last_modified if last_modified
      stub_request(:get, URL).to_return(status: 200, body: File.binread(zip), headers: headers)
    end
  end

  def sync!(guard: nil)
    Nabu::ZipFetch.sync!(url: URL, dir: @dir, attic_dir: @attic, guard: guard)
  end

  def test_fresh_fetch_unpacks_the_tree_and_pins_the_zip_sha256
    stub_zip({ "a.json" => "alpha", "sub/b.json" => "beta" })
    result = sync!
    assert_equal "alpha", File.read(File.join(@dir, "a.json"))
    assert_equal "beta", File.read(File.join(@dir, "sub", "b.json"))
    assert_match(/\A\h{64}\z/, result.sha)
    assert_empty result.atticked
    refute result.not_modified
  end

  def test_second_fetch_sends_if_modified_since_and_304_means_untouched
    stub_zip({ "a.json" => "alpha" })
    first = sync!

    stub_request(:get, URL)
      .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
      .to_return(status: 304)
    second = sync!

    assert second.not_modified
    assert_equal first.sha, second.sha, "a 304 keeps the previously pinned sha"
    assert_equal "alpha", File.read(File.join(@dir, "a.json"))
  end

  def test_upstream_dropped_files_move_to_the_attic_with_a_sha_manifest
    stub_zip({ "a.json" => "alpha", "gone.json" => "doomed" })
    sync!

    stub_zip({ "a.json" => "alpha v2" })
    result = sync!

    assert_equal ["gone.json"], result.atticked
    refute File.exist?(File.join(@dir, "gone.json")), "dropped upstream → removed from the live tree"
    assert_equal "doomed", File.read(File.join(@attic, "gone.json")), "…but preserved in the attic"
    assert_equal "alpha v2", File.read(File.join(@dir, "a.json"))
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert_equal result.sha, manifest.fetch("gone.json"),
                 "the manifest records the zip sha the file vanished at"
  end

  def test_first_attic_copy_wins
    stub_zip({ "a.json" => "alpha", "gone.json" => "original" })
    sync!
    stub_zip({ "a.json" => "alpha", "gone.json" => "changed upstream" })
    sync!
    stub_zip({ "a.json" => "alpha" })
    sync!
    # gone.json was atticked when first dropped… and if upstream re-adds and
    # re-drops it, the attic keeps the FIRST retained copy.
    assert_equal "changed upstream", File.read(File.join(@attic, "gone.json"))
    stub_zip({ "a.json" => "alpha", "gone.json" => "resurrected" })
    sync!
    stub_zip({ "a.json" => "alpha" })
    sync!
    assert_equal "changed upstream", File.read(File.join(@attic, "gone.json"))
  end

  def test_guard_sees_doomed_paths_before_any_mutation_and_may_abort
    stub_zip({ "a.json" => "alpha", "gone.json" => "doomed" })
    sync!

    stub_zip({ "a.json" => "alpha v2" })
    seen = nil
    error = Class.new(StandardError)
    assert_raises(error) do
      sync!(guard: lambda { |doomed|
        seen = doomed
        raise error
      })
    end

    assert_equal [File.join(@dir, "gone.json")], seen
    assert_equal "alpha", File.read(File.join(@dir, "a.json")), "aborted → tree byte-unchanged"
    assert File.exist?(File.join(@dir, "gone.json"))
    refute Dir.exist?(@attic), "aborted → no attic writes"
  end

  def test_state_file_and_attic_are_never_reported_doomed
    stub_zip({ "a.json" => "alpha" })
    sync!
    stub_zip({ "a.json" => "alpha v2" })
    seen = nil
    sync!(guard: ->(doomed) { seen = doomed })
    assert_empty seen, "the .zip-fetch.json state file must not read as an upstream deletion"
  end

  def test_http_failure_raises_zip_fetch_error
    stub_request(:get, URL).to_return(status: 500)
    assert_raises(Nabu::ZipFetch::Error) { sync! }
  end

  def test_missing_last_modified_means_next_fetch_is_unconditional
    stub_zip({ "a.json" => "alpha" }, last_modified: nil)
    sync!
    stub_zip({ "a.json" => "alpha v2" }, last_modified: nil)
    result = sync!
    refute result.not_modified
    assert_equal "alpha v2", File.read(File.join(@dir, "a.json"))
  end
end
