# frozen_string_literal: true

require "json"
require_relative "../normalize"

module Nabu
  module Adapters
    # OKHC jsonl parser family (P91-1): one line of an Open Korean
    # Historical Corpus file is one RECORD — a titled, dated,
    # URL-addressable entry (an annal entry, a day's court record, a munjip
    # item). The schema (the deposit's own): id ("<corpus-prefix>:<id>"),
    # text (the body, newline-lined), content{body,title}, year, language
    # (a human label), script, source (institution), corpus (work name),
    # copyright (PER-RECORD — "Public Domain" or null/other), url
    # (permanent), metadata{page_path}.
    #
    # The LANGUAGES table maps the edition's labels onto the library's
    # codes: Literary Sinitic labels ("Classical Chinese", "Hanmun" — the
    # Korean-context name for the same written language) ride the held
    # Korean shelves' lzh precedent; the Korean stages stay honest-coarse
    # `ko` (the stage refinement is a posture/date-band story, never a
    # parse-time guess); "Middle Korean" alone claims okm (the held
    # ko-wikisource-mk precedent). An unknown label quarantines the record
    # loudly — a new label must be classified, never silently dropped.
    module OkhcJsonlParser
      Record = Data.define(:id, :title, :lines, :language, :year, :script,
                           :source, :corpus, :copyright, :url, :page_path)

      LANGUAGES = {
        "Classical Chinese" => "lzh",
        "Hanmun" => "lzh",
        "Middle Korean" => "okm",
        "Early Modern Korean" => "ko",
        "Korean" => "ko",
        "Modern Korean" => "ko",
        "North Korean" => "ko",
        "Japanese" => "jpn"
      }.freeze

      # Parse one jsonl line into a Record. Raises Nabu::ParseError on
      # malformed JSON or an unknown language label — the record (never the
      # file) quarantines.
      def self.parse_record(line)
        row = JSON.parse(line)
        label = row["language"].to_s
        language = LANGUAGES[label] or
          raise Nabu::ParseError, "okhc: unknown language label #{label.inspect} — classify it before ingesting"

        body = row.dig("content", "body") || row["text"] || ""
        lines = body.split("\n").map { |text| Normalize.nfc(text.strip) }.reject(&:empty?)
        Record.new(
          id: row.fetch("id"),
          title: presence(row.dig("content", "title")) || row["corpus"] || row.fetch("id"),
          lines: lines, language: language, year: row["year"],
          script: presence(row["script"]), source: presence(row["source"]),
          corpus: presence(row["corpus"]), copyright: presence(row["copyright"]),
          url: presence(row["url"]), page_path: presence(row.dig("metadata", "page_path"))
        )
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "okhc: malformed jsonl record: #{e.message[0, 120]}"
      end

      def self.presence(value)
        value.nil? || value == "" ? nil : value
      end
      private_class_method :presence
    end
  end
end
