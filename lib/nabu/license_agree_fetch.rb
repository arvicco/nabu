# frozen_string_literal: true

require "uri"
require "faraday"

require_relative "errors"
require_relative "zip_fetch"

module Nabu
  # The click-through licence-agree download arm (P80-7). PORTULAN CLARIN
  # gates its artifacts behind a Django form: a GET of the download URL
  # answers an HTML page carrying a CSRF token and a licence-agree
  # checkbox; POSTing the agreement back to the SAME URL streams the zip.
  # No account, no credential — the gate is consent, and consent is the
  # owner's standing grant (owner ruling №R-37, 2026-08-19: "I DO agree to
  # a license as requested by the sources, and you as an agent faithfully
  # implement it"), represented faithfully by this mechanism.
  #
  # The guardrail: this can never silently agree to terms nobody recorded.
  # The caller DECLARES the licence being accepted (+licence+ — the exact
  # value of the form's hidden licence field at grant time), and the agree
  # page's own field must match it verbatim. A mismatch means the portal's
  # terms drifted since the grant was recorded — the fetch raises INSTEAD
  # of agreeing, before any POST leaves the machine.
  #
  # Shaped like the Faraday connection ZipFetch expects (#get with the
  # RedirectFollow call signature), so the whole non-destructive ZipFetch
  # choreography — staging, attic, state file, the mass-deletion guard
  # seam — rides unchanged: the "GET" of the artifact URL IS the agree
  # dance, and the terminal response is the zip. Conditional headers ride
  # the POST; a portal that ignores them (PORTULAN answers 200 + the full
  # body every time) just re-downloads honestly — drift detection then
  # rides the zip sha in ZipFetch's state file.
  class LicenseAgreeFetch
    # Agree-dance failure: portal shape drift, licence drift, transport.
    # Adapters wrap it in Nabu::FetchError like they wrap ZipFetch::Error.
    class Error < Nabu::Error; end

    # Django renders the token input with single quotes and the form
    # fields with double quotes; accept either — attribute ORDER is the
    # template's, pinned by the recorded fixture page.
    TOKEN_RE = /name=['"]csrfmiddlewaretoken['"]\s+value=['"]([^'"]+)['"]/
    LICENCE_RE = /name=['"]licence['"]\s+value=['"]([^'"]+)['"]/

    def initialize(licence:, http: ZipFetch.default_http)
      @licence = licence
      @http = http
    end

    # The declared grant — public so callers (and tests) can hold the
    # accepted-licence wiring against the record.
    attr_reader :licence

    # The RedirectFollow/Faraday connection signature ZipFetch calls:
    # get(url, params, headers). Runs GET → verify → POST and returns the
    # POST response (the artifact) for ZipFetch to judge by status.
    def get(url, _params = nil, headers = {})
      page = agree_page(url)
      token = csrf_token(page, url)
      verify_licence!(page.body.to_s, url)
      post_agreement(url, token: token, cookies: cookie_header(page, url), headers: headers)
    end

    private

    def agree_page(url)
      response = request { @http.get(url, nil, {}) }
      raise Error, "licence-agree page answered HTTP #{response.status} for #{url}" unless response.status == 200

      response
    end

    def csrf_token(page, url)
      page.body.to_s[TOKEN_RE, 1] or
        raise Error, "no csrfmiddlewaretoken on the licence-agree page at #{url} (portal shape drift)"
    end

    # The №R-37 guardrail: the form's own licence field must repeat the
    # declared grant verbatim, or nothing is agreed to.
    def verify_licence!(body, url)
      offered = body[LICENCE_RE, 1] or
        raise Error, "no licence field on the licence-agree page at #{url} — refusing to agree blind"
      return if offered == @licence

      raise Error, "licence drift at #{url}: the agree page offers #{offered.inspect} but " \
                   "#{@licence.inspect} is the recorded grant — refusing to agree"
    end

    def post_agreement(url, token:, cookies:, headers:)
      form = URI.encode_www_form("csrfmiddlewaretoken" => token, "in_licence_agree_form" => "True",
                                 "licence" => @licence, "licence_agree" => "on")
      request do
        @http.post(url, form, headers.merge("Content-Type" => "application/x-www-form-urlencoded",
                                            "Cookie" => cookies, "Referer" => url))
      end
    end

    # Django's CSRF check needs the token COOKIE echoed beside the form
    # token; replay every cookie the page set. Set-Cookie values arrive
    # comma-joined through Faraday — split only at a comma that starts a
    # new name=value pair (expires= dates contain bare commas).
    def cookie_header(page, url)
      set_cookie = page.headers["set-cookie"].to_s
      pairs = set_cookie.split(/,(?=\s*[^;,=\s]+=)/).filter_map { |part| part[/\A\s*([^;=\s]+=[^;]*)/, 1] }
      raise Error, "the licence-agree page at #{url} set no cookie (the CSRF cookie is required)" if pairs.empty?

      pairs.uniq.join("; ")
    end

    def request
      yield
    rescue Faraday::Error => e
      raise Error, "transport error during the licence-agree dance: #{e.message}"
    end
  end
end
