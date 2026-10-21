# frozen_string_literal: true

require "csv"
require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # Parser for the Calfa definitions tables (the `calfa-tsv` family):
    # calfa-co/lexical-databases definitions/<lang>-definitionsNN.tsv and
    # definitions_proper/<lang>-definitionsNN.tsv — one ROW per dictionary
    # entry, header
    #
    #   Title  Complement  POS_1  Definition_1  …  POS_n  Definition_n
    #
    # (n = 6 in definitions/, 1 in definitions_proper/). Census 2026-10-21
    # at upstream 71109ce:
    #
    # - TAB-separated with CSV-style QUOTING: a field opening with '"'
    #   runs to its closing quote and doubles inner quotes (every
    #   <a href=""…""> anchor); one fr row (Վերստեայ) carries a literal
    #   TAB inside its quoted Definition_1. Ruby's CSV with col_sep TAB
    #   reads all four tables at their header width, no exceptions.
    # - CRLF line ends throughout.
    # - Inline markup, read and never kept: <letter>Ա</letter> (aïp) on
    #   the 38 alphabet-letter titles (the parenthesized letter name is
    #   upstream's gloss, kept in the body, dropped from the headword);
    #   <a href="./?s=X">label</a> cross-references (en 74, fr 186; one en
    #   href reads ".?s=", one fr anchor lacks its </a>) — every one
    #   preceded by "cf." but one → DictionaryCrossref kind "cf."/"see",
    #   target X, resolved by the loader on the folded headword (unique
    #   match only); <ab>/<ab.> abbreviations, <fr>, <i> unwrap; <br />
    #   (and one "<br >") opens an indented continuation line.
    # - A leading "*" on the title (en 313, fr 333) is upstream's mark for
    #   "middle or pre-modern forms and translations" (README): kept on the
    #   display headword, recorded as annotations.headword_mark, stripped
    #   from the lookup fold.
    # - Homographs are separate rows (en 108 titles ×2–3, fr 71, proper 2):
    #   the occurrence suffix ("Ակն", "Ակն:2", "Ակն:3" — the monlam idiom).
    # - One fr row is non-NFC (Տրամագիծ: "e" + U+0301) — composed here.
    #
    # == Entry shape
    #
    # entry_id = [id_prefix ":"] headword with whitespace runs as "_" (+
    # occurrence suffix) — upstream has no row id, the headword is the
    # stable key; key_raw = the Title verbatim; headword = the Title with
    # markup stripped; gloss = the first sense up to its first ";"; body =
    # "headword, complement" then one numbered line per sense, "(POS)"
    # first when upstream gives one; annotations = the POS labels verbatim
    # (+ headword_mark). No reflex rows: these tables carry no etymology.
    class CalfaTsvParser
      FIXED_COLUMNS = %w[Title Complement].freeze
      MARKS = %w[* +].freeze
      ANCHOR = %r{<a\b[^>]*?\bhref=["']?\.?/?\?s=([^"'>]*)["']?[^>]*>(.*?)(?:</a>|\z)}m
      LETTER = %r{\A<letter>(.*?)</letter>\s*(\(.*\))?\z}m

      # Parse +text+ (one whole table, already UTF-8) into DictionaryEntry
      # values in row order. +label+ names the file in errors.
      def entries(text, language:, label:, id_prefix: nil)
        rows = read_rows(text, label)
        header = rows.shift or raise Nabu::ParseError, "calfa-tsv: #{label}: empty table"
        check_header!(header, label)
        occurrences = Hash.new(0)
        rows.each_with_index.filter_map do |row, index|
          next if row.compact.all? { |cell| cell.strip.empty? }

          build_entry(row, header.size, language: language, id_prefix: id_prefix,
                                        occurrences: occurrences, where: "#{label} row #{index + 2}")
        end
      end

      private

      def read_rows(text, label)
        CSV.parse(text, col_sep: "\t", row_sep: :auto)
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "calfa-tsv: #{label}: #{e.message}"
      end

      def check_header!(header, label)
        pairs = header.drop(FIXED_COLUMNS.size)
        expected = (1..(pairs.size / 2)).flat_map { |n| ["POS_#{n}", "Definition_#{n}"] }
        return if header.first(2) == FIXED_COLUMNS && pairs.size.positive? && pairs == expected

        raise Nabu::ParseError, "calfa-tsv: #{label}: unexpected header #{header.inspect}"
      end

      def build_entry(row, width, language:, id_prefix:, occurrences:, where:)
        if row.size != width
          raise Nabu::ParseError, "calfa-tsv: #{where}: #{row.size} cells for a #{width}-column header"
        end

        title = nfc(row[0].to_s.strip, language)
        raise Nabu::ParseError, "calfa-tsv: #{where}: empty Title" if title.empty?

        headword, letter_name = headword_of(title)
        senses = senses_of(row, language)
        crossrefs = senses.flat_map { |sense| sense[:crossrefs] }
        Nabu::DictionaryEntry.new(
          entry_id: entry_id(headword, id_prefix, occurrences),
          key_raw: title, language: language, headword: headword,
          headword_folded: Normalize.search_form(unmarked(headword), language: language),
          gloss: gloss_of(senses),
          body: body_of(headword, letter_name, nfc(squish(row[1].to_s), language), senses),
          crossrefs: crossrefs.map { |ref| crossref(ref, language) },
          annotations: annotations_of(headword, senses)
        )
      end

      def headword_of(title)
        match = LETTER.match(title)
        return [squish(match[1]), match[2]] if match

        [squish(strip_tags(title)), nil]
      end

      def entry_id(headword, id_prefix, occurrences)
        base = [id_prefix, headword.gsub(/\s+/, "_")].compact.join(":")
        occurrences[base] += 1
        occurrences[base] > 1 ? "#{base}:#{occurrences[base]}" : base
      end

      # One Hash per non-empty Definition_n: its POS (nil when the cell is
      # empty), its rendered lines and its anchors.
      def senses_of(row, language)
        row.drop(FIXED_COLUMNS.size).each_slice(2).filter_map do |pos, definition|
          raw = nfc(definition.to_s, language)
          next if strip_tags(raw).strip.empty?

          pos = squish(pos.to_s)
          { pos: pos.empty? ? nil : pos, lines: render(raw), crossrefs: anchors(raw) }
        end
      end

      def anchors(raw)
        raw.to_enum(:scan, ANCHOR).map do
          match = Regexp.last_match
          { kind: raw[0...match.begin(0)].match?(/cf\.\s*\z/) ? "cf." : "see",
            target: squish(match[1]), label: squish(strip_tags(match[2])) }
        end
      end

      # The definition text as display lines: <br> splits, every tag unwraps.
      def render(raw)
        raw.split(%r{<br\s*/?\s*>}).map { |part| squish(strip_tags(part)) }.reject(&:empty?)
      end

      def strip_tags(text) = text.gsub(/<[^<>]*>/, "")

      def squish(text) = text.gsub(/[[:space:]]+/, " ").strip

      def gloss_of(senses)
        first = senses.first or return nil
        gloss = first[:lines].first.split(";").first.to_s.strip
        gloss.empty? ? nil : gloss
      end

      def body_of(headword, letter_name, complement, senses)
        head = [[headword, letter_name].compact.join(" "), complement].reject(&:empty?).join(", ")
        lines = [head]
        senses.each_with_index do |sense, index|
          first, *rest = sense[:lines]
          lines << "#{index + 1}. #{[sense[:pos] && "(#{sense[:pos]})", first].compact.join(' ')}"
          rest.each { |line| lines << "   #{line}" }
        end
        lines.join("\n")
      end

      def annotations_of(headword, senses)
        annotations = {}
        pos = senses.filter_map { |sense| sense[:pos] }.uniq
        annotations["pos"] = pos unless pos.empty?
        mark = MARKS.find { |candidate| headword.start_with?(candidate) }
        annotations["headword_mark"] = mark if mark
        annotations
      end

      def crossref(ref, language)
        folded = Normalize.search_form(ref.fetch(:target), language: language)
        Nabu::DictionaryCrossref.new(kind: ref.fetch(:kind), label: ref.fetch(:label), target: ref.fetch(:target),
                                     target_folded: folded.empty? ? nil : folded)
      end

      def unmarked(headword) = headword.sub(/\A[*+]+/, "")

      def nfc(text, language) = SourceRead.nfc(text, language: language)
    end
  end
end
