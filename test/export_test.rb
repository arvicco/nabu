# frozen_string_literal: true

require "test_helper"

# Nabu::Export (P121-1): the table registry — one explicit name => class
# map, so a further table (lemmas) registers with one file and one line.
class ExportTest < Minitest::Test
  def test_registry_names_the_shipped_tables
    assert_equal %w[documents links], Nabu::Export.names
    assert_equal Nabu::Export::Documents, Nabu::Export.table("documents")
    assert_equal Nabu::Export::Links, Nabu::Export.table("links")
  end

  def test_unknown_table_is_refused_naming_the_known_set
    error = assert_raises(Nabu::Export::Error) { Nabu::Export.table("lemmas") }
    assert_match(/unknown export table "lemmas"/, error.message)
    assert_match(/documents, links/, error.message)
  end

  # The registry contract every table honors — the frame relies on it.
  def test_every_registered_table_honors_the_contract
    Nabu::Export::TABLES.each do |name, klass|
      assert_equal name, klass::NAME
      refute_empty klass::SUMMARY.to_s
      %i[columns filters notes each_row].each do |verb|
        assert klass.method_defined?(verb), "#{klass} must define ##{verb}"
      end
    end
  end
end
