# frozen_string_literal: true

require "csv"
require "digest"
require "fileutils"
require "json"
require "yaml"

require_relative "../version"
require_relative "types"
require_relative "../model/validation"

module Nabu
  module Export
    # The exporter frame (P121-1): drives one table's row stream into a
    # data file and writes the manifest beside it. Format-agnostic tables,
    # table-agnostic frame — the format switch, the license filter, and the
    # manifest live here once.
    #
    # Rows stream straight to disk (one row in memory at a time, plus the
    # per-source tally). Both files are written to a staging name and
    # renamed into place, so an interrupted export never leaves a
    # half-written file posing as a finished one. Re-running the same
    # export over the same catalog yields byte-identical data (and a
    # manifest differing only in generated_at): tables stream in a stable
    # order and nothing time-dependent enters a row.
    class Writer
      MANIFEST_SUFFIX = ".manifest.yml"
      # const: progress cadence for the operator's tick line, not a corpus claim
      PROGRESS_EVERY = 100_000

      # +license_classes+: nil = every class (the manifest still names each
      # source drawn on); else the allowed effective classes — a row
      # survives only if EVERY draw falls inside the set (an edge carries
      # both endpoints' classes; an unresolved endpoint cannot be vouched
      # for). +progress+ (callable) receives the running row count every
      # +progress_every+ rows.
      def initialize(out_dir:, format:, license_classes: nil, clock: -> { Time.now }, progress: nil,
                     progress_every: PROGRESS_EVERY)
        @out_dir = out_dir
        @format = validate_format(format)
        @license_classes = validate_classes(license_classes)
        @clock = clock
        @progress = progress
        @progress_every = progress_every
      end

      def write(table)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        FileUtils.mkdir_p(@out_dir)
        name = table.class::NAME
        data_path = File.join(@out_dir, "#{name}.#{@format}")
        tally, rows, sha = stream(table, data_path)
        manifest_path = File.join(@out_dir, "#{name}#{MANIFEST_SUFFIX}")
        stage(manifest_path) { |io| io.write(YAML.dump(manifest(table, data_path, rows, sha, tally))) }
        Result.new(table: name, data_path: data_path, manifest_path: manifest_path, rows: rows,
                   seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end

      private

      def validate_format(format)
        return format if FORMATS.include?(format)

        raise Error, "unknown export format #{format.inspect} (choose from #{FORMATS.join(', ')})"
      end

      def validate_classes(classes)
        return nil if classes.nil?

        known = Nabu::Model::Validation::LICENSE_CLASSES
        unknown = classes - known
        return classes.uniq if unknown.empty? && !classes.empty?

        raise Error, "unknown license class #{unknown.join(', ').inspect} (choose from #{known.join(', ')})"
      end

      # Stream every admitted row into +path+; returns [tally, rows, sha256].
      def stream(table, path)
        names = table.columns.map(&:name)
        tally = Hash.new(0)
        rows = 0
        digest = Digest::SHA256.new
        stage(path) do |io|
          emit(io, digest, CSV.generate_line(names)) if @format == "csv"
          table.each_row(license_classes: @license_classes) do |row|
            next unless admitted?(row)

            emit(io, digest, serialize(names, row.values))
            row.draws.uniq.each { |slug, license| tally[[slug, license]] += 1 if slug }
            rows += 1
            @progress&.call(rows) if (rows % @progress_every).zero?
          end
        end
        [tally, rows, digest.hexdigest]
      end

      # One serialized line to disk, folded into the data file's sha256.
      def emit(io, digest, line)
        digest << line
        io.write(line)
      end

      def admitted?(row)
        @license_classes.nil? || row.draws.all? { |_slug, license| @license_classes.include?(license) }
      end

      def serialize(names, values)
        return CSV.generate_line(values) if @format == "csv"

        "#{JSON.generate(names.zip(values).to_h)}\n"
      end

      # Write through a staging file, then rename into place (atomic on one
      # filesystem); the staging file never survives a failure.
      def stage(path, &)
        staging = "#{path}.partial"
        File.open(staging, "wb", &)
        File.rename(staging, path)
      ensure
        FileUtils.rm_f(staging) if staging && File.exist?(staging)
      end

      def manifest(table, data_path, rows, sha, tally)
        {
          "table" => table.class::NAME,
          "description" => table.class::SUMMARY,
          "generated_at" => @clock.call.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
          "nabu_version" => Nabu::VERSION,
          "format" => @format,
          "data_file" => File.basename(data_path),
          "data_sha256" => sha,
          "filters" => table.filters.merge("license_class" => @license_classes),
          "total_rows" => rows,
          "columns" => table.columns.map { |column| { "name" => column.name, "description" => column.description } },
          "sources" => source_entries(tally),
          "notes" => table.notes
        }
      end

      # One entry per (source, effective class) drawn on, slug-ordered — a
      # source whose documents carry license overrides lists once per class.
      def source_entries(tally)
        tally.sort_by { |(slug, license), _| [slug, license.to_s] }.map do |(slug, license), count|
          { "source" => slug, "license_class" => license, "rows" => count }
        end
      end
    end
  end
end
