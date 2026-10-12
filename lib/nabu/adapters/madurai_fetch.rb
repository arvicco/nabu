# frozen_string_literal: true

require "digest"
require "json"

require_relative "../litopys_fetch"

module Nabu
  module Adapters
    # The Project Madurai page fetch (P122-3): Nabu::LitopysFetch's
    # census-listed retention contract (GET every listed page politely,
    # breaker, attic, sha-pinned state file) with two Madurai facts:
    #
    # - DEAD CATALOG LINKS: the works list links files the server does not
    #   have (census 2026-10-12: 5 of the 760 in-cone links answer 404 —
    #   pmuni073.html, pmuni0850.html, pmuni0861–0863.html). A 404 is the
    #   upstream catalog's own dirt, not a failed acquisition: the page is
    #   skipped and named (#missing), and discovery censuses it as "in the
    #   cone but not on disk". Any OTHER failure still fails the fetch.
    # - The pages are *.html, so the delisted-page sweep (the attic) globs
    #   *.html under pm_etexts/ instead of the Izbornyk *.htm.
    class MaduraiFetch < Nabu::LitopysFetch
      NOT_FOUND = /HTTP 404\b/

      def missing = @missing ||= []

      def prepare!
        @rels.each do |rel|
          body, host = get_with_fallback(rel)
          @pages[rel] = { body: body, sha: Digest::SHA256.hexdigest(body), host: host }
        rescue Nabu::LitopysFetch::Error => e
          raise unless e.message.match?(NOT_FOUND)

          missing << rel
        end
        @sha = Digest::SHA256.hexdigest(JSON.generate(@pages.sort.to_h { |rel, page| [rel, page[:sha]] }))
        @changed = @pages.reject { |rel, page| unchanged?(rel, page) }.keys
        @doomed = doomed_relpaths
      end

      private

      # Live e-text pages the list no longer names (a delisted or dead page
      # is atticked, never silently kept or dropped).
      def doomed_relpaths
        return [] unless Dir.exist?(@dir)

        Dir.glob("pm_etexts/**/*.html", base: @dir).sort.reject { |rel| @pages.key?(rel) }
      end
    end
  end
end
