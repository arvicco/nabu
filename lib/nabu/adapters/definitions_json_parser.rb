# frozen_string_literal: true

require "json"
require "cgi"
require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # The definitions-json parser family: a top-level JSON array of
    # {"word": String, "definitions": [String, ...]} records whose
    # definition strings carry the printed book's inline markup — <strong>
    # for bold forms and sense numerals, <i> for the English glosses. The
    # shape of stscoundrel's Cleasby-Vigfusson (1874) and Zoëga (1910)
    # editions (cleasby-vigfusson, zoega adapters).
    #
    # Per record, one DictionaryEntry:
    #
    # - entry_id: the word verbatim when it is unique in the file; a word
    #   printed more than once (homographs: 7 in Cleasby-Vigfusson, 1 in
    #   Zoëga at census) numbers EVERY occurrence 1-based in file order
    #   ("stefja:1", "stefja:2"). Upstream carries no ids, so the id is
    #   only as stable as the file's own order of homographs.
    # - key_raw / headword: the word, NFC.
    # - body: one line per definition, markup stripped, HTML entities
    #   decoded, whitespace collapsed, NFC (Normalize.nfc at this boundary —
    #   upstream carries 4 non-NFC records in Cleasby-Vigfusson).
    # - gloss: the first <i> span (the book's English) with at least three
    #   letters, trailing punctuation trimmed; nil when none.
    #
    # Deliberately unmined (declared): the source abbreviations in the
    # bodies (Fms., Nj., Grág. …) are print citations without a held
    # resolution target, and the <strong> forms are not split into
    # sub-entries — the body keeps both verbatim.
    class DefinitionsJsonParser
      ITALIC = %r{<i>(.*?)</i>}m
      TAG = /<[^>]+>/
      GLOSS_MIN_LETTERS = 3
      private_constant :ITALIC, :TAG, :GLOSS_MIN_LETTERS

      def initialize(language:)
        @language = language
      end

      def entries(path)
        records = load(path)
        counts = records.map { |record| word(record, path) }.tally
        seen = Hash.new(0)
        records.map do |record|
          w = word(record, path)
          seen[w] += 1
          build(record, w, counts[w] > 1 ? "#{w}:#{seen[w]}" : w)
        end
      end

      private

      def load(path)
        data = JSON.parse(SourceRead.utf8_file(path, label: "definitions-json"))
        raise Nabu::ParseError, "definitions-json: #{path}: top level is not an array" unless data.is_a?(Array)

        data
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "definitions-json: malformed JSON in #{path}: #{e.message}"
      end

      def word(record, path)
        w = record.is_a?(Hash) ? record["word"] : nil
        unless w.is_a?(String) && !w.strip.empty?
          raise Nabu::ParseError,
                "definitions-json: #{path}: record without a word"
        end

        Nabu::Normalize.nfc(w.strip)
      end

      def build(record, word, entry_id)
        definitions = Array(record["definitions"]).map { |d| Nabu::Normalize.nfc(d.to_s) }
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: word, language: @language,
          headword: word,
          headword_folded: Nabu::Normalize.search_form(word, language: @language),
          gloss: gloss(definitions),
          body: definitions.map { |d| plain(d) }.reject(&:empty?).join("\n")
        )
      end

      def gloss(definitions)
        definitions.each do |definition|
          definition.scan(ITALIC) do |(span)|
            text = plain(span).sub(/[\s;,:.]+\z/, "")
            return text if text.scan(/\p{L}/).size >= GLOSS_MIN_LETTERS
          end
        end
        nil
      end

      def plain(html)
        Nabu::Normalize.nfc(CGI.unescapeHTML(html.gsub(TAG, "")).gsub(/\s+/, " ").strip)
      end
    end
  end
end
