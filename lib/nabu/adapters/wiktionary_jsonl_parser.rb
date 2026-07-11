# frozen_string_literal: true

require "json"

require_relative "../normalize"

module Nabu
  module Adapters
    # The wiktionary-jsonl parser family (P13-10): kaikki.org's wiktextract
    # extraction of English Wiktionary — the third dictionary format after
    # TEI (lexica) and CSV (Bosworth-Toller). One JSON object per LINE, one
    # record per WORD x POS x etymology section; streamed line by line (the
    # OCS extract is 44 MB, the format scales to the GB-sized extracts).
    #
    # == What one record yields (Nabu::DictionaryEntry)
    #
    # - entry_id: "<word>:<pos>" + ":<etymology_number>" when present —
    #   kaikki records carry NO top-level id and `word` alone is not unique
    #   (homographs split by pos/etymology_number: и:character:1 / и:conj:2 /
    #   и:pron:3). Ten pairs in the full OCS file STILL collide (боль:noun
    #   x2, видимъ:verb:2 x2 …); those get a positional ":<n>" suffix in
    #   file order (the 2nd occurrence is ":2"). Stable while upstream file
    #   order is stable; a reorder is a revision, handled by the loader's
    #   content-sha semantics.
    # - key_raw: the `word` field verbatim (the Wiktionary page title).
    # - headword: the same, NFC.
    # - headword_folded: Normalize.search_form with the entry language — the
    #   generic chu fold (downcase + combining-mark strip: the titlo U+0483
    #   in ан҃г is \p{Mn} and falls away; jers/yuses are letters and stay),
    #   the same both-sides contract as lemma search (conventions §9).
    # - gloss: the first gloss string of the first glossed sense — the
    #   parent-most gloss of wiktextract's nesting path ("word, speech,
    #   utterance", not the leaf "word"); a trailing colon is trimmed
    #   ("inflection of видѣти (viděti):"). nil is honest for the no-gloss
    #   records (suffix stubs, unglossed form-of entries).
    # - body: the etymology_text paragraph KEPT verbatim first — it carries
    #   the Proto-Slavic/PIE chains the reconstruction axis will join on
    #   (improvements register) — then one line per sense: raw_glosses
    #   preferred over glosses (raw keeps the "(anatomy)" context labels),
    #   nesting path joined with " — ", numbered "N. " only when the record
    #   has several senses. A gloss-less sense renders its upstream `tags`
    #   in parens ("(morpheme, no-gloss)") so the body is never empty. NFC.
    # - citations: always empty — Wiktionary's quotations are unanchored
    #   (no urns), the Bosworth-Toller precedent exactly.
    class WiktionaryJsonlParser
      # Parse +path+ and return DictionaryEntry values in file order.
      # +language+ is the ISO 639-3 code the entries carry and fold by;
      # kaikki's own lang_code is 639-1 ("cu") and stays in the raw record.
      def initialize(language: "chu")
        @language = language
      end

      def entries(path)
        occurrences = Hash.new(0)
        each_record(path).map do |record, line_number|
          build_entry(record, occurrences, path: path, line_number: line_number)
        end
      end

      private

      def each_record(path)
        return enum_for(:each_record, path) unless block_given?

        File.foreach(path, encoding: Encoding::UTF_8).with_index(1) do |line, line_number|
          next if line.strip.empty?

          begin
            yield JSON.parse(line), line_number
          rescue JSON::ParserError => e
            raise Nabu::ParseError, "wiktionary-jsonl: malformed JSON at line #{line_number} " \
                                    "of #{path}: #{e.message}"
          end
        end
      end

      def build_entry(record, occurrences, path:, line_number:)
        word = record["word"]
        base_id = entry_id_base(record)
        occurrences[base_id] += 1
        entry_id = occurrences[base_id] > 1 ? "#{base_id}:#{occurrences[base_id]}" : base_id

        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: word, language: @language,
          headword: Nabu::Normalize.nfc(word.to_s),
          headword_folded: Nabu::Normalize.search_form(word.to_s, language: @language),
          gloss: gloss(record),
          body: body_text(record),
          citations: []
        )
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "wiktionary-jsonl: record at line #{line_number} " \
                                "of #{path} (word=#{word.inspect}): #{e.message}"
      end

      def entry_id_base(record)
        id = "#{record['word']}:#{record['pos']}"
        ety = record["etymology_number"]
        ety ? "#{id}:#{ety}" : id
      end

      def gloss(record)
        first = Array(record["senses"]).find { |sense| Array(sense["glosses"]).any? }
        return nil unless first

        text = first["glosses"].first.to_s.gsub(/\s+/, " ").strip.sub(/:\z/, "")
        text.empty? ? nil : Nabu::Normalize.nfc(text)
      end

      def body_text(record)
        senses = Array(record["senses"])
        numbered = senses.size > 1
        lines = senses.each_with_index.map do |sense, index|
          line = sense_line(sense)
          numbered ? "#{index + 1}. #{line}" : line
        end
        etymology = record["etymology_text"].to_s.strip
        text = [etymology, *lines].reject(&:empty?).join("\n")
        Nabu::Normalize.nfc(text)
      end

      def sense_line(sense)
        path = Array(sense["raw_glosses"])
        path = Array(sense["glosses"]) if path.empty?
        if path.empty?
          tags = Array(sense["tags"])
          tags.empty? ? "(no gloss)" : "(#{tags.join(', ')})"
        else
          path.map { |gloss| gloss.to_s.gsub(/\s+/, " ").strip }.join(" — ")
        end
      end
    end
  end
end
