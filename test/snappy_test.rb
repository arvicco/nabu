# frozen_string_literal: true

require "test_helper"
require "stringio"
require "nabu/snappy"

# Nabu::Snappy — the raw-block streaming decoder. The element vectors are
# built from the format description (google/snappy format_description.txt);
# real encoder output is exercised through the parquet fixtures
# (test/parquet_test.rb: fastparquet's cramjam and parquet-cpp's snappy).
class SnappyTest < Minitest::Test
  S = Nabu::Snappy

  def block(length, *elements) = [varint(length), *elements].join.b

  def varint(value)
    out = +""
    loop do
      byte = value & 0x7f
      value >>= 7
      out << (value.zero? ? byte : byte | 0x80).chr
      return out if value.zero?
    end
  end

  def literal(text)
    n = text.bytesize - 1
    n < 60 ? [n << 2].pack("C") + text : [60 << 2, n].pack("CC") + text
  end

  def copy1(length, offset) = [((offset >> 8) << 5) | ((length - 4) << 2) | 1, offset & 0xff].pack("CC")
  def copy2(length, offset) = [((length - 1) << 2) | 2, offset].pack("Cv")
  def copy4(length, offset) = [((length - 1) << 2) | 3, offset].pack("CV")

  def test_literals_and_each_copy_width
    data = block(17, literal("abcd"), copy1(4, 4), copy2(5, 8), copy4(4, 13))
    assert_equal "abcdabcdabcdaabcd", S.inflate(data)
  end

  def test_an_overlapping_copy_repeats_its_pattern
    assert_equal "ab#{'ab' * 5}", S.inflate(block(12, literal("ab"), copy1(10, 2)))
  end

  def test_a_long_literal_carries_its_length_in_a_following_byte
    text = "x" * 100
    assert_equal text, S.inflate(block(100, literal(text)))
  end

  def test_the_declared_length_is_enforced
    error = assert_raises(S::Error) { S.inflate(block(9, literal("abcd"))) }
    assert_match(/declared 9 bytes, decoded 4/, error.message)
  end

  def test_a_copy_past_the_output_raises
    assert_raises(S::Error) { S.inflate(block(8, literal("ab"), copy1(6, 3))) }
  end

  def test_streaming_flushes_all_but_the_window_and_the_chunks_reassemble
    data = block(28, literal("abcdefgh"), copy1(8, 8), literal("ijkl"), copy1(8, 4))
    chunks = []
    S.each_chunk(StringIO.new(data), data.bytesize, window: 8, flush: 4) { |chunk| chunks << chunk }
    assert_operator chunks.size, :>, 1, "an 8-byte window flushes as output grows"
    assert_equal "abcdefghabcdefghijklijklijkl", chunks.join
  end

  def test_a_copy_reaching_past_the_kept_window_raises_instead_of_guessing
    data = block(24, literal("abcdefgh"), literal("ijklmnop"), copy2(8, 16))
    error = assert_raises(S::Error) do
      S.each_chunk(StringIO.new(data), data.bytesize, window: 4, flush: 4) { |_| nil }
    end
    assert_match(/past the .*window/, error.message)
  end

  def test_truncated_input_raises
    data = block(8, literal("abcdefgh"))
    assert_raises(S::Error) { S.each_chunk(StringIO.new(data[0, 5]), data.bytesize) { |_| nil } }
  end
end
