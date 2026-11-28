# frozen_string_literal: true

require "strscan"

module Nabu
  # An incremental splitter for a JSON document whose top level is ONE array
  # of objects/arrays — the shape of a single-line pandas/records dump (the
  # 465 MB EDCS deposit is one line). It never parses the document: it reads
  # the file in chunks and yields each top-level element's byte [offset,
  # length], so a caller can index a dump in one streaming pass and later
  # read exactly one element back (File.binread(path, length, offset)) for a
  # per-element JSON.parse. Memory is bounded by the chunk size plus the
  # longest string literal.
  #
  # The scan is a small state machine over the structural bytes only: a
  # single regex skip consumes runs of non-structural bytes and COMPLETE
  # string literals (escapes included), so brackets and quotes inside
  # strings never count. A string cut by a chunk boundary is simply re-read
  # once the next chunk arrives. Strict on shape: anything but whitespace
  # before the opening "[", a scalar element at the top level, a truncated
  # file, or bytes after the closing "]" raise Error — a damaged dump is a
  # loud failure, never a silent short read.
  class JsonArraySplitter
    class Error < Nabu::Error; end

    # const: read size per IO call; any value works (the suite pins chunk
    # sizes down to one byte), larger is faster.
    CHUNK_SIZE = 4 * 1024 * 1024

    # Inside an element: runs of non-structural bytes and complete strings.
    INNER_SKIP = /(?:[^"{}\[\]]+|"(?>[^"\\]+|\\[\s\S])*")*/n
    # Between top-level elements (and around the array): whitespace and the
    # separating commas only.
    OUTER_SKIP = /[\s,]*/n
    LEADING = /\s*/n
    SKIPS = [LEADING, OUTER_SKIP, INNER_SKIP].freeze

    def initialize(path, chunk_size: CHUNK_SIZE)
      @path = path
      @chunk_size = chunk_size
    end

    # Yields [offset, length] per top-level element, in file order.
    def each(&block)
      return enum_for(:each) unless block

      File.open(@path, "rb") { |io| scan(io, &block) }
    end

    private

    def scan(io)
      buffer = +"".b
      base = 0 # file offset of buffer[0]
      depth = 0
      start = nil
      closed = false
      eof = false
      until eof && buffer.empty?
        chunk = io.read(@chunk_size)
        eof = chunk.nil?
        buffer << chunk unless eof
        scanner = StringScanner.new(buffer)
        loop do
          if closed
            scanner.skip(LEADING)
            raise Error, "#{@path}: bytes after the closing ] of the top-level array" unless scanner.eos?

            break
          end
          scanner.skip(SKIPS.fetch(depth.clamp(0, 2)))
          break if scanner.eos?

          byte = scanner.peek(1)
          if depth.zero?
            raise Error, "#{@path}: not a top-level array (starts with #{byte.inspect})" unless byte == "["

            depth = 1
          elsif depth == 1
            if byte == "]"
              closed = true
            elsif ["{", "["].include?(byte)
              start = base + scanner.pos
              depth = 2
            else
              raise Error, "#{@path}: top-level element at byte #{base + scanner.pos} is not an object or array"
            end
          else
            case byte
            when "\"" then break # a string literal the buffer cuts — wait for more bytes
            when "{", "[" then depth += 1
            else
              depth -= 1
              yield start, base + scanner.pos + 1 - start if depth == 1
            end
          end
          scanner.pos += 1
        end
        consumed = scanner.pos
        buffer = buffer.byteslice(consumed..) || +"".b
        base += consumed
        next unless eof
        raise Error, "#{@path}: truncated — the top-level array never closes" unless closed

        buffer.clear
      end
    end
  end
end
