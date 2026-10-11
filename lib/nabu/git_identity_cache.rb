# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

require_relative "canonical_identity_cache"

module Nabu
  # A memo of GIT-REPO identity tokens (DerivationFingerprint's per-repo
  # `git:<path>:<HEAD>` token plus its attic and declared-materialization
  # bytes) so the incremental rebuild's verdict sweep stops paying
  # `git status --porcelain` + `git rev-parse HEAD` for every embedded repo
  # on every run — kanripo alone carries 5,162 repos, ~80 s of the warm
  # sweep (Q124). The sibling of CanonicalIdentityCache (plain trees): the
  # same law, the same census discipline, the same racy guard.
  #
  # THE LAW: over-rebuilding is always safe; UNDER-REBUILDING IS THE SIN. A
  # stale hit — tokens returned for a repo whose HEAD or bytes they no
  # longer describe — would silently skip a dirty source. So a hit must be
  # impossible unless the repo is provably the one git vouched for, and
  # every doubt resolves to a MISS: the full git call, exactly the uncached
  # code path. A miss is always correct behavior, never an error.
  #
  # == What the git call vouches for, and what the census proves
  #
  # The uncached path stores a strong identity only when git says the
  # working tree is clean (or dirty only in the two vouched shapes) — "HEAD
  # names the bytes on disk" — and then names the repo by HEAD's sha. Weak
  # (nil) answers are NEVER stored: a dirty or doubtful repo pays the full
  # call on every sweep. A stored entry is therefore a past vouch; a hit
  # re-serves it only when a CENSUS proves nothing that vouch depended on
  # has changed since:
  #
  # - the working tree: every file under the repo except its own .git
  #   directory — tracked, untracked, ignored, the attic, declared
  #   materializations, nested repos' internals — as relative path plus
  #   (size, mtime_ns, ctime_ns, inode, device), walked exactly as
  #   CanonicalIdentityCache walks (directory test and stat both follow
  #   symlinks). Any edit, add, delete, rename or replace changes it: the
  #   bytes the vouch covered are byte-for-byte the bytes on disk.
  # - the git metadata HEAD and status read: every file under .git EXCEPT
  #   objects/, logs/ and hooks/ — HEAD, the index, packed-refs, every
  #   loose ref, config, info/ (exclude, sparse-checkout), shallow,
  #   FETCH_HEAD… A commit, checkout, reset, fetch, `git add` or a bare
  #   index touch changes it, so HEAD resolves to the same sha and git
  #   compares the same index against the same tree. The skipped dirs
  #   cannot move either answer: objects are content-addressed and
  #   immutable (the same HEAD sha names the same commit and tree forever),
  #   reflogs are history git never consults for HEAD or status, hooks do
  #   not run on status/rev-parse.
  # - the key's salt: the repo's root-relative path and its declared
  #   materializations (both shape the tokens), the identity code itself
  #   (the sha256 of this file, canonical_identity_cache.rb and
  #   derivation_fingerprint.rb — an edit to the identity formula
  #   invalidates every entry), and FORMAT.
  #
  # ctime closes the restored-mtime hazard and the racy guard closes the
  # same-tick hazard exactly as in CanonicalIdentityCache (see its doc): the
  # clock is read BEFORE the census, the census precedes the git call, and
  # a census with any file's ctime/mtime within RACY_WINDOW of that start is
  # answered honestly but never STORED. A change during the git call moves
  # a ctime past the census, so the stored key can never match again.
  #
  # The identity pass runs `git --no-optional-locks status`, so it never
  # refreshes .git/index itself — it is a pure reader of canonical/ (and a
  # self-written index would churn this memo's own key forever).
  #
  # Documented residuals (all outside the model or over-rebuild-safe): git
  # global/system config, the process environment and the git binary are
  # not keyed — they can change git's OPINION of a tree (clean ↔ dirty),
  # never the census-proven bytes or the HEAD a stored identity names, and
  # an entry exists only for a tree git once vouched clean with exactly
  # those bytes and that HEAD. A clock stepped backward by more than
  # RACY_WINDOW, or a filesystem that fakes ctime, is out of model, as for
  # the sibling. Deleting the memo, or a full rebuild (mode :refresh —
  # never READS, so stays the uncached reference), is always a correct
  # reset.
  #
  # == Home
  #
  # db/git_identities.json — DERIVED data (the derivability law): a pure
  # function of canonical/ + code, recomputed on any miss, deletable at any
  # time (the next sweep pays the git calls once). Unreadable or malformed
  # = empty; an unwritable home = no memo (still correct). Writes are
  # batched: #store only updates memory, #flush (called once per source
  # tree by DerivationFingerprint) replaces the file atomically — 5,162
  # repos must not mean 5,162 whole-file rewrites. A crash before a flush
  # loses entries (misses), never correctness.
  class GitIdentityCache
    FILENAME = "git_identities.json"
    FORMAT = 1
    RACY_WINDOW_NS = CanonicalIdentityCache::RACY_WINDOW_NS
    CODE_FILES = [__FILE__, File.join(__dir__, "canonical_identity_cache.rb"),
                  File.join(__dir__, "derivation_fingerprint.rb")].freeze
    # .git entries no HEAD/status answer depends on (class doc).
    UNKEYED_GIT_DIRS = %w[objects logs hooks].freeze

    # +mode+ as CanonicalIdentityCache: :use reads and writes (the
    # incremental sweep); :refresh never reads but stores (the full rebuild).
    def self.for_config(config, mode:)
      new(path: File.join(config.db_dir, FILENAME), mode: mode)
    end

    # Seam (tests divert the clock to step past the racy window).
    def self.now = Time.now

    # Seam (tests divert it to simulate an identity-code edit).
    def self.code_digest
      @code_digest ||= Digest::SHA256.hexdigest(
        CODE_FILES.map { |file| Digest::SHA256.file(file).hexdigest }.join("\n")
      )
    end

    attr_reader :path, :mode, :stats

    def initialize(path:, mode: :use)
      raise ArgumentError, "mode must be :use or :refresh" unless %i[use refresh].include?(mode)

      @path = path
      @mode = mode
      @stats = Hash.new(0)
      @dirty = false
    end

    # The tokens of the git repo at +repo+: the memo's when the census
    # proves the repo unchanged since git vouched for it, else the block's
    # (the honest full git call), memoized when strong and non-racy.
    # +salt+ carries everything else that shapes the tokens (root-relative
    # path, declared materializations). An uncensusable repo bypasses.
    def fetch(repo, salt:)
      started_ns = CanonicalIdentityCache.time_ns(self.class.now)
      census = census_of(repo)
      if census.nil?
        @stats[:bypass] += 1
        return yield
      end

      key = Digest::SHA256.hexdigest([FORMAT, self.class.code_digest, salt, census[:digest]].join("\0"))
      entry = entries[repo]
      if mode == :use && entry && entry["key"] == key && token_list?(entry["tokens"])
        @stats[:hit] += 1
        return entry["tokens"]
      end

      @stats[:miss] += 1
      tokens = yield
      store(repo, key, tokens) unless tokens.nil? || racy?(census, started_ns)
      tokens
    end

    # Persist the stores since the last flush (atomic tmp + rename: a
    # concurrent or crashed writer leaves the old memo or the new one).
    def flush
      return unless @dirty

      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{Process.pid}.tmp"
      File.write(tmp, JSON.generate("format" => FORMAT, "repos" => entries))
      File.rename(tmp, path)
      @dirty = false
    rescue SystemCallError
      nil
    end

    private

    def census_of(repo)
      git_dir = File.join(repo, ".git")
      return nil unless File.directory?(git_dir)

      digest = Digest::SHA256.new
      newest = [0]
      digest << "git\0"
      walk(git_dir, git_dir, digest, newest, skip: UNKEYED_GIT_DIRS)
      digest << "tree\0"
      walk(repo, repo, digest, newest, skip: %w[.git])
      { digest: digest.hexdigest, newest_ns: newest.first }
    rescue SystemCallError
      nil
    end

    # Feed every file under +dir+ (top-level names in +skip+ excepted) into
    # +digest+ as path + stat record; the newest ctime/mtime into +newest+.
    def walk(dir, root, digest, newest, skip: [])
      Dir.children(dir).sort.each do |name|
        next if skip.include?(name)

        full = File.join(dir, name)
        if File.directory?(full)
          walk(full, root, digest, newest)
          next
        end
        stat = File.stat(full)
        mtime = CanonicalIdentityCache.time_ns(stat.mtime)
        ctime = CanonicalIdentityCache.time_ns(stat.ctime)
        newest[0] = [newest.first, mtime, ctime].max
        # A path never contains NUL, the numbers never do: unambiguous.
        digest << full.delete_prefix("#{root}#{File::SEPARATOR}") << "\0" <<
          [stat.size, mtime, ctime, stat.ino, stat.dev].join(",") << "\0"
      end
    end

    def token_list?(tokens) = tokens.is_a?(Array) && tokens.all?(String)

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
      data.is_a?(Hash) && data["format"] == FORMAT && data["repos"].is_a?(Hash) ? data["repos"] : {}
    rescue SystemCallError, JSON::ParserError
      {}
    end

    def store(repo, key, tokens)
      entries[repo] = { "key" => key, "tokens" => tokens }
      @dirty = true
    end
  end
end
