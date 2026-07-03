# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test
  def test_base_error_is_a_standard_error
    assert_operator Nabu::Error, :<, StandardError
  end

  def test_parse_error_is_rescuable_as_nabu_error
    assert_operator Nabu::ParseError, :<, Nabu::Error
    caught = assert_raises(Nabu::Error) { raise Nabu::ParseError, "bad TEI" }
    assert_equal "bad TEI", caught.message
  end

  def test_fetch_error_is_rescuable_as_nabu_error
    assert_operator Nabu::FetchError, :<, Nabu::Error
    caught = assert_raises(Nabu::Error) { raise Nabu::FetchError, "upstream down" }
    assert_equal "upstream down", caught.message
  end

  def test_validation_error_is_rescuable_as_nabu_error
    assert_operator Nabu::ValidationError, :<, Nabu::Error
    caught = assert_raises(Nabu::Error) { raise Nabu::ValidationError, "urn must not be empty" }
    assert_equal "urn must not be empty", caught.message
  end

  def test_shell_error_is_rescuable_as_nabu_error
    assert_operator Nabu::Shell::Error, :<, Nabu::Error
    assert_raises(Nabu::Error) { raise Nabu::Shell::Error.new("boom", status: 1, stderr: "") }
  end
end
