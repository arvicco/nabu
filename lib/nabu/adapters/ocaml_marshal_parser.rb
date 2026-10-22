# frozen_string_literal: true

require_relative "source_read"

module Nabu
  module Adapters
    # The ocaml-marshal parser family (P142): a decoder for OCaml's
    # `Marshal` serialization — the intext format written by
    # `Marshal.to_string` / `output_value` (the OCaml runtime's
    # runtime/extern.c writes it, runtime/intern.c reads it; the format
    # is documented only by those two files). First consumer: SigLA,
    # whose web app ships its whole Linear A database as two Marshal
    # payloads (Nabu::Adapters::Sigla).
    #
    # Our own implementation, written against the runtime's documented
    # opcode table; the pyaegean reader (Apache-2.0) was studied for the
    # SigLA container's shape, not copied.
    #
    # == The format, as far as this decoder goes
    #
    # A 20-byte "small" header (magic 0x8495A6BE, then four big-endian
    # u32: data length, object count, 32-bit heap size, 64-bit heap
    # size) and ONE value, encoded as a prefix-coded tree:
    #
    #   0x80–0xFF  small block: tag = low 4 bits, size = bits 4–6
    #   0x40–0x7F  small int 0..63
    #   0x20–0x3F  small string, length = low 5 bits
    #   0x00/01/02/03  INT8 / INT16 / INT32 / INT64 (signed, big-endian)
    #   0x04/05/06  SHARED8 / 16 / 32 — a back-reference by DISTANCE from
    #              the newest registered object (how OCaml writes sharing
    #              and cycles)
    #   0x08       BLOCK32: header word, tag = low 8 bits, size = >> 10
    #   0x09/0x0A  STRING8 / STRING32
    #   0x0B/0x0C  DOUBLE big / little endian
    #   0x0D/0x0E/0x0F/0x07  float arrays (8- or 32-bit count, big/little)
    #   0x12/0x18/0x19  custom blocks — only the fixed-size boxed integers
    #              (_j int64, _i int32, _n nativeint) are understood
    #
    # Every NON-EMPTY block, string, double, float array and custom block
    # is registered in the shared-object table in allocation order;
    # zero-size blocks (atoms) and immediates are not. A block registers
    # BEFORE its fields are read, so a field may point back at its own
    # parent (OCaml permits cycles). The header's object count is checked
    # against the registrations at the end — a structural self-test that
    # the stream was read exactly as written — and the consumed length
    # against the declared data length.
    #
    # == What is refused (loud ParseError, never a guess)
    #
    # The 64-bit "big" header (0x8495A6BF), the compressed format
    # (0x8495A6BD, OCaml ≥ 5.1), BLOCK64, code pointers, and any custom
    # block other than the three boxed integers — none occurs in SigLA's
    # payloads, and a decoder that skips bytes it does not understand
    # would silently desynchronize.
    #
    # == Values out
    #
    # OCaml ints → Integer; strings → String (UTF-8-tagged; the bytes are
    # unchanged — validity is the consumer's call, OCaml strings are byte
    # arrays); doubles → Float; float arrays → Array of Float; boxed
    # integers → Integer; blocks → Block (tag + fields Array). The usual
    # encodings follow: a record or tuple is a tag-0 block; `None` and
    # constant constructors are immediates (0, 1, …); `Some x` is a
    # one-field tag-0 block; a list is nested two-field blocks ending in
    # 0; a Stdlib Map is a tree of 5-field nodes [left, key, value, right,
    # height] with 0 for Empty (see .map_entries).
    class OcamlMarshalParser
      MAGIC_SMALL = 0x8495A6BE
      MAGIC_BIG = 0x8495A6BF
      MAGIC_COMPRESSED = 0x8495A6BD
      HEADER_SIZE = 20

      CODE_INT8 = 0x00
      CODE_INT16 = 0x01
      CODE_INT32 = 0x02
      CODE_INT64 = 0x03
      CODE_SHARED8 = 0x04
      CODE_SHARED16 = 0x05
      CODE_SHARED32 = 0x06
      CODE_DOUBLE_ARRAY32_LITTLE = 0x07
      CODE_BLOCK32 = 0x08
      CODE_STRING8 = 0x09
      CODE_STRING32 = 0x0A
      CODE_DOUBLE_BIG = 0x0B
      CODE_DOUBLE_LITTLE = 0x0C
      CODE_DOUBLE_ARRAY8_BIG = 0x0D
      CODE_DOUBLE_ARRAY8_LITTLE = 0x0E
      CODE_DOUBLE_ARRAY32_BIG = 0x0F
      CODE_CUSTOM = 0x12
      CODE_BLOCK64 = 0x13
      CODE_CUSTOM_LEN = 0x18
      CODE_CUSTOM_FIXED = 0x19

      # Fixed payload widths of the custom blocks this decoder admits.
      CUSTOM_SIZES = { "_j" => 8, "_i" => 4, "_n" => 8 }.freeze

      # One OCaml heap block. +fields+ is filled after registration (the
      # cycle rule), so the struct is mutable by construction; consumers
      # treat it as read-only.
      Block = Struct.new(:tag, :fields) do
        def size = fields.size

        def [](index) = fields.fetch(index)

        def inspect
          "#<B#{tag} #{fields.map do |field|
            field.is_a?(Block) ? "B#{field.tag}[#{field.size}]" : field.inspect
          end.join(', ')}>"
        end
        alias_method :to_s, :inspect
      end

      # Header facts of one decoded payload, for provenance/diagnostics.
      Header = Data.define(:data_length, :object_count, :size32, :size64)

      # Decodes one Marshal payload (a binary String) to its Ruby value.
      def self.decode(bytes)
        new(bytes).decode
      end

      # Encodes a decoded value back to Marshal bytes (small header) —
      # the fixture-cut tool (test/fixtures/sigla/README.md): a trimmed
      # payload is re-serialized with the same choices OCaml's extern.c
      # makes (narrowest int/string/block code, sharing by object
      # identity, doubles little-endian), which the test suite proves by
      # re-encoding a real upstream payload byte-for-byte.
      def self.encode(value)
        Writer.new.encode(value)
      end

      # The in-order [key, value] pairs of a Stdlib Map value (Empty = the
      # immediate 0; Node = a 5-field block [l, k, v, r, h]). Iterative,
      # so a deep tree cannot exhaust the stack.
      def self.map_entries(node)
        entries = []
        stack = []
        current = node
        loop do
          while current.is_a?(Block)
            raise Nabu::ParseError, "OCaml Map node with #{current.size} fields (want 5)" unless current.size == 5

            stack << current
            current = current[0]
          end
          unless current.nil? || current.zero?
            raise Nabu::ParseError,
                  "OCaml Map leaf is #{current.inspect} (want 0, Empty)"
          end
          break if stack.empty?

          parent = stack.pop
          entries << [parent[1], parent[2]]
          current = parent[3]
        end
        entries
      end

      # The elements of an OCaml list (nested [head, tail] blocks ending in 0).
      def self.list_items(node)
        items = []
        while node.is_a?(Block)
          raise Nabu::ParseError, "OCaml list cell with #{node.size} fields (want 2)" unless node.size == 2

          items << node[0]
          node = node[1]
        end
        raise Nabu::ParseError, "OCaml list ends in #{node.inspect} (want 0, [])" unless node.zero?

        items
      end

      # An OCaml option: 0 → nil, Some x (one-field tag-0 block) → x.
      def self.option(value)
        return nil if value == 0 # rubocop:disable Style/NumericPredicate -- value may be a Block
        return value[0] if value.is_a?(Block) && value.tag.zero? && value.size == 1

        raise Nabu::ParseError, "not an OCaml option: #{value.inspect}"
      end

      attr_reader :header

      def initialize(bytes)
        @bytes = bytes.b
        @pos = 0
        @table = []
      end

      def decode
        @header = read_header
        @pos = HEADER_SIZE
        value = read_value
        consumed = @pos - HEADER_SIZE
        unless consumed == @header.data_length
          raise Nabu::ParseError, "OCaml Marshal: decoded #{consumed} of #{@header.data_length} declared bytes"
        end
        unless @table.size == @header.object_count
          raise Nabu::ParseError, "OCaml Marshal: registered #{@table.size} objects, header declares " \
                                  "#{@header.object_count} — the stream was misread"
        end
        value
      end

      private

      def read_header
        if @bytes.bytesize < HEADER_SIZE
          raise Nabu::ParseError,
                "OCaml Marshal: #{@bytes.bytesize} bytes is too short for a header"
        end

        magic, length, objects, size32, size64 = slice(0, HEADER_SIZE, "header").unpack("N5")
        check_magic!(magic)
        unless length == @bytes.bytesize - HEADER_SIZE
          raise Nabu::ParseError, "OCaml Marshal: header declares #{length} data bytes, " \
                                  "the payload carries #{@bytes.bytesize - HEADER_SIZE}"
        end
        Header.new(data_length: length, object_count: objects, size32: size32, size64: size64)
      end

      def check_magic!(magic)
        return if magic == MAGIC_SMALL

        kind = { MAGIC_BIG => "the 64-bit big-header format", MAGIC_COMPRESSED => "the compressed format" }[magic]
        raise Nabu::ParseError, "OCaml Marshal: #{kind || format('unknown magic 0x%08X', magic)} is not supported"
      end

      def read_value
        code = u8
        return read_block(code & 0x0F, (code >> 4) & 0x07) if code >= 0x80
        return code & 0x3F if code >= 0x40
        return read_string(code & 0x1F) if code >= 0x20

        read_coded(code)
      end

      # -- one branch per opcode is the format
      def read_coded(code)
        case code
        when CODE_INT8 then take(1).unpack1("c")
        when CODE_INT16 then take(2).unpack1("s>")
        when CODE_INT32 then take(4).unpack1("l>")
        when CODE_INT64 then take(8).unpack1("q>")
        when CODE_SHARED8 then shared(u8)
        when CODE_SHARED16 then shared(take(2).unpack1("n"))
        when CODE_SHARED32 then shared(take(4).unpack1("N"))
        when CODE_BLOCK32
          word = take(4).unpack1("N")
          read_block(word & 0xFF, word >> 10)
        when CODE_STRING8 then read_string(u8)
        when CODE_STRING32 then read_string(take(4).unpack1("N"))
        when CODE_DOUBLE_BIG then register(take(8).unpack1("G"))
        when CODE_DOUBLE_LITTLE then register(take(8).unpack1("E"))
        when CODE_DOUBLE_ARRAY8_BIG then read_doubles(u8, "G")
        when CODE_DOUBLE_ARRAY8_LITTLE then read_doubles(u8, "E")
        when CODE_DOUBLE_ARRAY32_BIG then read_doubles(take(4).unpack1("N"), "G")
        when CODE_DOUBLE_ARRAY32_LITTLE then read_doubles(take(4).unpack1("N"), "E")
        when CODE_CUSTOM, CODE_CUSTOM_LEN, CODE_CUSTOM_FIXED then read_custom(code)
        when CODE_BLOCK64 then raise Nabu::ParseError, "OCaml Marshal: BLOCK64 (a >2^22-field block) is not supported"
        else raise Nabu::ParseError, format("OCaml Marshal: unsupported opcode 0x%<code>02X at byte %<at>d",
                                            code: code, at: @pos - 1)
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity

      def read_block(tag, size)
        return Block.new(tag, [].freeze) if size.zero?

        block = register(Block.new(tag, []))
        size.times { block.fields << read_value }
        block.fields.freeze
        block
      end

      def read_string(length)
        register(take(length).force_encoding(Encoding::UTF_8).freeze)
      end

      def read_doubles(count, directive)
        register(Array.new(count) { take(8).unpack1(directive) }.freeze)
      end

      def read_custom(code)
        terminator = @bytes.index("\0", @pos)
        raise Nabu::ParseError, "OCaml Marshal: unterminated custom identifier at byte #{@pos}" unless terminator

        name = slice(@pos, terminator - @pos, "custom identifier")
        @pos = terminator + 1
        width = CUSTOM_SIZES[name]
        raise Nabu::ParseError, "OCaml Marshal: unsupported custom block #{name.inspect}" unless width

        take(8) if code == CODE_CUSTOM_LEN # the explicit 32/64-bit size words
        register(take(width).unpack1(width == 4 ? "l>" : "q>"))
      end

      def shared(distance)
        index = @table.size - distance
        unless distance.positive? && index >= 0
          raise Nabu::ParseError, "OCaml Marshal: shared reference #{distance} back of #{@table.size} objects"
        end

        @table[index]
      end

      def register(value)
        @table << value
        value
      end

      def u8
        take(1).getbyte(0)
      end

      def take(count)
        chunk = slice(@pos, count, "value")
        @pos += count
        chunk
      end

      # The bounds-checked read (the SourceRead belt): a short read is a
      # truncated payload, a ParseError — never a short slice decoded as
      # if whole.
      def slice(offset, length, what)
        SourceRead.slice(@bytes, offset: offset, length: length, what: "OCaml Marshal: truncated #{what} at")
      end

      # The encoder half (see .encode). Sharing is by Ruby object
      # identity, which the decoder preserves (a SHARED reference decodes
      # to the very object it points at). Ruby Floats carry no identity,
      # so a boxed double is always written fresh — OCaml shares a double
      # only when one boxed value is reachable twice, which SigLA's
      # payloads never do (the byte-identity test would catch it).
      class Writer
        # The GC color bits extern.c leaves in a BLOCK32 header word —
        # black (3 << 8) in every SigLA payload; the reader masks them off.
        BLACK = 0x300

        def initialize
          @out = +"".b
          @seen = {}.compare_by_identity
          @count = 0
        end

        def encode(value)
          @size32 = 0
          @size64 = 0
          write(value)
          [MAGIC_SMALL, @out.bytesize, @count, @size32, @size64].pack("N5") + @out
        end

        private

        # -- one branch per value kind
        def write(value)
          case value
          when Integer then write_int(value)
          when Float
            @count += 1
            grow(3, 2)
            @out << CODE_DOUBLE_LITTLE << [value].pack("E")
          when String, Block, Array
            return write_shared(@seen[value]) if @seen.key?(value)

            write_heap(value)
          else raise Nabu::ParseError, "OCaml Marshal: cannot encode #{value.class}"
          end
        end
        # rubocop:enable Metrics/PerceivedComplexity

        # Atoms (zero-size blocks) are static in OCaml: never registered,
        # never shared, no heap words.
        def write_heap(value)
          return write_atom(value.tag) if value.is_a?(Block) && value.fields.empty?

          @seen[value] = @count
          @count += 1
          case value
          when String then write_string(value.b)
          when Array then write_doubles(value)
          else write_block(value)
          end
        end

        def write_atom(tag)
          if tag < 16 then @out << (0x80 | tag)
          else @out << CODE_BLOCK32 << [tag].pack("N")
          end
        end

        # The header's heap-size words: what the value occupies once
        # interned on a 32- and a 64-bit runtime, headers included.
        def grow(words32, words64)
          @size32 += words32
          @size64 += words64
        end

        def write_int(int)
          if int.between?(0, 0x3F) then @out << (0x40 | int)
          elsif int.between?(-0x80, 0x7F) then @out << CODE_INT8 << [int].pack("c")
          elsif int.between?(-0x8000, 0x7FFF) then @out << CODE_INT16 << [int].pack("s>")
          elsif int.between?(-0x8000_0000, 0x7FFF_FFFF) then @out << CODE_INT32 << [int].pack("l>")
          else @out << CODE_INT64 << [int].pack("q>")
          end
        end

        def write_shared(index)
          distance = @count - index
          if distance < 0x100 then @out << CODE_SHARED8 << distance
          elsif distance < 0x10000 then @out << CODE_SHARED16 << [distance].pack("n")
          else @out << CODE_SHARED32 << [distance].pack("N")
          end
        end

        def write_string(bytes)
          length = bytes.bytesize
          grow(1 + ((length + 4) / 4), 1 + ((length + 8) / 8))
          if length < 0x20 then @out << (0x20 | length)
          elsif length < 0x100 then @out << CODE_STRING8 << length
          else @out << CODE_STRING32 << [length].pack("N")
          end
          @out << bytes
        end

        def write_doubles(doubles)
          grow(1 + (2 * doubles.size), 1 + doubles.size)
          if doubles.size < 0x100 then @out << CODE_DOUBLE_ARRAY8_LITTLE << doubles.size
          else @out << CODE_DOUBLE_ARRAY32_LITTLE << [doubles.size].pack("N")
          end
          @out << doubles.pack("E*")
        end

        def write_block(block)
          grow(1 + block.size, 1 + block.size)
          if block.tag < 16 && block.size < 8
            @out << (0x80 | block.tag | (block.size << 4))
          else
            @out << CODE_BLOCK32 << [(block.size << 10) | BLACK | block.tag].pack("N")
          end
          block.fields.each { |field| write(field) }
        end
      end
    end
  end
end
