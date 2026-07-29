# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The CLDF nomenclature enforcement point (P50-W1): ID is ALWAYS the first
# column, every ID matches the CLDF identifier regex (a URN is NEVER an ID),
# the minter is deterministic and idempotent, and violations raise instead of
# publishing a malformed table.
class DataBuildCsvWriterTest < Minitest::Test
  WRITER = Nabu::DataBuild::CsvWriter

  def write(columns:, rows:)
    Dir.mktmpdir("nabu-csv") do |dir|
      path = File.join(dir, "table.csv")
      count = WRITER.write(path: path, columns: columns, rows: rows)
      return [count, CSV.read(path, encoding: Encoding::UTF_8)]
    end
  end

  def test_round_trip_in_column_order
    count, table = write(
      columns: %w[ID Language_ID Form],
      rows: [
        { "ID" => "a1", "Form" => "agniḥ", "Language_ID" => "san" }, # key order must not matter
        { "ID" => "a2", "Language_ID" => "san" } # missing cell => empty
      ]
    )
    assert_equal 2, count
    assert_equal %w[ID Language_ID Form], table.first
    assert_equal %w[a1 san agniḥ], table[1]
    assert_equal ["a2", "san", nil], table[2]
  end

  def test_id_must_be_the_first_column
    error = assert_raises(Nabu::ValidationError) do
      write(columns: %w[Form ID], rows: [])
    end
    assert_match(/ID.*first column/i, error.message)
  end

  def test_a_urn_is_never_an_id
    error = assert_raises(Nabu::ValidationError) do
      write(columns: %w[ID], rows: [{ "ID" => "urn:x" }])
    end
    assert_match(/urn:x/, error.message)
    assert_match(/mint/i, error.message, "the refusal should point at the minter")
  end

  def test_duplicate_ids_raise
    assert_raises(Nabu::ValidationError) do
      write(columns: %w[ID], rows: [{ "ID" => "a" }, { "ID" => "a" }])
    end
  end

  def test_unknown_row_keys_raise
    assert_raises(Nabu::ValidationError) do
      write(columns: %w[ID], rows: [{ "ID" => "a", "Fromm" => "typo" }])
    end
  end

  def test_mint_id_is_deterministic_and_folds_urn_punctuation
    minted = WRITER.mint_id("urn:cts:greekLit:tlg0012.tlg001", "1.1")
    assert_equal "urn-cts-greekLit-tlg0012-tlg001-1-1", minted
    assert_equal minted, WRITER.mint_id("urn:cts:greekLit:tlg0012.tlg001", "1.1")
    assert_match(WRITER::ID_PATTERN, minted)
  end

  def test_mint_id_raises_when_nothing_identifier_worthy_survives
    assert_raises(Nabu::ValidationError) { WRITER.mint_id("::") }
    assert_raises(Nabu::ValidationError) { WRITER.mint_id("") }
    assert_raises(Nabu::ValidationError) { WRITER.mint_id }
  end

  # The property test the packet asks for: over seeded random garbage
  # (identifier chars, URN punctuation, Greek, spaces), every minted ID is
  # regex-valid and re-minting the mint is a fixed point; refusals happen
  # only when the input carried nothing identifier-worthy.
  def test_property_minted_ids_are_regex_valid_and_idempotent
    rng = Random.new(50_401)
    charset = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a +
              ["-", "_", ":", ".", "/", " ", "'", "—", "·", "μ", "ῆ", "√", "́"]
    300.times do
      raw = Array.new(rng.rand(1..24)) { charset.sample(random: rng) }.join
      begin
        minted = WRITER.mint_id(raw)
      rescue Nabu::ValidationError
        refute_match(/[a-zA-Z0-9_]/, raw, "refused #{raw.inspect} though it carried identifier characters")
        next
      end
      assert_match(WRITER::ID_PATTERN, minted, "minted #{minted.inspect} from #{raw.inspect}")
      assert_equal minted, WRITER.mint_id(minted), "minting must be idempotent on its own output"
    end
  end
end
