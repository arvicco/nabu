# frozen_string_literal: true

require_relative "loader"

module Nabu
  module Store
    # The local-lemmas loader lane (P84-1) — the LEMMAS-shaped sixth
    # loader (content_kind :lemmas), sharing the uniform call shape and
    # LoadReport so SyncRunner/Rebuild route to it with no special casing.
    #
    # Deliberately VALIDATION-ONLY: the shelf's derived product lives
    # FULLTEXT-side (Store::SilverLemmaIndexer projects the shards into
    # passage_lemmas at the index stage), so there is nothing to derive
    # into the catalog here — but a malformed shard must still quarantine
    # LOUDLY at sync/rebuild, and the discovery accounting must see every
    # shard. Counts are SHARD-grained: skipped = shards validated clean
    # (nothing catalog-side ever changes, the honest no-op), errored =
    # quarantined shards.
    class LemmaShelfLoader
      def initialize(db:, source:, ledger: nil)
        @db = db         # accepted for loader-call-shape uniformity; unused
        @source = source
        @ledger = ledger # likewise
      end

      def load_from(adapter, workdir:, full: true, on_document: nil)
        # +full+ is accepted for call-shape uniformity; a validation-only
        # lane has nothing to sweep on full loads.
        _ = full
        counts = Hash.new(0)
        processed = 0
        adapter.discover_with_attic(workdir).each do |ref|
          begin
            adapter.parse(ref)
            counts[:skipped] += 1
          rescue Nabu::ParseError
            counts[:errored] += 1
          end
          processed += 1
          on_document&.call(processed, counts[:errored])
        end
        LoadReport.new(added: 0, updated: 0, skipped: counts[:skipped],
                       withdrawn: 0, errored: counts[:errored])
      end
    end
  end
end
