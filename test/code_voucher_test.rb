# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "time"

# Nabu::CodeVoucher (P89-1, №R-54 (b)): can git vouch that a set of code
# files carries the same bytes it did at a given moment? The trust bridge
# re-stamps a source WITHOUT replay only on a yes — so every refusal path
# here is an under-rebuild guard. The cardinal rule: when git cannot vouch
# (untracked file, dirty tree, deletion after the moment), the answer is a
# quiet false, never a raise — the caller falls through to an honest replay.
class CodeVoucherTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("nabu-voucher")
    @watch = File.join(@root, "lib", "nabu", "adapters")
    FileUtils.mkdir_p(@watch)
    git("init", "--quiet")
    write("alpha.rb", "class Alpha; end\n")
    write("beta.rb", "class Beta; end\n")
    commit("seed")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_vouches_for_files_committed_before_the_stamp
    stamp_time = Time.now + 60
    assert voucher.vouches?(files: [path("alpha.rb"), path("beta.rb")], since: stamp_time)
  end

  def test_refuses_a_file_committed_after_the_stamp
    stamp_time = last_commit_time
    sleep 1.1 # git commit times are second-grained
    write("alpha.rb", "class Alpha; VERSION = 2; end\n")
    commit("newer than the stamp")

    refute voucher.vouches?(files: [path("alpha.rb"), path("beta.rb")], since: stamp_time)
    assert voucher.vouches?(files: [path("beta.rb")], since: stamp_time),
           "the untouched file still vouches"
  end

  def test_refuses_an_untracked_file
    File.write(path("gamma.rb"), "class Gamma; end\n")

    refute voucher.vouches?(files: [path("gamma.rb")], since: Time.now + 60),
           "git cannot vouch for bytes it never committed"
  end

  def test_refuses_a_dirty_watched_tree
    File.write(path("alpha.rb"), "class Alpha; DIRTY = true; end\n")

    refute voucher.vouches?(files: [path("beta.rb")], since: Time.now + 60),
           "uncommitted edits under the watched tree poison every vouch"
  end

  def test_refuses_after_a_deletion_under_the_watched_tree
    stamp_time = last_commit_time
    sleep 1.1
    git("rm", "--quiet", path("beta.rb"))
    commit("delete beta")

    refute voucher.vouches?(files: [path("alpha.rb")], since: stamp_time),
           "a deletion changes closure membership invisibly — conservative refusal"
    assert voucher.vouches?(files: [path("alpha.rb")], since: last_commit_time + 60),
           "a stamp minted after the deletion is unaffected by it"
  end

  def test_accepts_a_string_since
    assert voucher.vouches?(files: [path("alpha.rb")], since: (Time.now + 60).to_s)
  end

  private

  def voucher = Nabu::CodeVoucher.new(repo_root: @root, watch_dir: @watch)

  def path(basename) = File.join(@watch, basename)

  def write(basename, content) = File.write(path(basename), content)

  def git(*)
    Nabu::Shell.run("git", "-C", @root, *)
  end

  def commit(message)
    git("add", "-A")
    git("-c", "user.email=test@nabu", "-c", "user.name=test",
        "commit", "--quiet", "-m", message)
  end

  def last_commit_time
    Time.parse(git("log", "-1", "--format=%cI").strip)
  end
end
