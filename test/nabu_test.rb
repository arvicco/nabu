# frozen_string_literal: true

require "test_helper"
require "net/http"

class NabuTest < Minitest::Test
  def test_version_is_defined_and_well_formed
    refute_nil Nabu::VERSION
    assert_match(/\A\d+\.\d+\.\d+\z/, Nabu::VERSION)
  end

  def test_http_attempts_are_blocked
    assert_raises(WebMock::NetConnectNotAllowedError) do
      Net::HTTP.get(URI("http://example.com"))
    end
  end
end
