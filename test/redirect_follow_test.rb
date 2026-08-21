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

  # P80 live-gate fix (the aranese/HF xet-bridge 403, 2026-08-20): a signed
  # CDN URL's query must travel BYTE-VERBATIM — Faraday's params machinery
  # re-sorts the params and normalizes escapes (%7E → ~), and CloudFront
  # matches the requested URL against the signed Policy's Resource string
  # byte-for-byte, so any mangle is a 403. WebMock normalizes queries too,
  # so this asserts on the wire url via the Faraday TEST adapter instead.
  SIGNED_QUERY = "response-content-disposition=inline%3B+filename%3D%22a.arn%22" \
                 "&Expires=1787207529&Signature=MEUCIEnsfNmkE%7EqQ_w&Key-Pair-Id=K1"

  # A Rack-level capture: the raw middleware sees env.url exactly as it
  # goes on the wire, with no stub-matcher normalization in the way.
  class WireTap < Faraday::Middleware
    def self.urls = @urls ||= []

    def call(env)
      self.class.urls << env.url.to_s
      env.status = 200
      env.response_headers = Faraday::Utils::Headers.new
      env.body = "bytes"
      Faraday::Response.new(env)
    end
  end

  def wire_conn
    WireTap.urls.clear
    Faraday.new { |f| f.use WireTap }
  end

  def test_the_query_string_travels_byte_verbatim
    url = "https://cdn.example/xet/abc?#{SIGNED_QUERY}"
    response, final_url = Nabu::RedirectFollow.get(url, http: wire_conn, error: Nabu::Error)

    assert_equal 200, response.status
    assert_equal url, final_url
    assert_equal [url], WireTap.urls, "the wire url must be the given url byte-for-byte — " \
                                      "no param re-sorting, no escape normalization"
  end

  class RedirectThenTap < WireTap
    def call(env)
      if self.class.urls.empty?
        self.class.urls << env.url.to_s
        env.status = 302
        env.response_headers = Faraday::Utils::Headers.new("Location" => env.request_headers["X-Redirect-To"])
        env.body = ""
        Faraday::Response.new(env)
      else
        super
      end
    end
  end

  def test_a_redirect_location_with_a_signed_query_is_followed_verbatim
    RedirectThenTap.urls.clear
    conn = Faraday.new { |f| f.use RedirectThenTap }
    target = "https://cdn.example/xet/abc?#{SIGNED_QUERY}"
    Nabu::RedirectFollow.get("https://host.example/resolve/a.arn", http: conn, error: Nabu::Error,
                                                                   headers: { "X-Redirect-To" => target })

    assert_equal target, RedirectThenTap.urls.last,
                 "the redirect hop must hit the Location byte-for-byte"
  end
end
