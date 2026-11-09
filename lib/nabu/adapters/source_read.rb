# frozen_string_literal: true

require "zlib"

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
    #   SourceRead.utf8_lines(path, label: "hmml-reading-room") { |line| … }
    #   SourceRead.utf8_gzip(path, label: "vakk page")
    #   SourceRead.utf8_member(SourceRead.zip_file(path), entry, label: path)
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

      # The gzipped file at +path+, gunzipped whole and read as UTF-8 through
      # #utf8 (the error names the path, as #utf8_file). Container defects
      # stay Zlib::Error (and a missing file Errno::ENOENT): each caller maps
      # them onto its own contract, as with #zip_file. For members too big
      # to slurp, #utf8_lines with gzip: true.
      def utf8_gzip(path, label:, repair: nil)
        utf8(Zlib.gunzip(File.binread(path)), label: "#{label}: #{path}", repair: repair)
      end

      # Stream +path+ line by line — the reader for files too big to slurp
      # (a multi-hundred-MB JSONL member): each line (terminator kept, the
      # File.foreach split) is checked as UTF-8 and yielded; the file is
      # never read whole. Without a block, a lazy Enumerator. An invalid
      # line is Nabu::ParseError "<label>: <path> line <n> is not valid
      # UTF-8"; +repair+ as #utf8, per line. +gzip+ streams the lines of a
      # gzipped file (Zlib::GzipReader; container defects stay Zlib::Error).
      def utf8_lines(path, label:, repair: nil, gzip: false, &block)
        return enum_for(:utf8_lines, path, label: label, repair: repair, gzip: gzip) unless block

        if gzip
          Zlib::GzipReader.open(path) { |io| check_lines(io, path, label, repair, &block) }
        else
          File.open(path, "rb") { |io| check_lines(io, path, label, repair, &block) }
        end
        nil
      end

      def check_lines(io, path, label, repair)
        io.each_line.with_index(1) do |line, number|
          text = line.force_encoding(Encoding::UTF_8)
          yield text.valid_encoding? ? text : utf8(line, label: "#{label}: #{path} line #{number}", repair: repair)
        end
      end
      private_class_method :check_lines

      # Open the ZIP archive at +path+ (a Nabu::ZipReader over its bytes) —
      # the belt's one binary read. Structural defects stay
      # Nabu::ZipReader::Error: each caller maps it onto its own contract
      # (quarantine at parse, a refusal at fetch/drop). Member text comes
      # out through #utf8_member.
      def zip_file(path)
        Nabu::ZipReader.new(File.binread(path))
      end

      # One member of +zip+ (from #zip_file) as UTF-8 text, through #utf8:
      # the error label is "<label>: <member name>" (the name's upstream
      # bytes, read as UTF-8 and scrubbed — names are never decoded beyond
      # the label).
      def utf8_member(zip, entry, label:, repair: nil)
        name = entry.name.b.dup.force_encoding(Encoding::UTF_8).scrub
        utf8(zip.extract(entry), label: "#{label}: #{name}", repair: repair)
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
