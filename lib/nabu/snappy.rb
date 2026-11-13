# frozen_string_literal: true

require "stringio"

require_relative "errors"

module Nabu
  # A streaming decoder for the RAW Snappy block format (the compression
  # parquet writers apply per page — no framing, no CRCs; format spec:
  # github.com/google/snappy/blob/main/format_description.txt). Pure Ruby,
  # no gem (the dependency budget): the first consumer is the
  # PleIAs/French-PD-Books parquet shards, whose text pages run to ~526 MB
  # uncompressed in ONE snappy block — so the decoder never holds the whole
  # output. It yields the decompressed bytes in chunks and keeps only a
  # back-reference WINDOW of already-yielded output.
  #
  # Why a window is enough: every reference encoder (snappy C++, the Rust
  # snap crate that cramjam/fastparquet use, Go's) compresses its input in
  # independent 64 KiB fragments, so no copy reaches further back than
  # 65,536 bytes. WINDOW keeps 16× that; a copy reaching past it raises
  # instead of decoding garbage.
  #
  # Element grammar (tag byte, low two bits):
  #   00 literal — length-1 in the upper six bits, or (60..63) a 1–4 byte
  #      little-endian length-1 following the tag; the bytes follow.
  #   01 copy, 1-byte offset — length-4 in bits 2..4, offset's high three
  #      bits in bits 5..7, low byte following.
  #   10 copy, 2-byte LE offset — length-1 in the upper six bits.
  #   11 copy, 4-byte LE offset — likewise.
  # A copy whose offset is shorter than its length repeats the pattern
  # (run-length encoding by overlap).
  module Snappy
    class Error < Nabu::Error; end

    # const: the back-reference window kept after a flush (16× the 64 KiB
    # fragment every reference encoder uses), not a corpus claim
    WINDOW = 1 << 20
    # const: output flushed to the caller in chunks of about this size
    FLUSH = 4 << 20
    # const: input read from the IO in blocks of this size
    READ = 4 << 20
    # const: the largest element (tag + 4 length bytes + a 64 KiB literal
    # is the reference encoders' ceiling; a longer literal refills on demand)
    ELEMENT = 70_000

    # Decompress a whole in-memory block (tests, small pages).
    def self.inflate(bytes)
      out = +""
      out.force_encoding(Encoding::BINARY)
      each_chunk(StringIO.new(bytes.b), bytes.bytesize) { |chunk| out << chunk }
      out
    end

    # Stream-decode the +length+ compressed bytes at +io+'s position,
    # yielding binary output chunks; the chunks total exactly the length
    # the block's preamble declares, or this raises.
    # +window+/+flush+ are seams for tests (a tiny window proves the
    # flush keeps exactly the bytes a back-reference may still reach).
    def self.each_chunk(io, length, window: WINDOW, flush: FLUSH, &)
      Decoder.new(io, length, window: window, flush: flush).run(&)
    end

    # One block's decoder state (input buffer, output window).
    class Decoder
      def initialize(io, length, window:, flush:)
        @io = io
        @remaining = length
        @window = window
        @flush = flush
        @in = "".b
        @pos = 0
        @out = "".b
        @yielded = 0
      end

      def run(&block)
        expected = read_varint
        until @pos >= @in.bytesize && @remaining.zero?
          fill(ELEMENT)
          element!
          flush!(block) if @out.bytesize >= @flush + @window
        end
        block.call(@out) unless @out.empty?
        total = @yielded + @out.bytesize
        raise Error, "snappy block declared #{expected} bytes, decoded #{total}" unless total == expected
      end

      private

      def element!
        tag = byte
        case tag & 3
        when 0 then literal!(tag >> 2)
        when 1 then copy!(((tag >> 2) & 7) + 4, ((tag >> 5) << 8) | byte)
        when 2 then copy!((tag >> 2) + 1, le(2))
        else copy!((tag >> 2) + 1, le(4))
        end
      end

      def literal!(code)
        length = code < 60 ? code + 1 : le(code - 59) + 1
        fill(length)
        raise Error, "snappy literal of #{length} bytes runs past the block" if @in.bytesize - @pos < length

        @out << @in.byteslice(@pos, length)
        @pos += length
      end

      def copy!(length, offset)
        size = @out.bytesize
        raise Error, "snappy copy with offset 0" if offset.zero?
        raise Error, "snappy copy reaches #{offset} bytes back, past the #{size}-byte window" if offset > size

        if offset >= length
          @out << @out.byteslice(size - offset, length)
        else
          pattern = @out.byteslice(size - offset, offset)
          @out << (pattern * ((length / offset) + 1)).byteslice(0, length)
        end
      end

      # Yield all but the window; keep the window for back-references.
      def flush!(block)
        cut = @out.bytesize - @window
        block.call(@out.byteslice(0, cut))
        @yielded += cut
        @out = @out.byteslice(cut, @window)
      end

      # Ensure +need+ unread input bytes are buffered (or the block's end).
      def fill(need)
        return if @in.bytesize - @pos >= need || @remaining.zero?

        @in = @in.byteslice(@pos, @in.bytesize - @pos)
        @pos = 0
        while @in.bytesize < need && @remaining.positive?
          chunk = @io.read([READ, need].max.clamp(1, @remaining))
          raise Error, "snappy input ended #{@remaining} bytes early" if chunk.nil? || chunk.empty?

          @in << chunk.b
          @remaining -= chunk.bytesize
        end
      end

      def byte
        fill(1)
        value = @in.getbyte(@pos) or raise Error, "snappy input ended inside an element"
        @pos += 1
        value
      end

      def le(count)
        fill(count)
        raise Error, "snappy input ended inside an element" if @in.bytesize - @pos < count

        value = 0
        count.times { |i| value |= @in.getbyte(@pos + i) << (8 * i) }
        @pos += count
        value
      end

      def read_varint
        value = 0
        shift = 0
        loop do
          b = byte
          value |= (b & 0x7f) << shift
          return value if b < 0x80

          shift += 7
          raise Error, "snappy preamble varint is too long" if shift > 35
        end
      end
    end
  end
end
