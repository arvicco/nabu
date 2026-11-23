# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"
require "yaml"

require_relative "../errors"
require_relative "../shell"

module Nabu
  module Ops
    # `rake outreach:probe` — machine-probes the outreach channel surfaces
    # (directory listings, registry entries, the PRs and issues we opened
    # on foreign repos) and prints one delta line per probe:
    #
    #   <name> · <observed state> · <expectation verdict> · <delta>
    #
    # The probe list is data, not code: a gitignored board file
    # (FILE, under the boards dir) holding a `probes:` list. Row shapes:
    #
    #   - { name: <label>, kind: http, url: <url>, expect: <200 | "substring"> }
    #       an Integer expect is the HTTP status; a String is a
    #       case-insensitive body substring (status must then be 2xx)
    #   - { name: <label>, kind: registry, q: <search term>, expect: <"name substring">? }
    #       GET the MCP registry's v0 server search; the state is the
    #       matching server's name + latest version; expect defaults to
    #       "some server name contains q"
    #   - { name: <label>, kind: gh_pr | gh_issue, repo: <owner/repo>, number: <n>,
    #       expect: <"OPEN" | "MERGED" | "CLOSED">? }
    #       via the gh CLI: state + the last comment's date; without an
    #       expect the row is watch-only (the delta is the signal)
    #
    # The delta is computed against the previous run's observations,
    # recorded beside the probe list (STATE_FILE) after every run: a
    # changed state (a new comment, a version bump, a status flip) reads
    # "CHANGED (was …)". Like the other board instruments this is LOCAL
    # tooling over gitignored files: no probe list (a public clone, a
    # lane worktree) is an announced skip. gh absent or failing is an
    # announced per-row SKIP, never a crash; an HTTP failure is a state.
    class OutreachProbe
      FILE = File.join("outreach", "probes.yml")
      STATE_FILE = File.join("outreach", "probes-last.yml")
      REGISTRY = "https://registry.modelcontextprotocol.io/v0/servers"
      KINDS = %w[http registry gh_pr gh_issue].freeze
      REDIRECTS = 3

      class ProbeError < Nabu::Error; end

      # One probe's outcome. +met+ is true/false, or nil when the row
      # declares no expectation (or was skipped).
      Result = Data.define(:name, :state, :met, :previous, :skipped) do
        def changed? = !skipped && !previous.nil? && previous != state

        def line
          return "#{name} · SKIP · #{state}" if skipped

          verdict = case met
                    when true then "expectation met"
                    when false then "expectation NOT met"
                    else "no expectation"
                    end
          delta = if previous.nil? then "first run"
                  elsif changed? then "CHANGED (was #{previous})"
                  else "unchanged"
                  end
          "#{name} · #{state} · #{verdict} · #{delta}"
        end
      end

      Report = Data.define(:skipped, :results) do
        def unmet = results.count { |r| r.met == false }
        def changed = results.count(&:changed?)
      end

      # +http+ is a callable url → [status Integer, body String] (the
      # default is a plain GET, redirects followed — WebMock intercepts it
      # in tests); +runner+ is a callable argv → stdout raising
      # Nabu::Shell::Error on failure (the house seam, injected in tests).
      def initialize(boards_dir:, http: self.class.method(:http_get), runner: Nabu::Shell.method(:run))
        @path = File.join(boards_dir, FILE)
        @state_path = File.join(boards_dir, STATE_FILE)
        @http = http
        @runner = runner
      end

      def self.http_get(url, limit: REDIRECTS)
        uri = URI(url)
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                                           open_timeout: 15, read_timeout: 30) do |http|
          http.request(Net::HTTP::Get.new(uri, "User-Agent" => "nabu-outreach-probe"))
        end
        if response.is_a?(Net::HTTPRedirection) && limit.positive? && response["location"]
          return http_get(URI.join(url, response["location"]).to_s, limit: limit - 1)
        end

        [Integer(response.code, 10), response.body.to_s]
      end

      def run
        return Report.new(skipped: true, results: []) unless File.file?(@path)

        previous = load_previous
        results = rows.map { |row| probe(row, previous) }
        record(results, previous)
        Report.new(skipped: false, results: results)
      end

      private

      def rows
        data = YAML.safe_load_file(@path) || {}
        list = data.is_a?(Hash) ? data["probes"] : nil
        raise ProbeError, "#{@path}: expected a top-level `probes:` list" unless list.is_a?(Array)

        list.each_with_index.map do |row, i|
          raise ProbeError, "#{@path}: probe ##{i + 1} is not a mapping" unless row.is_a?(Hash)
          raise ProbeError, "#{@path}: probe ##{i + 1} has no name" if row["name"].to_s.empty?
          raise ProbeError, "#{@path}: #{row['name']}: unknown kind #{row['kind'].inspect}" unless
            KINDS.include?(row["kind"])

          row
        end
      end

      def probe(row, previous)
        state, met = send(:"probe_#{row['kind']}", row)
        Result.new(name: row["name"], state: state, met: met, previous: previous[row["name"]], skipped: false)
      rescue Nabu::Shell::Error => e
        Result.new(name: row["name"], state: "gh unavailable or failed (#{e.message.lines.first.to_s.strip})",
                   met: nil, previous: nil, skipped: true)
      end

      def probe_http(row)
        status, body = fetch(row["url"])
        return [status, false] unless status.is_a?(Integer)

        expect = row["expect"]
        case expect
        when Integer then ["HTTP #{status}", status == expect]
        when String
          found = body.downcase.include?(expect.downcase)
          ["HTTP #{status}, #{'no ' unless found}\"#{expect}\"", (200..299).cover?(status) && found]
        else ["HTTP #{status}", nil]
        end
      end

      def probe_registry(row)
        query = row["q"].to_s
        status, body = fetch("#{REGISTRY}?search=#{URI.encode_www_form_component(query)}")
        return [status, false] unless status.is_a?(Integer)
        return ["registry HTTP #{status}", false] unless (200..299).cover?(status)

        servers = registry_servers(body)
        wanted = (row["expect"] || query).to_s.downcase
        hits = servers.select { |name, _| name.downcase.include?(wanted) }
        return ["no server matching \"#{wanted}\"", false] if hits.empty?

        [hits.map { |name, version| "#{name} #{version}" }.join(", "), true]
      rescue JSON::ParserError => e
        ["registry body unparseable (#{e.message[0, 60]})", false]
      end

      # [name, version] per server, latest version only: v0 lists one
      # entry per published version, the official _meta flags the latest.
      def registry_servers(body)
        entries = JSON.parse(body).fetch("servers", [])
        by_name = entries.group_by { |entry| (entry["server"] || entry)["name"].to_s }
        by_name.map do |name, versions|
          latest = versions.find { |e| e.dig("_meta", "io.modelcontextprotocol.registry/official", "isLatest") }
          [name, ((latest || versions.last)["server"] || latest || versions.last)["version"]]
        end
      end

      def probe_gh_pr(row) = probe_gh("pr", row)
      def probe_gh_issue(row) = probe_gh("issue", row)

      def probe_gh(noun, row)
        out = @runner.call("gh", noun, "view", row["number"].to_s, "--repo", row["repo"].to_s,
                           "--json", "state,comments")
        data = JSON.parse(out)
        last = data.fetch("comments", []).filter_map { |c| c["createdAt"] }.max
        state = "#{data['state']} · #{last ? "last comment #{last[0, 10]}" : 'no comments'}"
        expect = row["expect"]
        [state, expect ? data["state"].to_s.casecmp?(expect.to_s) : nil]
      rescue JSON::ParserError => e
        raise Nabu::Shell::Error.new("gh output unparseable: #{e.message}", status: nil, stderr: "")
      end

      # [status, body] or ["unreachable: …", ""] — an unreachable surface
      # is an observed state, never a crash.
      def fetch(url)
        @http.call(url)
      rescue SocketError, SystemCallError, Timeout::Error, IOError, OpenSSL::SSL::SSLError,
             Net::HTTPBadResponse => e
        ["unreachable: #{e.class.name.split('::').last}", ""]
      end

      def load_previous
        return {} unless File.file?(@state_path)

        data = YAML.safe_load_file(@state_path)
        data.is_a?(Hash) ? data : {}
      end

      # Skipped rows keep their earlier observation — a gh outage is not
      # a delta.
      def record(results, previous)
        fresh = results.reject(&:skipped).to_h { |r| [r.name, r.state.to_s] }
        File.write(@state_path, YAML.dump(previous.merge(fresh)))
      end
    end
  end
end
