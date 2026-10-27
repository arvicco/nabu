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
                           :source, :corpus, :copyright, :url, :page_path, :entities)

      # == The named-entity markup (P146)
      #
      # Some records carry a parallel content.body_xml (and title_xml)
      # whose <ner_TYPE>…</ner_TYPE> spans mark names inside the plain
      # body; xml line N is body line N (censused: every ilseongnok
      # record holding both splits to the same line count). Full-slice
      # census (2026-10-27, all 16 files): ilseongnok 323,658 records —
      # 인물 1,531,000 · 관직 1,135,039 · 관서 312,431 · 지명 283,505 ·
      # 건물 142,860 · 물건 108,338 · 세주 42,637 · 서명 35,647 · 능원
      # 21,446 · 주석 37; aks_kyu_nhm (the AKS royal-court documents) 287
      # records — person 2,723 · place 941; klc 396 records — unknown
      # 6,929 · 948a54 1,869. No other file carries the field.
      #
      # ENTITY_TYPES (the TYPE after the tag's ner_ namespace, verbatim)
      # are the NAME classes. Skipped by rule as text structure, not
      # names: ilseongnok's 세주 (interlinear small-note) and 주석
      # (annotation); klc's "unknown" (the cyclical-year heads of 年譜
      # chronologies) and "948a54" (a colour class over 吐 reading
      # particles). The aks spans are visibly machine-grade (比國人禮雍
      # splits as person 人禮) — carried verbatim as upstream's own claim.
      # The grain is the passage (the line): a span's text rides the line
      # it sits on, without character offsets (the EpidocParser
      # InlineLayer shape). A record whose xml line count disagrees with
      # its body carries no entities — never guessed.
      ENTITY_TYPES = %w[인물 관직 관서 지명 건물 물건 서명 능원 person place].freeze
      NER_SPAN = %r{<ner_([^<>/\s]+)>(.*?)</ner_\1>}m

      LANGUAGES = {
        "Classical Chinese" => "lzh",
        "Hanmun" => "lzh",
        "Middle Korean" => "okm",
        "Early Modern Korean" => "ko",
        "Korean" => "ko",
        "Modern Korean" => "ko",
        "North Korean" => "ko",
        "Japanese" => "jpn",
        # The first-sync census (2026-09-01, 1,198,780 records): the gongu
        # PD collection and the legation records carry Western-language
        # documents — 2,735 English + 25 French, quarantined by the
        # unknown-label net exactly as designed, classified here (the held
        # en/fra codes).
        "English" => "en",
        "French" => "fra"
      }.freeze

      # Parse one jsonl line into a Record. Raises Nabu::ParseError on
      # malformed JSON or an unknown language label — the record (never the
      # file) quarantines.
      def self.parse_record(line)
        row = JSON.parse(line)
        label = row["language"].to_s
        language = LANGUAGES[label] or
          raise Nabu::ParseError, "okhc: unknown language label #{label.inspect} — classify it before ingesting"

        content = row["content"] || {}
        body = content["body"] || row["text"] || ""
        lines = body_lines(body)
        Record.new(
          id: row.fetch("id"),
          title: presence(row.dig("content", "title")) || row["corpus"] || row.fetch("id"),
          lines: lines, language: language, year: row["year"],
          script: presence(row["script"]), source: presence(row["source"]),
          corpus: presence(row["corpus"]),
          # The deposit names the field copyright_status; the repo's older
          # sample.jsonl says copyright (schema drift found at the first
          # sync — read both, deposit spelling first).
          copyright: presence(row["copyright_status"] || row["copyright"]),
          url: presence(row["url"]), page_path: presence(row.dig("metadata", "page_path")),
          entities: line_entities(content, lines)
        )
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "okhc: malformed jsonl record: #{e.message[0, 120]}"
      end

      def self.body_lines(body)
        body.split("\n").map { |text| Normalize.nfc(text.strip) }.reject(&:empty?)
      end

      # Per passage line: the NAME spans its xml twin marks (nil when none).
      # The twin is body_xml when the body is present, else title_xml (a
      # body-less record's passages ARE its title — composition
      # "{title}\n{body}"). Lines pair by index after the SAME blank-line
      # filter the body takes; a count mismatch carries nothing.
      def self.line_entities(content, lines)
        xml = content.key?("body") ? content["body_xml"] : content["title_xml"]
        xml_lines = body_lines(xml.to_s)
        return Array.new(lines.size) unless xml_lines.size == lines.size

        xml_lines.map do |line|
          spans = line.scan(NER_SPAN).filter_map do |type, text|
            text = Normalize.nfc(text.strip)
            { "type" => type, "text" => text } if ENTITY_TYPES.include?(type) && !text.empty?
          end
          spans.empty? ? nil : spans
        end
      end

      def self.presence(value)
        value.nil? || value == "" ? nil : value
      end
      private_class_method :presence, :body_lines, :line_entities
    end
  end
end
