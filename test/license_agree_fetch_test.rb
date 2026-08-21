# frozen_string_literal: true

require "test_helper"

# Nabu::LicenseAgreeFetch (P80-7): the click-through licence-agree
# download arm — PORTULAN CLARIN gates its zips behind a Django form
# (GET the download URL → HTML with a CSRF token + a licence-agree
# checkbox → POST the agreement → the SAME URL streams the zip).
# Owner ruling №R-37 (2026-08-19) sanctions representing the owner's
# licence acceptance; the mechanism's guardrail is that the caller
# DECLARES the licence being accepted, and the form's own hidden
# licence field must match it verbatim — portal drift means the grant
# no longer applies and the fetch refuses to agree.
#
# The fixture is the WHOLE live agree page (retrieved 2026-08-19) —
# see test/fixtures/bdcamoes/README.md. No network: WebMock.
class LicenseAgreeFetchTest < Minitest::Test
  URL = "https://portal.example/repository/download/abc123/"
  PAGE = File.binread(File.join(Nabu::TestSupport.fixtures("bdcamoes"),
                                "fetch", "licence-agree-page.html"))
  # The fixture page's own token value (the recorded live shape).
  PAGE_TOKEN = PAGE[/name='csrfmiddlewaretoken' value='([^']+)'/, 1]

  def fetch(licence: "CC-BY")
    Nabu::LicenseAgreeFetch.new(licence: licence, http: Faraday.new)
  end

  def stub_agree_page(body: PAGE, status: 200)
    stub_request(:get, URL).to_return(
      status: status, body: body,
      headers: { "Content-Type" => "text/html; charset=utf-8",
                 "Set-Cookie" => ["repository-csrftoken=COOKIETOKEN; " \
                                  "expires=Wed, 18-Aug-2027 16:27:21 GMT; Max-Age=31449600; Path=/",
                                  "portulanclarin-lang=en-us; Domain=.portal.example; Path=/"] }
    )
  end

  def stub_zip_post
    stub_request(:post, URL).to_return(
      status: 200, body: "PK\x03\x04zipbytes".b,
      headers: { "Content-Type" => "application/zip",
                 "Content-Disposition" => "attachment; filename=archive.zip" }
    )
  end

  # -- the happy dance --------------------------------------------------------

  def test_get_runs_the_agree_dance_and_returns_the_zip_response
    stub_agree_page
    stub_zip_post
    response = fetch.get(URL)
    assert_equal 200, response.status
    assert_equal "application/zip", response.headers["content-type"]
    assert response.body.b.start_with?("PK\x03\x04".b), "the terminal response is the zip"
  end

  def test_the_post_carries_the_pages_token_the_agreement_fields_and_the_cookies
    refute_nil PAGE_TOKEN, "the fixture page must carry a csrfmiddlewaretoken"
    stub_agree_page
    stub_zip_post
    fetch.get(URL)
    assert_requested(:post, URL) do |req|
      form = URI.decode_www_form(req.body).to_h
      form["csrfmiddlewaretoken"] == PAGE_TOKEN &&
        form["in_licence_agree_form"] == "True" &&
        form["licence"] == "CC-BY" &&
        form["licence_agree"] == "on" &&
        req.headers["Cookie"].include?("repository-csrftoken=COOKIETOKEN") &&
        req.headers["Referer"] == URL
    end
  end

  def test_get_matches_the_faraday_connection_signature_zip_fetch_calls
    # RedirectFollow.attempt calls http.get(url, nil, headers) — the shim
    # must accept exactly that shape so the ZipFetch choreography rides
    # unchanged.
    stub_agree_page
    stub_zip_post
    response = fetch.get(URL, nil, { "If-Modified-Since" => "yesterday" })
    assert_equal 200, response.status
  end

  # -- the №R-37 guardrail ----------------------------------------------------

  def test_a_licence_mismatch_refuses_to_agree_before_any_post
    stub_agree_page
    error = assert_raises(Nabu::LicenseAgreeFetch::Error) do
      fetch(licence: "MS NC-NoReD-ND 2.0").get(URL)
    end
    assert_match(/licence drift/i, error.message)
    assert_match(/CC-BY/, error.message, "names what the page offers")
    assert_match(/MS NC-NoReD-ND 2\.0/, error.message, "names the recorded grant")
    assert_not_requested :post, URL
  end

  def test_a_page_without_a_licence_field_never_agrees
    stub_agree_page(body: PAGE.gsub("licence", "permit"))
    assert_raises(Nabu::LicenseAgreeFetch::Error) { fetch.get(URL) }
    assert_not_requested :post, URL
  end

  # -- portal-shape defenses --------------------------------------------------

  def test_a_page_without_a_csrf_token_raises_shape_drift
    stub_agree_page(body: "<html><body>maintenance</body></html>")
    error = assert_raises(Nabu::LicenseAgreeFetch::Error) { fetch.get(URL) }
    assert_match(/csrfmiddlewaretoken/, error.message)
    assert_not_requested :post, URL
  end

  def test_a_non_200_agree_page_raises
    stub_agree_page(status: 503)
    error = assert_raises(Nabu::LicenseAgreeFetch::Error) { fetch.get(URL) }
    assert_match(/503/, error.message)
  end

  def test_a_page_that_sets_no_cookie_raises
    stub_request(:get, URL).to_return(status: 200, body: PAGE)
    error = assert_raises(Nabu::LicenseAgreeFetch::Error) { fetch.get(URL) }
    assert_match(/cookie/i, error.message, "Django rejects a POST without the CSRF cookie — fail loudly here")
    assert_not_requested :post, URL
  end

  def test_a_transport_error_wraps_in_the_mechanism_error
    stub_request(:get, URL).to_raise(Faraday::ConnectionFailed.new("boom"))
    error = assert_raises(Nabu::LicenseAgreeFetch::Error) { fetch.get(URL) }
    assert_match(/transport error/, error.message)
  end
end
