# frozen_string_literal: true

module Nabu
  module Ops
    # The lect: filter timing harness (`rake bench:lect_filter`): times the
    # catalog-join path Query::LectFilter dispatches to — the materialized
    # lect_target EXISTS pair, or the legacy (language, source) pairs on a
    # never-materialized catalog — over a given catalog, for a handful of
    # representative (term, lect) queries. Each case runs the SAME
    # Query::Search call twice per repeat, with and without the lect, so
    # the difference isolates the filter's cost (the evidence for or
    # against a dedicated FTS lect column). Read-only: it only issues
    # Search reads; the rake task opens both databases readonly.
    class LectFilterBench
      Case = Data.define(:query, :lect)
      Row = Data.define(:query, :lect, :hits, :baseline_hits, :baseline_ms, :filtered_ms, :incomplete) do
        def overhead_ms = filtered_ms - baseline_ms
      end

      # Anchors (the identity branch: the bare stored code) beside stages
      # (the facet branch), over a common Latin, Greek and Akkadian term.
      DEFAULT_CASES = "rex@lat,rex@lat:med,λόγος@grc,λόγος@grc:koi,šarru@akk"
      DEFAULT_LIMIT = 20

      def self.parse_cases(spec)
        spec.to_s.split(",").map(&:strip).reject(&:empty?).map do |item|
          query, lect = item.split("@", 2)
          raise Nabu::Error, "bench case #{item.inspect} is not TERM@LECT" if lect.to_s.empty? || query.empty?

          Case.new(query: query, lect: lect)
        end
      end

      # +clock+ returns monotonic seconds (injectable for deterministic
      # tests); +repeats+ runs per variant — the row reports the median.
      def initialize(catalog:, fulltext:, lects:, repeats: 5, limit: DEFAULT_LIMIT,
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @catalog = catalog
        @search = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext, lects: lects)
        @repeats = repeats
        @limit = limit
        @clock = clock
      end

      # Which catalog-join shape LectFilter takes on this catalog.
      def path
        Store::LectFacets.materialized?(@catalog) ? :target : :pairs
      end

      def run(cases)
        cases.map do |kase|
          baseline_ms, baseline = time { @search.run(kase.query, limit: @limit) }
          filtered_ms, filtered = time { @search.run(kase.query, limit: @limit, lect: kase.lect) }
          Row.new(query: kase.query, lect: kase.lect, hits: filtered.size, baseline_hits: baseline.size,
                  baseline_ms: baseline_ms, filtered_ms: filtered_ms,
                  incomplete: !@search.incomplete_hint.nil?)
        end
      end

      def report(rows)
        lines = ["lect filter bench — path: #{path}, limit #{@limit}, median of #{@repeats} run(s)"]
        rows.each do |row|
          lines << format("  %<query>-12s %<lect>-10s hits %<hits>d/%<baseline_hits>d  " \
                          "unfiltered %<baseline_ms>.1f ms  filtered %<filtered_ms>.1f ms  " \
                          "%<overhead_ms>+.1f ms%<note>s",
                          **row.to_h, overhead_ms: row.overhead_ms,
                                      note: row.incomplete ? "  (window exhausted)" : "")
        end
        lines
      end

      private

      # Median wall time in ms over +@repeats+ calls, plus the last result.
      def time
        result = nil
        samples = Array.new(@repeats) do
          started = @clock.call
          result = yield
          (@clock.call - started) * 1000.0
        end
        [samples.sort[samples.size / 2], result]
      end
    end
  end
end
