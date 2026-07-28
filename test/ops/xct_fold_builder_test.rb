# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

module Ops
  # Nabu::Ops::XctFoldBuilder (P50-W3): the generator behind lib/nabu/xct.rb,
  # reading the SAME authored rule table (config/ewts/rules.csv) the
  # xct/wylie-fold dataset builder publishes — one source of truth, two
  # consumers. Dev-time ops code, no network.
  class XctFoldBuilderTest < Minitest::Test
    def builder
      @builder ||= Nabu::Ops::XctFoldBuilder.new(rules_path: Nabu::Ops::XctFoldBuilder::RULES_PATH)
    end

    def test_regeneration_is_byte_stable_against_the_committed_module
      committed = File.read(File.join(Nabu::Config::PROJECT_ROOT, "lib", "nabu", "xct.rb"))
      assert_equal committed, builder.render,
                   "lib/nabu/xct.rb is stale — regenerate with `rake fold:xct` and commit the result"
    end

    def test_render_carries_no_timestamp
      refute_match(/\b20\d\d-\d\d-\d\d\b/, builder.render,
                   "the generated module must be byte-stable across days — no generation date")
    end

    def test_rows_expose_the_validated_table_for_the_dataset_builder
      rows = builder.rows
      assert_operator rows.size, :>=, 90
      assert_equal %w[ID Tibetan EWTS Kind Codepoints Comment], rows.first.keys
      rows.each do |row|
        assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, row["ID"]
        tibetan = row["Tibetan"]
        assert_equal 1, tibetan.chars.size, "#{row['ID']}: one NFC codepoint per rule"
        assert_equal tibetan, tibetan.unicode_normalize(:nfc)
        assert_equal format("U+%04X", tibetan.ord), row["Codepoints"],
                     "#{row['ID']}: Codepoints must name the Tibetan form's codepoint"
      end
      assert_equal rows.size, rows.map { |row| row["Tibetan"] }.uniq.size, "no duplicate Tibetan forms"
      assert_equal rows.size, rows.map { |row| row["ID"] }.uniq.size, "no duplicate IDs"
    end

    def test_every_rule_round_trips_into_the_generated_tables
      lookup = {
        "consonant" => Nabu::Xct::CONSONANTS, "subjoined" => Nabu::Xct::SUBJOINED,
        "vowel" => Nabu::Xct::VOWELS, "mark" => Nabu::Xct::MARKS,
        "punctuation" => Nabu::Xct::OTHERS, "digit" => Nabu::Xct::OTHERS
      }
      builder.rows.each do |row|
        table = lookup.fetch(row["Kind"])
        assert_equal row["EWTS"], table[row["Tibetan"]],
                     "#{row['ID']}: the generated module must carry the CSV's mapping verbatim"
      end
      total = Nabu::Xct::CONSONANTS.size + Nabu::Xct::SUBJOINED.size + Nabu::Xct::VOWELS.size +
              Nabu::Xct::MARKS.size + Nabu::Xct::OTHERS.size
      assert_equal builder.rows.size, total, "the module must carry exactly the CSV's rules, nothing else"
    end

    def test_refuses_duplicate_tibetan_forms
      error = assert_raises(Nabu::ValidationError) { rigged_builder { |rows| rows << rows[1].dup } }
      assert_match(/duplicate/, error.message)
    end

    def test_refuses_a_codepoints_column_that_contradicts_the_tibetan_form
      error = assert_raises(Nabu::ValidationError) do
        rigged_builder { |rows| rows[1][4] = "U+0F00" }
      end
      assert_match(/U\+0F00/, error.message)
    end

    def test_refuses_an_unknown_kind
      error = assert_raises(Nabu::ValidationError) { rigged_builder { |rows| rows[1][3] = "letter" } }
      assert_match(/kind/i, error.message)
    end

    private

    # Re-write the real rules with one rigged mutation and build from that.
    def rigged_builder
      rows = CSV.read(Nabu::Ops::XctFoldBuilder::RULES_PATH)
      header = rows.shift
      yield rows
      Dir.mktmpdir do |dir|
        path = File.join(dir, "rules.csv")
        CSV.open(path, "w") do |csv|
          csv << header
          rows.each { |row| csv << row }
        end
        return Nabu::Ops::XctFoldBuilder.new(rules_path: path)
      end
    end
  end
end
