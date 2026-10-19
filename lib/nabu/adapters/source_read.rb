# frozen_string_literal: true

module Nabu
  module Adapters
    # The encoding/bounds belt at the adapter read seam (architecture §3).
    # It lives under adapters/ so the per-source parser closure covers it:
    # only the adapters that read through it re-derive when it changes,
    # never the whole library.
    #
    # An adapter's read path is a SECOND error channel beside ParseError:
    # invalid bytes raise ArgumentError / Encoding errors from deep inside a
    # parser, which the loader's per-document net (ParseError → quarantine)
    # does not catch, so one bad upstream page aborts the whole sync; and a
    # byte pointer past its buffer returns a SHORT slice that decodes as a
    # truncated cell or reads on into the next frame. Each family that met
    # one of these grew its own guard; this module is the one copy.
    #
    # The contract: every check here turns bad bytes into Nabu::ParseError —
    # the document is quarantined, the sync continues — and leaves good bytes
    # exactly as they were (the belt never "cleans" upstream text).
    #
    #   SourceRead.utf8_file(path, label: "titus-pahlavi", repair: :severed_tags)
    #   SourceRead.utf8(bytes, label: "zip:#{member}")
    #   SourceRead.nfc(text, language: lang)
    #   SourceRead.slice(heap, offset: ptr, length: len, what: "#{path}: var pointer")
    #
    # New adapter code reads canonical files through these helpers; the
    # conventions scan (test/adapters/source_read_conventions_test.rb)
    # fails on a new bare File.read/binread/foreach/open in adapters/.
    module SourceRead
      # TITUS severs a multibyte character around an HTML tag: the lead byte
      # (plus any continuation bytes before the cut) sits BEFORE the tag and
      # the remaining continuation bytes AFTER it. Real specimens (both
      # titus-pahlavi): snstrl/snstr002 "LCḎr̄'\xCC</a>\xB1" (U+0331) and
      # zwy/zwy005 "štr\xCA</a>\xBC" (U+02BC).
      SEVERED_SEQUENCE = %r{([\xC2-\xF4][\x80-\xBF]{0,2})(</?[A-Za-z][^<>]*>)([\x80-\xBF]{1,3})}n

      # The named repairs a caller may opt into (none is ever implicit).
      REPAIRS = %i[severed_tags].freeze

      module_function

      # Read +path+ as UTF-8 (a leading BOM is upstream text and stays). See
      # #utf8 for +label+ and +repair+; the error names the path.
      def utf8_file(path, label:, repair: nil)
        utf8(File.binread(path), label: "#{label}: #{path}", repair: repair)
      end

      # +bytes+ as a valid UTF-8 String, or Nabu::ParseError "<label> is not
      # valid UTF-8". +repair+ (:severed_tags) attempts the severed-sequence
      # rejoin before giving up: the bytes after the tag move in front of it,
      # completing the character on the text it was cut from.
      def utf8(bytes, label:, repair: nil)
        raise ArgumentError, "unknown repair #{repair.inspect}" unless repair.nil? || REPAIRS.include?(repair)

        text = bytes.dup.force_encoding(Encoding::UTF_8)
        return text if text.valid_encoding?

        if repair == :severed_tags
          repaired = repair_severed(bytes)
          return repaired if repaired.valid_encoding?

          raise Nabu::ParseError, "#{label} is not valid UTF-8 (beyond the severed-sequence repair)"
        end
        raise Nabu::ParseError, "#{label} is not valid UTF-8"
      end

      # The severed-sequence rejoin (see SEVERED_SEQUENCE), tagged UTF-8 —
      # the caller re-validates.
      def repair_severed(bytes)
        bytes.b.gsub(SEVERED_SEQUENCE, '\2\1\3').force_encoding(Encoding::UTF_8)
      end

      # NFC at the adapter boundary, honoring the named exemption list
      # (Normalize::NFC_EXEMPT_LANGUAGES — hbo/arc keep upstream mark order).
      # Invalid bytes are a ParseError, never Normalize::EncodingError.
      def nfc(text, language:)
        return text if Normalize.nfc_exempt?(language)

        Normalize.nfc(text)
      rescue Normalize::EncodingError => e
        raise Nabu::ParseError, e.message
      end

      # Exactly +length+ bytes of +bytes+ from +offset+, or Nabu::ParseError
      # "<what> <offset>+<length> reaches past the end of the file" — never a
      # short slice the caller would decode as if whole.
      def slice(bytes, offset:, length:, what:)
        if offset.negative? || length.negative? || offset + length > bytes.bytesize
          raise Nabu::ParseError, "#{what} #{offset}+#{length} reaches past the end of the file"
        end

        bytes.byteslice(offset, length)
      end
    end
  end
end
