# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

require_relative "errors"

module Nabu
  # The Manual Adapter pattern (P63-1, ruling Dp-a): shared machinery for
  # upstreams a machine cannot fetch (captcha interstitials, POST-form dumps,
  # account walls) but a human can. The adapter declares a Spec; `nabu sync`
  # then behaves in one of three honest ways:
  #
  #   - nothing held, nothing dropped  → AwaitingAcquisition, whose MESSAGE is
  #     the instruction card (upstream URL, steps, expected files, the exact
  #     incoming/<slug>/ drop path) — a clean abort, never a stack;
  #   - a drop present under incoming/<slug>/ → validated (each FileSpec's
  #     sniff), previous holding atticked, files MOVED into canonical/<slug>/,
  #     `.manual-fetch.json` provenance stamped (per-file sha256, acquisition
  #     mtime, ingest time, upstream URL) — the `.zip-fetch.json` analogue;
  #   - a held ingest and no (or byte-identical) drop → no-op reporting the
  #     stored pin, canonical untouched.
  #
  # Identical re-drops are left in incoming/ (the owner's file is never
  # deleted); refused drops are never consumed. Provenance and idempotency
  # thereby work exactly like fetched sources — same-sha = no-op, replaced
  # holdings survive in the attic.
  class ManualDrop
    STATE_FILE = ".manual-fetch.json"

    # One expected drop file. `sniff` is a callable(path) returning nil when
    # the file looks right or ONE plain sentence when it must be refused
    # (a saved captcha page, a truncated download). Optional files ride along
    # when offered and are never demanded by the card.
    FileSpec = Data.define(:name, :description, :required, :sniff)

    # What one completed sync did: the combined pin, whether bytes moved.
    Result = Data.define(:sha, :ingested, :not_modified)

    # The awaiting state IS the message — subclassing FetchError keeps every
    # existing abort path (CLI rescue, sync runner) printing it clean.
    class AwaitingAcquisition < Nabu::FetchError; end

    # The adapter-declared acquisition contract.
    Spec = Data.define(:slug, :upstream_url, :steps, :files, :refresh_hint) do
      def instruction_card(drop_dir:)
        lines = ["#{slug} awaits manual acquisition — this upstream needs a human " \
                 "(captcha/form), by design.", ""]
        steps.each_with_index { |step, i| lines << "  #{i + 1}. #{step}" }
        lines << ""
        lines << "Get it from: #{upstream_url}"
        lines << "Then place the download here:"
        files.each do |f|
          suffix = f.required ? "" : " (optional)"
          lines << "  #{File.join(drop_dir, f.name)}   — #{f.description}#{suffix}"
        end
        lines << ""
        lines << "Re-run this sync once the files are in place. #{refresh_hint}"
        lines.join("\n")
      end
    end

    def self.sync!(spec:, drop_dir:, dir:, attic_dir:, progress: nil)
      new(spec: spec, drop_dir: drop_dir, dir: dir, attic_dir: attic_dir, progress: progress).sync!
    end

    # The combined pin over the stored per-file shas — deterministic, order-
    # independent, repeated verbatim by no-op syncs.
    def self.pin(dir)
      state = read_state(dir)
      files = state["files"]
      return nil unless files.is_a?(Hash) && !files.empty?

      Digest::SHA256.hexdigest(files.sort.map { |name, sha| "#{name}:#{sha}" }.join("\n"))
    end

    def self.read_state(dir)
      path = File.join(dir, STATE_FILE)
      return {} unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    def initialize(spec:, drop_dir:, dir:, attic_dir:, progress: nil)
      @spec = spec
      @drop_dir = drop_dir
      @dir = dir
      @attic_dir = attic_dir
      @progress = progress
    end

    def sync!
      offered = offered_files
      held = self.class.read_state(@dir)["files"] || {}
      unless required_offered_complete?(offered)
        # A held shelf with an empty (or optional-only) drop is simply up to
        # date; anything else is the awaiting state, and the card is the message.
        return no_op_result if !held.empty? && offered.none? { |f, _| f.required }

        raise AwaitingAcquisition, @spec.instruction_card(drop_dir: @drop_dir)
      end

      validate!(offered)
      shas = offered.to_h { |f, path| [f.name, Digest::SHA256.file(path).hexdigest] }
      return no_op_result if identical?(shas, held)

      ingest!(offered, shas, held)
      Result.new(sha: self.class.pin(@dir), ingested: true, not_modified: false)
    end

    private

    # [FileSpec, absolute drop path] for every expected file present in the drop.
    def offered_files
      @spec.files.filter_map do |f|
        path = File.join(@drop_dir, f.name)
        [f, path] if File.file?(path)
      end
    end

    def required_offered_complete?(offered)
      names = offered.map { |f, _| f.name }
      @spec.files.select(&:required).all? { |f| names.include?(f.name) }
    end

    def no_op_result
      Result.new(sha: self.class.pin(@dir), ingested: false, not_modified: true)
    end

    def validate!(offered)
      offered.each do |f, path|
        complaint = f.sniff.call(path)
        raise Nabu::FetchError, "#{@spec.slug}: #{f.name} refused — #{complaint}" if complaint
      end
    end

    # Every offered sha matches the held pin AND the held file is still on
    # disk — only then is a re-drop a no-op (drop copies left in place).
    def identical?(shas, held)
      return false if held.empty?

      shas.all? { |name, sha| held[name] == sha && File.file?(File.join(@dir, name)) }
    end

    def ingest!(offered, shas, held)
      acquired_at = offered.map { |_, path| File.mtime(path) }.max
      attic!(offered)
      FileUtils.mkdir_p(@dir)
      offered.each { |f, path| FileUtils.mv(path, File.join(@dir, f.name)) }
      state = {
        "files" => held.merge(shas).sort.to_h,
        "acquired_at" => acquired_at.utc.iso8601,
        "ingested_at" => Time.now.utc.iso8601,
        "upstream_url" => @spec.upstream_url
      }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # Replaced holdings survive under <attic>/manual-<stamp>/ — the GitFetch
    # attic discipline; nothing under canonical/ ever just vanishes.
    def attic!(offered)
      doomed = offered.filter_map { |f, _| f.name if File.file?(File.join(@dir, f.name)) }
      return if doomed.empty?

      stamp_dir = File.join(@attic_dir, "manual-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}")
      FileUtils.mkdir_p(stamp_dir)
      doomed.each { |name| FileUtils.mv(File.join(@dir, name), File.join(stamp_dir, name)) }
    end
  end
end
