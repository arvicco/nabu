# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# Every dataset ships languages.csv (P50-W1): CLDF columns, ID = Nabu's
# language code, statics straight from the Feature's Language value.
class DataBuildLanguagesTableTest < Minitest::Test
  def test_writes_the_cldf_language_table
    Dir.mktmpdir("nabu-languages") do |dir|
      count = Nabu::DataBuild::LanguagesTable.write(
        dir: dir, languages: [Nabu::DataBuild::LANGUAGES.fetch("san")]
      )
      table = CSV.read(File.join(dir, "languages.csv"), encoding: Encoding::UTF_8)
      assert_equal 1, count
      assert_equal %w[ID Name Glottocode ISO639P3code], table.first
      assert_equal %w[san Sanskrit sans1269 san], table[1]
    end
  end

  def test_resource_entry_is_tabular_with_id_primary_key
    resource = Nabu::DataBuild::LanguagesTable.resource(count: 2)
    assert_equal "languages", resource.name
    assert_equal "languages.csv", resource.path
    assert_equal 2, resource.rows
    assert_equal ["ID"], resource.primary_key
    assert_equal(%w[ID Name Glottocode ISO639P3code], resource.fields.map { |field| field[:name] })
  end
end
