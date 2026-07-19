# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

# Nabu::LfsFetch (P31-2): pointer detection/parsing, batch-API
# materialization with sha256 verification, and the restore→pull→
# re-materialize cycle that keeps GitFetch's ff-merge contract intact on a
# machine without git-lfs. All HTTP through WebMock; git against local
# tmpdir repos (the GitFetch test precedent).
class LfsFetchTest < Minitest::Test
  BATCH_URL = "https://example.test/owner/repo.git/info/lfs/objects/batch"

  def payload = "real payload bytes\n"
  def oid = Digest::SHA256.hexdigest(payload)

  def pointer_text(oid: self.oid, size: payload.bytesize)
    "version https://git-lfs.github.com/spec/v1\noid sha256:#{oid}\nsize #{size}\n"
  end

  def stub_batch(oid: self.oid, size: payload.bytesize, href: "https://lfs.test/object")
    stub_request(:post, BATCH_URL).to_return(status: 200, body: JSON.generate(
      objects: [{ oid: oid, size: size, actions: { download: { href: href } } }]
    ))
  end

  def test_pointer_detection_and_parsing
    Dir.mktmpdir do |dir|
      path = File.join(dir, "data.csv")
      File.write(path, pointer_text)
      assert Nabu::LfsFetch.pointer?(path)
      parsed = Nabu::LfsFetch.parse_pointer(path)
      assert_equal oid, parsed[:oid]
      assert_equal payload.bytesize, parsed[:size]

      File.write(path, "a" * 600)
      refute Nabu::LfsFetch.pointer?(path), "a large file is payload, not a pointer"
      File.write(path, "just small junk")
      refute Nabu::LfsFetch.pointer?(path)
    end
  end

  def test_materialize_downloads_verifies_and_records_state
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "data.csv"), pointer_text)
      stub_batch
      stub_request(:get, "https://lfs.test/object").to_return(status: 200, body: payload)

      note = fetcher(dir).materialize!
      assert_equal payload, File.read(File.join(dir, "data.csv"))
      assert_match(/data\.csv=#{oid[0, 8]} \(#{payload.bytesize} B, downloaded\)/, note)
      state = JSON.parse(File.read(File.join(dir, Nabu::LfsFetch::STATE_FILE)))
      assert_equal({ "data.csv" => oid }, state)
    end
  end

  def test_materialize_rejects_a_corrupt_payload_and_leaves_the_pointer
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "data.csv"), pointer_text)
      stub_batch
      stub_request(:get, "https://lfs.test/object").to_return(status: 200, body: "tampered")

      error = assert_raises(Nabu::LfsFetch::Error) { fetcher(dir).materialize! }
      assert_match(/verification failed/, error.message)
      assert Nabu::LfsFetch.pointer?(File.join(dir, "data.csv")),
             "a failed verification must never replace the pointer"
    end
  end

  def test_materialize_surfaces_batch_object_errors
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "data.csv"), pointer_text)
      stub_request(:post, BATCH_URL).to_return(status: 200, body: JSON.generate(
        objects: [{ oid: oid, size: payload.bytesize,
                    error: { code: 404, message: "Object does not exist" } }]
      ))
      error = assert_raises(Nabu::LfsFetch::Error) { fetcher(dir).materialize! }
      assert_match(/Object does not exist/, error.message)
    end
  end

  def test_restore_then_rematerialize_reuses_the_oid_cache_without_a_download
    Dir.mktmpdir do |dir|
      repo = File.join(dir, "repo")
      FileUtils.mkdir_p(repo)
      File.write(File.join(repo, "data.csv"), pointer_text)
      Nabu::Shell.run("git", "-C", repo, "init", "--quiet")
      Nabu::Shell.run("git", "-C", repo, "add", ".")
      Nabu::Shell.run("git", "-C", repo, "-c", "user.email=t@t", "-c", "user.name=t",
                      "commit", "--quiet", "-m", "seed")

      stub_batch
      download = stub_request(:get, "https://lfs.test/object").to_return(status: 200, body: payload)
      lfs = fetcher(repo)
      lfs.materialize!
      assert_equal payload, File.read(File.join(repo, "data.csv"))

      # The pull cycle: pointer restored (tree clean for the merge)…
      lfs.restore_pointers!
      assert Nabu::LfsFetch.pointer?(File.join(repo, "data.csv"))
      status = Nabu::Shell.run("git", "-C", repo, "status", "--porcelain")
      assert_equal "", status.strip, "restored tree must be clean in git's eyes"

      # …then re-materialization is a cache rename, not a second download.
      note = fetcher(repo).materialize!
      assert_equal payload, File.read(File.join(repo, "data.csv"))
      assert_match(/cached/, note)
      assert_requested(download, times: 1)
    end
  end

  def test_materialize_is_quiet_when_files_are_already_payloads
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "data.csv"), payload)
      note = fetcher(dir).materialize!
      assert_match(/present/, note)
    end
  end

  private

  def fetcher(dir)
    Nabu::LfsFetch.new(repo_url: "https://example.test/owner/repo", dir: dir,
                       paths: ["data.csv"])
  end
end
