# frozen_string_literal: true

require "faraday"
require "uri"
require "yaml"

# The full entrypoint: the delta line reads both dbs through Store.
require_relative "../../nabu"

module Nabu
  module Ops
    # `rake acquisition:probe` — batch HTTP state checks for the
    # acquisition plan's recorded park / re-check conditions ("the file
    # host is dead", "the corpus page answers"), so a gate re-reads them
    # in one command instead of by hand. Data-driven: the probe list is
    # the instance board's .docs/acquisition/probes.yml (gitignored; absent
    # = the task skips, announced). A list of rows:
    #
    #   - name: lnb-file-host                       # the line's label
    #     url: https://dom.lndb.lv/data/obj/1062448
    #     expect: any                               # an HTTP status (200), "any"
    #                                               # (any HTTP answer), or a
    #                                               # substring of the body
    #     note: "LNB file host — dead 2026-11-23"   # printed beside the state
    #
    # One request per row, a short timeout, NEVER a retry (a probe reports
    # state; it does not try to change it), at most MAX_REDIRECTS redirect
    # hops followed. A status/any expectation asks HEAD (falling back to one
    # GET when upstream refuses the method — 405/501); a substring
    # expectation asks GET. Each row prints `name → state (expect …) —
    # VERDICT — note`; VERDICT is "as expected" or "CHANGED". Informational:
    # nothing here exits nonzero on a CHANGED row — the change is the
    # news the gate reads.
    class AcquisitionProbe
      class Invalid < Nabu::Error; end

      MAX_REDIRECTS = 3
      # const: the per-request timeout (seconds) — a probe, not a download
      TIMEOUT_S = 10
      REDIRECTS = [301, 302, 303, 307, 308].freeze
      METHOD_REFUSED = [405, 501].freeze
      USER_AGENT = "nabu-acquisition-probe (+https://github.com/arvicco/nabu)"

      Row = Data.define(:name, :url, :expect, :note) do
        def status_expectation? = expect.is_a?(Integer) || expect == "any"

        def describe = expect.is_a?(Integer) || expect == "any" ? expect.to_s : expect.inspect
      end

      # status: the final HTTP status (nil = no HTTP answer); error: the
      # transport failure text; body: the GET body (substring rows only).
      Answer = Data.define(:status, :error, :body, :hops)

      Result = Data.define(:row, :answer) do
        def ok?
          return false if answer.status.nil?

          case row.expect
          when "any" then true
          when Integer then answer.status == row.expect
          else answer.body.to_s.include?(row.expect)
          end
        end

        def state
          return "no answer (#{answer.error})" if answer.status.nil?

          hops = answer.hops.positive? ? " after #{answer.hops} redirect(s)" : ""
          "HTTP #{answer.status}#{hops}"
        end

        def line
          note = row.note.to_s.empty? ? "" : " — #{row.note}"
          "#{row.name} → #{state} (expect #{row.describe}) — #{ok? ? 'as expected' : 'CHANGED'}#{note}"
        end
      end

      # The rows of +path+; raises Invalid on a malformed list.
      def self.load(path)
        data = YAML.safe_load_file(path) || []
        raise Invalid, "#{path}: expected a list of probe rows" unless data.is_a?(Array)

        data.each_with_index.map do |raw, index|
          raise Invalid, "#{path}: row #{index + 1} is not a mapping" unless raw.is_a?(Hash)

          name, url = raw.values_at("name", "url").map { |value| value.to_s.strip }
          raise Invalid, "#{path}: row #{index + 1} needs a name and an http(s) url" if
            name.empty? || !url.match?(%r{\Ahttps?://})

          Row.new(name: name, url: url, expect: expectation(raw["expect"]), note: raw["note"].to_s)
        end
      end

      def self.expectation(value)
        case value
        when Integer then value
        when nil then "any"
        else value.to_s.match?(/\A\d{3}\z/) ? Integer(value.to_s, 10) : value.to_s
        end
      end
      private_class_method :expectation

      def initialize(rows:, http: nil, out: $stdout)
        @rows = rows
        @http = http || Faraday.new(request: { timeout: TIMEOUT_S, open_timeout: TIMEOUT_S },
                                    headers: { "User-Agent" => USER_AGENT })
        @out = out
      end

      def run
        results = @rows.map do |row|
          result = Result.new(row: row, answer: ask(row))
          @out.puts(result.line)
          result
        end
        changed = results.count { |result| !result.ok? }
        @out.puts("acquisition:probe — #{results.size} probe(s): #{results.size - changed} as expected, " \
                  "#{changed} CHANGED")
        results
      end

      # The held-vs-searchable line: LIVE catalog passages vs the fulltext
      # index's passages_fts rows, each db opened READ-ONLY, with the
      # withdrawn passages printed beside them as their own number (they
      # are never indexed, so counting them as held reported a gap made of
      # nothing but withdrawals). An absent or unreadable (locked,
      # mid-rebuild) db is an announced skip.
      def self.searchable_delta(catalog_path:, fulltext_path:)
        missing = [catalog_path, fulltext_path].reject { |path| File.file?(path) }
        return "held-vs-searchable: skipped (no #{missing.map { |p| File.basename(p) }.join(', ')})" unless
          missing.empty?

        held = with_db(catalog_path) { |db| held_counts(db) }
        searchable = with_db(fulltext_path) { |db| db[:passages_fts].count }
        delta = held[:live] - searchable
        "held-vs-searchable: #{held[:live]} live catalog passage(s) (+#{held[:withdrawn]} withdrawn, never " \
          "indexed), #{searchable} in passages_fts — delta #{delta}" \
          "#{' (held but not yet searchable)' unless delta.zero?}"
      rescue Sequel::Error => e
        "held-vs-searchable: skipped (#{e.class.name.split('::').last}: #{e.message.lines.first.to_s.strip})"
      end

      # { live:, withdrawn: } passages of +db+ (the catalog). "Live" is the
      # fulltext indexer's own membership predicate (Store::Indexer's
      # slice datasets): passages.withdrawn = false AND the passage's
      # documents.withdrawn = false. Withdrawn is everything else — a
      # withdrawn passage, or a still-flagged-live passage of a withdrawn
      # document.
      #
      # Cost (the catalog holds ~136M passages): the live side reads the
      # maintained source_aggregates table when present — passages_count is
      # exactly that predicate's count, moved at write time in the loader's
      # own transaction (Store::SourceAggregates) — a SUM over one row per
      # source, O(#sources), effectively free. The withdrawn side is total
      # minus live, and the total is the very COUNT(*) the old line ran (a
      # scan of passages' narrowest index), so the probe costs what it did
      # before plus that sum. Only a catalog predating the aggregate table
      # falls back to counting the passages ⋈ documents join on the
      # predicate — the same full scan plus a primary-key lookup per
      # passage, roughly 2-3× the old count; there is no maintained figure
      # to read instead.
      def self.held_counts(db)
        total = db[:passages].count
        live = if Store::SourceAggregates.available?(db)
                 db[Store::SourceAggregates::TABLE].sum(:passages_count).to_i
               else
                 db[:passages].join(:documents, id: Sequel[:passages][:document_id])
                              .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
                              .count
               end
        { live: live, withdrawn: total - live }
      end

      def self.with_db(path)
        db = Store.connect(path, readonly: true)
        yield db
      ensure
        db&.disconnect
      end
      private_class_method :with_db

      private

      def ask(row)
        verb = row.status_expectation? ? :head : :get
        response, hops = follow(verb, row.url)
        response, hops = follow(:get, row.url) if verb == :head && METHOD_REFUSED.include?(response.status)
        Answer.new(status: response.status, error: nil, body: verb == :get ? response.body : nil, hops: hops)
      rescue Faraday::Error, URI::Error => e
        Answer.new(status: nil, error: "#{e.class.name.split('::').last}: #{e.message}", body: nil, hops: 0)
      end

      # [final response, redirect hops]; a redirect past MAX_REDIRECTS is
      # reported as that redirect's own status.
      def follow(verb, url)
        hops = 0
        loop do
          response = @http.public_send(verb, url)
          location = response.headers["location"].to_s
          return [response, hops] unless REDIRECTS.include?(response.status) && !location.empty? &&
                                         hops < MAX_REDIRECTS

          hops += 1
          url = URI.join(url, location).to_s
        end
      end
    end
  end
end
