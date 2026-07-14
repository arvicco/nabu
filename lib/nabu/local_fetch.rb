# frozen_string_literal: true

require "digest"
require "json"

module Nabu
  # The NO-NETWORK fetch strategy behind `sync_policy: local` sources (P19-1,
  # architecture §16) — GitFetch/ZipFetch/FileFetch's sibling for shelves
  # whose "upstream" is the owner (or a sanctioned agent path) placing files
  # under canonical/<slug>/ directly. Sync = re-scan the tree; there is
  # nothing to download and nothing this fetch can restore, so its whole job
  # is INTEGRITY ACCOUNTING:
  #
  # - validates the tree exists and is non-empty (a missing local shelf is a
  #   FetchError with guidance, never a silent empty sync);
  # - sha256-hashes every live file and reports the map — the adapter turns
  #   it into per-file FetchReport#repos entries, so the EXISTING ledger-pin
  #   machinery (SyncRunner#update_pins) records one pin per file and `nabu
  #   health` can hold the tree against the pins (corruption/deletion
  #   surfaces there; see Health::Invariants#local_shelf_integrity);
  # - attic semantics on deletion, within honest limits: this fetch runs
  #   AFTER any deletion happened, so it cannot copy bytes that are already
  #   gone. The sanctioned retire flow is MOVING a file into
  #   <dir>/.attic/<same relative path> (by hand today; tooling later) —
  #   discover_with_attic then rediscovers it retained, exactly like every
  #   other source. A file that vanished WITHOUT an attic copy is reported
  #   (Result#vanished, with its last-known sha kept in the pin map so the
  #   pin lingers and health stays loud until the owner restores it from
  #   backup/git or attics it deliberately);
  # - the house mass-deletion breaker: when more than
  #   Adapter::MASS_DELETION_THRESHOLD of the previously scanned files
  #   vanished un-atticked, Nabu::SyncAborted is raised BEFORE the state file
  #   advances (--force proceeds, honestly noting the loss).
  #
  # State file (.local-fetch.json, the ZipFetch/FileFetch pattern): the
  # relative-path → sha256 map of the last completed scan — what "vanished
  # since last scan" is judged against, and what a 304-equivalent would be if
  # local scans were not already cheap enough to run unconditionally.
  class LocalFetch
    # Tree-level failure (missing/empty dir). Adapters wrap it in FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".local-fetch.json"

    # What one completed scan found: the tree digest (+sha+ — sha256 over the
    # sorted per-file sha lines, the FetchReport pin), the live per-file sha
    # map, the files that vanished un-atticked since the last scan (rel path
    # → last-known sha), and how many retired properly into the attic.
    Result = Data.define(:sha, :files, :vanished, :retired)

    def self.sync!(dir:, attic_dir:, force: false, hint: nil)
      new(dir: dir, attic_dir: attic_dir, hint: hint).sync!(force: force)
    end

    # +hint+ (P19-4): an optional shelf-specific "how to populate me" tail
    # for the missing-tree error — each shelf knows its own front door.
    def initialize(dir:, attic_dir:, hint: nil)
      @dir = dir
      @attic_dir = attic_dir
      @hint = hint
    end

    def sync!(force: false)
      files = scan
      if files.empty?
        raise Error, "no local tree at #{@dir} — place files there first" \
                     "#{" (#{@hint})" if @hint}"
      end
      previous = state
      vanished, retired = classify_missing(previous, files)
      guard_mass_deletion!(previous, vanished) unless force
      write_state!(files)
      Result.new(sha: tree_sha(files), files: files, vanished: vanished, retired: retired)
    end

    private

    # Every live file under the tree, excluding the state file and the attic:
    # relative path → sha256 of its bytes.
    def scan
      return {} unless Dir.exist?(@dir)

      attic_prefix = attic_relprefix
      Dir.glob("**/*", File::FNM_DOTMATCH, base: @dir)
         .reject { |rel| rel.end_with?(".") }
         .select { |rel| File.file?(File.join(@dir, rel)) }
         .reject { |rel| rel == STATE_FILE || (attic_prefix && rel.start_with?(attic_prefix)) }
         .sort
         .to_h { |rel| [rel, Digest::SHA256.file(File.join(@dir, rel)).hexdigest] }
    end

    # Previously scanned files no longer live: in the attic → retired (the
    # sanctioned flow — its pin drops, the attic copy carries the asset);
    # not in the attic → vanished (last-known sha kept, pin lingers, health
    # shouts).
    def classify_missing(previous, files)
      vanished = {}
      retired = 0
      previous.each do |rel, sha|
        next if files.key?(rel)

        if File.file?(File.join(@attic_dir, rel))
          retired += 1
        else
          vanished[rel] = sha
        end
      end
      [vanished, retired]
    end

    # Same threshold and abort type as every other fetch path — but judged
    # over un-atticked disappearances only (a deliberate retire is not loss).
    def guard_mass_deletion!(previous, vanished)
      return if previous.empty? || vanished.empty?
      return if vanished.size <= Adapter::MASS_DELETION_THRESHOLD * previous.size

      raise SyncAborted.new(existing_count: previous.size, would_withdraw_count: vanished.size,
                            threshold: Adapter::MASS_DELETION_THRESHOLD)
    end

    def tree_sha(files)
      Digest::SHA256.hexdigest(files.map { |rel, sha| "#{rel} #{sha}\n" }.join)
    end

    def state
      path = File.join(@dir, STATE_FILE)
      return {} unless File.file?(path)

      JSON.parse(File.read(path)).fetch("files", {})
    rescue JSON::ParserError
      {}
    end

    def write_state!(files)
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate({ "files" => files }))
    end

    def attic_relprefix
      dir = File.expand_path(@dir)
      attic = File.expand_path(@attic_dir)
      return nil unless attic.start_with?("#{dir}#{File::SEPARATOR}")

      "#{attic.delete_prefix("#{dir}#{File::SEPARATOR}")}#{File::SEPARATOR}"
    end
  end
end
