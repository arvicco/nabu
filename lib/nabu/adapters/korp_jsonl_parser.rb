# frozen_string_literal: true

require "json"

module Nabu
  module Adapters
    # The korp-jsonl parser family: one upstream text as landed by
    # Nabu::KorpFetch — one JSON line per Korp sentence, in corpus order:
    #
    #   {"structs": {"text_filename": "jafro1791.sen", "text_title": "…",
    #                "text_datefrom": "17910101", "text_dateto": "17911231",
    #                "span_page": "1", "div_n": "d1", "sentence_id": "1",
    #                "sentence_code": "JAFro1791-1", "sentence_type": "sentence",
    #                "sentence_cRef": "", …},
    #    "tokens": [["Hyödyllinen", null, null], ["sinu", "sinun", "sinun~"], …]}
    #
    # (tokens: [word, word_completed, word_tilde] with null where the value
    # equals the word — the VKS attribute set.)
    #
    # == The passage grain (the declared rule)
    #
    # VKS's own citation unit is the sentence_code — the corpus's line /
    # verse / paragraph key ("JAFro1791-116", "Jh-19:38-623c" = John 19:38 on
    # page 623 column c, "As1805g-2"); Korp's sentence segmentation splits
    # one code into several sentences. One Unit per RUN of consecutive
    # sentences sharing a code, cited by the code with ":" read "." (the
    # urn separator) — Jh-19.38-623c; a code recurring after other codes
    # takes the house :b2 suffix in document order. Text: the "word" layer
    # (the print surface as the corpus transcribes it), tokens joined by
    # spaces with punctuation glued left. Annotations: "page" (span_page),
    # "div" (div_n), "headings" (the sentences typed heading), "refs" (a
    # sentence_cRef — Agricola's marginal scripture references), "date"
    # (the text element's own year span, when the file carries several
    # dated text elements — the decree and sermon collections), and
    # "expansions" [{form, completed, marked}] for every token whose
    # abbreviation the corpus completed (sinu → sinun, marked sinun~).
    class KorpJsonlParser
      Unit = Data.define(:citation, :text, :annotations)

      GLUE_LEFT = [",", ".", ";", ":", "?", "!", ")", "]", "»", "”"].freeze
      GLUE_RIGHT = ["(", "["].freeze

      # +text+ is one landed .jsonl file. Returns [units, rows] — the Units
      # in order and the parsed rows (the adapter reads text-level metadata
      # from them).
      def parse(text, label:)
        rows = text.each_line.with_index(1).map { |line, number| row(line, label, number) }
        raise Nabu::ParseError, "#{label}: no sentences" if rows.empty?

        dated = rows.map { |r| date_span(r["structs"]) }.uniq.size > 1
        runs = rows.chunk_while { |a, b| code(a) == code(b) }
        units = runs.map { |run| unit(run, dated: dated) }
        [disambiguate(units), rows]
      end

      private

      def row(line, label, number)
        parsed = JSON.parse(line)
        unless parsed.is_a?(Hash) && parsed["structs"].is_a?(Hash) && parsed["tokens"].is_a?(Array)
          raise Nabu::ParseError, "#{label}:#{number}: not a {structs, tokens} line"
        end

        parsed
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "#{label}:#{number}: malformed JSON: #{e.message}"
      end

      def code(row)
        row["structs"]["sentence_code"].to_s
      end

      def date_span(structs)
        [structs["text_datefrom"].to_s[0, 4], structs["text_dateto"].to_s[0, 4]]
      end

      def unit(run, dated:)
        first = run.first["structs"]
        raw = code(run.first)
        citation = raw.empty? ? "s.#{first['sentence_id']}" : raw.tr(":", ".").gsub(%r{[\s/]+}, "_")
        annotations = { "code" => raw }
        annotations["page"] = first["span_page"] unless first["span_page"].to_s.empty?
        annotations["div"] = first["div_n"] unless first["div_n"].to_s.empty?
        if dated
          from, to = date_span(first)
          annotations["date"] = { "not_before" => Integer(from, 10), "not_after" => Integer(to, 10) } \
            if from.match?(/\A\d{4}\z/) && to.match?(/\A\d{4}\z/)
        end
        collect(run, annotations)
        Unit.new(citation: citation, text: Normalize.nfc(render(run)), annotations: annotations)
      end

      def collect(run, annotations)
        headings = run.select { |r| r["structs"]["sentence_type"] == "heading" }.map { |r| Normalize.nfc(render([r])) }
        annotations["headings"] = headings unless headings.empty?
        refs = run.map { |r| r["structs"]["sentence_cRef"].to_s }.reject(&:empty?).uniq
        annotations["refs"] = refs unless refs.empty?
        expansions = run.flat_map { |r| r["tokens"] }.select { |t| t[1] }.map do |word, completed, marked|
          { "form" => Normalize.nfc(word.to_s), "completed" => Normalize.nfc(completed.to_s),
            "marked" => Normalize.nfc(marked.to_s) }
        end
        annotations["expansions"] = expansions unless expansions.empty?
      end

      def render(run)
        out = +""
        glue_next = true
        run.each do |row|
          row["tokens"].each do |token|
            word = token.first.to_s
            next if word.empty?

            out << " " unless glue_next || GLUE_LEFT.include?(word)
            out << word
            glue_next = GLUE_RIGHT.include?(word)
          end
          glue_next = false
        end
        out.strip
      end

      def disambiguate(units)
        seen = Hash.new(0)
        units.map do |unit|
          seen[unit.citation] += 1
          count = seen[unit.citation]
          count == 1 ? unit : unit.with(citation: "#{unit.citation}:b#{count}")
        end
      end
    end
  end
end
