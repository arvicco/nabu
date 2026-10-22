# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "errors"
require_relative "model_output"

module Nabu
  # The SANCTIONED write gateway to the local-model-output shelf
  # (architecture §16 "the model-output convention"): every paid-model
  # lane's raw output and per-run provenance. Model output is
  # NON-DERIVABLE (it costs money to regenerate), so the derivability law
  # homes it here under local/shelves/, never db/; a lane's derived
  # product (a projection into the catalog, an index) is a separate,
  # owner-armed step over this shelf — the silver-dates mold.
  #
  # == Layout
  #
  #   local/shelves/local-model-output/<producer>/runs/<label>/<model>/
  #     config.json    the run's identity, written ONCE: producer, label,
  #                    model, backend, source path, params, and per stage
  #                    the FULL verbatim prompt + its version + sha256
  #     costs.tsv      append-only, one row per PAID call
  #                    (stage, unit, usd, backend) — flushed + fsynced per
  #                    call, so the run's spend survives any interruption
  #     outputs.jsonl  append-only, one row per paid call: the cache key,
  #                    its four recipe components, the output, generated_at
  #     torn.log       (only after a kill mid-write) the torn tail bytes
  #                    set aside on resume — audit, never re-read as rows
  #
  # == Runs: resume, sibling, never overwrite
  #
  # #open_run with a (producer, label, model) whose directory is absent
  # creates the run; one whose config.json carries the SAME identity
  # resumes it (finished units answer from the cache, costs keep
  # appending); a DIFFERENT identity under the same directory is a
  # RunConflict — a run is never overwritten. A rerun under a new model is
  # therefore a SIBLING directory under the same label by construction.
  #
  # == The cache
  #
  # #lookup(producer:, key:) answers from every run of the producer (the
  # latest row wins), indexed once per shelf instance and kept current by
  # this gateway's own appends. Stale keys (a bumped prompt version, a new
  # model) never match; #orphans censuses them — the shelf never deletes.
  class ModelShelf
    SLUG = "local-model-output"

    # Producer names and run labels: one lowercase path segment.
    SEGMENT = /\A[a-z0-9][a-z0-9._-]*\z/

    COSTS_FILE = "costs.tsv"
    OUTPUTS_FILE = "outputs.jsonl"
    CONFIG_FILE = "config.json"
    TORN_FILE = "torn.log"
    COSTS_HEADER = %w[stage unit usd backend].freeze

    class Error < Nabu::Error; end

    # An existing run directory whose recorded identity differs.
    class RunConflict < Error; end

    # A mid-file row the reader cannot faithfully parse (file:line).
    class FormatError < Error; end

    Cost = Data.define(:stage, :unit, :usd, :backend)

    # One cached model answer.
    Output = Data.define(:key, :urn, :tool, :prompt_version, :model, :output, :generated_at) do
      def self.from_h(hash)
        new(key: hash["key"], urn: hash["urn"], tool: hash["tool"], prompt_version: hash["prompt_version"],
            model: hash["model"], output: hash["output"], generated_at: hash["generated_at"])
      end

      def to_h
        { "key" => key, "urn" => urn, "tool" => tool, "prompt_version" => prompt_version,
          "model" => model, "output" => output, "generated_at" => generated_at }
      end
    end

    def self.dir(config)
      config.source_workdir(SLUG)
    end

    # A model id as a directory name: anything outside [A-Za-z0-9._-]
    # becomes "_" ("vendor/model:2026-10" → "vendor_model_2026-10").
    def self.model_dirname(model)
      model.to_s.gsub(/[^A-Za-z0-9._-]/, "_")
    end

    def initialize(dir:)
      @dir = dir
      @index = {}
    end

    attr_reader :dir

    # Create or resume the run (class note). +stages+ are
    # ModelOutput::Prompt objects; +source+ the input path the lane reads;
    # +params+ a JSON-able hash of every effective knob.
    def open_run(producer:, label:, model:, backend:, stages:, source:, params:, now: Time.now)
      check_segment!(producer, "producer")
      check_segment!(label, "run label")
      raise Error, "a run needs at least one prompt stage" if stages.empty?

      identity = run_identity(producer: producer, label: label, model: model, backend: backend,
                              stages: stages, source: source, params: params)
      run_dir = File.join(producer_dir(producer), "runs", label, self.class.model_dirname(model))
      config_path = File.join(run_dir, CONFIG_FILE)
      if File.file?(config_path)
        recorded = JSON.parse(File.read(config_path)).except("created_at")
        unless recorded == identity
          raise RunConflict, "#{run_dir} already holds a run with a different identity — " \
                             "a run is never overwritten; choose a new label"
        end
      else
        FileUtils.mkdir_p(run_dir)
        write_atomic(config_path, "#{JSON.pretty_generate(identity.merge('created_at' => now.utc.iso8601))}\n")
      end
      Run.new(dir: run_dir, stages: stages, on_output: ->(row) { remember(producer, row) })
    end

    # The cached answer for +key+ under +producer+, or nil.
    def lookup(producer:, key:)
      index(producer)[key]
    end

    # Every output row of +producer+, run order then line order.
    def outputs(producer:)
      run_dirs(producer).flat_map { |run_dir| Run.read_outputs(File.join(run_dir, OUTPUTS_FILE)) }
    end

    # The orphan census: rows whose prompt version is not +current+'s for
    # their tool ({ tool => version }), counted per [tool, version]. A
    # tool absent from +current+ counts whole (retired). Never deletes.
    def orphans(producer:, current:)
      outputs(producer: producer).each_with_object(Hash.new(0)) do |row, tally|
        next if current[row.tool] == row.prompt_version

        tally[[row.tool, row.prompt_version]] += 1
      end
    end

    private

    def producer_dir(producer) = File.join(@dir, producer)

    def run_dirs(producer)
      Dir.glob(File.join(producer_dir(producer), "runs", "*", "*")).select { |path| File.directory?(path) }.sort
    end

    def index(producer)
      @index[producer] ||= outputs(producer: producer).to_h { |row| [row.key, row] }
    end

    def remember(producer, row)
      index(producer)[row.key] = row
    end

    def run_identity(producer:, label:, model:, backend:, stages:, source:, params:)
      {
        "producer" => producer, "label" => label, "model" => model, "backend" => backend,
        "source" => source, "params" => JSON.parse(JSON.generate(params)),
        "stages" => stages.map do |prompt|
          { "tool" => prompt.tool, "prompt_version" => prompt.version, "prompt_sha256" => prompt.sha256,
            "prompt" => prompt.text }
        end
      }
    end

    def check_segment!(value, what)
      return if value.to_s.match?(SEGMENT)

      raise Error, "#{what} #{value.inspect} must be one lowercase path segment (#{SEGMENT.source})"
    end

    def write_atomic(path, body)
      tmp = "#{path}.tmp"
      File.write(tmp, body)
      File.rename(tmp, path)
    end

    # One run directory: the append-only sidecars. Appends are one write
    # of one whole line, flushed and fsynced — a kill can tear at most the
    # row in flight, which the reader reports (torn_rows) instead of
    # parsing, and the next append on resume sets aside to torn.log first
    # so it can never glue onto a fragment.
    class Run
      def self.read_outputs(path)
        lines, = split_lines(path)
        lines.each_with_index.map do |line, i|
          Output.from_h(JSON.parse(line))
        rescue JSON::ParserError => e
          raise FormatError, "malformed output row #{path}:#{i + 1}: #{e.message}"
        end
      end

      # [complete lines, torn tail or nil] — a final segment without its
      # newline is a torn write, never a row.
      def self.split_lines(path)
        return [[], nil] unless File.file?(path)

        body = File.read(path, encoding: "UTF-8")
        parts = body.split("\n", -1)
        torn = parts.pop
        [parts.reject(&:empty?), torn.to_s.empty? ? nil : torn]
      end

      def initialize(dir:, stages:, on_output:)
        @dir = dir
        @stages = stages
        @on_output = on_output
      end

      attr_reader :dir, :stages

      def stage?(prompt)
        @stages.any? do |stage|
          stage.tool == prompt.tool && stage.version == prompt.version && stage.text == prompt.text
        end
      end

      def append_cost!(stage:, unit:, usd:, backend:)
        [stage, unit, backend].each do |field|
          raise Error, "costs.tsv field #{field.inspect} carries a tab or newline" if field.to_s.match?(/[\t\n]/)
        end
        path = File.join(@dir, COSTS_FILE)
        append_line!(path, COSTS_HEADER.join("\t")) unless File.file?(path)
        append_line!(path, [stage, unit, format("%.6f", usd), backend].join("\t"))
      end

      def append_output!(row)
        append_line!(File.join(@dir, OUTPUTS_FILE), JSON.generate(row.to_h))
        @on_output.call(row)
        row
      end

      def costs
        lines, = self.class.split_lines(File.join(@dir, COSTS_FILE))
        lines.drop(1).each_with_index.map do |line, i|
          stage, unit, usd, backend = line.split("\t", -1)
          raise FormatError, "malformed cost row #{File.join(@dir, COSTS_FILE)}:#{i + 2}" if backend.nil?

          Cost.new(stage: stage, unit: unit, usd: Float(usd), backend: backend)
        end
      end

      def total_usd = costs.sum(&:usd)

      # Torn tails currently sitting at the end of the sidecars.
      def torn_rows
        [COSTS_FILE, OUTPUTS_FILE].filter_map { |name| self.class.split_lines(File.join(@dir, name)).last }
      end

      private

      def append_line!(path, line)
        set_aside_torn_tail!(path)
        File.open(path, "a") do |file|
          file.write("#{line}\n")
          file.flush
          file.fsync
        end
      end

      # Cheap on the hot path: only a file whose LAST byte is not a newline
      # (the rare post-kill state) is read whole.
      def set_aside_torn_tail!(path)
        return unless File.file?(path) && File.size(path).positive?
        return if File.open(path, "rb") { |file| file.seek(-1, IO::SEEK_END) && file.read(1) } == "\n"

        _, torn = self.class.split_lines(path)
        return if torn.nil?

        File.open(File.join(@dir, TORN_FILE), "a") do |log|
          log.write("#{Time.now.utc.iso8601}\t#{File.basename(path)}\t#{torn}\n")
        end
        File.truncate(path, File.size(path) - torn.bytesize)
      end
    end
  end
end
