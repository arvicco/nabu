# frozen_string_literal: true

require "uri"
require "faraday"
require_relative "zip_fetch"

module Nabu
  # One-shot HTTP download for `nabu ingest URL...` (P20-0) — the intake
  # front door's fetch arm. Deliberately NOT a sync fetch path (no retention
  # contract, no state file): the downloaded file is handed to the shelf
  # gateway as if the owner had it locally, and the staging dir dissolves.
  # Its jobs are the ones a one-shot acquisition needs:
  #
  # - redirect honesty: a bounded manual follow loop over 301/302/303/307/308
  #   (MAX_REDIRECTS hops; no redirect middleware exists in the codebase and
  #   the dependency budget stays shut, so the loop is hand-rolled).
  #   archive.org 302s every download to a mirror node — the motivating
  #   case. A relative Location resolves against the current url (URI.join).
  # - filename derivation: a Content-Disposition filename= (sanitized —
  #   quotes stripped, any path components dropped) wins; otherwise the
  #   percent-decoded basename of the FINAL url's path; an empty or
  #   extension-less final basename is mirror-handler garbage and falls back
  #   to the ORIGINAL url's basename (the owner's url is the honest name
  #   source). Collisions inside the staging dir get a numbered suffix.
  # - binary body: written with binwrite, sha-able by the shelf unchanged.
  #
  # The connection is the shared cert-hardened ZipFetch.default_http (system
  # trust store plus the vendored intermediates); tests inject +http:+.
  class UrlDownload
    # HTTP-level failure (non-200 terminal status, transport error, redirect
    # runaway). The ingest engine reports it per item; the batch proceeds.
    class Error < Nabu::Error; end

    # What counts as a download argument to `nabu ingest`.
    URL_PATTERN = %r{\Ahttps?://}i
    # Statuses followed; anything else non-200 is terminal.
    REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze
    # Hop cap — beyond this the chain is honestly a loop.
    MAX_REDIRECTS = 5

    def self.url?(value)
      value.to_s.match?(URL_PATTERN)
    end

    def initialize(http: ZipFetch.default_http)
      @http = http
    end

    # GET +url+ (redirects followed), write the body binary into +dir+ under
    # the derived collision-safe name, return the absolute path.
    def fetch(url, dir:)
      response, final_url = follow(url)
      path = unique_path(dir, filename_for(response, final_url, url))
      File.binwrite(path, response.body.to_s.b)
      path
    end

    private

    # The bounded follow loop: returns [terminal 200 response, its url].
    def follow(url)
      current = url
      hops = 0
      loop do
        response = get(current)
        return [response, current] if response.status == 200
        raise Error, "HTTP #{response.status} for #{current}" unless REDIRECT_STATUSES.include?(response.status)

        hops += 1
        raise Error, "too many redirects (more than #{MAX_REDIRECTS} hops) for #{url}" if hops > MAX_REDIRECTS

        location = response.headers["location"].to_s
        raise Error, "HTTP #{response.status} redirect without a Location header for #{current}" if location.empty?

        current = URI.join(current, location).to_s
      end
    end

    def get(url)
      @http.get(url)
    rescue Faraday::Error => e
      raise Error, "transport error for #{url}: #{e.message}"
    end

    # -- filename derivation ---------------------------------------------------

    def filename_for(response, final_url, original_url)
      disposition_filename(response.headers["content-disposition"]) ||
        extensioned(url_basename(final_url)) ||
        url_basename(original_url) ||
        url_basename(final_url) ||
        "download"
    end

    # filename="quoted name.pdf" or filename=bare.pdf. RFC 6266's filename*=
    # form is not chased — quoted/bare covers the shelf's upstreams, and a
    # miss just falls through to the url basename.
    def disposition_filename(header)
      raw = header.to_s[/filename\s*=\s*"([^"]*)"/i, 1] || header.to_s[/filename\s*=\s*([^;\s]+)/i, 1]
      raw && sanitize(raw.delete('"'))
    end

    # The percent-decoded basename of the url's path, sanitized; nil when
    # the path names no file.
    def url_basename(url)
      sanitize(URI.decode_uri_component(File.basename(URI.parse(url).path.to_s)))
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    # One honest file name: path components dropped, whitespace trimmed;
    # nil when nothing usable remains.
    def sanitize(name)
      clean = File.basename(name.tr("\\", "/").strip)
      clean.empty? || %w[/ . ..].include?(clean) ? nil : clean
    end

    def extensioned(name)
      name && !File.extname(name).empty? ? name : nil
    end

    # Collision-safe target inside the staging dir: stem-1.ext, stem-2.ext…
    def unique_path(dir, name)
      candidate = File.join(dir, name)
      return candidate unless File.exist?(candidate)

      stem = File.basename(name, ".*")
      extension = File.extname(name)
      (1..).each do |n|
        candidate = File.join(dir, "#{stem}-#{n}#{extension}")
        return candidate unless File.exist?(candidate)
      end
    end
  end
end
