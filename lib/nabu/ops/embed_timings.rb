# frozen_string_literal: true

require_relative "../store/stage_timings"

module Nabu
  module Ops
    # The `nabu embed` stage record: the command's two passes land in the
    # history ledger's stage_timings under kind "embed" (the verb — the
    # key the reconstruction plan's enrichment line reads,
    # Ops::Reconstruction::Plan#verb_estimate), scope "corpus":
    #
    #   - "census": the scope walk that classifies every live passage
    #     fresh / stale / missing — rows = the live passages walked;
    #   - "encode": the campaign proper (worker up, the owed remainder
    #     embedded, batches committed) — seconds = the Result's own
    #     elapsed time, rows = the passages embedded. Recorded only when
    #     something embedded: a fully-fresh delta run is the census plus
    #     a worker handshake, and its ~0 s must not govern the price of
    #     the next real encode.
    #
    # Every number comes from values the command already holds (the
    # census it printed, the Result it printed) — no extra scan. A
    # `--status` run records nothing (a dry read, the dry-run rule), and
    # a failed campaign records nothing (a half-run stage would be a lie).
    #
    # Lives in ops/ (outside the shared derivation core) on purpose, the
    # EmbedCensus precedent: the embed lane writes no db/ row a rebuild
    # derives, so its bookkeeping must not move the core digest.
    module EmbedTimings
      KIND = "embed"
      SCOPE = "corpus"

      module_function

      def record!(ledger, census:, census_seconds:, result:)
        Store::StageTimings.record!(ledger, kind: KIND, scope: SCOPE, stage: "census",
                                            seconds: census_seconds, rows: census.total)
        return unless result.embedded.positive?

        Store::StageTimings.record!(ledger, kind: KIND, scope: SCOPE, stage: "encode",
                                            seconds: result.elapsed_seconds, rows: result.embedded)
      end
    end
  end
end
