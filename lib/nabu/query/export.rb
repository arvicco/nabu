# frozen_string_literal: true

require "json"

module Nabu
  module Query
    # `nabu export`: stream the corpus out in a durable, tool-agnostic form
    # (maintenance §7 — exit formats are first-class; the data must survive the
    # code). Two formats in v1:
    #
    #   plain  one passage per line, internal newlines collapsed to spaces.
    #   jsonl  one JSON object per line: urn, language, text, text_normalized,
    #          annotations. `annotations` is the PARSED annotations_json, so the
    #          line carries a real nested object — never a double-encoded string.
    #
    # CoNLL-U is deferred to the enrichment phase (it needs the token model);
    # the CLI rejects `--format conllu` with that message.
    #
    # == Streaming, always
    #
    # The corpus is ~238k passages, so #run NEVER materializes: it returns an
    # Enumerator that pulls rows from the Sequel dataset one at a time and emits
    # already-serialized lines. `.first(n)` or `.lazy` consume only what they
    # take. The CLI writes each line as it arrives (no join).
    #
    # Same corpus-visibility rules as Search: only non-withdrawn passages of
    # non-withdrawn documents, with the same effective-license semantics
    # (document override coalesced over source class) and exact-class filter.
    class Export
      FORMATS = %w[plain jsonl].freeze

      def initialize(catalog:)
        @catalog = catalog
      end

      # Return an Enumerator of serialized lines (Strings, no trailing newline).
      # +format+ is "plain" or "jsonl"; +lang+/+license+ are optional filters.
      def run(format:, lang: nil, license: nil)
        serialize = serializer(format)
        dataset = export_dataset(lang: lang, license: license)
        Enumerator.new do |yielder|
          dataset.each { |row| yielder << serialize.call(row) }
        end
      end

      private

      def serializer(format)
        case format
        when "plain" then method(:serialize_plain)
        when "jsonl" then method(:serialize_jsonl)
        else raise ArgumentError, "unknown export format: #{format.inspect}"
        end
      end

      # Plain text: collapse any internal newline runs to a single space so one
      # passage stays on one line, then trim edges.
      def serialize_plain(row)
        row.fetch(:text).gsub(/\s*\n+\s*/, " ").strip
      end

      def serialize_jsonl(row)
        JSON.generate(
          urn: row.fetch(:urn),
          language: row.fetch(:language),
          text: row.fetch(:text),
          text_normalized: row.fetch(:text_normalized),
          annotations: parse_annotations(row.fetch(:annotations_json))
        )
      end

      # annotations_json is stored as canonical JSON (default "{}"); parse it so
      # the emitted line carries a JSON object, not a quoted string. A NULL or
      # blank column degrades to an empty object.
      def parse_annotations(json)
        return {} if json.nil? || json.strip.empty?

        JSON.parse(json)
      rescue JSON::ParserError
        {}
      end

      # Live passages (passage and its document both non-withdrawn), optionally
      # filtered by language and effective license class, in stable primary-key
      # order (index-backed, so the stream never buffers a sort).
      def export_dataset(lang:, license:)
        dataset = @catalog[:passages]
                  .join(:documents, id: Sequel[:passages][:document_id])
                  .join(:sources, id: Sequel[:documents][:source_id])
                  .where(Sequel[:passages][:withdrawn] => false,
                         Sequel[:documents][:withdrawn] => false)
        dataset = dataset.where(Sequel[:passages][:language] => lang) if lang
        dataset = dataset.where(license_expr => license) if license
        dataset.select(*columns).order(Sequel[:passages][:id])
      end

      # Effective license class: document override wins over source class (P1-3).
      def license_expr
        Sequel.function(:coalesce,
                        Sequel[:documents][:license_override],
                        Sequel[:sources][:license_class])
      end

      def columns
        [
          Sequel[:passages][:urn],
          Sequel[:passages][:language],
          Sequel[:passages][:text],
          Sequel[:passages][:text_normalized],
          Sequel[:passages][:annotations_json]
        ]
      end
    end
  end
end
