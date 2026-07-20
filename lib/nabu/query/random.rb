# frozen_string_literal: true

require_relative "catalog_join"
require_relative "show"

module Nabu
  module Query
    # `nabu show --random [--source SLUG] [--count N]` (P11-9): render N random
    # passages in the standard show layout — the eyeball ritual at every source
    # flip ("do the passages look right?").
    #
    # == Honest randomness over the VISIBLE set
    #
    # Unlike plain Show (an inspector that reveals withdrawn rows), --random is a
    # corpus-facing sampler: it draws from the SAME two-level-visible passage set
    # as search/export (neither passage nor its document withdrawn), reusing
    # CatalogJoin so the visibility rule can never drift. Randomness is real —
    # ORDER BY RANDOM() over that set — not a "first N" masquerade; every visible
    # passage has an equal chance, so a flip's sample is representative.
    #
    # == Shape of an answer
    #
    # Each hit is a Show::PassageResult, rendered by the CLI exactly as
    # `nabu show <urn>` would render it (text, document, license, provenance) —
    # the ritual shows the real thing, not a digest. Count is capped at
    # MAX_COUNT (a sampler, not a dump); an unknown --source is a caller error
    # (a synced source with zero visible passages is an empty, honest result).
    class Random
      # A caller-fixable problem (unknown source slug): the CLI turns the
      # message into a clean stderr line + exit 1.
      class Error < Nabu::Error; end

      # Sampler ceiling: an eyeball ritual is a handful, never a firehose.
      # const: a UX bound, not a corpus claim
      MAX_COUNT = 20

      include CatalogJoin

      def initialize(catalog:)
        @catalog = catalog
      end

      # N random visible passages as Show::PassageResults, optionally scoped to
      # one source. count is clamped to [1, MAX_COUNT]. An unknown +source+
      # raises Error; a known source with nothing visible returns [].
      def run(source: nil, count: 1)
        ensure_known_source!(source) if source

        n = count.to_i.clamp(1, MAX_COUNT)
        scope = visible_passages(lang: nil, license: nil)
        scope = scope.where(Sequel[:sources][:slug] => source) if source
        urns = scope.order(Sequel.function(:random))
                    .limit(n)
                    .select_map(Sequel[:passages][:urn])

        show = Show.new(catalog: @catalog)
        # Show reveals the same passage the sampler drew (visibility already
        # applied); reusing it keeps --random byte-identical to `show <urn>`.
        urns.filter_map { |urn| show.run(urn) }
      end

      private

      def ensure_known_source!(source)
        return if @catalog[:sources].where(slug: source).any?

        raise Error, "unknown source #{source.inspect} — run nabu status to see synced sources"
      end
    end
  end
end
