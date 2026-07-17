# frozen_string_literal: true

require_relative "normalize"

module Nabu
  # StarLing → Unicode text decoder (P22-0), the boundary transcoder behind
  # the starling-dbf parser family (Betacode/SLP1's sibling for the Tower of
  # Babel databases; .docs/surveys/pie-survey.md §3.1).
  #
  # == The encoding (from the published StarLing package, help/encoding.htm)
  #
  # StarLing text mixes THREE layers:
  #
  # - a SINGLE-BYTE page (CP866-derived Cyrillic + phonetic symbols in
  #   0x80–0xFF, plus \x1D-prefixed extended-latin escapes);
  # - DOUBLEBYTE runs: control bytes \x01–\x07 open one of seven doublebyte
  #   sets ("every two bytes are interpreted as a single character"); any
  #   byte < 0x80 terminates the run (\x01–\x07 immediately re-open); \x7F
  #   is the invisible flow breaker. The IE databases use set 1 only (the
  #   \x01\x83/\x01\x85 Greek + combining ranges, plus — vasmer, P23-0 —
  #   the \x01\x86–\x88 Church Slavonic font range);
  # - in-band `\`-style markup: \B \I \C \U \L \H open bold/italic/
  #   condensed/underline/sub/superscript, the lowercase letters close them
  #   (stripped here — the text is what survives).
  #
  # == The tables — never guess byte meanings
  #
  # Byte-run → Unicode mappings come EXCLUSIVELY from the vendored
  # config/starling/ tables (provenance: config/starling/README.md):
  # unipro.lst — the "fully Unicode compatible" conversion table the current
  # StarLing 3.9.0 release wires as its own Unicode conversion — and, since
  # P23-0, chslav.lst — the same release's Church Slavonic conversion
  # (config.str `[Chslav font]`), which owns the \x01-shifted \x86/\x87/\x88
  # doublebyte range vasmer's Old Cyrillic citations are typed in (absent
  # from unipro.lst; key spaces disjoint, so merging the tries changes no
  # existing decode). Table lines map a StarLing byte sequence to `U+XXXX`
  # (first line per left side is the forward mapping; later duplicates serve
  # upstream's reverse conversion) or to another StarLing sequence (alias
  # rows — resolved through the tables themselves). Sequences may span mode
  # transitions (α + \x7F + macron byte = one precomposed ᾱ entry), so
  # decoding walks a longest-match trie with the current shift byte
  # virtually prefixed.
  #
  # Structural bytes handled OUTSIDE the table, each verified against the
  # live starlingdb.org rendering of the same records (2026-07-15): \x15 is
  # the paragraph mark (the site renders <P>) → "\n"; CR dropped/LF kept;
  # \x7F invisible. An unmapped byte or pair decodes to U+FFFD — never
  # silently dropped (pokorny/piet carry exactly ONE such stray — \x80\xA8
  # after τέλλω in pokorny #1089 — and vasmer 28 more, all stray high bytes
  # inside per-character shift runs; the official web converter drops or
  # garbles them; fixtures pin our honest replacements instead).
  #
  # Output is UTF-8 NFC (the house boundary rule).
  module StarlingText
    TABLE_PATHS = %w[unipro.lst chslav.lst].map do |name|
      File.expand_path("../../config/starling/#{name}", __dir__)
    end.freeze

    STYLE_MARKUP = /\A\\[BbIiCcUuLlHh]/
    private_constant :STYLE_MARKUP

    REPLACEMENT = "\u{FFFD}"
    PARAGRAPH_MARK = 0x15
    FLOW_BREAKER = 0x7F
    SHIFTS = (0x01..0x07)
    private_constant :REPLACEMENT, :PARAGRAPH_MARK, :FLOW_BREAKER, :SHIFTS

    module_function

    # Decode a StarLing byte string to UTF-8 NFC text.
    def decode(bytes)
      out = +""
      shift = nil
      i = 0
      while i < bytes.bytesize
        byte = bytes.getbyte(i)
        if shift && byte >= 0x80
          shift, i = decode_shifted(bytes, i, shift, out)
        else
          shift = nil if byte < 0x80
          shift, i = decode_single(bytes, i, byte, shift, out)
        end
      end
      Nabu::Normalize.nfc(out)
    end

    # -- decoding steps (module_function makes these private-ish; they are
    # -- not part of the public surface) ------------------------------------

    def decode_shifted(bytes, index, shift, out)
      length, text = longest_match(bytes, index, shift)
      if length
        out << text
        [mode_after(bytes, index, length, shift), index + length]
      else
        out << REPLACEMENT
        [shift, index + 2]
      end
    end

    def decode_single(bytes, index, byte, shift, out)
      case byte
      when SHIFTS then [byte, index + 1]
      when FLOW_BREAKER, 0x0D then [shift, index + 1]
      when PARAGRAPH_MARK, 0x0A then (out << "\n") && [shift, index + 1]
      when 0x5C then decode_backslash(bytes, index, shift, out)
      else
        length, text = longest_match(bytes, index, nil)
        if length
          out << text
          [shift, index + length]
        else
          out << (byte < 0x80 ? byte.chr : REPLACEMENT)
          [shift, index + 1]
        end
      end
    end

    def decode_backslash(bytes, index, shift, out)
      return [shift, index + 2] if bytes.byteslice(index, 2).match?(STYLE_MARKUP)

      out << "\\"
      [shift, index + 1]
    end

    # Longest table match at +index+; in doublebyte mode the table keys carry
    # the shift byte once at the front, so the walk starts below that node.
    def longest_match(bytes, index, shift)
      node = trie
      node = node[shift] or return nil if shift

      best = nil
      i = index
      while i < bytes.bytesize
        node = node[bytes.getbyte(i)] or break
        i += 1
        best = [i - index, node.fetch(:text)] if node.key?(:text)
      end
      best
    end

    # A matched sequence may cross mode transitions (…\x7F + single-byte
    # diacritic): replay the structural rules over the matched bytes to know
    # the mode decoding resumes in.
    def mode_after(bytes, index, length, shift)
      i = index
      while i < index + length
        byte = bytes.getbyte(i)
        if shift && byte >= 0x80
          i += 2
          next
        end
        shift = SHIFTS.cover?(byte) ? byte : nil
        i += 1
      end
      shift
    end

    # -- the tables ----------------------------------------------------------

    def trie
      @trie ||= build_trie(TABLE_PATHS.map { |path| File.binread(path) })
    end

    def build_trie(tables)
      trie = {}
      aliases = []
      tables.each do |table|
        each_mapping(table) do |left, right|
          if (unicode = right[/\AU\+(\h{4,6})/n, 1])
            insert(trie, left, [unicode.to_i(16)].pack("U"))
          else
            aliases << [left, right.sub(/\s+\*.*\z/n, "").sub(/\s+\z/n, "")]
          end
        end
      end
      resolve_aliases(trie, aliases)
      trie
    end

    def each_mapping(table)
      table.split(/\r?\n/).each do |line|
        next if line.empty? || line.start_with?("*")

        match = line.match(/\A(.*?) = (.*)\z/mn) or next
        left = match[1].match?(/\A +\z/n) ? match[1] : match[1].sub(/ +\z/n, "")
        yield left, match[2]
      end
    end

    # Alias rows spell their target in StarLing bytes; resolve them through
    # the already-built trie (never hand-guessed). An alias whose target the
    # table cannot decode is skipped rather than invented.
    def resolve_aliases(trie, aliases)
      @trie = trie
      aliases.each do |left, right|
        decoded = decode(right)
        insert(trie, left, decoded) unless decoded.empty? || decoded.include?(REPLACEMENT)
      end
    end

    # First mapping per byte sequence wins — upstream's own forward rule.
    def insert(trie, bytes, text)
      node = trie
      bytes.each_byte { |b| node = (node[b] ||= {}) }
      node[:text] = text unless node.key?(:text)
    end
  end
end
