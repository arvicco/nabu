# frozen_string_literal: true

require "fileutils"
require "json"

module Nabu
  # The many-repo git fetch (P33-0; architecture §8) — nabu's first source
  # whose upstream is not one repository but an ORG of them: github.com/
  # kanripo, 9,355 one-text repos (census 2026-07-20). Cloning the org
  # wholesale is neither wanted (scope is a per-class owner decision) nor
  # polite; this class composes the existing GitFetch discipline into a
  # catalog-driven, paced, resumable wave:
  #
  #   1. DISCOVERY INDEX — the KR-Catalog repo (org-mode catalogs, 3.4 MB)
  #      is itself synced through GitFetch (non-destructive pull, attic and
  #      all) into <dir>/KR-Catalog. The wave's scope is the `:KR_ID:`
  #      entries of the catalog files for the configured classes
  #      (KR/KR<class-letter>*.txt); a class with no catalog file is a loud
  #      Error, never a silent empty wave.
  #   2. PER-TEXT SHALLOW FETCHES — each in-scope text is its own GitFetch
  #      (`--depth 1`, master only: Kanripo keeps alternate editions as git
  #      BRANCHES — master carries the BASEEDITION working text, the census
  #      finding behind the one-branch decision). Texts are processed
  #      SEQUENTIALLY and each one completes (prepare → caller's guard →
  #      merge → ledger pin) before the next begins — deliberately NOT the
  #      UD all-prepare-then-merge choreography: at ~3,000 repos, holding
  #      every repo hostage to the last one would mean an interrupted wave
  #      pins NOTHING; here interruption loses at most the text in flight.
  #      The guard consequently protects at TEXT grain (each repo's doomed
  #      paths against its own files), which is also stricter than a
  #      source-wide fraction.
  #   3. POLITE PACING — every network operation (catalog pull, text clone
  #      or fetch, even a failed clone probe) is followed by +delay+
  #      seconds (DEFAULT_DELAY, conservative; the owner-adjustable knob is
  #      config/sources.yml documentation → Kanripo adapter). Skipped texts
  #      cost no network and no pause, so a resumed or unchanged wave is
  #      fast.
  #   4. RESUMABLE WAVES, PER-TEXT PINS — the fetch ledger
  #      (<dir>/.kanripo-fetch.json, the sefaria index-pin precedent
  #      git-flavored) records per text the fetched HEAD sha and the
  #      CATALOG sha it was fetched under. A text whose pin carries the
  #      current catalog sha is SKIPPED without touching the network — an
  #      interrupted wave resumes exactly where it died, refetching
  #      nothing. When the catalog advances, every pin is stale and each
  #      text gets one (cheap, usually no-op) fetch under the new catalog
  #      sha: catalog commit = wave identity. The ledger is rewritten after
  #      EVERY text, so a kill at any point loses at most one entry.
  #
  # Catalog ids with no matching repo are REAL (61 of the 2,989 wave-1 ids
  # at census): a clone failing with git's not-found signature is recorded
  # in the ledger as status "absent" under the current catalog sha —
  # censused, reported, retried once per catalog advance — while any other
  # failure (network, permission) aborts the wave loudly. The ledger lives
  # in the workdir root (BESIDE the per-text git repos, inside none of
  # them) and is derived state about canonical, not canonical content:
  # adapters' discover ignores it.
  class KanripoFetch
    # Fetch-layer failure that is not a Shell error: a class with no catalog
    # file, a malformed ledger. Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    CATALOG_DIRNAME = "KR-Catalog"
    LEDGER_FILE = ".kanripo-fetch.json"

    # Seconds between network operations. Conservative default — one text
    # every two seconds is ~25 min for the 732-text KR1 class; the owner had
    # no faster requirement and github gets a gentle, obviously non-abusive
    # request rhythm.
    DEFAULT_DELAY = 2.0

    KR_ID = /^:KR_ID:\s*(KR\d[a-z]\d{4})\s*$/
    ABSENT_SIGNATURE = /not found|does not exist|could not read|access denied|denied/i

    # What one wave did: the catalog pin, the per-outcome text id lists
    # (cloned/refreshed/absent), the count skipped via standing pins, and
    # the attic activity ("<id>/<relpath>" entries).
    Result = Data.define(:catalog_sha, :cloned, :refreshed, :skipped, :absent, :atticked)

    def self.sync!(catalog_url:, repo_base:, dir:, attic_dir:, classes:,
                   delay: DEFAULT_DELAY, progress: nil, guard: nil, sleeper: nil)
      new(catalog_url: catalog_url, repo_base: repo_base, dir: dir, attic_dir: attic_dir,
          classes: classes, delay: delay, progress: progress, guard: guard, sleeper: sleeper).sync!
    end

    def initialize(catalog_url:, repo_base:, dir:, attic_dir:, classes:,
                   delay: DEFAULT_DELAY, progress: nil, guard: nil, sleeper: nil)
      @catalog_url = catalog_url
      @repo_base = repo_base
      @dir = dir
      @attic_dir = attic_dir
      @classes = classes
      @delay = delay
      @progress = progress
      @guard = guard
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @cloned = []
      @refreshed = []
      @absent = []
      @skipped = 0
      @atticked = []
    end

    def sync!
      @catalog_sha = sync_catalog!
      scope_ids.each { |id| sync_text!(id) }
      Result.new(catalog_sha: @catalog_sha, cloned: @cloned, refreshed: @refreshed,
                 skipped: @skipped, absent: @absent, atticked: @atticked)
    end

    private

    # The discovery index rides the standard GitFetch contract (attic under
    # <attic_dir>/KR-Catalog); no guard — the catalog is scope metadata, not
    # ingestible content, and its deletions are atticked regardless.
    def sync_catalog!
      result = GitFetch.sync!(
        repo_url: @catalog_url, dir: catalog_dir,
        attic_dir: File.join(@attic_dir, CATALOG_DIRNAME), progress: @progress
      )
      pace!
      result.sha
    end

    # The wave scope: every :KR_ID: of every catalog file of the configured
    # classes, unique and sorted (stable resume order).
    def scope_ids
      @classes.flat_map { |kr_class| class_ids(kr_class) }.uniq.sort
    end

    def class_ids(kr_class)
      files = Dir.glob(File.join(catalog_dir, "KR", "#{kr_class}[a-z].txt"))
      raise Error, "#{@catalog_url}: no catalog files for class #{kr_class}" if files.empty?

      files.flat_map { |file| File.read(file).scan(KR_ID).flatten }
    end

    def sync_text!(id)
      return @skipped += 1 if pinned_current?(id)

      dir = text_dir(id)
      pull = GitFetch.new(repo_url: "#{@repo_base}/#{id}", dir: dir,
                          attic_dir: File.join(@attic_dir, id), progress: @progress)
      fresh = !Dir.exist?(File.join(dir, ".git"))
      return unless prepare_text!(pull, id, fresh: fresh)

      @guard&.call(dir, pull.doomed_paths)
      pull.complete!
      @atticked.concat(pull.atticked.map { |rel| "#{id}/#{rel}" })
      pin_text!(id, pull.head_sha)
      (fresh ? @cloned : @refreshed) << id
      pace!
    end

    # A text is current when its ledger pin was written under the current
    # catalog sha — including a standing "absent" verdict. Skips cost no
    # network; a vanished clone dir invalidates the pin (resume re-clones).
    def pinned_current?(id)
      pin = ledger.dig("texts", id)
      return false unless pin && pin["catalog_sha"] == @catalog_sha

      pin["status"] == "absent" || Dir.exist?(File.join(text_dir(id), ".git"))
    end

    # Phase 1 for one text. A FRESH clone failing with git's not-found
    # signature is the recorded-absent path (false = wave moves on); any
    # other Shell failure — and any failure on an EXISTING clone, where the
    # repo demonstrably existed — propagates to abort the wave.
    def prepare_text!(pull, id, fresh:)
      pull.prepare!
      true
    rescue Shell::Error => e
      raise unless fresh && absent_signature?(e)

      record_text!(id, { "status" => "absent", "catalog_sha" => @catalog_sha })
      @absent << id
      pace!
      false
    end

    # git's not-found voice lives in the captured stderr (Shell::Error keeps
    # it beside the message): "repository ... not found" on github,
    # "repository ... does not exist" on local transports.
    def absent_signature?(error)
      "#{error.message}\n#{error.stderr}".match?(ABSENT_SIGNATURE)
    end

    def pin_text!(id, sha)
      record_text!(id, { "sha" => sha, "catalog_sha" => @catalog_sha })
    end

    # Rewritten after every text — the resumability contract: a killed wave
    # keeps every completed pin.
    def record_text!(id, pin)
      state = ledger
      state["catalog"] = { "sha" => @catalog_sha }
      (state["texts"] ||= {})[id] = pin
      File.write(ledger_path, JSON.pretty_generate(state))
      @ledger = state
    end

    def ledger
      @ledger ||= read_ledger
    end

    def read_ledger
      return {} unless File.file?(ledger_path)

      parsed = JSON.parse(File.read(ledger_path))
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {} # a corrupt ledger only costs resume skips, never the wave
    end

    def pace!
      @sleeper.call(@delay) if @delay.positive?
    end

    def catalog_dir = File.join(@dir, CATALOG_DIRNAME)
    def text_dir(id) = File.join(@dir, id)
    def ledger_path = File.join(@dir, LEDGER_FILE)
  end
end
