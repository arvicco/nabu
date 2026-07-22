# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

# RundataSqliteParser (P40-6): the read-only reader over the SRDB SQLite
# artifact Rundata-net ships (runes.<hash>.sqlite3). Exercised against the
# schema-preserving 4-inscription trim of the REAL 45 MB browser artifact
# (test/fixtures/rundata/runes-trim.sqlite3 — full DDL incl. views); the
# per-inscription JSON API fixtures in the same dir document/cross-check the
# expected field values.
class RundataSqliteParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("rundata")
  TRIM = File.join(FIXTURES, "runes-trim.sqlite3")

  def parser
    Nabu::Adapters::RundataSqliteParser.new(TRIM)
  end

  # --- census -----------------------------------------------------------------

  def test_census_yields_every_inscription_with_meta_ordered_by_signum
    census = parser.each_inscription.to_a
    assert_equal ["DR 42", "N KJ101", "U 344", "Ög 136"], census.map(&:signum)
    assert_equal [3824, 6473, 1997, 327], census.map(&:signature_id)
  end

  def test_census_reports_the_present_lanes_honestly
    lanes = parser.each_inscription.to_h { |ins| [ins.signum, ins.lanes] }
    # All four carry run/fvn/rsv/eng; swe exists only for U 344 and Ög 136
    # (matches the JSON API fixtures — DR 42 and N KJ101 have no Swedish
    # translation).
    assert_equal %w[run fvn rsv eng swe], lanes.fetch("U 344")
    assert_equal %w[run fvn rsv eng swe], lanes.fetch("Ög 136")
    assert_equal %w[run fvn rsv eng], lanes.fetch("DR 42")
    assert_equal %w[run fvn rsv eng], lanes.fetch("N KJ101")
  end

  def test_a_blank_lane_value_is_absent_not_present
    Dir.mktmpdir do |dir|
      doctored = File.join(dir, "runes-doctored.sqlite3")
      FileUtils.cp(TRIM, doctored)
      db = SQLite3::Database.new(doctored)
      db.execute("UPDATE translation_english SET value = '  ' WHERE signature_id = 1997")
      db.close
      lanes = Nabu::Adapters::RundataSqliteParser.new(doctored)
                                                 .each_inscription.to_h { |ins| [ins.signum, ins.lanes] }
      assert_equal %w[run fvn rsv swe], lanes.fetch("U 344"),
                   "a whitespace-only lane row is an honest absence, never an empty document"
    end
  end

  # --- record -----------------------------------------------------------------

  def test_record_carries_the_five_lanes_verbatim
    record = parser.record(1997)
    assert_equal "U 344", record.signum
    assert_equal "in ulfr hafiR o| |onklati ' þru kialt| |takat þit uas fursta þis " \
                 "tusti ka-t ' þ(a) ---- (þ)urktil ' þa kalt knutr",
                 record.lanes.fetch("run"),
                 "the transliteration notation (|, ', (a), ----, -) IS content — verbatim"
    assert_equal "And Ulfr has taken three payments in England. That was the first that " \
                 "Tosti paid. Then Þorketill paid. Then Knútr paid.",
                 record.lanes.fetch("eng")
    assert record.lanes.fetch("fvn").start_with?("En \"Ulfr hefir á \"Englandi"),
           "the name-prefix double quote is upstream notation, kept"
    assert record.lanes.fetch("rsv").start_with?("En \"UlfR hafiR a \"Ænglandi")
    assert record.lanes.key?("swe")
  end

  def test_record_meta_fields_verbatim
    meta = parser.record(1997).meta
    assert_equal "Yttergärde", meta.fetch("found_location")
    assert_equal "Orkesta sn", meta.fetch("parish")
    assert_equal "Seminghundra hd", meta.fetch("district")
    assert_equal "Vallentuna", meta.fetch("municipality")
    assert_equal "V", meta.fetch("dating")
    assert_equal 725, meta.fetch("year_from")
    assert_equal 1100, meta.fetch("year_to")
    assert_equal "Pr 3", meta.fetch("style"), "the upstream NBSP in Gräslund style codes is data"
    assert_equal "Åsmund (A)", meta.fetch("carver")
    assert_equal "granit", meta.fetch("material")
    assert_equal "runsten", meta.fetch("objectInfo")
    assert_in_delta 59.604644, meta.fetch("latitude")
    assert_in_delta 18.109098, meta.fetch("longitude")
    assert_in_delta 59.604637, meta.fetch("present_latitude")
    assert_in_delta 18.109983, meta.fetch("present_longitude")
    assert_equal 0, meta.fetch("lost")
    assert_equal 0, meta.fetch("recent")
  end

  def test_record_resolves_the_material_type_join
    assert_equal "stone", parser.record(1997).material_type
    assert_equal "stone", parser.record(6473).material_type
  end

  def test_record_aliases_references_and_crosses_are_empty_in_the_trim
    # The trim keeps only the four ROOT signature rows and zero
    # meta_information_references/crosses rows (manifest.yml); the JSON API
    # fixtures document that aliases (Ög 136 → B 913/L 2028) and references
    # exist upstream. The reader returns honest empties here.
    record = parser.record(327)
    assert_equal [], record.aliases
    assert_equal [], record.references
    assert_nil record.crosses
  end

  def test_record_reads_aliases_from_child_signatures
    Dir.mktmpdir do |dir|
      doctored = File.join(dir, "runes-doctored.sqlite3")
      FileUtils.cp(TRIM, doctored)
      db = SQLite3::Database.new(doctored)
      db.execute("INSERT INTO signatures (signature_text, parent_id) VALUES ('B 913', 327)")
      db.execute("INSERT INTO signatures (signature_text, parent_id) VALUES ('L 2028', 327)")
      db.close
      record = Nabu::Adapters::RundataSqliteParser.new(doctored).record(327)
      assert_equal ["B 913", "L 2028"], record.aliases
    end
  end

  def test_unknown_signature_id_returns_nil
    assert_nil parser.record(999_999)
  end

  def test_a_corrupt_artifact_raises_parse_error_naming_the_file
    Dir.mktmpdir do |dir|
      bad = File.join(dir, "runes-bad.sqlite3")
      File.write(bad, "this is not a sqlite database, honest")
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::RundataSqliteParser.new(bad).each_inscription.to_a
      end
      assert_match(/runes-bad\.sqlite3/, error.message)
    end
  end

  def test_the_reader_opens_the_artifact_read_only
    # readonly: true at open — a write through the reader's own handle must
    # be impossible (the canonical artifact is a permanent asset; CLAUDE.md
    # ground rules). The handle is an implementation detail, so the pin
    # peeks the ivar rather than growing a test-only API.
    reader = parser
    reader.each_inscription.first # force the connection open
    handle = reader.instance_variable_get(:@db)
    assert_raises(SQLite3::ReadOnlyException) do
      handle.execute("UPDATE meta_information SET dating = 'X'")
    end
  end
end
