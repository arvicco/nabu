# frozen_string_literal: true

require_relative "errors"
require_relative "snappy"

module Nabu
  # A minimal, streaming, pure-Ruby parquet READER — exactly the slice of
  # the format the house's parquet-only upstreams need, no gem (the
  # dependency budget; the blbooks lane routed around parquet, the
  # PleIAs/French-PD-Books re-host serves nothing else). Format reference:
  # github.com/apache/parquet-format (parquet.thrift, Encodings.md).
  #
  # Supported — and anything else raises Parquet::Error, never guesses:
  # - flat schemas (one level under the root; REQUIRED or OPTIONAL leaves);
  # - BYTE_ARRAY, INT32, INT64, DOUBLE, BOOLEAN physical types;
  # - DATA_PAGE (v1) pages, PLAIN values, RLE/bit-packed hybrid definition
  #   levels; dictionary pages and v2 pages raise;
  # - UNCOMPRESSED and SNAPPY (Nabu::Snappy) codecs.
  #
  # Columns STREAM: #each_value decodes one column chunk page by page and
  # yields [row_index, value]; a page's values are pulled out of the
  # decompressor as they complete, so a 526 MB text page never sits in
  # memory whole. +want+ (a Set of row indexes, or nil = every row) lets
  # the caller skip the values it does not keep without materializing
  # them (the bytes still stream through — PLAIN is not seekable).
  class Parquet
    class Error < Nabu::Error; end

    MAGIC = "PAR1".b
    PHYSICAL = { 0 => :boolean, 1 => :int32, 2 => :int64, 3 => :int96, 4 => :float, 5 => :double,
                 6 => :byte_array, 7 => :fixed_len_byte_array }.freeze
    CODECS = { 0 => :uncompressed, 1 => :snappy }.freeze
    REQUIRED = 0
    OPTIONAL = 1
    DATA_PAGE = 0
    PLAIN = 0
    RLE = 3

    Column = Data.define(:name, :type, :optional, :codec, :num_values, :data_offset, :total_size)

    # +io+ is a seekable binary IO over the whole file.
    def initialize(io)
      @io = io
      @io.binmode
      read_footer!
    end

    attr_reader :num_rows, :created_by

    def column_names = @columns.keys

    # The whole column as an Array (small metadata columns).
    def column(name)
      values = Array.new(@num_rows)
      each_value(name) { |row, value| values[row] = value }
      values
    end

    # Yield [row_index, value] for every row of +name+ (nil for a null),
    # or only the rows in +want+.
    def each_value(name, want: nil, &)
      column = @columns.fetch(name) { raise Error, "no column #{name.inspect} (have #{column_names.join(', ')})" }
      row = 0
      offset = column.data_offset
      while row < column.num_values
        @io.seek(offset)
        header, header_size = read_header
        page_end = offset + header_size + header.fetch(3)
        row = read_page(column, header, row, want, &)
        offset = page_end
      end
      raise Error, "#{name}: pages hold #{row} values, the chunk declares #{column.num_values}" unless
        row == column.num_values
    end

    # The data pages of +name+'s chunk (headers only; nothing decoded).
    def page_count(name)
      column = @columns.fetch(name)
      offset = column.data_offset
      stop = offset + column.total_size
      pages = 0
      while offset < stop
        @io.seek(offset)
        header, header_size = read_header
        offset += header_size + header.fetch(3)
        pages += 1
      end
      pages
    end

    private

    # -- footer -------------------------------------------------------------

    def read_footer!
      @io.seek(0, IO::SEEK_END)
      size = @io.pos
      raise Error, "not a parquet file (#{size} bytes)" if size < 12

      @io.seek(size - 8)
      length = @io.read(4).unpack1("V")
      raise Error, "not a parquet file (no PAR1 trailer)" unless @io.read(4) == MAGIC

      @io.seek(size - 8 - length)
      meta = Thrift.new(@io.read(length)).struct
      @num_rows = meta.fetch(3)
      @created_by = meta[6]
      @columns = columns_from(meta)
    end

    def columns_from(meta)
      schema = meta.fetch(2)
      root = schema.first
      leaves = schema.drop(1)
      raise Error, "nested schema (#{leaves.size} elements, root declares #{root[5]})" unless
        root[5] == leaves.size && leaves.none? { |el| el[5] }

      groups = meta.fetch(4)
      raise Error, "#{groups.size} row groups; at most one is supported" if groups.size > 1

      # A zero-row file writes no row group: every column is empty.
      chunks = groups.empty? ? leaves.map { { 3 => { 4 => 0, 5 => 0, 9 => 0, 7 => 0 } } } : groups.first.fetch(1)
      leaves.zip(chunks).to_h do |element, chunk|
        md = chunk.fetch(3)
        name = element.fetch(4)
        [name, Column.new(name: name, type: PHYSICAL.fetch(element.fetch(1)),
                          optional: element.fetch(3) == OPTIONAL,
                          codec: CODECS.fetch(md.fetch(4)) { |code| raise Error, "#{name}: codec #{code} unsupported" },
                          num_values: md.fetch(5), data_offset: md.fetch(9), total_size: md.fetch(7))]
      end
    end

    # -- pages --------------------------------------------------------------

    # The page header at the IO position: [fields, header byte size]; the
    # IO is left at the first byte of the page's data.
    def read_header
      start = @io.pos
      [256, 65_536].each do |window|
        @io.seek(start)
        thrift = Thrift.new(@io.read(window) || "".b)
        header = thrift.struct
        @io.seek(start + thrift.pos)
        return [header, thrift.pos]
      rescue Thrift::Underflow
        next
      end
      raise Error, "a page header at byte #{start} runs past 64 KiB"
    end

    def read_page(column, header, row, want, &block)
      raise Error, "#{column.name}: page type #{header[1]} (only v1 data pages are supported)" unless
        header.fetch(1) == DATA_PAGE

      data = header.fetch(5)
      count = data.fetch(1)
      raise Error, "#{column.name}: value encoding #{data[2]} (only PLAIN)" unless data.fetch(2) == PLAIN

      stream = PageStream.new(@io, column.codec, header.fetch(3))
      defined = column.optional ? definition_levels(stream, count, data.fetch(3)) : Array.new(count, 1)
      defined.each do |level|
        if level.zero?
          block.call(row, nil) if want.nil? || want.include?(row)
        elsif want.nil? || want.include?(row)
          block.call(row, read_value(stream, column.type))
        else
          skip_value(stream, column.type)
        end
        row += 1
      end
      row
    end

    # v1 levels: a 4-byte LE byte length, then the RLE/bit-packed hybrid
    # at bit width 1 (a flat OPTIONAL leaf's max level).
    def definition_levels(stream, count, encoding)
      raise Error, "definition-level encoding #{encoding} (only RLE)" unless encoding == RLE

      bytes = stream.read(stream.read(4).unpack1("V"))
      Hybrid.decode(bytes, count: count, width: 1)
    end

    def read_value(stream, type)
      case type
      when :byte_array then stream.read(stream.read(4).unpack1("V"))
      when :int64 then stream.read(8).unpack1("q<")
      when :int32 then stream.read(4).unpack1("l<")
      when :double then stream.read(8).unpack1("E")
      else raise Error, "physical type #{type} unsupported"
      end
    end

    def skip_value(stream, type)
      case type
      when :byte_array then stream.skip(stream.read(4).unpack1("V"))
      else read_value(stream, type)
      end
    end

    # A page's decompressed bytes as a pull stream over Snappy's chunks.
    class PageStream
      def initialize(io, codec, size)
        @chunks = case codec
                  when :snappy then Enumerator.new { |y| Snappy.each_chunk(io, size) { |chunk| y << chunk } }
                  else Enumerator.new { |y| y << io.read(size).b }
                  end
        @buffer = "".b
        @pos = 0
      end

      def read(count)
        more(count)
        value = @buffer.byteslice(@pos, count)
        @pos += count
        value
      end

      def skip(count)
        while count.positive?
          more(1)
          take = [count, @buffer.bytesize - @pos].min
          @pos += take
          count -= take
        end
      end

      private

      def more(count)
        while @buffer.bytesize - @pos < count
          chunk = begin
            @chunks.next
          rescue StopIteration
            raise Error, "page ended #{count - (@buffer.bytesize - @pos)} byte(s) early"
          end
          @buffer = @buffer.byteslice(@pos, @buffer.bytesize - @pos) << chunk
          @pos = 0
        end
      end
    end

    # The RLE/bit-packed hybrid (Encodings.md): runs headed by a ULEB128;
    # low bit 0 = RLE run (count = header >> 1, one value in ceil(width/8)
    # bytes), 1 = bit-packed groups of eight (header >> 1 groups, LSB first).
    module Hybrid
      def self.decode(bytes, count:, width:)
        values = []
        pos = 0
        value_bytes = (width + 7) / 8
        while values.size < count
          header, pos = uleb(bytes, pos)
          if header.even?
            value = 0
            value_bytes.times { |i| value |= bytes.getbyte(pos + i) << (8 * i) }
            pos += value_bytes
            values.concat(Array.new(header >> 1, value))
          else
            groups = header >> 1
            bits = bytes.byteslice(pos, groups * width).unpack1("b*")
            pos += groups * width
            (groups * 8).times { |i| values << bits[i * width, width].reverse.to_i(2) }
          end
        end
        values.first(count)
      end

      def self.uleb(bytes, pos)
        value = 0
        shift = 0
        loop do
          b = bytes.getbyte(pos) or raise Error, "definition levels end inside a run header"
          pos += 1
          value |= (b & 0x7f) << shift
          return [value, pos] if b < 0x80

          shift += 7
        end
      end
    end

    # The Thrift COMPACT protocol, generically: a struct decodes to a Hash
    # of field id → value (structs nest as Hashes, lists as Arrays,
    # binaries as binary Strings), so the reader names fields by their
    # parquet.thrift ids and unknown fields cost nothing.
    class Thrift
      class Underflow < Error; end

      def initialize(bytes)
        @bytes = bytes.b
        @pos = 0
      end

      attr_reader :pos

      def struct
        fields = {}
        last = 0
        loop do
          head = byte
          return fields if head.zero?

          type = head & 0x0f
          delta = head >> 4
          id = delta.zero? ? zigzag(varint) : last + delta
          last = id
          fields[id] = value(type)
        end
      end

      private

      def value(type)
        case type
        when 1 then true
        when 2 then false
        when 3 then [byte].pack("C").unpack1("c")
        when 4, 5, 6 then zigzag(varint)
        when 7 then take(8).unpack1("E")
        when 8 then take(varint)
        when 9, 10 then list
        when 11 then map
        when 12 then struct
        else raise Error, "thrift: unknown compact type #{type}"
        end
      end

      def list
        head = byte
        size = head >> 4
        size = varint if size == 15
        type = head & 0x0f
        Array.new(size) { [1, 2].include?(type) ? byte == 1 : value(type) }
      end

      def map
        size = varint
        return {} if size.zero?

        types = byte
        Array.new(size) { [value(types >> 4), value(types & 0x0f)] }.to_h
      end

      def byte
        raise Underflow, "thrift: input ended at byte #{@pos}" if @pos >= @bytes.bytesize

        value = @bytes.getbyte(@pos)
        @pos += 1
        value
      end

      def take(count)
        raise Underflow, "thrift: input ended inside a #{count}-byte value" if @pos + count > @bytes.bytesize

        value = @bytes.byteslice(@pos, count)
        @pos += count
        value
      end

      def varint
        value = 0
        shift = 0
        loop do
          b = byte
          value |= (b & 0x7f) << shift
          return value if b < 0x80

          shift += 7
        end
      end

      def zigzag(value) = (value >> 1) ^ -(value & 1)
    end
  end
end
