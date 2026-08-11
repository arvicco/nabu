# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The egy/unikemet-signs builder (P73-9 rider): the Egyptian sign spine —
# one row per Unikemet codepoint with Gardiner-style catalog code,
# description, functions, values, and the JSesh/Hieroglyphica/IFAO
# concordances, verbatim from the Unicode data file.
class UnikemetSignsBuilderTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("unikemet"), "Unikemet.txt")

  def build!(root)
    canonical = File.join(root, "canonical")
    FileUtils.mkdir_p(File.join(canonical, "unikemet"))
    FileUtils.cp(FIXTURE, File.join(canonical, "unikemet", "Unikemet.txt"))
    out = File.join(root, "out")
    FileUtils.mkdir_p(out)
    [Nabu::DataBuild::UnikemetSignsBuilder.new(canonical_dir: canonical)
                                          .build(catalog: nil, out_dir: out), out]
  end

  def test_one_row_per_codepoint_with_the_concordances
    Dir.mktmpdir do |root|
      result, out = build!(root)
      table = CSV.read(File.join(out, "unikemet-signs.csv"), headers: true)
      assert_equal %w[ID Codepoint Glyph Gardiner UniK Core Description Functions Values
                      JSesh Hieroglyphica IFAO Source].join(","),
                   table.headers.join(",")
      assert_equal 6, table.size, "one row per fixture codepoint"

      horus = table.find { |row| row["Codepoint"] == "U+13143" }
      assert_equal %w[U13143 𓅃 G-12-002 G005 C G5 ḥr],
                   horus.values_at("ID", "Glyph", "Gardiner", "UniK", "Core", "JSesh", "Values"),
                   "the falcon carries its catalog code and concordances verbatim"
      assert_equal "Logogram (Horus)", horus["Functions"]
      assert_equal 6, result.resources.first.rows
    end
  end

  def test_a_missing_cone_refuses_with_a_sync_hint
    Dir.mktmpdir do |root|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::UnikemetSignsBuilder.new(canonical_dir: File.join(root, "nope"))
                                             .build(catalog: nil, out_dir: root)
      end
      assert_match(/sync/, error.message)
    end
  end
end
