# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "errors"

module Nabu
  # The SANCTIONED write gateway to the local-dates shelf (P122-1,
  # architecture §16) — the SIXTH local-shelf gateway, the LemmaShelf
  # mold at document grain: model- or tool-emitted date ESTIMATES are
  # NON-DERIVABLE (paid or compute-heavy output — the derivability law
  # routes it to a shelf, never db/), so they land here through this one
  # gateway, driven by `nabu silver-dates --import`. Everything else — the
  # SilverDates projection, its census — stays read-only on the shelf.
  #
  # == Layout
  #
  #   local/shelves/local-dates/shard-NNNNNN.jsonl
  #   local/shelves/local-dates/.projection-armed.json
  #
  # Shards are append-only JSONL, one DOCUMENT estimate per line: urn,
  # not_before/not_after (signed historical years, BCE negative, no year
  # 0; either bound may be open), the basis label the estimator claims
  # ("model", "stylometry", …), the estimator's name + version, an
  # optional confidence in [0, 1] and free note. A shard lands whole via
  # tmp + validate + rename (the LemmaShelf rule). A later estimate for the
  # same urn SUPERSEDES an earlier one (shard order, then line order) — a
  # re-run never has to rewrite history to correct it.
  #
  # == The arm marker
  #
  # The projection into the timeline is the OWNER's act (`nabu
  # silver-dates --project`), recorded here as shelf furniture so it
  # survives `nabu rebuild`: an armed shelf re-projects at every rebuild
  # flavor, builder refresh and sync; an unarmed one never reaches db/.
  # `--retract` removes the marker (and the projected rows).
  class DateShelf
    # The shelf's directory name under local/shelves/.
    SLUG = "local-dates"

    SHARD_GLOB = "shard-*.jsonl"
    SHARD_FORMAT = "shard-%06d.jsonl"

    # The owner's projection ruling (dot-prefixed: furniture, never a shard).
    ARM_FILE = ".projection-armed.json"

    # A basis label is one lowercase word (hyphens allowed): it renders in
    # every silver date's provenance string.
    BASIS_NAME = /\A[a-z][a-z0-9-]*\z/

    # A gateway refusal (invalid record, unknown urn, empty batch). The CLI
    # reports it; nothing was written.
    class Error < Nabu::Error; end

    # A shard or import line the reader cannot faithfully parse — raised
    # naming file:line; the projection must never guess past it.
    class FormatError < Nabu::Error; end

    # One document's date estimate plus provenance.
    Record = Data.define(:urn, :not_before, :not_after, :basis, :estimator, :estimator_version,
                         :confidence, :note, :generated_at) do
      def self.from_h(hash)
        new(urn: hash["urn"], not_before: hash["not_before"], not_after: hash["not_after"],
            basis: hash["basis"], estimator: hash["estimator"],
            estimator_version: hash["estimator_version"], confidence: hash["confidence"],
            note: hash["note"], generated_at: hash["generated_at"])
      end

      def to_h
        { "urn" => urn, "not_before" => not_before, "not_after" => not_after, "basis" => basis,
          "estimator" => estimator, "estimator_version" => estimator_version,
          "confidence" => confidence, "note" => note, "generated_at" => generated_at }
      end
    end

    def self.dir(config)
      config.source_workdir(SLUG)
    end

    # The shelf when it exists on this box, else nil — what the replay
    # rails hand Store::SilverDates.replay! (an absent shelf projects
    # nothing, honestly).
    def self.present(config)
      dir = dir(config)
      Dir.exist?(dir) ? new(dir: dir) : nil
    end

    # Parse an import file (JSONL, one estimate object per line; blank
    # lines skipped) into Records — the --import front door's reader. A
    # malformed line raises FormatError naming file:line; validation is
    # append_batch!'s.
    def self.read_import(path)
      File.foreach(path).with_index(1).filter_map do |line, lineno|
        next if line.strip.empty?

        hash = JSON.parse(line)
        raise JSON::ParserError, "not a JSON object" unless hash.is_a?(Hash)

        Record.from_h(hash)
      rescue JSON::ParserError => e
        raise FormatError, "malformed estimate #{File.basename(path)}:#{lineno}: #{e.message}"
      end
    end

    # +resolver+ (a callable urn → boolean, optional) is consulted for
    # every record BEFORE any byte lands — an estimate for a urn the
    # catalog does not hold would sit unprojectable forever (the NoteShelf
    # rule); +force+ on the append skips it deliberately.
    def initialize(dir:, resolver: nil)
      @dir = dir
      @resolver = resolver
    end

    attr_reader :dir

    # Append one batch as the next numbered shard. Every record is
    # validated (and resolved, unless +force+) BEFORE any byte lands; the
    # shard is staged to .tmp, reparsed whole, and only then renamed into
    # place. A record without generated_at is stamped +now+. Returns the
    # shard path.
    def append_batch!(records:, force: false, now: Time.now)
      raise Error, "refusing an empty batch — nothing to shelve" if records.empty?

      records = records.map { |record| record.generated_at ? record : record.with(generated_at: now.utc.iso8601) }
      records.each { |record| validate!(record) }
      resolve!(records) unless force
      FileUtils.mkdir_p(@dir)
      path = File.join(@dir, format(SHARD_FORMAT, next_shard_number))
      tmp = "#{path}.tmp"
      File.write(tmp, records.map { |record| JSON.generate(record.to_h) }.join("\n") << "\n")
      revalidate!(tmp)
      File.rename(tmp, path)
      path
    end

    # Stream every record, shard order then line order.
    def each_record
      shard_paths.each do |path|
        File.foreach(path).with_index(1) do |line, lineno|
          yield parse_line(line, path, lineno)
        end
      end
      nil
    end

    # { urn => Record } — the LATEST estimate per urn (supersession by
    # shelf order; class note).
    def latest_by_urn
      latest = {}
      each_record { |record| latest[record.urn] = record }
      latest
    end

    def shard_paths
      return [] unless Dir.exist?(@dir)

      Dir[File.join(@dir, SHARD_GLOB)]
    end

    # -- the owner's projection ruling ----------------------------------

    def armed?
      File.file?(arm_path)
    end

    # Record the owner's projection ruling (tmp + rename). Idempotent: a
    # re-arm keeps the first ruling's timestamp.
    def arm!(now: Time.now)
      return arm_path if armed?

      FileUtils.mkdir_p(@dir)
      tmp = "#{arm_path}.tmp"
      File.write(tmp, JSON.pretty_generate("armed_at" => now.utc.iso8601))
      File.rename(tmp, arm_path)
      arm_path
    end

    def disarm!
      FileUtils.rm_f(arm_path)
      nil
    end

    # Parse one shard line into a Record. A malformed line raises
    # FormatError naming shard:line.
    def parse_line(line, path, lineno)
      hash = JSON.parse(line)
      raise JSON::ParserError, "not a JSON object" unless hash.is_a?(Hash)

      record = Record.from_h(hash)
      validate!(record)
      record
    rescue JSON::ParserError, Error => e
      raise FormatError, "malformed date shard #{File.basename(path)}:#{lineno} (#{path}): #{e.message}"
    end

    private

    def arm_path = File.join(@dir, ARM_FILE)

    def next_shard_number
      last = shard_paths.map { |p| p[/shard-(\d+)\.jsonl\z/, 1].to_i }.max || 0
      last + 1
    end

    def validate!(record)
      urn = record.urn.to_s.strip
      raise Error, "a date estimate needs a urn" if urn.empty?

      validate_bounds!(record)
      unless record.basis.is_a?(String) && BASIS_NAME.match?(record.basis)
        raise Error, "estimate #{urn} needs a basis label (one lowercase word, e.g. \"model\") — " \
                     "got #{record.basis.inspect}"
      end
      if [record.estimator, record.estimator_version].any? { |value| value.to_s.strip.empty? }
        raise Error, "estimate #{urn} needs estimator provenance (estimator + estimator_version)"
      end
      unless record.confidence.nil? || (record.confidence.is_a?(Numeric) && record.confidence.between?(0, 1))
        raise Error, "estimate #{urn}: confidence must be a number in [0, 1] — got #{record.confidence.inspect}"
      end
      raise Error, "estimate #{urn}: note must be text" unless record.note.nil? || record.note.is_a?(String)
    end

    # Signed historical years (Nabu::Timeline): integers, no year 0, at
    # least one bound, never reversed.
    def validate_bounds!(record)
      bounds = [record.not_before, record.not_after]
      raise Error, "estimate #{record.urn} carries no bound — an empty estimate is not shelf material" \
        if bounds.all?(&:nil?)

      bounds.compact.each do |year|
        raise Error, "estimate #{record.urn}: bounds are signed integer years — got #{year.inspect}" \
          unless year.is_a?(Integer)
        raise Error, "estimate #{record.urn}: there is no year 0 (1 BCE is -1, 1 CE is 1)" if year.zero?
      end
      return unless bounds.none?(&:nil?) && record.not_before > record.not_after

      raise Error, "estimate #{record.urn}: not_before #{record.not_before} is after not_after #{record.not_after}"
    end

    def resolve!(records)
      return unless @resolver

      missing = records.map(&:urn).uniq.reject { |urn| @resolver.call(urn) }
      return if missing.empty?

      raise Error, "#{missing.size} estimate urn(s) the catalog does not hold as live documents: " \
                   "#{missing.first(5).join(', ')}#{' …' if missing.size > 5} — fix the urns, or --force " \
                   "to shelve them for documents not yet held"
    end

    # The staged shard must parse whole before it may claim a shard name.
    def revalidate!(tmp)
      File.foreach(tmp).with_index(1) { |line, lineno| parse_line(line, tmp, lineno) }
    rescue FormatError
      FileUtils.rm_f(tmp)
      raise
    end
  end
end
