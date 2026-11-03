# frozen_string_literal: true

require "json"
require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # The Mahan Kosh JSON parser family: redroyals/mahan-kosh-multilingual's
    # id-keyed grid (data/entries/core.json — {"count", "entries": [{id,
    # hw, tr, vol, page, sources, excluded?, exclude_reason?}]}) joined to
    # its Gurmukhi column (data/entries/gurmukhi.json — {id => {text,
    # align, lemma?}}). The GURMUKHI LANE ONLY, by rule: the English
    # (en.json, "from the Punjabi University Patiala edition", 2006–2011)
    # and its Hindi derivative are a modern translation whose rights the
    # packager cannot be shown to hold, and the other 25 columns are
    # machine translations — none is read here.
    #
    # Per live grid row (excluded rows — front matter, tables, abbreviation
    # keys, duplicate artefacts — skipped), one DictionaryEntry:
    #
    # - entry_id: the grid id verbatim ("1-37-0" = volume-page-sequence),
    #   the packager's stable key across every column.
    # - headword: the Gurmukhi column's own `lemma` when it records one
    #   (the book's lemma where it differs from the grid headword — 5,651
    #   at census), else the grid `hw`; key_raw: the grid `hw`.
    # - body: the Gurmukhi text, one line per upstream "#" (the print's
    #   paragraph breaks), whitespace collapsed, NFC (upstream carries
    #   non-NFC Gurmukhi — nukta letters precomposed); last line the print
    #   locator "Mahan Kosh vol. V, p. P". A row without a recovered body
    #   (4,022 — "The headword could not be joined to the book lemma
    #   without guessing") is its locator alone.
    #   Upstream quirk, carried verbatim (canonical means canonical):
    #   5,623 bodies hold 12,439 Private Use Area codepoints (14 distinct,
    #   U+F02C–U+F03F; U+F032 alone 5,918) — residue of the legacy
    #   Gurmukhi font the text was keyed in ("ਵਿਸ\u{F032}ਨੁ"); a word
    #   carrying one does not fold to its Unicode spelling.
    # - gloss: the body's first sense — up to its first danda "।" —
    #   at most GLOSS_MAX characters; nil without a body.
    # - annotations: {"volume", "page"} — the 1930 print's locator.
    #
    # Deliberately unread (declared): the grid's `tr` transliteration
    # and `sources` string ride the Patiala English edition, held off with
    # it.
    class MahanKoshJsonParser
      LANGUAGE = "pan"
      GLOSS_MAX = 100
      private_constant :GLOSS_MAX

      def entries(core_path:, gurmukhi_path:)
        bodies = load(gurmukhi_path)
        unless bodies.is_a?(Hash)
          raise Nabu::ParseError,
                "mahan-kosh-json: #{gurmukhi_path}: top level is not an object"
        end

        rows = load(core_path)
        rows = rows["entries"] if rows.is_a?(Hash)
        raise Nabu::ParseError, "mahan-kosh-json: #{core_path}: no entries array" unless rows.is_a?(Array)

        rows.reject { |row| row["excluded"] }.map { |row| build(row, bodies[row["id"]], core_path) }
      end

      private

      def load(path)
        JSON.parse(SourceRead.utf8_file(path, label: "mahan-kosh-json"))
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "mahan-kosh-json: malformed JSON in #{path}: #{e.message}"
      end

      def build(row, body, path)
        id = row["id"].to_s
        grid_hw = plain(row["hw"])
        if id.empty? || grid_hw.empty?
          raise Nabu::ParseError,
                "mahan-kosh-json: #{path}: row without id/hw #{row.inspect[0, 80]}"
        end

        lemma = plain(body && body["lemma"])
        headword = lemma.empty? ? grid_hw : lemma
        lines = plain_lines(body && body["text"])
        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: grid_hw, language: LANGUAGE, headword: headword,
          headword_folded: Nabu::Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss(lines.first),
          body: (lines + ["Mahan Kosh vol. #{row['vol']}, p. #{row['page']}"]).join("\n"),
          annotations: { "volume" => row["vol"], "page" => row["page"] }.compact
        )
      end

      def plain_lines(text) = text.to_s.split("#").map { |line| plain(line) }.reject(&:empty?)

      def gloss(line)
        return nil unless line

        cut = line.split("।", 2).first.to_s.strip
        cut = "#{cut[0, GLOSS_MAX].sub(/\s+\S*\z/, '')}…" if cut.length > GLOSS_MAX
        cut.match?(/\p{L}/) ? cut : nil
      end

      def plain(value) = Nabu::Normalize.nfc(value.to_s.gsub(/\s+/, " ").strip)
    end
  end
end
