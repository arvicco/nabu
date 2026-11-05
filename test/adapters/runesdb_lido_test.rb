# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Adapters::RunesdbLido (P160): the per-find LIDO record reader. The
# field map is pinned through the adapter (runesdb_test.rb); this file
# holds the reader's edge rules, exercised on the real fixture records
# (test/fixtures/runesdb/lido/) with single values mutated in a tmp copy.
class RunesdbLidoTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("runesdb")
  Lido = Nabu::Adapters::RunesdbLido

  def real(id = 629) = File.read(File.join(FIXTURES, "lido", "#{id}.xml"))

  def read_mutated(body)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "629.xml")
      File.write(path, body)
      Lido.read(path, find_id: "629")
    end
  end

  def test_the_zero_year_sentinel_and_empty_marks_mint_no_bound
    zero = real.sub("<lido:earliestDate>700</lido:earliestDate>", "<lido:earliestDate>0</lido:earliestDate>")
               .sub("<lido:latestDate>900</lido:latestDate>", "<lido:latestDate>0</lido:latestDate>")
    refute read_mutated(zero).key?("date"), "Kylver/Rö carry 0/0 — no year 0 in the house model"
    open = real.sub("<lido:latestDate>900</lido:latestDate>", "<lido:latestDate>-</lido:latestDate>")
    assert_equal({ "not_before" => 700, "raw" => "700" }, read_mutated(open)["date"])
  end

  def test_a_reversed_pair_swaps_with_the_raw_verbatim
    reversed = real.sub("<lido:earliestDate>700</lido:earliestDate>", "<lido:earliestDate>950</lido:earliestDate>")
    assert_equal({ "not_before" => 900, "not_after" => 950, "raw" => "950–900" }, read_mutated(reversed)["date"])
  end

  def test_a_non_year_value_rides_raw_only
    prose = real.sub("<lido:earliestDate>700</lido:earliestDate>", "<lido:earliestDate>8. Jh.</lido:earliestDate>")
    assert_equal({ "not_after" => 900, "raw" => "8. Jh.–900" }, read_mutated(prose)["date"])
  end

  def test_a_misfiled_record_is_a_parse_error
    error = assert_raises(Nabu::ParseError) do
      Lido.read(File.join(FIXTURES, "lido", "629.xml"), find_id: "720")
    end
    assert_match(/recordID "629" is not find 720/, error.message)
  end

  def test_a_truncated_record_is_a_parse_error
    assert_raises(Nabu::ParseError) { read_mutated(real[0, 4000]) }
  end

  def test_the_serving_timestamp_is_never_read
    stamped = real.sub("</lido:recordWrap>",
                       "<lido:recordInfoSet><lido:recordMetadataDate>2026-01-01T00:00:00" \
                       "</lido:recordMetadataDate></lido:recordInfoSet></lido:recordWrap>")
    assert_equal Lido.read(File.join(FIXTURES, "lido", "629.xml"), find_id: "629"), read_mutated(stamped),
                 "a re-served record (restamped on every GET) mines identically"
  end
end
