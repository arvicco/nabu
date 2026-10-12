# frozen_string_literal: true

require "test_helper"

# Nabu::Query::DateBasis (P122-1): the closed date-class vocabulary behind
# `search --date-basis` — parse, normalize, refuse unknowns naming the set.
class QueryDateBasisTest < Minitest::Test
  def test_known_set_is_the_stored_vocabulary
    assert_equal %w[artifact composition edition], Nabu::Query::DateBasis::KNOWN
  end

  def test_absent_value_is_no_filter
    assert_nil Nabu::Query::DateBasis.parse(nil)
  end

  def test_comma_list_parses_sorted_and_deduplicated
    assert_equal %w[artifact composition], Nabu::Query::DateBasis.parse(" Composition, artifact,composition ")
    assert_equal %w[edition], Nabu::Query::DateBasis.parse(%w[edition])
  end

  def test_unknown_class_is_refused_naming_the_known_set
    error = assert_raises(Nabu::Error) { Nabu::Query::DateBasis.parse("artifact,model") }
    assert_match(/unknown date basis "model"/, error.message)
    assert_match(/choose from artifact, composition, edition/, error.message)
  end

  def test_empty_list_is_refused
    assert_raises(Nabu::Error) { Nabu::Query::DateBasis.parse(" , ") }
  end
end
