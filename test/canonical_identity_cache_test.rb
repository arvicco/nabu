# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::CanonicalIdentityCache: the plain-tree identity memo behind the
# incremental verdict sweep. THE LAW under test: a stale hit is impossible
# — any drift in the file census (add, remove, rename, resize, retime,
# in-place rewrite with a restored mtime) forces the honest full re-hash;
# only a byte-identical, untouched tree hits.
class CanonicalIdentityCacheTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("nabu-identity-cache")
    @canonical = File.join(@root, "canonical")
    @cache_path = File.join(@root, "db", Nabu::CanonicalIdentityCache::FILENAME)
    @tree = File.join(@canonical, "corpus")
    FileUtils.mkdir_p(File.join(@tree, "sub"))
    File.write(File.join(@tree, "one.txt"), "Iliad\nμῆνιν\n")
    File.write(File.join(@tree, "sub", "two.txt"), "Odyssey\nἄνδρα\n")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # -- the drift matrix ----------------------------------------------------

  def test_a_byte_identical_untouched_tree_hits
    past_the_racy_window do
      first = fetch_counting(cache)
      assert_equal 1, first[:hashes], "a cold memo hashes"
      second = fetch_counting(cache)
      assert_equal 0, second[:hashes], "an untouched tree must hit"
      assert_equal first[:identity], second[:identity]
      assert_equal uncached_identity, second[:identity]
    end
  end

  def test_an_added_file_forces_a_rehash
    assert_drift_rehashes { File.write(File.join(@tree, "three.txt"), "Theogony\n") }
  end

  def test_a_removed_file_forces_a_rehash
    assert_drift_rehashes { File.delete(File.join(@tree, "sub", "two.txt")) }
  end

  def test_a_renamed_file_forces_a_rehash
    assert_drift_rehashes { FileUtils.mv(File.join(@tree, "one.txt"), File.join(@tree, "uno.txt")) }
  end

  def test_a_resized_file_forces_a_rehash
    assert_drift_rehashes { File.write(File.join(@tree, "one.txt"), "Iliad\nμῆνιν ἄειδε\n") }
  end

  def test_a_retouched_file_forces_a_rehash_and_keeps_the_identity
    identity = assert_drift_rehashes do
      FileUtils.touch(File.join(@tree, "one.txt"), mtime: Time.now - 86_400)
    end
    assert_equal uncached_identity, identity, "content is the identity; the re-hash confirms it"
  end

  # The mtime hazard: a same-size in-place rewrite whose mtime is restored
  # keeps (path, size, mtime, inode). ctime — which no user call can set —
  # must still catch it.
  def test_a_same_size_rewrite_with_restored_mtime_forces_a_rehash
    file = File.join(@tree, "one.txt")
    old_mtime = File.stat(file).mtime
    old_ino = File.stat(file).ino
    identity = assert_drift_rehashes do
      File.open(file, "r+") { |io| io.write("X") } # same size, in place
      File.utime(old_mtime, old_mtime, file)
    end
    assert_equal old_ino, File.stat(file).ino, "precondition: same inode"
    assert_equal old_mtime, File.stat(file).mtime, "precondition: mtime restored"
    refute_equal stale_identity_before_drift, identity, "the rewrite moved the identity"
    assert_equal uncached_identity, identity
  end

  # A racy census (a file changed within the window of the census start)
  # is computed honestly but never memoized: a same-tick later change
  # could not be told apart from it.
  def test_a_racy_tree_is_never_stored
    memo = cache
    first = fetch_counting(memo) # real clock: the files were just written
    second = fetch_counting(memo)
    assert_equal [1, 1], [first[:hashes], second[:hashes]]
    assert_equal 2, memo.stats[:racy]
    refute File.exist?(@cache_path), "nothing racy reaches the memo"
  end

  # -- bypass and reset ----------------------------------------------------

  def test_a_git_bearing_tree_bypasses_the_memo
    FileUtils.mkdir_p(File.join(@tree, "sub", "repo", ".git"))
    past_the_racy_window do
      memo = cache
      2.times { assert_equal 1, fetch_counting(memo)[:hashes] }
      assert_equal 2, memo.stats[:bypass]
      refute File.exist?(@cache_path)
    end
  end

  def test_refresh_mode_never_reads_but_warms_the_next_use
    past_the_racy_window do
      refresh = cache(mode: :refresh)
      2.times { assert_equal 1, fetch_counting(refresh)[:hashes], "refresh never trusts the memo" }
      assert_equal 0, fetch_counting(cache)[:hashes], "a refresh-written memo serves the next :use"
    end
  end

  def test_the_memo_persists_across_instances_and_survives_deletion
    past_the_racy_window do
      fetch_counting(cache)
      assert_equal 0, fetch_counting(cache)[:hashes]
      File.delete(@cache_path)
      result = fetch_counting(cache)
      assert_equal 1, result[:hashes], "a deleted memo is just a cold one"
      assert_equal uncached_identity, result[:identity]
    end
  end

  def test_a_corrupt_memo_reads_as_empty
    FileUtils.mkdir_p(File.dirname(@cache_path))
    File.write(@cache_path, "{ not json")
    past_the_racy_window do
      assert_equal 1, fetch_counting(cache)[:hashes]
      assert_equal 0, fetch_counting(cache)[:hashes], "the rewrite healed the memo"
    end
  end

  def test_a_forged_identity_under_a_stale_key_is_never_served
    past_the_racy_window do
      fetch_counting(cache)
      data = JSON.parse(File.read(@cache_path))
      data["trees"][@tree]["identity"] = "forged"
      File.write(@cache_path, JSON.generate(data))
      File.write(File.join(@tree, "one.txt"), "changed bytes\n")
      assert_equal uncached_identity, fetch_counting(cache)[:identity]
    end
  end

  def test_an_identity_code_edit_invalidates_every_entry
    past_the_racy_window do
      fetch_counting(cache)
      with_diverted_code_digest { assert_equal 1, fetch_counting(cache)[:hashes] }
    end
  end

  def test_an_unwritable_home_still_answers_honestly
    blocker = File.join(@root, "blocker")
    File.write(blocker, "a file where the db dir should be")
    memo = Nabu::CanonicalIdentityCache.new(path: File.join(blocker, "db", "memo.json"))
    past_the_racy_window do
      assert_equal uncached_identity, fetch_counting(memo)[:identity]
    end
  end

  def test_unknown_modes_are_refused
    assert_raises(ArgumentError) { cache(mode: :trust) }
  end

  # -- through the fingerprint ---------------------------------------------

  def test_the_cached_identity_is_the_uncached_identity
    past_the_racy_window do
      memo = cache
      cold = Nabu::DerivationFingerprint.canonical_identity(@tree, cache: memo)
      warm = Nabu::DerivationFingerprint.canonical_identity(@tree, cache: memo)
      assert_equal uncached_identity, cold
      assert_equal cold, warm
      assert_equal 1, memo.stats[:hit]
    end
  end

  def test_a_missing_tree_stays_weak_and_unmemoized
    memo = cache
    assert_nil Nabu::DerivationFingerprint.canonical_identity(File.join(@canonical, "absent"), cache: memo)
    assert_empty memo.stats
  end

  private

  def cache(mode: :use) = Nabu::CanonicalIdentityCache.new(path: @cache_path, mode: mode)

  def uncached_identity = Nabu::DerivationFingerprint.canonical_identity(@tree)

  # Fetch through +memo+, counting how often the honest computation ran.
  def fetch_counting(memo)
    hashes = 0
    identity = memo.fetch(@tree) do
      hashes += 1
      uncached_identity
    end
    { identity: identity, hashes: hashes }
  end

  # Warm the memo, apply the drift, prove the next fetch re-hashes and
  # answers the honest identity. Returns that identity.
  def assert_drift_rehashes
    past_the_racy_window do
      fetch_counting(cache)
      @stale_identity = uncached_identity
      assert_equal 0, fetch_counting(cache)[:hashes], "precondition: warm"
    end
    yield
    # The drift is old news to a clock past the window: it must miss on
    # the census alone, not merely because it is racy.
    past_the_racy_window do
      memo = cache
      result = fetch_counting(memo)
      assert_equal 1, result[:hashes], "the drift must force a full re-hash"
      assert_equal 0, memo.stats[:racy], "precondition: the miss was the census, not the racy guard"
      assert_equal uncached_identity, result[:identity]
      result[:identity]
    end
  end

  def stale_identity_before_drift = @stale_identity

  # Step the census clock 60 s ahead so freshly written fixture files are
  # outside the racy window (they cannot be backdated: ctime is unsettable).
  def past_the_racy_window(&)
    divert(:now, -> { Time.now + 60 }, &)
  end

  def with_diverted_code_digest(&)
    divert(:code_digest, -> { "edited-identity-code" }, &)
  end

  def divert(name, replacement)
    singleton = Nabu::CanonicalIdentityCache.singleton_class
    original = Nabu::CanonicalIdentityCache.method(name)
    singleton.define_method(name) { replacement.call }
    yield
  ensure
    singleton.define_method(name, original)
  end
end
