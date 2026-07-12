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
    # - reflexes (P14-1, opt-in via reflexes: true): the worded nodes of the
    #   `descendants` tree, flattened depth-first into DictionaryReflex
    #   values — the reconstruction crosswalk's edges (architecture §12).
    #   Off by default so the wiktionary-cu shelf (whose records also carry
    #   descendants) keeps its stored shas untouched; its backfill is a
    #   deliberate future decision (improvements register).
    class WiktionaryJsonlParser
      # Upstream Wiktionary lang_codes → the catalog's language tags, for
      # the codes that differ among languages the catalog holds gold lemmas
      # for (Wiktionary uses ISO 639-1 where one exists). Everything else
      # passes through as itself when it is a shape-valid tag, else nil
      # (the lone "ML." Medieval-Latin code in the wild): display-only,
      # never a crosswalk join candidate.
      LANG_CODE_MAP = { "cu" => "chu", "la" => "lat", "sa" => "san" }.freeze

      # Parse +path+ and return DictionaryEntry values in file order.
      # +language+ is the ISO 639-3 code the entries carry and fold by;
      # kaikki's own lang_code is 639-1 ("cu") and stays in the raw record.
      # +reflexes+ turns on descendants-tree extraction (reconstruction
      # shelves only).
      def initialize(language: "chu", reflexes: false)
        @language = language
        @reflexes = reflexes
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
          citations: [],
          reflexes: @reflexes ? reflexes(record) : []
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

      # -- reflexes (P14-1) ---------------------------------------------------------

      # Depth-first over the descendants tree; only worded nodes mint
      # reflexes (branch-grouping nodes — "East Slavic" — carry none).
      def reflexes(record)
        collect_reflexes(Array(record["descendants"]), [])
      end

      def collect_reflexes(nodes, out)
        nodes.each do |node|
          next unless node.is_a?(Hash)

          out << build_reflex(node) unless node["word"].to_s.strip.empty?
          collect_reflexes(Array(node["descendants"]), out)
        end
        out
      end

      def build_reflex(node)
        language = reflex_language(node["lang_code"].to_s)
        word = Nabu::Normalize.nfc(node["word"].to_s)
        roman = node["roman"].to_s.strip.empty? ? nil : Nabu::Normalize.nfc(node["roman"])
        Nabu::DictionaryReflex.new(
          lang_code: node["lang_code"].to_s, language: language,
          word: word, roman: roman,
          word_folded: reflex_fold(word, language),
          roman_folded: roman && reflex_fold(roman, language)
        )
      end

      # The map first; unmapped codes pass through as themselves when they
      # are shape-valid tags, else nil (display-only).
      def reflex_language(lang_code)
        mapped = LANG_CODE_MAP.fetch(lang_code, lang_code)
        mapped.match?(Nabu::Model::Validation::LANGUAGE_SHAPE) ? mapped : nil
      end

      # The conventions-§9 search form, with the leading asterisk of
      # reconstructed reflexes stripped FIRST (upstream writes "*bogъ" under
      # a PIE entry; the sla-pro shelf keys headword_folded without it —
      # the same convention `define *bogъ` strips at query time). nil when
      # the fold comes out empty.
      def reflex_fold(text, language)
        folded = Nabu::Normalize.search_form(text.sub(/\A\*/, ""), language: language)
        folded.strip.empty? ? nil : folded
      end
    end
  end
end
