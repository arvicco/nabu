# frozen_string_literal: true

require_relative "show"

module Nabu
  module Query
    # `nabu show --random [--source SLUG] [--count N]` (P11-9; resampled
    # P41-r2): render N random passages in the standard show layout — the
    # eyeball ritual at every source flip ("do the passages look right?").
    #
    # == Honest randomness over the VISIBLE set
    #
    # The sampler draws from the SAME two-level-visible passage set as
    # search/export (neither passage nor its document withdrawn), reusing
    # CatalogJoin so the visibility rule can never drift.
    #
    # == The id-probe (P41-r2 — owner report at the 62.8M-passage scale)
    #
    # ORDER BY RANDOM() sorts the WHOLE visible set per draw — measured
    # 2m19s for one openiti passage (34.6M rows) the night the corpus
    # doubled; "should be instant". The sampler now probes: draw a random
    # rowid r in the scope's [min,max] id range and take the first visible
    # scope row with id >= r (wrapping to min when the tail is a gap) —
    # O(log n) per draw against the passages primary key. HONESTY: this is
    # near-uniform, not perfectly uniform — a row's draw probability is
    # proportional to the id-gap preceding it, which for nabu's bulk-loaded
    # shelves (each sync appends a dense id run) deviates negligibly; the
    # perfect-uniformity claim of the P11-9 comment is retired with the
    # algorithm. A scope too small or too gap-ridden to fill the request
    # (PROBE_ATTEMPTS misses per draw) falls back to ORDER BY RANDOM(),
    # which is instant at exactly the sizes where probing struggles.
    #
    # == Shape of an answer
    #
    # Each hit is a Show::PassageResult, rendered by the CLI exactly as
    # `nabu show <urn>` would render it (text, document, license,
    # provenance) — the ritual shows the real thing, not a digest. Count is
    # capped at MAX_COUNT (a sampler, not a dump); an unknown --source is a
    # caller error (a synced source with zero visible passages is an empty,
    # honest result).
    class Random
      # A caller-fixable problem (unknown source slug): the CLI turns the
      # message into a clean stderr line + exit 1.
      class Error < Nabu::Error; end

      # Sampler ceiling: an eyeball ritual is a handful, never a firehose.
      # const: a UX bound, not a corpus claim
      MAX_COUNT = 20

      # Probe misses tolerated per requested draw before the small-scope
      # ORDER BY RANDOM() fallback.
      # const: a retry bound, not a corpus claim
      PROBE_ATTEMPTS = 8

      # +rng+ is injectable for deterministic tests.
      def initialize(catalog:, rng: ::Random.new)
        @catalog = catalog
        @rng = rng
      end

      # N random visible passages as Show::PassageResults, optionally scoped
      # to one source. count is clamped to [1, MAX_COUNT]. An unknown
      # +source+ raises Error; a known source with nothing visible returns [].
      def run(source: nil, count: 1)
        ensure_known_source!(source) if source

        n = count.to_i.clamp(1, MAX_COUNT)
        # JOIN-FREE probing (the measured lesson: probing THROUGH the
        # documents/sources join defeats the passages-PK walk — the planner
        # drives from the join and scans; 4m45s scoped vs 0.4s bare). The
        # two-level visibility rule is preserved join-free: candidate
        # documents are prefiltered to non-withdrawn (per source, or checked
        # per candidate corpus-wide), passages filter on their own withdrawn
        # flag, and Show re-applies full visibility on render.
        scope = @catalog[:passages].where(withdrawn: false)
        if source
          doc_ids = @catalog[:documents]
                    .where(source_id: @catalog[:sources].where(slug: source).select(:id))
                    .where(withdrawn: false)
                    .select(:id)
          scope = scope.where(document_id: doc_ids)
        end

        urns = probe_urns(scope, n, check_document: source.nil?)
        show = Show.new(catalog: @catalog)
        # Show reveals the same passage the sampler drew (visibility already
        # applied); reusing it keeps --random byte-identical to `show <urn>`.
        urns.filter_map { |urn| show.run(urn) }
      end

      private

      # +check_document+: corpus-wide probes carry no document prefilter (no
      # IN-list), so a candidate's document withdrawal is checked per draw —
      # withdrawn documents are rare, a miss just retries.
      def probe_urns(scope, count, check_document:)
        min = scope.min(:id)
        max = scope.max(:id)
        return [] unless min && max

        urns = []
        misses = 0
        while urns.size < count && misses < count * PROBE_ATTEMPTS
          urn = probe_one(scope, @rng.rand(min..max), min, check_document: check_document)
          if urn.nil? || urns.include?(urn)
            misses += 1
          else
            urns << urn
          end
        end
        urns.size < count ? sorted_fallback(scope, count, check_document: check_document) : urns
      end

      # First visible scope row at or after +r+ in rowid order, wrapping to
      # +min+ when r lands past the scope's tail rows.
      def probe_one(scope, probe_id, floor, check_document:)
        row = first_at_or_after(scope, probe_id) || first_at_or_after(scope, floor)
        return nil unless row
        return nil if check_document && document_withdrawn?(row[:document_id])

        row[:urn]
      end

      def first_at_or_after(scope, id)
        scope.where { Sequel[:passages][:id] >= id }
             .order(:id)
             .limit(1)
             .select(:urn, :document_id)
             .first
      end

      def document_withdrawn?(document_id)
        @catalog[:documents].where(id: document_id).get(:withdrawn) ? true : false
      end

      # The exact sampler for scopes the probe cannot fill (tiny or
      # gap-ridden): fine there, because ORDER BY RANDOM() is instant at
      # exactly those sizes.
      def sorted_fallback(scope, count, check_document:)
        rows = scope.order(Sequel.function(:random)).limit(count * 2).select_map(%i[urn document_id])
        rows.reject { |_, doc_id| check_document && document_withdrawn?(doc_id) }
            .map(&:first)
            .first(count)
      end

      def ensure_known_source!(source)
        return if @catalog[:sources].where(slug: source).any?

        raise Error, "unknown source #{source.inspect} — run nabu status to see synced sources"
      end
    end
  end
end
