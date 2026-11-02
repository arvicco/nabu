# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "errors"

module Nabu
  # The SANCTIONED write gateway to the local-meter shelf (P152,
  # architecture §16) — the EIGHTH local-shelf gateway, the DateShelf mold
  # at passage grain: the scansion lane's machine output (silver scansions
  # of Greek/Latin dactylic verse, Nabu::Scansion) is HEAVY-derived under
  # the cost law — a full-corpus pass over ~6.8M lat/grc passages, run only
  # by its own command (`nabu scan-meter --run`), never by a rebuild — so
  # it lives on a shelf, never in db/. The SilverMeter projection, the
  # census and the health check stay read-only on it.
  #
  # == Layout
  #
  #   local/shelves/local-meter/shard-NNNNNN.jsonl
  #   local/shelves/local-meter/.projection-armed.json
  #
  # Shards are append-only JSONL. Two record kinds:
  #
  #   passage  — one line's verdict: urn, language, the passage's
  #              content_sha256 at scan time (the input identity —
  #              staleness is a sha mismatch), status scanned/unscanned,
  #              and for a scanned line meter/feet/quantities/
  #              word_pattern/basis (unscanned: the reason);
  #   document — the verse gate's verdict for a document whose lines did
  #              not scan as dactylic verse (urn, passages, scanned), so a
  #              resumed campaign skips it without shelving its prose.
  #
  # Every record carries the scanner name + version and generated_at. A
  # later record for the same urn SUPERSEDES an earlier one (shard order,
  # then line order) — a re-run under a new scanner version appends, it
  # never rewrites history. A shard lands whole via tmp + validate + rename.
  class MeterShelf
    SLUG = "local-meter"

    SHARD_GLOB = "shard-*.jsonl"
    SHARD_FORMAT = "shard-%06d.jsonl"

    # The owner's projection ruling (dot-prefixed: furniture, never a shard).
    ARM_FILE = ".projection-armed.json"

    KINDS = %w[passage document].freeze
    STATUSES = %w[scanned unscanned].freeze
    METERS = %w[hexameter pentameter].freeze
    BASES = %w[unique laws defaults].freeze
    LANGUAGES = %w[lat grc].freeze

    class Error < Nabu::Error; end
    class FormatError < Nabu::Error; end

    FIELDS = %i[kind urn language content_sha256 status meter feet quantities word_pattern basis reason
                passages scanned scanner scanner_version generated_at].freeze

    Record = Data.define(*FIELDS) do
      def initialize(**fields)
        super(**FIELDS.to_h { |f| [f, nil] }.merge(fields))
      end

      def self.from_h(hash)
        new(**FIELDS.to_h { |f| [f, hash[f.to_s]] })
      end

      def to_h = FIELDS.to_h { |f| [f.to_s, public_send(f)] }.compact

      def passage? = kind == "passage"

      def scanned? = status == "scanned"
    end

    # The shelf's census over its LATEST records (the bare `scan-meter`
    # card and the health check): scanned / unscanned lines, document gate
    # records, the newest generated_at, the scanner versions present, and
    # how many lines an older scanner than the running one produced (the
    # code-staleness half; text staleness needs the catalog —
    # Store::SilverMeter#project! and #drop_stale! count it).
    Census = Data.define(:scanned, :unscanned, :gates, :newest, :versions, :old_code) do
      def self.of(shelf, current: Scansion::VERSION)
        counts = Hash.new(0)
        versions = Hash.new(0)
        newest = nil
        shelf.latest_by_urn.each_value do |record|
          newest = record.generated_at if newest.nil? || record.generated_at.to_s > newest
          versions[record.scanner_version] += 1
          key = record.passage? ? record.status.to_sym : :gates
          counts[key] += 1
          counts[:old_code] += 1 if record.passage? && record.scanner_version != current
        end
        new(scanned: counts[:scanned], unscanned: counts[:unscanned], gates: counts[:gates], newest: newest,
            versions: versions.sort.to_h, old_code: counts[:old_code])
      end
    end

    def self.dir(config)
      config.source_workdir(SLUG)
    end

    # The shelf when it exists on this box, else nil (the replay rails
    # hand Store::SilverMeter.replay! an absent shelf as nil — nothing to
    # project, honestly).
    def self.present(config)
      dir = dir(config)
      Dir.exist?(dir) ? new(dir: dir) : nil
    end

    def initialize(dir:)
      @dir = dir
    end

    attr_reader :dir

    # Append one batch as the next numbered shard: every record validated
    # BEFORE any byte lands, staged to .tmp, reparsed whole, renamed into
    # place. A record without generated_at is stamped +now+. Returns the
    # shard path.
    def append_batch!(records:, now: Time.now)
      raise Error, "refusing an empty batch — nothing to shelve" if records.empty?

      stamp = now.utc.iso8601
      records = records.map { |record| record.generated_at ? record : record.with(generated_at: stamp) }
      records.each { |record| validate!(record) }
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
        File.foreach(path).with_index(1) { |line, lineno| yield parse_line(line, path, lineno) }
      end
      nil
    end

    # { urn => Record } — the LATEST record per urn (supersession by shelf
    # order), both kinds.
    def latest_by_urn
      latest = {}
      each_record { |record| latest[record.urn] = record }
      latest
    end

    def shard_paths
      return [] unless Dir.exist?(@dir)

      Dir[File.join(@dir, SHARD_GLOB)]
    end

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

    def parse_line(line, path, lineno)
      hash = JSON.parse(line)
      raise JSON::ParserError, "not a JSON object" unless hash.is_a?(Hash)

      record = Record.from_h(hash)
      validate!(record)
      record
    rescue JSON::ParserError, Error => e
      raise FormatError, "malformed meter shard #{File.basename(path)}:#{lineno} (#{path}): #{e.message}"
    end

    private

    def arm_path = File.join(@dir, ARM_FILE)

    def next_shard_number
      last = shard_paths.map { |p| p[/shard-(\d+)\.jsonl\z/, 1].to_i }.max || 0
      last + 1
    end

    def validate!(record)
      urn = record.urn.to_s.strip
      raise Error, "a meter record needs a urn" if urn.empty?
      raise Error, "#{urn}: kind must be one of #{KINDS.join('/')}" unless KINDS.include?(record.kind)
      raise Error, "#{urn}: needs scanner provenance (scanner + scanner_version)" if
        [record.scanner, record.scanner_version].any? { |value| value.to_s.strip.empty? }

      record.passage? ? validate_passage!(urn, record) : validate_document!(urn, record)
    end

    def validate_passage!(urn, record)
      raise Error, "#{urn}: language must be one of #{LANGUAGES.join('/')}" unless LANGUAGES.include?(record.language)
      raise Error, "#{urn}: needs the passage content_sha256 it scanned" if record.content_sha256.to_s.empty?
      raise Error, "#{urn}: status must be scanned/unscanned" unless STATUSES.include?(record.status)

      if record.scanned?
        raise Error, "#{urn}: meter must be one of #{METERS.join('/')}" unless METERS.include?(record.meter)
        raise Error, "#{urn}: feet must be D/S" unless record.feet.to_s.match?(/\A[DS]{2,5}\z/)
        raise Error, "#{urn}: quantities must be -/u" unless record.quantities.to_s.match?(/\A[-u]{12,17}\z/)
        raise Error, "#{urn}: basis must be one of #{BASES.join('/')}" unless BASES.include?(record.basis)
      elsif record.reason.to_s.empty?
        raise Error, "#{urn}: an unscanned record names its reason"
      end
    end

    def validate_document!(urn, record)
      raise Error, "#{urn}: a document gate record carries passages + scanned counts" unless
        record.passages.is_a?(Integer) && record.scanned.is_a?(Integer)
    end

    def revalidate!(tmp)
      File.foreach(tmp).with_index(1) { |line, lineno| parse_line(line, tmp, lineno) }
    rescue FormatError
      FileUtils.rm_f(tmp)
      raise
    end
  end
end
