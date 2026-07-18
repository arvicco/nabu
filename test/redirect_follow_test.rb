# frozen_string_literal: true

require "test_helper"

# Nabu::RedirectFollow: the ONE bounded redirect-follow loop behind every
# plain-HTTP fetch arm (UrlDownload, ZipFetch, FileFetch). The consumer test
# files pin the full per-caller matrices (loop cap, missing Location,
# conditional flows); this file pins the helper's own contract — headers
# riding every hop, the accept list, the caller's error class. No network:
# WebMock stubs throughout.
class RedirectFollowTest < Minitest::Test
  URL = "https://example.org/files/1"
  MIRROR = "https://mirror.example.net/blob"

  def get(accept: [200], headers: {})
    Nabu::RedirectFollow.get(URL, http: Faraday.new, error: Nabu::Error,
                                  headers: headers, accept: accept)
  end

  def test_headers_ride_every_hop_and_the_final_url_is_returned
    stub_request(:get, URL)
      .with(headers: { "If-Modified-Since" => "then" })
      .to_return(status: 302, headers: { "Location" => MIRROR })
    stub_request(:get, MIRROR)
      .with(headers: { "If-Modified-Since" => "then" })
      .to_return(status: 200, body: "mirror bytes")

    response, final_url = get(headers: { "If-Modified-Since" => "then" })
    assert_equal "mirror bytes", response.body
    assert_equal MIRROR, final_url
  end

  def test_an_accepted_status_terminates_at_the_first_hop
    stub_request(:get, URL).to_return(status: 304)
    response, final_url = get(accept: [200, 304])
    assert_equal 304, response.status
    assert_equal URL, final_url
  end

  def test_a_status_outside_the_accept_list_raises_the_callers_error_class
    stub_request(:get, URL).to_return(status: 304)
    error = assert_raises(Nabu::Error) { get } # accept defaults to [200]
    assert_match(/HTTP 304/, error.message)
  end

  def test_transport_error_is_wrapped_with_the_url_named
    stub_request(:get, URL).to_raise(Faraday::ConnectionFailed.new("boom"))
    error = assert_raises(Nabu::Error) { get }
    assert_match(/transport error/, error.message)
    assert_match(/example\.org/, error.message)
  end
end
