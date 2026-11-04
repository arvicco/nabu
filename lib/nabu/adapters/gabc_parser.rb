# frozen_string_literal: true

module Nabu
  module Adapters
    # The gabc parser family: the LYRIC TEXT layer of a GABC score (the
    # Gregorio project's plain-text chant notation) and of the TeX blocks
    # GregoBase stores beside its scores. A standalone, individually tested
    # component the Gregobase adapter composes. It never sees the database:
    # callers hand it one GABC or TeX string and get text back.
    #
    # == GABC in one paragraph (gregorio-project.github.io/gabc)
    #
    # A score is an optional header ("key: value;" lines closed by a "%%"
    # line) and a body in which every syllable's text is followed by its
    # notes in parentheses: "Ma(g)rí(hi)a(ih)". Clefs "(c4)", bars "(,)
    # (;) (:) (::)", custodes and NABC neumes after "|" ("(f|vi)") all live
    # INSIDE the parentheses, so dropping every note group leaves exactly the
    # sung text with its word spacing. Outside the notes the text carries:
    # style tags (<b> <i> <c> <sc> <ul> <tt> <e> <eu> <nlba> <clear>) whose
    # content is text; <sp>…</sp> special characters (℣ ℟ ✠ ǽ œ́ …); <v>…</v>
    # raw TeX for the typesetter and <alt>…</alt> text printed above the
    # staff, both dropped; {…} vowel-centering braces, dropped as braces;
    # [...] the translation line printed under the syllable, dropped (the
    # raw GABC rides beside the text, so nothing is lost); and % comments to
    # the end of the line (transcribers comment out e.g. an "E u o u a e").
    # The printed asterisk "*", the dagger "†" and editorial rubrics such as
    # "ij." (sing twice) are text and stay. A "~" outside the notes is
    # TeX's non-breaking space.
    #
    # == TeX blocks
    #
    # GregoBase interleaves TeX elements with the scores (mostly layout:
    # \grechangedim, \gresetclivisalignment …) and keeps verses typeset in
    # TeX (\Vbar, {\bf …}, "\\" line ends). #tex_text drops the layout
    # commands WITH their arguments, maps the sign commands, and keeps every
    # other command's braced argument as text; a layout-only block
    # extracts to "".
    #
    # Output is whitespace-collapsed and stripped; NFC normalization is the
    # adapter's boundary job.
    class GabcParser
      # <sp>…</sp> contents → the sign Gregorio typesets (its own table);
      # anything else keeps its inner text verbatim.
      SPECIAL = {
        "V/" => "℣", "R/" => "℟", "+" => "✠", "*" => "*", "†" => "†",
        "'ae" => "ǽ", "'æ" => "ǽ", "ae" => "æ", "æ" => "æ",
        "'oe" => "œ́", "'œ" => "œ́", "oe" => "œ", "œ" => "œ",
        "\\Vbar." => "℣.", "\\Rbar." => "℟.", "\\P" => "¶"
      }.freeze

      STYLE_TAG = %r{</?(?:b|i|c|e|eu|nlba|sc|ul|tt|u|clear|pr)>}
      DROPPED_SPANS = %r{<(v|alt)>.*?</\1>}m
      TRANSLATION = /\[[^\[\]]*\]/
      # Private-use stand-ins so a special "[" / "]" survives the
      # translation strip.
      BRACKETS = { "[" => "\u{E000}", "]" => "\u{E001}" }.freeze

      HEADER_END = /^%%[ \t]*\r?$\n?/
      HEADER_LINE = /\A\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*;?\s*\z/

      # TeX commands that typeset layout, not text: removed with every
      # [optional] and {braced} argument.
      TEX_LAYOUT = %w[
        grechangedim gresetclivisalignment greannotation grecommentary grechangecount
        gresetinitiallines greillumination grechangestyle grechangeglyph gresetlinecolor
        grefontsize gresetheadercapture vspace hspace setlength vskip hskip kern begin end
      ].freeze
      # TeX accent commands → the combining mark (NFC composes at the
      # boundary): \'a, \'{a}.
      TEX_ACCENTS = { "'" => "́", "`" => "̀", "^" => "̂", "\"" => "̈", "~" => "̃" }.freeze
      TEX_ACCENT = /\\(['`^"~])(?:\{(\p{L})\}|(\p{L}))/
      TEX_SIGNS = {
        "Vbar" => "℣", "Rbar" => "℟", "dag" => "†", "gredagger" => "†", "GreDagger" => "†",
        "grestar" => "*", "GreStar" => "*", "textasteriskcentered" => "*",
        "ae" => "æ", "oe" => "œ", "AE" => "Æ", "OE" => "Œ"
      }.freeze

      class << self
        # [header hash, body]: the "key: value;" lines before a "%%" line
        # (a repeated key collects its values into an array); no "%%" line
        # means no header.
        def split_header(gabc)
          match = HEADER_END.match(gabc)
          return [{}, gabc] unless match

          [parse_header(match.pre_match), match.post_match]
        end

        # The sung text of one GABC body (header already split or absent).
        def text(gabc)
          _, body = split_header(gabc)
          lyric = strip_notes(body.gsub(DROPPED_SPANS, ""))
          lyric = lyric.gsub(%r{<sp>(.*?)</sp>}m) { protect(SPECIAL.fetch(Regexp.last_match(1), Regexp.last_match(1))) }
          lyric = lyric.gsub(TRANSLATION, "").gsub(STYLE_TAG, "").delete("{}").tr("~", " ")
          squish(unprotect(lyric))
        end

        # The text of one TeX block ("" when it is layout only).
        def tex_text(tex)
          out = tex.gsub(/(?<!\\)%[^\n]*/, "").gsub(/\\\\(?:\[[^\]]*\])?/, "\n")
          TEX_LAYOUT.each { |name| out = drop_command(out, name) }
          out = out.gsub(TEX_ACCENT) do
            "#{Regexp.last_match(2) || Regexp.last_match(3)}#{TEX_ACCENTS[Regexp.last_match(1)]}"
          end
          out = out.gsub(/\\([A-Za-z]+)\b *(?:\{\})?/) do
            name = Regexp.last_match(1)
            TEX_SIGNS.key?(name) ? TEX_SIGNS[name] : ""
          end
          # what remains: tabbing controls (\= \> \< \+ \- \'), spacing (\ \, \; \!), italic correction (\/)
          out = out.gsub(%r{\\[=><+\-'`/ ,;!]}, " ")
          squish(out.delete("{}$").tr("~", " "))
        end

        # A TeX verses block split into stanzas at blank lines.
        def tex_stanzas(tex)
          tex.split(/\r?\n[ \t]*\r?\n/).map(&:strip).reject(&:empty?)
        end

        # A GABC verses block split at verse numbers ("2. …", "3. …" at a
        # line start); a block without them is one chunk. Chunks carrying
        # no text are dropped.
        def verse_chunks(gabc)
          gabc.gsub("\r\n", "\n").split(/(?=^[ \t]*\d+\.\s)/).map(&:strip).reject { |chunk| text(chunk).empty? }
        end

        private

        def parse_header(header)
          header.each_line.with_object({}) do |line, fields|
            match = HEADER_LINE.match(line.chomp)
            next unless match

            key = match[1]
            value = match[2]
            fields[key] = fields.key?(key) ? [*fields[key], value] : value
          end
        end

        # Drop every parenthesised note group, and % comments to the end of
        # the line. An unclosed "(" swallows the rest of its line (damaged
        # notes never leak into the text).
        def strip_notes(body)
          out = +""
          in_notes = false
          skip_line = false
          body.each_char do |char|
            if char == "\n"
              in_notes = false
              skip_line = false
              out << char
            elsif skip_line || (in_notes && char != ")")
              next
            elsif in_notes
              in_notes = false
            elsif char == "("
              in_notes = true
            elsif char == "%"
              skip_line = true
            else
              out << char
            end
          end
          out
        end

        # Remove \name with its optional star, [optional] and {braced}
        # arguments (balanced braces).
        def drop_command(tex, name)
          pattern = /\\#{name}(?![A-Za-z])\*?/
          out = +""
          rest = tex
          while (match = pattern.match(rest))
            out << match.pre_match
            rest = skip_arguments(match.post_match)
          end
          out << rest
        end

        def skip_arguments(text)
          text = text.sub(/\A[ \t]*\[[^\]]*\]/, "")
          loop do
            stripped = text.sub(/\A[ \t]*/, "")
            break unless stripped.start_with?("{")

            depth = 0
            index = stripped.each_char.with_index do |char, i|
              depth += 1 if char == "{"
              depth -= 1 if char == "}"
              break i if depth.zero?
            end
            return "" unless index.is_a?(Integer)

            text = stripped[(index + 1)..]
          end
          text
        end

        def protect(value) = value.gsub(/[\[\]]/, BRACKETS)
        def unprotect(value) = value.gsub(/[\u{E000}\u{E001}]/, BRACKETS.invert)
        def squish(value) = value.gsub(/[[:space:]]+/, " ").strip
      end
    end
  end
end
