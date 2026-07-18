# frozen_string_literal: true

require "uri"
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
  #   the honest terminal response either way.
  module RedirectFollow
    # Statuses followed; any other status outside +accept+ is terminal.
    REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze
    # Hop cap — beyond this the chain is honestly a loop.
    MAX_REDIRECTS = 5

    # GET +url+ over the Faraday connection +http+, following redirects.
    # Returns [response, final_url] when the status lands in +accept+;
    # raises +error+ (the caller's error class) for any other non-redirect
    # status, a redirect without a Location, a chain past MAX_REDIRECTS, or
    # a transport failure.
    def self.get(url, http:, error:, headers: {}, accept: [200])
      current = url
      hops = 0
      loop do
        response = attempt(current, http: http, error: error, headers: headers)
        return [response, current] if accept.include?(response.status)
        raise error, "HTTP #{response.status} for #{current}" unless REDIRECT_STATUSES.include?(response.status)

        hops += 1
        raise error, "too many redirects (more than #{MAX_REDIRECTS} hops) for #{url}" if hops > MAX_REDIRECTS

        location = response.headers["location"].to_s
        raise error, "HTTP #{response.status} redirect without a Location header for #{current}" if location.empty?

        current = URI.join(current, location).to_s
      end
    end

    def self.attempt(url, http:, error:, headers:)
      http.get(url, nil, headers)
    rescue Faraday::Error => e
      raise error, "transport error for #{url}: #{e.message}"
    end
    private_class_method :attempt
  end
end
