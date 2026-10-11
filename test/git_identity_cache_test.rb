# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::GitIdentityCache: the per-repo memo of git-tree identity tokens
# behind the incremental verdict sweep (Q124 — kanripo's 5,162 embedded
# repos cost ~100 s of `git status` + `rev-parse` per warm sweep). THE LAW
# under test: a stale hit is impossible — a new commit, a dirty file, an
# untracked file, an index touch, a moved ref, a same-size rewrite with its
# mtime restored: each forces the full git call; only an untouched repo
# answers from the memo. A weak (dirty) repo is never stored.
class GitIdentityCacheTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("nabu-git-identity-cache")
    @canonical = File.join(@root, "canonical")
    @cache_path = File.join(@root, "db", Nabu::GitIdentityCache::FILENAME)
    @tree = File.join(@canonical, "kanripo-style")
    @repo = git_tree("kanripo-style/KR1a0001", "a.txt" => "one\n", "sub/b.txt" => "two\n")
    @sibling = git_tree("kanripo-style/KR1a0002", "c.txt" => "three\n")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # -- hit -------------------------------------------------------------------

  def test_an_untouched_repo_answers_from_the_memo_with_no_git_call
    past_the_racy_window do
      cold = measure(cache)
      assert_operator cold[:git_calls], :>=, 4, "a cold memo pays status + rev-parse per repo"
      warm_memo = cache
      warm = measure(warm_memo)
      assert_equal 0, warm[:git_calls], "an untouched tree must answer without a single git call"
      assert_equal cold[:identity], warm[:identity]
      assert_equal uncached_identity, warm[:identity]
      assert_equal({ hit: 2 }, warm_memo.stats)
    end
  end

  # -- the drift matrix: every doubt pays the full git call -----------------

  def test_a_new_commit_forces_the_full_call_and_moves_the_identity
    identity = assert_drift_pays_full_call do
      File.write(File.join(@repo, "a.txt"), "one, revised\n")
      git(@repo, "add", ".")
      git_commit(@repo, "revise")
    end
    refute_equal @before, identity
  end

  def test_a_dirty_tracked_file_forces_the_full_call_and_reads_weak
    identity = assert_drift_pays_full_call { File.write(File.join(@repo, "a.txt"), "tampered\n") }
    assert_nil identity
  end

  def test_an_untracked_file_forces_the_full_call_and_reads_weak
    identity = assert_drift_pays_full_call { File.write(File.join(@repo, "sub", "stray.txt"), "x\n") }
    assert_nil identity
  end

  def test_a_deleted_tracked_file_forces_the_full_call_and_reads_weak
    identity = assert_drift_pays_full_call { File.delete(File.join(@repo, "sub", "b.txt")) }
    assert_nil identity
  end

  def test_an_index_touch_forces_the_full_call
    identity = assert_drift_pays_full_call { FileUtils.touch(File.join(@repo, ".git", "index")) }
    assert_equal @before, identity, "the index moved, the bytes did not: same honest identity"
  end

  def test_a_staged_but_uncommitted_change_forces_the_full_call_and_reads_weak
    identity = assert_drift_pays_full_call do
      File.write(File.join(@repo, "a.txt"), "staged\n")
      git(@repo, "add", "a.txt")
    end
    assert_nil identity
  end

  def test_a_moved_ref_forces_the_full_call
    identity = assert_drift_pays_full_call do
      git(@repo, "checkout", "--quiet", "-b", "other")
      File.write(File.join(@repo, "a.txt"), "one, on another branch\n")
      git(@repo, "add", ".")
      git_commit(@repo, "branch")
    end
    refute_equal @before, identity
  end

  def test_a_reset_back_to_an_older_commit_forces_the_full_call
    File.write(File.join(@repo, "a.txt"), "one, second\n")
    git(@repo, "add", ".")
    git_commit(@repo, "second")
    identity = assert_drift_pays_full_call { git(@repo, "reset", "--quiet", "--hard", "HEAD~1") }
    refute_equal @before, identity, "HEAD now names the older commit"
  end

  # The mtime hazard, git edition: a same-size in-place rewrite with its
  # mtime restored keeps (path, size, mtime, inode); ctime still moves.
  def test_a_same_size_rewrite_with_restored_mtime_forces_the_full_call
    file = File.join(@repo, "a.txt")
    mtime = File.stat(file).mtime
    identity = assert_drift_pays_full_call do
      File.open(file, "r+") { |io| io.write("X") }
      File.utime(mtime, mtime, file)
    end
    assert_nil identity, "git sees the rewrite: the tree is dirty"
  end

  def test_an_attic_edit_forces_the_full_call_and_moves_the_identity
    File.write(File.join(@repo, ".git", "info", "exclude"), "/.attic/\n")
    FileUtils.mkdir_p(File.join(@repo, ".attic"))
    File.write(File.join(@repo, ".attic", "retired.txt"), "gone upstream\n")
    identity = assert_drift_pays_full_call do
      File.write(File.join(@repo, ".attic", "retired.txt"), "gone upstream, edited\n")
    end
    refute_equal @before, identity
  end

  # -- what is never stored --------------------------------------------------

  def test_a_weak_repo_is_never_stored
    File.write(File.join(@sibling, "c.txt"), "tampered\n") # sorts second: the walk reaches it
    past_the_racy_window do
      2.times { assert_nil measure(cache)[:identity] }
      memo = cache
      assert_operator measure(memo)[:git_calls], :>=, 1, "a dirty repo always pays the full call"
      assert_equal({ hit: 1, miss: 1 }, memo.stats, "only the clean repo hits; the dirty one pays every time")
      assert_equal [@repo], JSON.parse(File.read(@cache_path)).fetch("repos").keys
    end
  end

  def test_a_racy_census_is_never_stored
    memo = cache # real clock: the repos were just written
    measure(memo)
    assert_equal 2, memo.stats[:racy]
    refute File.exist?(@cache_path), "nothing racy reaches the memo"
  end

  # -- granularity, salt, reset ----------------------------------------------

  def test_one_drifted_repo_pays_alone
    past_the_racy_window do
      measure(cache)
      File.write(File.join(@sibling, "c.txt"), "three, revised\n")
      git(@sibling, "add", ".")
      git_commit(@sibling, "revise")
    end
    past_the_racy_window do
      memo = cache
      result = measure(memo)
      assert_equal({ hit: 1, miss: 1 }, memo.stats)
      assert_equal uncached_identity, result[:identity]
    end
  end

  def test_the_salt_keys_the_entry
    past_the_racy_window do
      memo = cache
      memo.fetch(@repo, salt: "a") { ["git:a"] }
      assert_equal ["git:a"], memo.fetch(@repo, salt: "a") { flunk "an equal salt must hit" }
      assert_equal ["git:b"], memo.fetch(@repo, salt: "b") { ["git:b"] }, "a new salt must miss"
    end
  end

  def test_declared_materializations_salt_the_entry
    texts = File.join(@repo, "texts")
    FileUtils.mkdir_p(texts)
    File.write(File.join(texts, "x.conllu"), "extracted\n")
    past_the_racy_window do
      assert_nil identity_of(@repo, cache), "undeclared: weak"
      strong = identity_of(@repo, cache, materialized: %w[texts])
      refute_nil strong, "the declaration is part of the key — the weak answer cannot shadow it"
      assert_nil identity_of(@repo, cache), "and the strong answer cannot shadow the undeclared walk"
    end
  end

  def test_refresh_mode_never_reads_but_warms_the_next_use
    past_the_racy_window do
      refresh = cache(mode: :refresh)
      measure(refresh)
      assert_operator measure(refresh)[:git_calls], :>=, 4, "refresh never trusts the memo"
      assert_equal 0, measure(cache)[:git_calls], "a refresh-written memo serves the next :use"
    end
  end

  def test_an_identity_code_edit_invalidates_every_entry
    past_the_racy_window do
      measure(cache)
      with_diverted_code_digest { assert_operator measure(cache)[:git_calls], :>=, 4 }
    end
  end

  def test_a_deleted_or_corrupt_memo_is_just_a_cold_one
    past_the_racy_window do
      measure(cache)
      File.write(@cache_path, "{ not json")
      assert_operator measure(cache)[:git_calls], :>=, 4
      assert_equal 0, measure(cache)[:git_calls], "the rewrite healed the memo"
      File.delete(@cache_path)
      assert_equal uncached_identity, measure(cache)[:identity]
    end
  end

  def test_a_forged_identity_under_a_stale_key_is_never_served
    past_the_racy_window do
      measure(cache)
      data = JSON.parse(File.read(@cache_path))
      data["repos"].each_value { |entry| entry["tokens"] = ["git:forged"] }
      File.write(@cache_path, JSON.generate(data))
      File.write(File.join(@repo, "a.txt"), "tampered\n")
      assert_nil measure(cache)[:identity]
    end
  end

  def test_an_unwritable_home_still_answers_honestly
    blocker = File.join(@root, "blocker")
    File.write(blocker, "a file where the db dir should be")
    memo = Nabu::GitIdentityCache.new(path: File.join(blocker, "db", "memo.json"))
    past_the_racy_window { assert_equal uncached_identity, measure(memo)[:identity] }
  end

  def test_unknown_modes_are_refused
    assert_raises(ArgumentError) { cache(mode: :trust) }
  end

  # -- the identity pass is a pure reader of canonical/ ----------------------

  # `git status` opportunistically rewrites a stale index; the identity pass
  # must not (it would also churn the memo's own index key forever).
  def test_the_identity_pass_never_rewrites_the_index
    file = File.join(@repo, "a.txt")
    File.utime(Time.now - 3600, Time.now - 3600, file) # stale index stat info
    index = File.join(@repo, ".git", "index")
    before = File.binread(index)
    refute_nil uncached_identity
    assert_equal before, File.binread(index), "the identity pass must not refresh the index"
  end

  private

  def cache(mode: :use) = Nabu::GitIdentityCache.new(path: @cache_path, mode: mode)

  def uncached_identity = Nabu::DerivationFingerprint.canonical_identity(@tree)

  def identity_of(dir, memo, materialized: [])
    Nabu::DerivationFingerprint.canonical_identity(dir, materialized: materialized, repo_cache: memo)
  end

  # The tree's identity through +memo+, counting the git calls it paid.
  def measure(memo)
    calls = 0
    singleton = Nabu::Shell.singleton_class
    original = Nabu::Shell.method(:run)
    singleton.define_method(:run) do |*argv|
      calls += 1 if argv.first == "git"
      original.call(*argv)
    end
    identity = identity_of(@tree, memo)
    { identity: identity, git_calls: calls }
  ensure
    singleton.define_method(:run, original)
  end

  # Warm the memo, apply the drift, prove the next sweep pays the full call
  # on the census alone (not the racy guard) and answers the honest
  # identity. Returns that identity; @before holds the pre-drift one.
  def assert_drift_pays_full_call
    past_the_racy_window do
      measure(cache)
      @before = uncached_identity
      assert_equal 0, measure(cache)[:git_calls], "precondition: warm"
    end
    yield
    past_the_racy_window do
      memo = cache
      result = measure(memo)
      assert_operator result[:git_calls], :>=, 1, "the drift must force the full git call"
      assert_equal 1, memo.stats[:miss], "exactly the drifted repo misses"
      # A weak repo poisons the walk at once (KR1a0001 sorts first), so the
      # sibling is only reached — and must hit — when the drift kept it strong.
      assert_equal 1, memo.stats[:hit], "its untouched sibling still hits" if result[:identity]
      assert_equal 0, memo.stats[:racy], "precondition: the miss was the census, not the racy guard"
      honest = uncached_identity
      honest.nil? ? assert_nil(result[:identity]) : assert_equal(honest, result[:identity])
      result[:identity]
    end
  end

  def past_the_racy_window(&)
    divert(:now, -> { Time.now + 60 }, &)
  end

  def with_diverted_code_digest(&)
    divert(:code_digest, -> { "edited-identity-code" }, &)
  end

  def divert(name, replacement)
    singleton = Nabu::GitIdentityCache.singleton_class
    original = Nabu::GitIdentityCache.method(name)
    singleton.define_method(name) { replacement.call }
    yield
  ensure
    singleton.define_method(name, original)
  end

  def git_tree(slug, files)
    dir = File.join(@canonical, slug)
    files.each do |name, content|
      FileUtils.mkdir_p(File.dirname(File.join(dir, name)))
      File.write(File.join(dir, name), content)
    end
    git(dir, "init", "--quiet")
    git(dir, "add", ".")
    git_commit(dir, "seed")
    dir
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *)
  end

  def git_commit(dir, message)
    git(dir, "-c", "user.email=test@nabu", "-c", "user.name=test", "commit", "--quiet", "-m", message)
  end
end
