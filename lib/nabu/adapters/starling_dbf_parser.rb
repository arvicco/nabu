# frozen_string_literal: true

require_relative "../errors"
require_relative "../starling_text"

module Nabu
  module Adapters
    # The starling-dbf parser family (P22-0): a hand-rolled dBase III table
    # reader for the StarLing / Tower of Babel database downloads
    # (docs/pie-survey.md §3.1) — header, 32-byte field descriptors,
    # fixed-width records — plus the StarLing var-text convention layered on
    # top: a character field of length 6 whose descriptor byte 12 is "V"
    # does not hold text but a POINTER into the sibling .var file (uint32 LE
    # offset + uint16 LE length; six spaces = empty). Var payloads (and any
    # inline character cells) are StarLing-encoded text, decoded to UTF-8
    # NFC through Nabu::StarlingText (the table-driven boundary transcoder).
    #
    # Format facts read from the files themselves and cross-checked against
    # the published StarLing 3.9.0 package (config/starling/README.md):
    # version byte 0x03 (plain dBase III, no memo flag — StarLing's .var
    # replaces the dBase .dbt), record count at offset 4 (uint32 LE), header
    # and record lengths at 8/10 (uint16 LE), descriptors from offset 32
    # until the 0x0D terminator, records prefixed by the deletion flag
    # (0x2A "*" = deleted, skipped), optional trailing 0x1A EOF marker
    # (pokorny.dbf has one, piet.dbf does not — both real).
    #
    # Numeric (N) cells come back as trimmed strings; character cells as
    # decoded text or nil when empty. Damage raises Nabu::ParseError — the
    # adapter's quarantine lane.
    class StarlingDbfParser
      HEADER_LENGTH = 32
      DESCRIPTOR_LENGTH = 32
      DESCRIPTOR_TERMINATOR = 0x0D
      DELETED_FLAG = 0x2A
      VAR_MARKER = 0x56 # "V" in descriptor byte 12: this cell points into .var
      VAR_POINTER_LENGTH = 6
      EMPTY_CELL = " " * VAR_POINTER_LENGTH
      DBASE_III = 0x03

      # One column: +name+ (upstream, e.g. "ROOT"), +type+ ("C"/"N"),
      # +length+ in record bytes, +var+ true when the cell is a var-pointer.
      Field = Data.define(:name, :type, :length, :var)

      def initialize(dbf_path:, var_path: nil)
        @dbf_path = dbf_path
        @var_path = var_path || dbf_path.sub(/\.dbf\z/i, ".var")
      end

      def fields
        header
        @fields
      end

      # Yield one { field name => value } hash per live record, file order.
      def each_record(&block)
        return enum_for(:each_record) unless block

        header
        @record_count.times do |index|
          record = @data.byteslice(@header_length + (index * @record_length), @record_length)
          next if record.nil? || record.bytesize < @record_length
          next if record.getbyte(0) == DELETED_FLAG

          yield read_record(record)
        end
      end

      private

      def header
        @header ||= begin
          @data = File.binread(@dbf_path)
          version = @data.getbyte(0)
          unless version == DBASE_III
            raise Nabu::ParseError,
                  "#{@dbf_path}: not a dBase III table (version byte 0x#{format('%02x', version.to_i)})"
          end

          @record_count = @data[4, 4].unpack1("V")
          @header_length = @data[8, 2].unpack1("v")
          @record_length = @data[10, 2].unpack1("v")
          @fields = read_descriptors
          true
        end
      end

      def read_descriptors
        fields = []
        offset = HEADER_LENGTH
        while offset < @header_length && @data.getbyte(offset) != DESCRIPTOR_TERMINATOR
          descriptor = @data.byteslice(offset, DESCRIPTOR_LENGTH)
          type = descriptor[11]
          length = descriptor.getbyte(16)
          fields << Field.new(
            name: descriptor[0, 11].unpack1("Z*"), type: type, length: length,
            var: type == "C" && length == VAR_POINTER_LENGTH && descriptor.getbyte(12) == VAR_MARKER
          )
          offset += DESCRIPTOR_LENGTH
        end
        raise Nabu::ParseError, "#{@dbf_path}: no field descriptors" if fields.empty?

        fields
      end

      def read_record(record)
        position = 1 # byte 0 is the deletion flag
        @fields.each_with_object({}) do |field, row|
          cell = record.byteslice(position, field.length)
          position += field.length
          row[field.name] = cell_value(field, cell)
        end
      end

      def cell_value(field, cell)
        case field.type
        when "N" then cell.strip
        when "C" then field.var ? var_text(cell) : inline_text(cell)
        else cell
        end
      end

      def inline_text(cell)
        text = StarlingText.decode(cell).strip
        text.empty? ? nil : text
      end

      def var_text(cell)
        return nil if cell == EMPTY_CELL

        offset, length = cell.unpack("Vv")
        payload = var_data.byteslice(offset, length)
        if payload.nil? || payload.bytesize < length
          raise Nabu::ParseError,
                "#{@var_path}: var pointer #{offset}+#{length} reaches past the end of the file"
        end
        StarlingText.decode(payload)
      end

      def var_data
        @var_data ||= begin
          raise Nabu::ParseError, "#{@dbf_path}: sibling .var file missing" unless File.file?(@var_path)

          File.binread(@var_path)
        end
      end
    end
  end
end
