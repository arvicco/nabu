# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Adapters::StarlingDbfParser (P22-0): the hand-rolled dBase III table
# reader under the starling-dbf family — header, field descriptors, records,
# and StarLing's var-pointer convention (length-6 C cells whose descriptor
# byte 12 is "V" hold uint32-offset + uint16-length into the sibling .var).
# Fixtures are trimmed REAL upstream tables (test/fixtures/starling/README.md).
class StarlingDbfParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("starling")
  POKORNY = File.join(FIXTURES, "pokorny.dbf")
  PIET = File.join(FIXTURES, "piet.dbf")
  ALTET = File.join(FIXTURES, "altaic", "altet.dbf")
  STIBET = File.join(FIXTURES, "sintib", "stibet.dbf")

  def parser(path = POKORNY) = Nabu::Adapters::StarlingDbfParser.new(dbf_path: path)

  def test_reads_the_pokorny_field_roster
    assert_equal %w[NUMBER ROOT MEANING GER_MEAN GRAMMAR COMMENTS DERIVATIVE
                    MATERIAL REF SEEALSO PAGES PIET],
                 parser.fields.map(&:name)
  end

  def test_reads_the_piet_field_roster_with_the_branch_columns
    names = parser(PIET).fields.map(&:name)
    assert_equal %w[NUMBER PROTO PRNUM MEANING RUSMEAN REFERNUM HITT IND AVEST IRAN ARM
                    GREEK SLAV SLAVNUM BALT BALTNUM GERM GERMNUM LAT ITAL CELT ALB TOKH
                    REFER COMMENT], names
  end

  def test_var_pointer_cells_decode_and_empty_cells_are_nil
    records = parser.each_record.to_a
    assert_equal 3, records.size
    first = records.first
    assert_equal "1", first.fetch("NUMBER")
    assert_equal "ā", first.fetch("ROOT")
    assert_equal "interjection", first.fetch("MEANING")
    assert_nil first.fetch("GRAMMAR"), "a six-space cell is an empty field"
    assert_nil first.fetch("SEEALSO")
    assert_equal "0", first.fetch("PIET"), "numeric fields come back as trimmed strings"
  end

  def test_the_decoded_material_carries_the_greek_run_and_paragraph_breaks
    material = parser.each_record.to_a.first.fetch("MATERIAL")
    assert_includes material, "gr. ἆ Ausruf des Unwillens"
    assert_includes material, "\n", "\\x15 paragraph marks become newlines"
    assert material.unicode_normalized?(:nfc)
  end

  def test_numbers_and_crosslinks_across_all_fixture_records
    by_number = parser.each_record.to_h { |rec| [rec.fetch("NUMBER"), rec] }
    assert_equal %w[1 721 1089], by_number.keys
    assert_equal "1763", by_number.fetch("721").fetch("PIET")
    assert_equal "562", by_number.fetch("1089").fetch("PIET")
  end

  def test_each_record_without_a_block_returns_an_enumerator
    enum = parser.each_record
    assert_kind_of Enumerator, enum
    assert_equal 3, enum.count
  end

  def test_a_deleted_record_is_skipped
    Dir.mktmpdir do |dir|
      data = File.binread(POKORNY)
      hlen = data[8, 2].unpack1("v")
      data[hlen] = "*" # dBase deletion flag on the first (real) record
      File.binwrite(File.join(dir, "pokorny.dbf"), data)
      FileUtils.cp(File.join(FIXTURES, "pokorny.var"), dir)
      numbers = parser(File.join(dir, "pokorny.dbf")).each_record.map { |r| r.fetch("NUMBER") }
      assert_equal %w[721 1089], numbers
    end
  end

  def test_a_missing_var_file_raises_parse_error
    Dir.mktmpdir do |dir|
      FileUtils.cp(POKORNY, dir)
      error = assert_raises(Nabu::ParseError) { parser(File.join(dir, "pokorny.dbf")).each_record.to_a }
      assert_match(/\.var/, error.message)
    end
  end

  def test_a_var_pointer_past_the_end_of_the_var_file_raises_parse_error
    Dir.mktmpdir do |dir|
      FileUtils.cp(POKORNY, dir)
      File.binwrite(File.join(dir, "pokorny.var"), File.binread(File.join(FIXTURES, "pokorny.var"), 40))
      assert_raises(Nabu::ParseError) { parser(File.join(dir, "pokorny.dbf")).each_record.to_a }
    end
  end

  # P104-3, the first junk-pointer lane (censused: ONE cell in the eight
  # packages — altet #1728's TURC slot carries the literal whitespace bytes
  # \x0a\x20\x20\x0a\x0a\x20 where a var pointer belongs). Whitespace bytes
  # are not a pointer: the field reads empty, the record parses whole.
  def test_whitespace_junk_in_a_var_pointer_slot_reads_as_an_empty_field
    record = parser(ALTET).each_record.find { |r| r.fetch("NUMBER") == "1728" }
    refute_nil record, "the defect record itself parses"
    assert_nil record.fetch("TURC"), "the junk slot is an honest empty field"
    assert_equal "*pā̀ró ( ~ p`-, -ŕ-)", record.fetch("PROTO").strip, "the rest of the record decodes whole"
  end

  # P104-3, the second lane (censused: ONE record — stibet #2785, whose
  # seven pointers sit at 663142+ against the shipped 640,352-byte
  # stibet.var: upstream's var tail is truncated). A pointer ENTIRELY past
  # the var file decodes to the honest replacement character — marked,
  # never silently dropped, never a whole-base quarantine. A payload
  # RUNNING past from a valid offset keeps the torn-file raise (the test
  # above).
  def test_a_pointer_entirely_past_the_var_file_decodes_to_the_replacement_character
    record = parser(STIBET).each_record.find { |r| r.fetch("NUMBER") == "2785" }
    refute_nil record
    assert_equal "�", record.fetch("PROTO")
    assert_equal "�", record.fetch("COMMENTS")
  end

  def test_a_non_dbase_file_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      # the .var file itself is real upstream bytes but no dBase table
      Nabu::Adapters::StarlingDbfParser.new(dbf_path: File.join(FIXTURES, "pokorny.var")).fields
    end
    assert_match(/dBase/, error.message)
  end
end
