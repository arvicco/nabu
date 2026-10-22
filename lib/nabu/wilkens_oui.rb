# frozen_string_literal: true

require_relative "normalize"
require_relative "stext_layout"

module Nabu
  # Entry segmentation for Jens Wilkens, Handwörterbuch des Altuigurischen
  # (Göttingen 2021; CC BY-SA 4.0) — the Old Uyghur–German–Turkish
  # dictionary, read from its born-digital text layer as positioned, styled
  # lines (Nabu::StextLayout).
  #
  # == Why layout, not lines
  #
  # The plain text layer runs `headword German || Türkisch`, but entries
  # stack and wrap: a naive line grain cannot tell a new collocation from
  # a wrapped gloss. The page itself carries three unambiguous signals:
  #
  # * MAIN entries open at the column margin with a bold headword (Word's
  #   synthetic fill+stroke bold); their continuation lines stay at the
  #   margin;
  # * SUB entries (collocations, filed "stets ausschließlich unter dem
  #   ersten Element" — Vorbemerkungen) open at a hanging indent (+11.7 pt)
  #   with an italic phrase; their continuations stay at the indent;
  # * an indent line right after a main-entry line can therefore ONLY open
  #   a sub-entry ("forced"). The one genuinely ambiguous junction is an
  #   indent line after an indent line — a new sub-entry or a wrapped
  #   gloss? A new one needs an italic lead that shares its first letters
  #   with the main headword (or a known variant shape), a previous record
  #   that has reached its gloss (|| / → / †), no parenthetical left open
  #   since its last ||, no language abbreviation dangling at its end, and
  #   no glued punctuation after the italic run (an italic Sanskrit word
  #   wrapped from "(Skt." is running text).
  #
  # Geometry is the book's own (measured across all 929 folios): mirrored
  # margins, even folios x≈47.1/250.0, odd folios x≈58.4/261.7; the folio
  # parity comes from the printed folio Page#folio.
  #
  # == Measured on the whole body (folios 1–929, 2026-10-22)
  #
  # 49,621 records (29,873 main / 19,748 sub); 99.99 % of the glossed
  # records split into both halves; 0.65 % of main headwords out of the
  # book's alphabetical order — on review the upstream's own collation
  # (spaced Chinese syllables, name sorting, typos), not segmentation.
  # Known residue (~10 records): a parenthesis left unbalanced in the
  # source swallows the next sub-entry; a sub-entry led by a roman "(…)".
  module WilkensOui
    Entry = Data.define(:kind, :headword, :homonym, :parent, :parent_homonym, :folio, :column,
                        :german, :turkish, :xref, :note, :error, :labels, :body, :raw)

    # Folio parity → column margins (left, right) and right edges.
    MARGINS = { even: { left: 47.1, right: 250.0 }, odd: { left: 58.4, right: 261.7 } }.freeze
    RIGHT_EDGES = { even: { left: 223.0, right: 426.0 }, odd: { left: 234.0, right: 437.0 } }.freeze
    INDENT = 11.7
    TOLERANCE = 3.0
    MAX_INDENT = 30.0
    # A line ending this far short of the column's right edge closed its paragraph.
    SHORT_LINE = 12.0
    # Running text cannot end a record on a dangling source-language abbreviation.
    LANG_TAIL = /(?:\b(?:Skt|TochA|TochB|Toch|Sogd|Chin|Mo|Tib|tib|Parth|Gr|Syr|Khotansak|vgl|s|bk|krş)\.|
                 \b(?:MP|BHS|TochA|TochB|von)|[(=<])\s*\z/x
    LABELS = /\((m|c|br|r|tib|p|adv\.|enkl\.|intr\.|tr\.)\)/
    GRAMMAR = /\b(n\. pr\.|n\. loc\.|Postp\.|Part\.|Interjektion|Vokativpartikel)/
    XREF = /\A(?:-\s*)?(?:~\s*\S+\s*)?(?:\([^)]*\)\s*)?(?:†\s*)?(?:\([^)]*\)\s*)?→\s*(.+)\z/
    # Letters folded for the first-letters comparison only (never output).
    FOLD = { "ā" => "a", "ī" => "i", "ū" => "u", "ē" => "e", "ō" => "o", "ṭ" => "t", "ḍ" => "d", "ṣ" => "s",
             "ẓ" => "z", "ṅ" => "n", "ṇ" => "n", "ṃ" => "m", "ḥ" => "h", "ś" => "s", "ṛ" => "r", "ḷ" => "l",
             "ı" => "i", "I" => "i", "İ" => "i" }.freeze

    # Feeds pages in reading order; #entries holds the finished records,
    # #anomalies the census of every rule that fired (the quarantine
    # residue a shipping adapter reports).
    class Segmenter
      attr_reader :anomalies

      def initialize
        @entries = []
        @anomalies = Hash.new(0)
        @cur = nil
        @main = nil
        @prev = nil
      end

      # +continued+: the page directly follows the previously fed one, so
      # its leading continuation lines belong to the open record. A gap
      # (fixture trims, a partial range) closes the flow instead.
      def feed(page, continued: true)
        unless continued
          flush
          @main = nil
          @prev = nil
        end
        @folio = page.folio
        parity = page.folio.to_i.even? ? :even : :odd
        page.lines.each { |line| feed_line(line, parity) }
        self
      end

      # The finished records. Closes the open record: call once all pages are fed.
      def entries
        flush
        @entries
      end

      private

      def feed_line(line, parity)
        kind = position(line, parity)
        head = bold_head(line.glyphs)
        prev_short = @prev && @prev[:x1] < RIGHT_EDGES.fetch(@prev[:parity]).fetch(@prev[:column]) - SHORT_LINE
        @prev = { x1: line.x1, parity: parity, column: line.column }

        if head && kind == :other && line.text.strip.size <= 3
          @anomalies[:letter_heading] += 1
        elsif head && kind == :margin && !headword_wrap?
          open_main(line, head)
        elsif kind == :indent && @cur && (how = sub_start(line, prev_short))
          open_sub(line, how)
        elsif @cur.nil?
          @anomalies[:orphan_line] += 1
        else
          continue(line, kind, head)
        end
      end

      def position(line, parity)
        dx = line.x0 - MARGINS.fetch(parity).fetch(line.column)
        return :margin if dx.abs < TOLERANCE
        return :indent if (dx - INDENT).abs < TOLERANCE
        return :other unless dx.between?(TOLERANCE, MAX_INDENT)

        @anomalies[:odd_indent] += 1
        :indent
      end

      def blank?(glyph) = glyph.char.strip.empty?
      def digit_mark?(glyph) = glyph.small && glyph.char.match?(/\d/)

      # A bold line at the margin while the open main entry has no body
      # yet is that headword wrapping, not a new entry.
      def headword_wrap? = @cur && @cur[:kind] == :main && @cur[:body].strip.empty?

      # Leading subscript homonym digits, roman editorial marks (* †), then
      # the bold run (spaces may sit between bold words); a verb-stem
      # hyphen set roman right after the stem joins the headword.
      def bold_head(glyphs)
        i = 0
        homonym = +""
        while glyphs[i] && digit_mark?(glyphs[i])
          homonym << glyphs[i].char
          i += 1
        end
        start = i
        i += 1 while glyphs[i]&.char&.match?(/[*†°]/) && !glyphs[i].bold
        return nil if i > start && !glyphs[i]&.bold

        last = nil
        while (g = glyphs[i]) && (g.bold || blank?(g) || digit_mark?(g))
          last = i if g.bold && !blank?(g)
          i += 1
        end
        return nil unless last

        j = last + 1
        j += 1 while glyphs[j]&.char == " " && glyphs[j + 1]&.char == "-"
        if glyphs[j]&.char == "-" && (glyphs[j + 1].nil? || glyphs[j + 1].char.strip.empty?)
          @anomalies[:roman_verb_hyphen] += 1
          return { homonym: homonym, head: glyphs[start..last] + [glyphs[j]], rest: glyphs[(j + 1)..] || [] }
        end
        { homonym: homonym, head: glyphs[start..last], rest: glyphs[(last + 1)..] }
      end

      def italic_head(glyphs)
        last = nil
        i = 0
        while glyphs[i] && (glyphs[i].italic || glyphs[i].char.strip.empty?)
          last = i if glyphs[i].italic && !glyphs[i].char.strip.empty?
          i += 1
        end
        last && { head: glyphs[0..last], rest: glyphs[(last + 1)..] }
      end

      def italic_led?(glyphs)
        first = glyphs.find { |g| !g.char.match?(/[*†\s]/) && !(g.small && g.char.match?(/\d/)) }
        first&.italic
      end

      def sub_start(line, prev_short)
        return :forced if @cur[:kind] == :main # indent after a main-entry line opens a sub-entry
        return nil if @cur[:body].strip.empty? # the sub-entry phrase itself is still wrapping
        return nil unless italic_led?(line.glyphs)
        return nil if soft_wrap_pending?
        return nil if @cur[:raw].match?(LANG_TAIL)
        return nil if open_paren?(@cur[:body].split("||").last.to_s)
        return nil unless @cur[:body].match?(/\|\||→|†/) # no gloss yet: the record cannot have ended

        ih = italic_head(line.glyphs.drop_while { _1.char.match?(/[*†\s]/) })
        return nil if ih.nil?
        return nil if ih[:rest].first&.char&.match?(/[)’,;!:.]/) # an italic citation glued to punctuation

        return :prefix if first_letters_match?(text(ih[:head]))
        return :short if prev_short

        nil
      end

      def soft_wrap_pending?
        @cur[:raw].match?(/\p{L}-\s*\z/) && !@cur[:raw].match?(/→\s*\S+-\s*\z/)
      end

      def open_paren?(str) = str.count("(") > str.count(")")

      # Sub-entries repeat the main headword's first letters; the dictionary
      # also files variant spellings under one lemma (initial y-/h- dropped
      # or added, ä~e, upstream doubled-letter typos), hence the shifted checks.
      def first_letters_match?(phrase)
        a = fold(@main[:headword])
        b = fold(phrase)
        n = [2, a.size, b.size].min
        return false unless n.positive?
        return true if a[0, n] == b[0, n]

        variant = a[1, n] == b[0, n] || a[0, n] == b[1, n] || a[1, n - 1] == b[1, n - 1]
        @anomalies[:variant_prefix] += 1 if variant
        variant
      end

      def fold(str)
        str.split("~").first.to_s.gsub(/\^\d+|[()\[\]<>{}*†°?\d\s.,\-–]/, "")
           .chars.map { |ch| FOLD.fetch(ch) { FOLD.fetch(ch.downcase, ch.downcase) } }.join.squeeze
      end

      def open_main(line, head)
        flush
        @main = @cur = {
          kind: :main, homonym: head[:homonym].empty? ? nil : head[:homonym].to_i,
          headword: text(head[:head]).strip, folio: @folio, column: line.column,
          body: +"", raw: text(line.glyphs), last: last_glyph(line.glyphs)
        }
        @cur[:body] = text(head[:rest])
      end

      def open_sub(line, how)
        @anomalies[:"sub_#{how}"] += 1
        flush
        lead = line.glyphs.take_while { _1.char.match?(/[*†\s]/) }
        ih = italic_head(line.glyphs.drop(lead.size))
        unless ih
          @anomalies[:sub_without_italic_head] += 1
          ih = { head: [], rest: line.glyphs.drop(lead.size) }
        end
        @cur = {
          kind: :sub, parent: @main[:headword], parent_homonym: @main[:homonym],
          headword: (text(lead) + text(ih[:head])).strip, folio: @folio, column: line.column,
          body: text(ih[:rest]), raw: text(line.glyphs), last: last_glyph(line.glyphs)
        }
      end

      def continue(line, kind, head)
        soft = style(@cur[:last]) == style(line.glyphs.find { !_1.char.strip.empty? })
        @cur[:last] = last_glyph(line.glyphs)
        @cur[:raw] = join(@cur[:raw], text(line.glyphs), soft: soft)

        if head && kind == :margin # a bold headword wrapping onto its next line
          @anomalies[:headword_wrap] += 1
          @cur[:headword] = join(@cur[:headword], text(head[:head]).strip, soft: soft)
          @cur[:body] = text(head[:rest])
        elsif @cur[:kind] == :sub && @cur[:body].strip.empty? && kind == :indent && (ih = italic_head(line.glyphs))
          @anomalies[:sub_phrase_wrap] += 1
          @cur[:headword] = join(@cur[:headword], text(ih[:head]).strip, soft: soft)
          @cur[:body] = text(ih[:rest])
        else
          expected = @cur[:kind] == :main ? :margin : :indent
          @anomalies[:"#{@cur[:kind]}_continuation_at_#{kind}"] += 1 if kind != expected
          @cur[:body] = join(@cur[:body], text(line.glyphs), soft: soft)
        end
      end

      def style(glyph)
        return nil unless glyph

        if glyph.bold then :bold
        elsif glyph.italic then :italic
        else :roman
        end
      end

      def last_glyph(glyphs) = glyphs.reverse.find { !_1.char.strip.empty? }

      # A wrap hyphen whose next line starts lowercase in the SAME style is
      # a typesetting break (dost-/luk, mai-/thuna): rejoin. A styled
      # (italic/bold) hyphen followed by another style is a verb-stem
      # hyphen ("sür-" then the German gloss): keep it, with a space.
      def join(left, right, soft:)
        if left.match?(/\p{L}-\s*\z/) && right.match?(/\A\p{Ll}/) && soft
          @anomalies[:dehyphenated] += 1
          left.sub(/-\s*\z/, "") + right
        elsif left.match?(/-\s*\z/)
          soft ? left.rstrip + right : "#{left.rstrip} #{right}"
        else
          "#{left.rstrip} #{right}"
        end
      end

      # Small digits render as ^n (homonym numbers, word-pair marks: Liebe₂).
      def text(glyphs) = glyphs.map { |g| g.small && g.char.match?(/\d/) ? "^#{g.char}" : g.char }.join

      def flush
        return unless @cur

        @entries << build(@cur)
        @cur = nil
      end

      def build(rec)
        body = squish(rec[:body])
        xref = body.match(XREF)&.[](1)
        german, turkish = halves(body)
        labels = []
        labels << "verb" if rec[:headword].end_with?("-")
        body.scan(LABELS) { labels << _1.first }
        body.scan(GRAMMAR) { labels << _1.first }
        Entry.new(
          kind: rec[:kind], headword: nfc(squish(rec[:headword])), homonym: rec[:homonym],
          parent: rec[:parent] && nfc(squish(rec[:parent])), parent_homonym: rec[:parent_homonym],
          folio: rec[:folio], column: rec[:column],
          german: german && nfc(german), turkish: turkish && nfc(turkish), xref: xref && nfc(xref),
          note: !xref && !body.include?("||") && body.match?(/→|†|\AVar\./),
          error: body.match?(/\A(?:\([^)]*\)\s*)?†/), labels: labels.uniq.freeze,
          body: nfc(body), raw: nfc(squish(rec[:raw]))
        )
      end

      def squish(str) = str.gsub(/\s+/, " ").strip
      def nfc(str) = Nabu::Normalize.nfc(str)

      # "G1 || T1; G2 || T2" → ["G1; G2", "T1; T2"]: each inner segment
      # splits on its last top-level ';' (the Turkish sense ends there and
      # the next German sense begins).
      def halves(body)
        parts = body.split("||")
        return [nil, nil] if parts.size < 2

        german = [parts.first]
        turkish = []
        parts.drop(1).each_with_index do |part, i|
          if i == parts.size - 2
            turkish << part
          else
            cut = last_top_level_semicolon(part)
            turkish << (cut ? part[0...cut] : part)
            german << (cut ? part[(cut + 1)..] : "")
          end
        end
        [german.map(&:strip).join("; "), turkish.map(&:strip).join("; ")]
      end

      def last_top_level_semicolon(str)
        depth = 0
        cut = nil
        str.each_char.with_index do |ch, j|
          depth += 1 if "([".include?(ch)
          depth -= 1 if ")]".include?(ch)
          cut = j if ch == ";" && depth.zero?
        end
        cut
      end
    end
  end
end
