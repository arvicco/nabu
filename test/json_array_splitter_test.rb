# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

# Nabu::JsonArraySplitter: the incremental top-level-array splitter that
# lets a single-line JSON dump of hundreds of MB (the EDCS deposit) be
# walked element by element — byte offsets and lengths, never a whole-file
# JSON.parse.
class JsonArraySplitterTest < Minitest::Test
  def with_file(content)
    Dir.mktmpdir("json-array-splitter") do |dir|
      path = File.join(dir, "dump.json")
      File.binwrite(path, content)
      yield path
    end
  end

  def slices(content, chunk_size: Nabu::JsonArraySplitter::CHUNK_SIZE)
    with_file(content) do |path|
      Nabu::JsonArraySplitter.new(path, chunk_size: chunk_size).each.map do |offset, length|
        File.binread(path, length, offset)
      end
    end
  end

  def test_yields_each_top_level_object_by_offset_and_length
    elements = [{ "a" => 1 }, { "b" => [1, { "c" => "}" }] }, { "d" => {} }]
    assert_equal(elements, slices(JSON.generate(elements)).map { |slice| JSON.parse(slice) })
  end

  def test_brackets_and_escaped_quotes_inside_strings_never_split
    content = '[{"t":"a } ] { [ \\" ,"},{"u":"\\\\"},{"v":"\\\\\\"}"}]'
    parsed = slices(content).map { |slice| JSON.parse(slice) }
    assert_equal [{ "t" => 'a } ] { [ " ,' }, { "u" => "\\" }, { "v" => '\\"}' }], parsed
  end

  def test_chunk_boundaries_anywhere_give_the_same_slices
    elements = [{ "id" => "EDCS-1", "text" => "Δέκιος // D(ecimi) \\ \"x\" }{" }, { "id" => "EDCS-2", "e" => {} },
                ["nested", ["array"]]]
    content = "  \n#{JSON.pretty_generate(elements)}\n"
    expected = slices(content)
    assert_equal 3, expected.size
    (1..12).each do |chunk_size|
      assert_equal expected, slices(content, chunk_size: chunk_size), "chunk size #{chunk_size}"
    end
  end

  def test_multibyte_text_offsets_are_byte_offsets
    content = '[{"g":"Λείβιος"},{"l":"salve"}]'
    with_file(content) do |path|
      offsets = Nabu::JsonArraySplitter.new(path).each.to_a
      assert_equal [[1, 22], [24, 13]], offsets, "Λείβιος is 7 letters, 14 bytes"
    end
  end

  def test_an_empty_array_yields_nothing
    assert_empty slices("[ ]")
  end

  def test_a_non_array_document_raises
    error = assert_raises(Nabu::JsonArraySplitter::Error) { slices('{"a":1}') }
    assert_match(/top-level array/, error.message)
  end

  def test_a_scalar_top_level_element_raises
    assert_raises(Nabu::JsonArraySplitter::Error) { slices('[{"a":1},"stray"]') }
  end

  def test_a_truncated_dump_raises
    error = assert_raises(Nabu::JsonArraySplitter::Error) { slices('[{"a":1},{"b":"unterminated') }
    assert_match(/truncated/, error.message)
    assert_raises(Nabu::JsonArraySplitter::Error) { slices('[{"a":1},{"b":2}') }
  end

  def test_trailing_bytes_after_the_array_raise
    assert_raises(Nabu::JsonArraySplitter::Error) { slices('[{"a":1}] {"b":2}') }
  end

  def test_each_without_a_block_is_an_enumerator
    with_file('[{"a":1}]') do |path|
      assert_kind_of Enumerator, Nabu::JsonArraySplitter.new(path).each
    end
  end
end
