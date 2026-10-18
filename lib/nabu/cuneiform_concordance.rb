# frozen_string_literal: true

require_relative "normalize"

module Nabu
  # The shared key rules of the cuneiform catalogue concordance — the
  # CDLI ↔ ETCSL ↔ ORACC triangle meets at reference-edge HUBS (the
  # composite_id mold: urn:nabu:cdli:q… targets are dangling-but-stable
  # hubs every witness of one composite points at, and `nabu links
  # <hub>` lists them all). Two hub spaces live here, each folded
  # identically on both asserting sides so the hubs meet:
  #
  # - "object:<KEY>" — one physical fragment named by its museum or
  #   excavation siglum. ETCSL lists its witnesses as "CBS 7914 (JCS 1
  #   27)" (publication in parentheses, joins "N 1013 + Ni 9950"); CDLI
  #   catalogues "CBS 07914" (zero-padded) and the Istanbul collection as
  #   "Ist Ni 04405" where ETCSL writes "Ni 4405". The key tokenizes on
  #   letter/digit runs (punctuation and spacing drift fall away), strips
  #   leading zeros, upcases, sheds the leading "Ist" collection prefix,
  #   and drops trailing prose after the last number (short suffixes like
  #   the "a" of "54a" stay). A join yields one hub per fragment; a bare
  #   join number inherits the previous fragment's prefix ("CBS 10305 +
  #   10315"); "=" equations (excavation = museum number) yield both. A
  #   withheld or unknown number ("BM —", "unknown") yields nothing.
  # - "etcsl:<number>" — one ETCSL composition. ETCSL's own file numbers
  #   pad irregularly (c.0.2.01, c.3.1.06.1) while CDLI pads every segment
  #   ("ETCSL 1.08.02.01"); the hub folds both to unpadded segments
  #   (1.8.2.1). ETCSL urns stay FROZEN as minted — the hub is a separate
  #   key both sides assert.
  #
  # Pure functions, no state: each adapter calls them at its own parse.
  module CuneiformConcordance
    OBJECT_SCHEME = "object:"
    ETCSL_SCHEME = "etcsl:"

    # The indirect-join marker "(+)" / "(+?)" survives parenthetical
    # stripping under this placeholder.
    INDIRECT = "\u0000"

    # An ETCSL number segment: digits with an optional letter suffix
    # (6.1.03a) or a bare letter (2.4.2.a).
    ETCSL_SEGMENT = /\A(?:\d+[a-z]?|[a-z])\z/

    # "ETCSL 6.01.02 Proverbs …" — the number must be followed by a
    # space, ";" or ")" so a value cut at the catalogue's column limit
    # ("ETCSL 4.08.0") is never read as a claim.
    ETCSL_REF = /ETCSL\s+(\d+(?:\.[0-9a-z]+)+)(?=[\s;)])/

    module_function

    # The display form of one witness entry: publication parentheticals
    # stripped, sic/editorial flags dropped, joins intact.
    def museum_number(raw)
      text = Normalize.nfc(raw.to_s).gsub(/\(\+\??\)/, INDIRECT)
      text = strip_parentheticals(text)
      text = text.gsub("***", "").delete("!").sub(/\A\s*\?/, "")
      text.gsub(INDIRECT, " (+) ").gsub(/\s+/, " ").strip.sub(/\s*\?\z/, "")
    end

    # One "object:<KEY>" hub per fragment of a (possibly joined) entry.
    def object_hubs(raw)
      prefix = nil
      fragments(raw).filter_map do |fragment|
        if fragment.match?(/\A\d+[a-z]?\z/i) && prefix
          fragment = "#{prefix} #{fragment}"
        else
          prefix = fragment[/\A(.*?)\s*\d+[a-z]?\z/i, 1]
          prefix = nil if prefix.to_s.strip.empty?
        end
        key = object_key(fragment)
        "#{OBJECT_SCHEME}#{key}" if key
      end.uniq
    end

    # "etcsl:1.8.2.1" from either padding, or nil for a malformed number.
    def etcsl_hub(number)
      segments = number.to_s.strip.downcase.split(".")
      return nil if segments.size < 2 || !segments.all? { |segment| segment.match?(ETCSL_SEGMENT) }

      "#{ETCSL_SCHEME}#{segments.map { |segment| segment.sub(/\A0+(?=\d)/, '') }.join('.')}"
    end

    # The ETCSL composition numbers a CDLI subgenre cell names, in order;
    # numbers outside ETCSL's grammar (CDLI's own "add01" addenda) are
    # dropped.
    def etcsl_refs(text)
      text.to_s.scan(ETCSL_REF).flatten.select { |number| etcsl_hub(number) }.uniq
    end

    def strip_parentheticals(text)
      previous = nil
      text = text.gsub(/\([^()]*\)/, " ") while previous != (previous = text)
      text
    end

    def fragments(raw)
      museum_number(raw).gsub("(+)", "+").split(/\s*[+=]\s*/).map(&:strip).reject(&:empty?)
    end

    # Letter/digit runs, zeros stripped, upcased; the Istanbul prefix
    # shed; trailing prose after the last number dropped (≤2-letter
    # suffixes kept). nil when no number remains.
    def object_key(fragment)
      tokens = fragment.scan(/[A-Za-z]+|\d+/).map { |token| token.match?(/\A\d+\z/) ? token.to_i.to_s : token.upcase }
      tokens.shift if tokens.first == "IST"
      last = tokens.rindex { |token| token.match?(/\A\d+\z/) } or return nil

      tail = tokens[(last + 1)..].take_while { |token| token.size <= 2 }
      (tokens[0..last] + tail).join(" ")
    end
  end
end
