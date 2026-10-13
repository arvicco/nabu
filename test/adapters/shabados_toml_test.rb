# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::ShabadosToml (P122-3) — the strict TOML-subset reader of
# the shabados-toml family. Real records from test/fixtures/shabados plus
# minimal strings for the escape and refusal edges.
class ShabadosTomlTest < Minitest::Test
  TOML = Nabu::Adapters::ShabadosToml
  ROOT = File.join(Nabu::TestSupport.fixtures("shabados"), "database", "collections")

  def read(rel) = TOML.parse(File.read(File.join(ROOT, rel), encoding: "UTF-8"), path: rel)

  def test_a_line_record_reads_its_array_of_tables
    record = read("lines/P/PX/PXES.toml")
    content = record.fetch("content")
    assert_equal 2, content.size
    assert_equal({ "assets" => ["DGDG"], "type" => "primary", "data" => "ੴ ਸਤਿਗੁਰ ਪ੍ਰਸਾਦਿ ॥",
                   "page" => 1, "line" => 1 }, content.first)
    assert_equal ["DDTK"], content.last["assets"]
  end

  def test_a_source_record_reads_arrays_and_nested_tables
    record = read("sources/SGGS.toml")
    assert_equal ["1DSA"], record["sections"]
    assert_equal "gurū granth sāhib", record.dig("name", "Latn")
    assert_equal "ਗੁਰੂ ਗ੍ਰੰਥ ਸਾਹਿਬ", record.dig("name", "Guru")
    assert_equal "Guru Granth Sahib", record.dig("translation", "en")
  end

  def test_an_asset_record_reads_dotted_tables_and_an_array_of_tables_under_one
    record = read("assets/DDTK.toml")
    assert_equal "Sundar Gutka Damdami Taksal", record.dig("name", "en")
    assert_equal "Mallewal", record.dig("reference", "authors", 0, "last")
  end

  def test_escapes_literals_and_integers
    text = <<~TOML
      a = "say \\"ਹਾਂ\\" \\\\ ok\\n"
      b = 'raw \\n'
      c = -12
      d = []
      e = [ "x", "y\\"z" ]
      f = "\\u0A13"
    TOML
    parsed = TOML.parse(text, path: "x.toml")
    assert_equal "say \"ਹਾਂ\" \\ ok\n", parsed["a"]
    assert_equal "raw \\n", parsed["b"], "a literal string keeps its backslash"
    assert_equal(-12, parsed["c"])
    assert_equal [], parsed["d"]
    assert_equal ["x", "y\"z"], parsed["e"]
    assert_equal "ਓ", parsed["f"]
  end

  def test_unclassified_shapes_are_refused_never_guessed
    ["a = 1.5", "a = true", "a = { b = 1 }", "a = \"unterminated", "a = \"bad \\q\"", "a = [ 1, 2 ]",
     "not toml at all"].each do |line|
      error = assert_raises(Nabu::ParseError, line) { TOML.parse("#{line}\n", path: "x.toml") }
      assert_match(/x\.toml:1:/, error.message)
    end
    assert_raises(Nabu::ParseError) { TOML.parse("a = 1\na = 2\n", path: "x.toml") }
  end
end
