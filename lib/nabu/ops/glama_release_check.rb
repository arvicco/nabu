# frozen_string_literal: true

require "net/http"
require "uri"

require_relative "../errors"
require_relative "../version"

module Nabu
  module Ops
    # `rake release:glama` — the post-release directory probe (ops §12
    # step 8). A Glama release is the listing's OWN containerized build,
    # made from the server's admin page — it is not produced by the
    # GitHub release (the admin's auto-release option exists but its
    # trigger is unverified; under clarification with Glama, 2026-11-10).
    # When a release changes the server's start requirements, the build
    # fails on THEIR builder, where our CI never looks. The probe reads
    # two PUBLIC, unauthenticated
    # surfaces: the listing page (the released version must be visible on
    # it) and the score badge SVG (the grade, reported informationally —
    # a still-queued evaluation is not a release failure). The directory
    # API is deliberately not used: it is key-gated and carries display
    # terms; the listing page is ours and public.
    class GlamaReleaseCheck
      class FetchError < Nabu::Error; end

      LISTING_URL = "https://glama.ai/mcp/servers/arvicco/nabu"
      BADGE_URL = "#{LISTING_URL}/badges/score.svg".freeze
      # The badge's <title> spells the verdict: "… rated A on Glama".
      GRADE = /rated\s+([A-F])\s+on\s+Glama/

      Report = Data.define(:version, :version_listed, :grade, :findings) do
        def clean? = findings.empty?
      end

      def self.http_fetch(url)
        response = Net::HTTP.get_response(URI(url))
        raise FetchError, "#{url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body.to_s
      end

      # +fetch+ is a callable url → body (tests inject; the default is a
      # plain GET that raises FetchError on any non-success).
      def initialize(version: Nabu::VERSION, fetch: self.class.method(:http_fetch))
        @version = version
        @fetch = fetch
      end

      def run
        listing = @fetch.call(LISTING_URL)
        badge = @fetch.call(BADGE_URL)
        listed = listing.match?(/(?<![\d.])#{Regexp.escape(@version)}(?![\d.])/)
        findings = []
        unless listed
          findings << "#{@version} not visible on the listing — the Glama release has not " \
                      "been made or has not propagated (a Glama release is its own " \
                      "containerized build, not the GitHub release; ops §12 step 8)"
        end
        Report.new(version: @version, version_listed: listed,
                   grade: badge[GRADE, 1], findings: findings)
      rescue FetchError => e
        Report.new(version: @version, version_listed: false, grade: nil, findings: [e.message])
      end
    end
  end
end
