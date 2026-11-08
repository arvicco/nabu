# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "../errors"

module Nabu
  module Ops
    # `rake outreach:swh` — one owner-fired Software Heritage round for
    # the whole repo family: POST a "save code now" request per repo
    # (public API, no auth) and read back the latest recorded snapshot
    # SWHID where one exists. Save requests are queued on SWH's side, so
    # the SWHID usually appears on a LATER run than the save it answers —
    # a missing visit is not a finding; a rejected save is. Direct curl
    # POSTs are permission-gated in loop sessions (2026-11-08), which is
    # exactly why this is one packaged command instead.
    class SwhSave
      class FetchError < Nabu::Error; end

      API = "https://archive.softwareheritage.org/api/1"
      REPOS = %w[nabu nabu-lects nabu-places nabu-data nabu-edubba nabu-skill].freeze
      # The 404 sentinel the client returns for a visitless origin (SWH
      # answers 404 there; every other non-success raises).
      NOT_FOUND = :not_found

      Row = Data.define(:repo, :request_status, :snapshot_swhid)
      Report = Data.define(:rows, :findings) do
        def clean? = findings.empty?
      end

      def self.http_call(method, url)
        uri = URI(url)
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          method == "POST" ? http.post(uri.request_uri, "") : http.get(uri.request_uri)
        end
        return NOT_FOUND if response.is_a?(Net::HTTPNotFound)
        raise FetchError, "#{method} #{url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body.to_s
      end

      # +http+ is a callable (method, url) → body | NOT_FOUND (tests
      # inject; the default raises FetchError on any non-success but 404).
      def initialize(repos: REPOS, http: self.class.method(:http_call))
        @repos = repos
        @http = http
      end

      def run
        rows = []
        findings = []
        @repos.each do |repo|
          origin = "https://github.com/arvicco/#{repo}"
          status = save_status(origin)
          findings << "#{repo}: save request #{status}" unless status == "accepted"
          rows << Row.new(repo: repo, request_status: status, snapshot_swhid: snapshot(origin))
        rescue FetchError => e
          findings << "#{repo}: #{e.message}"
          rows << Row.new(repo: repo, request_status: "error", snapshot_swhid: nil)
        end
        Report.new(rows: rows, findings: findings)
      end

      private

      def save_status(origin)
        body = @http.call("POST", "#{API}/origin/save/git/url/#{origin}/")
        return "error" if body == NOT_FOUND

        JSON.parse(body).fetch("save_request_status", "unknown")
      end

      def snapshot(origin)
        body = @http.call("GET", "#{API}/origin/#{origin}/visit/latest/?require_snapshot=true")
        return nil if body == NOT_FOUND

        hex = JSON.parse(body)["snapshot"]
        hex && "swh:1:snp:#{hex}"
      end
    end
  end
end
