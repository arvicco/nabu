# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Xlsx (P77-r6, №R-30) — the minimal in-house xlsx sheet reader:
# zip + XML, shared strings resolved, sparse rows padded with nils by
# column position. Deliberately dumb: strings out, no types, no styles,
# no formulas — exactly what reading a works TABLE needs and nothing
# an office suite needs. Fixtures: the OSTA tables trimmed to the
# fixture abbrevs (structure + sharedStrings verbatim).
class XlsxTest < Minitest::Test
  OBRAS = File.join(Nabu::TestSupport.fixtures("osta"), "tables", "tabla-obras.xlsx")
  CODICES = File.join(Nabu::TestSupport.fixtures("osta"), "tables", "tabla-codices.xlsx")

  def test_rows_reads_the_first_sheet_by_default
    rows = Nabu::Xlsx.rows(OBRAS)
    assert_equal "Abreviaturas HSMS", rows.first[0]
    assert_equal "BETA manid", rows.first[1]
    assert_equal 28, rows.size,
                 "header + the 27 kept work rows (PN2 is a cancionero: 17 works in one codex)"
  end

  def test_shared_strings_and_inline_numbers_both_resolve_to_strings
    rows = Nabu::Xlsx.rows(OBRAS)
    rhj = rows.find { |r| r[0] == "RHJ" }
    refute_nil rhj
    assert_equal "HSMS-0198", rhj[3], "a shared-string cell"
    assert_match(/\A\d+\z/, rhj[1], "a numeric cell (BETA manid) comes back as its string form")
  end

  def test_sparse_rows_pad_skipped_columns_with_nil
    rows = Nabu::Xlsx.rows(OBRAS)
    rhj = rows.find { |r| r[0] == "RHJ" }
    # Column H (Traductor, index 7) is absent in the RHJ row — the pad
    # keeps every later column at its header position.
    assert_nil rhj[7]
    assert_equal "castellano", rhj[12], "lengua 1 stays at its header index"
  end

  def test_rows_reads_a_named_sheet
    rows = Nabu::Xlsx.rows(OBRAS, sheet: "en elaboración")
    assert_equal 1, rows.size, "the fixture trims every non-data sheet to its header row"
  end

  def test_unknown_sheet_and_unreadable_file_raise_nabu_errors
    assert_raises(Nabu::Xlsx::Error) { Nabu::Xlsx.rows(OBRAS, sheet: "no such sheet") }
    Dir.mktmpdir do |dir|
      bogus = File.join(dir, "not-a-zip.xlsx")
      File.write(bogus, "plain text")
      assert_raises(Nabu::Xlsx::Error) { Nabu::Xlsx.rows(bogus) }
    end
  end

  def test_codices_table_reads_with_the_same_contract
    rows = Nabu::Xlsx.rows(CODICES)
    assert_equal "HSMS ID", rows.first[0]
    fjz = rows.find { |r| r[1] == "FJZ" }
    refute_nil fjz
    assert_equal "Nueva York: Hispanic Society of America", fjz[4]
  end
end
