# frozen_string_literal: true

require "uri"
require "time"
require "faraday"

module Nabu
  # The ONE bounded redirect-follow loop behind every plain-HTTP fetch arm
  # (UrlDownload, ZipFetch, FileFetch — extracted from UrlDownload at the
  # 2026-07-18 diorisis incident: figshare's ndownloader 302s EVERY download
  # to an S3 mirror, and the sync fetchers treated any non-200/304 as an
  # error). Hand-rolled deliberately: no redirect middleware ships in the
  # dependency budget.
  #
  # Doctrine (the UrlDownload precedent, now shared):
  # - bounded follow of 301/302/303/307/308, MAX_REDIRECTS hops, honest
  #   errors for the loop cap and for a redirect without a Location;
  # - a relative Location resolves against the CURRENT url (URI.join);
  # - the terminal response is the artifact, but identity (state files, sha
  #   pins, Last-Modified replay) stays keyed to the caller's ORIGINAL url —
  #   mirror targets rotate — which is why the final url is returned beside
  #   the response instead of silently replacing anything;
  # - +headers+ ride EVERY hop: a conditional GET's If-Modified-Since must
  #   reach the mirror, and upstream may answer 304 at the first hop
  #   (pre-redirect) or at the last — callers put 304 in +accept+ and get
  #   the honest terminal response either way;
  # - HTTP 429 carrying Retry-After (the 2026 Wikimedia per-client API
  #   limits answer bursts this way) backs off min(Retry-After,
  #   RETRY_AFTER_CAP) seconds and retries ONCE per get; a second 429, a
  #   429 without the header, or an unreadable header is the honest error.
  module RedirectFollow
    # Statuses followed; any other status outside +accept+ is terminal.
    REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze
    # Hop cap — beyond this the chain is honestly a loop.
    MAX_REDIRECTS = 5
    # Too Many Requests — the one status that may earn a back-off.
    RATE_LIMITED = 429
    # Longest Retry-After pause honoured, in seconds: a larger ask is a
    # quota exhausted, not a burst — the retry after the cap then fails
    # honestly instead of stalling a sync for an hour.
    RETRY_AFTER_CAP = 120
    # The real pause; tests inject their own sleeper.
    SLEEPER = ->(seconds) { Kernel.sleep(seconds) }

    # A signed CDN URL's query must travel BYTE-VERBATIM (the aranese/HF
    # xet-bridge 403, 2026-08-20): Faraday's default params machinery
    # decode/encode-cycles the query — re-sorting params, normalizing
    # escapes (%7E → ~) — and CloudFront matches the requested URL against
    # the signed Policy's Resource string byte-for-byte, so any mangle is
    # a 403 on a URL that curls fine. This encoder satisfies Faraday's
    # decode→Hash / encode→String contract while smuggling the raw query
    # through untouched. Callers passing explicit params would land beside
    # the raw key — RedirectFollow never does (headers only).
    module VerbatimQuery
      RAW = "__nabu_raw_query__"

      def self.decode(query) = { RAW => query }

      def self.encode(params)
        raw = params[RAW]
        rest = params.except(RAW)
        return raw.to_s if rest.empty?

        [raw, Faraday::FlatParamsEncoder.encode(rest)].reject { |part| part.to_s.empty? }.join("&")
      end
    end

    # GET +url+ over the Faraday connection +http+, following redirects.
    # Returns [response, final_url] when the status lands in +accept+;
    # raises +error+ (the caller's error class) for any other non-redirect
    # status, a redirect without a Location, a chain past MAX_REDIRECTS, or
    # a transport failure.
    #
    # +stream+ (P41-2, the 5.9 GB OpenITI artifact): a factory called at the
    # START of every hop, returning that hop's Faraday on_data proc — the
    # response body then streams through the proc chunk by chunk instead of
    # buffering in memory. A factory (not a bare proc) because a redirect
    # hop's body streams too: the caller resets its sink each hop, so only
    # the terminal artifact's bytes survive.
    #
    # +sleeper+ takes the Retry-After pause in seconds (tests inject one).
    def self.get(url, http:, error:, headers: {}, accept: [200], stream: nil, sleeper: SLEEPER)
      current = url
      hops = 0
      backed_off = false
      loop do
        response = attempt(current, http: http, error: error, headers: headers, on_data: stream&.call)
        return [response, current] if accept.include?(response.status)

        if response.status == RATE_LIMITED && !backed_off && (pause = retry_after(response))
          backed_off = true
          sleeper.call(pause)
          next
        end
        raise error, "HTTP #{response.status} for #{current}" unless REDIRECT_STATUSES.include?(response.status)

        hops += 1
        raise error, "too many redirects (more than #{MAX_REDIRECTS} hops) for #{url}" if hops > MAX_REDIRECTS

        location = response.headers["location"].to_s
        raise error, "HTTP #{response.status} redirect without a Location header for #{current}" if location.empty?

        current = URI.join(current, location).to_s
      end
    end

    # The capped pause a 429's Retry-After asks for (delta-seconds or an
    # HTTP-date), or nil when the header is absent or unreadable.
    def self.retry_after(response)
      value = response.headers["retry-after"].to_s.strip
      seconds = if value.match?(/\A\d+\z/)
                  value.to_i
                else
                  (Time.httpdate(value) - Time.now).ceil
                end
      seconds.clamp(0, RETRY_AFTER_CAP)
    rescue ArgumentError
      nil
    end
    private_class_method :retry_after

    def self.attempt(url, http:, error:, headers:, on_data: nil)
      # The encoder must be in place BEFORE the url is assigned — Request#url
      # decodes the query with options.params_encoder at assignment time, so
      # `http.get(url) { … }` would already have mangled it.
      http.get do |request|
        request.options.params_encoder = VerbatimQuery
        request.url(url)
        request.headers.update(headers)
        request.options.on_data = on_data unless on_data.nil?
      end
    rescue Faraday::Error => e
      raise error, "transport error for #{url}: #{e.message}"
    end
    private_class_method :attempt
  end
end
