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

  # --- HTTP 429 + Retry-After (the 2026 Wikimedia per-client API limits) ----
  # The sleeper is injected: no test ever sleeps.

  def get_with_sleeper(slept)
    Nabu::RedirectFollow.get(URL, http: Faraday.new, error: Nabu::Error, sleeper: ->(s) { slept << s })
  end

  def test_a_429_with_retry_after_backs_off_and_retries_once
    stub_request(:get, URL).to_return({ status: 429, headers: { "Retry-After" => "7" } },
                                      { status: 200, body: "after the pause" })
    slept = []
    response, final_url = get_with_sleeper(slept)
    assert_equal "after the pause", response.body
    assert_equal URL, final_url
    assert_equal [7], slept
    assert_requested :get, URL, times: 2
  end

  def test_the_retry_after_pause_is_capped
    stub_request(:get, URL).to_return({ status: 429, headers: { "Retry-After" => "3600" } },
                                      { status: 200, body: "ok" })
    slept = []
    get_with_sleeper(slept)
    assert_equal [Nabu::RedirectFollow::RETRY_AFTER_CAP], slept
    assert_operator Nabu::RedirectFollow::RETRY_AFTER_CAP, :<=, 120
  end

  def test_an_http_date_retry_after_is_honoured_as_seconds_from_now
    stub_request(:get, URL).to_return({ status: 429, headers: { "Retry-After" => (Time.now + 30).httpdate } },
                                      { status: 200, body: "ok" })
    slept = []
    get_with_sleeper(slept)
    assert_equal 1, slept.size
    assert_in_delta 30, slept.first, 2
  end

  def test_a_second_429_raises_the_honest_error
    stub_request(:get, URL).to_return(status: 429, headers: { "Retry-After" => "1" })
    slept = []
    error = assert_raises(Nabu::Error) { get_with_sleeper(slept) }
    assert_match(/HTTP 429/, error.message)
    assert_equal [1], slept, "one back-off, then the abort"
    assert_requested :get, URL, times: 2
  end

  def test_a_429_without_retry_after_raises_at_once
    stub_request(:get, URL).to_return(status: 429)
    slept = []
    error = assert_raises(Nabu::Error) { get_with_sleeper(slept) }
    assert_match(/HTTP 429/, error.message)
    assert_empty slept
    assert_requested :get, URL, times: 1
  end

  def test_an_unreadable_retry_after_raises_at_once
    stub_request(:get, URL).to_return(status: 429, headers: { "Retry-After" => "soon" })
    slept = []
    assert_raises(Nabu::Error) { get_with_sleeper(slept) }
    assert_empty slept
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
