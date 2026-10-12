# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"
require "json"
require "yaml"

module Export
  # Nabu::Export::Writer (P121-1): the exporter frame — streams any
  # registered table's rows to CSV or JSONL and writes the license manifest
  # beside the data file. A fake table isolates the frame from the catalog.
  class WriterTest < Minitest::Test
    Column = Nabu::Export::Column
    Row = Nabu::Export::Row

    # The smallest object honoring the table contract (Nabu::Export class
    # note): NAME, SUMMARY, columns, filters, each_row, notes.
    class FakeTable
      NAME = "fake"
      SUMMARY = "A fake table for frame tests"

      attr_reader :seen_license_classes

      def initialize(rows)
        @rows = rows
      end

      def columns
        [Column.new(name: "urn", description: "the urn"),
         Column.new(name: "year", description: "a signed year"),
         Column.new(name: "license_class", description: "effective class")]
      end

      def filters = { "source" => nil }

      def notes = { "fake_note" => 1 }

      def each_row(license_classes: nil, &)
        @seen_license_classes = license_classes
        @rows.each(&)
      end
    end

    def rows
      [Row.new(values: ["urn:a", -300, "open"], draws: [%w[alpha open]]),
       Row.new(values: ["urn:b", nil, "nc"], draws: [%w[beta nc]]),
       Row.new(values: ["urn:c, with comma", 14, "open"], draws: [%w[alpha open]])]
    end

    def write(out, format: "csv", license_classes: nil, clock: -> { Time.utc(2026, 10, 12, 9, 0, 0) },
              table: FakeTable.new(rows))
      Nabu::Export::Writer.new(out_dir: out, format: format, license_classes: license_classes, clock: clock)
                          .write(table)
    end

    def test_csv_writes_a_header_and_one_line_per_row_with_null_as_empty
      Dir.mktmpdir do |out|
        result = write(out)
        assert_equal File.join(out, "fake.csv"), result.data_path
        table = CSV.read(result.data_path)
        assert_equal %w[urn year license_class], table.first
        assert_equal ["urn:a", "-300", "open"], table[1]
        assert_equal ["urn:b", nil, "nc"], table[2], "NULL is an empty cell"
        assert_equal ["urn:c, with comma", "14", "open"], table[3], "commas are quoted, not split"
        assert_equal 3, result.rows
      end
    end

    def test_jsonl_writes_one_typed_object_per_row
      Dir.mktmpdir do |out|
        result = write(out, format: "jsonl")
        assert_equal File.join(out, "fake.jsonl"), result.data_path
        lines = File.readlines(result.data_path).map { |line| JSON.parse(line) }
        assert_equal 3, lines.size
        assert_equal({ "urn" => "urn:a", "year" => -300, "license_class" => "open" }, lines.first)
        assert_nil lines[1].fetch("year"), "NULL stays a JSON null"
      end
    end

    def test_manifest_names_the_table_filters_rows_and_every_source_drawn_on
      Dir.mktmpdir do |out|
        result = write(out)
        assert_equal File.join(out, "fake.manifest.yml"), result.manifest_path
        manifest = YAML.safe_load_file(result.manifest_path)
        assert_equal "fake", manifest.fetch("table")
        assert_equal "A fake table for frame tests", manifest.fetch("description")
        assert_equal "2026-10-12T09:00:00Z", manifest.fetch("generated_at")
        assert_equal "csv", manifest.fetch("format")
        assert_equal "fake.csv", manifest.fetch("data_file")
        assert_equal Digest::SHA256.file(result.data_path).hexdigest, manifest.fetch("data_sha256")
        assert_equal 3, manifest.fetch("total_rows")
        assert_equal({ "source" => nil, "license_class" => nil }, manifest.fetch("filters"))
        assert_equal [{ "name" => "urn", "description" => "the urn" },
                      { "name" => "year", "description" => "a signed year" },
                      { "name" => "license_class", "description" => "effective class" }],
                     manifest.fetch("columns")
        assert_equal [{ "source" => "alpha", "license_class" => "open", "rows" => 2 },
                      { "source" => "beta", "license_class" => "nc", "rows" => 1 }],
                     manifest.fetch("sources")
        assert_equal({ "fake_note" => 1 }, manifest.fetch("notes"))
        assert_equal Nabu::VERSION, manifest.fetch("nabu_version")
      end
    end

    def test_license_filter_keeps_only_rows_whose_every_draw_is_in_the_set
      Dir.mktmpdir do |out|
        table = FakeTable.new(rows + [Row.new(values: ["urn:d", 1, "open"], draws: [%w[alpha open], %w[beta nc]]),
                                      Row.new(values: ["urn:e", 2, nil], draws: [[nil, nil]])])
        result = write(out, license_classes: %w[open attribution], table: table)
        assert_equal %w[open attribution], table.seen_license_classes, "the filter is pushed down too"
        urns = CSV.read(result.data_path, headers: true).map { |row| row["urn"] }
        assert_equal ["urn:a", "urn:c, with comma"], urns,
                     "an nc draw, a mixed draw, and an unresolved draw all fall out"
        manifest = YAML.safe_load_file(result.manifest_path)
        assert_equal %w[open attribution], manifest.dig("filters", "license_class")
        assert_equal [{ "source" => "alpha", "license_class" => "open", "rows" => 2 }], manifest.fetch("sources")
        assert_equal 2, manifest.fetch("total_rows")
      end
    end

    def test_an_unresolved_draw_is_not_a_source_but_the_row_rides_when_unfiltered
      Dir.mktmpdir do |out|
        table = FakeTable.new([Row.new(values: ["urn:e", 2, nil], draws: [[nil, nil]])])
        result = write(out, table: table)
        assert_equal 1, result.rows
        assert_empty YAML.safe_load_file(result.manifest_path).fetch("sources")
      end
    end

    def test_unknown_format_and_unknown_license_class_are_refused
      Dir.mktmpdir do |out|
        error = assert_raises(Nabu::Export::Error) { write(out, format: "xlsx") }
        assert_match(/csv, jsonl/, error.message)
        error = assert_raises(Nabu::Export::Error) { write(out, license_classes: %w[open bogus]) }
        assert_match(/bogus/, error.message)
        assert_match(/attribution/, error.message, "the refusal names the valid classes")
      end
    end

    def test_two_runs_are_byte_identical_except_generated_at
      Dir.mktmpdir do |out|
        first = write(out, clock: -> { Time.utc(2026, 1, 1) })
        data = File.binread(first.data_path)
        manifest = File.read(first.manifest_path)
        second = write(out, clock: -> { Time.utc(2026, 2, 2) })
        assert_equal data, File.binread(second.data_path)
        strip = ->(text) { text.lines.reject { |line| line.start_with?("generated_at:") }.join }
        refute_equal manifest, File.read(second.manifest_path), "generated_at moved"
        assert_equal strip.call(manifest), strip.call(File.read(second.manifest_path))
      end
    end

    def test_writes_leave_no_staging_debris_and_create_the_out_dir
      Dir.mktmpdir do |root|
        out = File.join(root, "deep", "exports")
        write(out)
        assert_equal %w[fake.csv fake.manifest.yml], Dir.children(out).sort
      end
    end

    def test_progress_ticks_on_the_given_interval
      Dir.mktmpdir do |out|
        ticks = []
        Nabu::Export::Writer.new(out_dir: out, format: "csv", clock: -> { Time.now },
                                 progress: ->(count) { ticks << count }, progress_every: 2)
                            .write(FakeTable.new(rows))
        assert_equal [2], ticks
      end
    end
  end
end
