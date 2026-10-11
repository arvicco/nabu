# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Nabu
  # A memo of PLAIN-TREE canonical identities (DerivationFingerprint
  # .canonical_identity) so the incremental rebuild's verdict sweep stops
  # re-hashing every byte of every non-git tree on every run (124 of ~210
  # trees; ndl-kotenseki alone is 1.1 GB). Git-bearing trees are never
  # cached: their identity is already cheap (HEAD + porcelain), and git —
  # not this memo — is what vouches for them.
  #
  # THE LAW: over-rebuilding is always safe; UNDER-REBUILDING IS THE SIN. A
  # stale hit — a cached identity returned for bytes it does not describe —
  # would silently skip a dirty source. So a hit must be impossible unless
  # the tree is provably the one that was hashed, and every doubt resolves
  # to a MISS (a full re-hash of that tree, exactly the uncached code path).
  # A miss is always correct behavior, never an error.
  #
  # == The key
  #
  # One entry per tree (absolute dir), validated by a CENSUS DIGEST over:
  # - the identity code itself: the sha256 of this file and of
  #   derivation_fingerprint.rb (CODE_FILES) — any edit to the identity
  #   formula invalidates every entry, so a memo can never answer with an
  #   identity an older formula computed;
  # - the FULL file census, walked exactly as the identity walk walks
  #   (same recursion, same directory test, symlinks followed the same
  #   way): every file's relative path plus its (size, mtime_ns, ctime_ns,
  #   inode, device) from File.stat. A file added, removed, renamed,
  #   resized, retimed, rewritten in place, or replaced (new inode) changes
  #   the census, so the digest misses and the tree is fully re-hashed.
  #
  # == Why ctime closes the mtime hazard
  #
  # mtime is user-settable (touch -r, cp -p, rsync -t, File.utime): a
  # same-size in-place edit with its mtime restored would keep (path,
  # size, mtime, inode) — the classic stale-cache hazard. ctime is NOT
  # user-settable: the kernel stamps it with the current clock on every
  # data or metadata change (utime itself included). So the remaining
  # hazard is only a change landing in the SAME clock tick as the ctime
  # the census recorded (the racy-git problem). It is closed by refusing to
  # STORE a racy census: the wall clock is read BEFORE the census, and if
  # any file's ctime or mtime is at or after (that time - RACY_WINDOW) the
  # identity is computed honestly and returned but not memoized. Every
  # stored entry therefore has all ctimes at least RACY_WINDOW older than
  # the moment the census began; any later change stamps a ctime at or
  # after that moment (minus at most the filesystem's timestamp
  # truncation, which the 2 s window covers — 1 s HFS+, 2 s FAT, ns APFS),
  # so it cannot equal the recorded one and the next census misses.
  #
  # Ordering: census first, then the hash. A change during the hash makes
  # the stored identity describe newer bytes than the census — but that
  # change also moved ctime past the census, so the stored key can never
  # match again (a guaranteed miss, never a stale hit).
  #
  # Documented residuals (all over-rebuild-safe or outside the model): a
  # system clock stepped BACKWARD by more than RACY_WINDOW between two
  # writes could in principle replay an old ctime — it would also have to
  # reproduce the exact nanosecond ctime, mtime, size and inode; a
  # filesystem that fakes ctime (some network/FUSE mounts) is out of model
  # — canonical/ lives on the local disk. Deleting the cache file, or a
  # full rebuild (which never READS the memo — mode :refresh — and so stays
  # the uncached reference), is always a correct reset.
  #
  # == Home
  #
  # db/canonical_identities.json — DERIVED data (the derivability law):
  # the memo is a pure function of canonical/ + code, recomputed on any
  # miss, and may be deleted at any time with zero correctness cost (the
  # next sweep simply pays the full hash once). Unreadable or malformed =
  # empty; an unwritable home = no memo (still correct).
  class CanonicalIdentityCache
    FILENAME = "canonical_identities.json"
    FORMAT = 1
    RACY_WINDOW_NS = 2_000_000_000
    NS = 1_000_000_000
    CODE_FILES = [__FILE__, File.join(__dir__, "derivation_fingerprint.rb")].freeze

    # +mode+ :use reads and writes the memo (the incremental sweep);
    # :refresh never reads but stores every fresh computation (the full
    # rebuild — the reference stays uncached while warming the next sweep).
    def self.for_config(config, mode:)
      new(path: File.join(config.db_dir, FILENAME), mode: mode)
    end

    # Seam (tests divert the clock to step past the racy window).
    def self.now = Time.now

    # Seam (tests divert it to simulate an identity-code edit).
    def self.code_digest
      Digest::SHA256.hexdigest(CODE_FILES.map { |file| Digest::SHA256.file(file).hexdigest }.join("\n"))
    end

    attr_reader :path, :mode, :stats

    def initialize(path:, mode: :use)
      raise ArgumentError, "mode must be :use or :refresh" unless %i[use refresh].include?(mode)

      @path = path
      @mode = mode
      @stats = Hash.new(0)
    end

    # The identity of +dir+: the memo's when the census proves the tree
    # unchanged, else the block's (the honest full computation), memoized
    # when the census is a plain, non-racy one. A git-bearing tree or an
    # unstattable file bypasses the memo entirely.
    def fetch(dir)
      started_ns = self.class.time_ns(self.class.now)
      census = census_of(dir)
      if census.nil?
        @stats[:bypass] += 1
        return yield
      end

      key = Digest::SHA256.hexdigest([FORMAT, self.class.code_digest, census[:digest]].join("\0"))
      entry = entries[dir]
      if mode == :use && entry && entry["key"] == key
        @stats[:hit] += 1
        return entry["identity"]
      end

      @stats[:miss] += 1
      identity = yield
      store(dir, key, identity) unless identity.nil? || racy?(census, started_ns)
      identity
    end

    def self.time_ns(time) = (time.tv_sec * NS) + time.tv_nsec

    private

    # Walk +dir+ exactly as DerivationFingerprint's identity walk does; nil
    # when a .git directory appears anywhere (not a plain tree) or a file
    # cannot be statted (the identity walk will raise or decide honestly).
    def census_of(dir)
      digest = Digest::SHA256.new
      newest = [0]
      return nil unless plain_census?(dir, dir, digest, newest)

      { digest: digest.hexdigest, newest_ns: newest.first }
    rescue SystemCallError
      nil
    end

    # Is +dir+ a plain tree? Feeds every file's census record into +digest+
    # (and the newest ctime/mtime into +newest+) on the way; false at the
    # first .git directory.
    def plain_census?(dir, root, digest, newest)
      return false if File.directory?(File.join(dir, ".git"))

      Dir.children(dir).sort.each do |name|
        full = File.join(dir, name)
        if File.directory?(full)
          return false unless plain_census?(full, root, digest, newest)

          next
        end
        stat = File.stat(full)
        mtime = self.class.time_ns(stat.mtime)
        ctime = self.class.time_ns(stat.ctime)
        newest[0] = [newest.first, mtime, ctime].max
        # A path never contains NUL, the numbers never do: unambiguous.
        digest << full.delete_prefix("#{root}#{File::SEPARATOR}") << "\0" <<
          [stat.size, mtime, ctime, stat.ino, stat.dev].join(",") << "\0"
      end
      true
    end

    def racy?(census, started_ns)
      return false if census[:newest_ns] < started_ns - RACY_WINDOW_NS

      @stats[:racy] += 1
      true
    end

    def entries
      @entries ||= load_entries
    end

    def load_entries
      data = JSON.parse(File.read(path))
      data.is_a?(Hash) && data["format"] == FORMAT && data["trees"].is_a?(Hash) ? data["trees"] : {}
    rescue SystemCallError, JSON::ParserError
      {}
    end

    # Atomic replace (tmp + rename): a concurrent or crashed writer leaves
    # either the old memo or the new one — at worst lost entries (misses).
    def store(dir, key, identity)
      entries[dir] = { "key" => key, "identity" => identity }
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{Process.pid}.tmp"
      File.write(tmp, JSON.generate("format" => FORMAT, "trees" => entries))
      File.rename(tmp, path)
    rescue SystemCallError
      nil
    end
  end
end
