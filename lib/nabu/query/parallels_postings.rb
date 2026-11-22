# frozen_string_literal: true

require_relative "parallels"
require_relative "../store/fts5_tokens"
require_relative "../store/reuse_postings"

module Nabu
  module Query
    # The parallels engine answered from the gram-postings store instead of
    # per-gram FTS probes (the reuse-batch redesign; Store::ReusePostings,
    # Nabu::BatchParallelsPostings). The SAME scoring code as
    # Query::Parallels — this is a subclass that replaces exactly two
    # seams and inherits everything else:
    #
    # - fts_probe(gram): the old engine's one FTS round-trip per gram (the
    #   measured 92% of its time at CJK scale) becomes a lookup in a
    #   chunk-prefetched postings map. It returns the rows the FTS probe
    #   would — the CJK-lane matches first, then the main-lane ones, each in
    #   ascending passage id, unioned (fts_probe's own `(lane + rows).uniq`)
    #   — so probe_grams, the rarity weights, the score sums and even the
    #   candidates' insertion order (which breaks pool-boundary ties) are
    #   the old engine's, bit for bit. A gram the store holds as COMMON
    #   (df at or over its cap) answers a cutoff-sized row set, which
    #   probe_grams skips exactly as it skips a capped FTS probe.
    # - candidate_rows: the per-anchor catalog join becomes a read of a
    #   per-CHUNK resolved map (#resolve: the same CatalogJoin query, run
    #   once over the union of the chunk's pool candidates) — the
    #   passage→document map and visibility set the design names, sized to
    #   the chunk rather than the corpus (a corpus-wide map would be ~0.5 GB
    #   at the 107M-passage census).
    #
    # index_grams, probe_grams, assemble, document_hit and the evidence
    # spans are inherited untouched — the parity contract
    # (batch_parallels_postings_test) is that both engines mint identical
    # edges and scores.
    #
    # == The spike's lesson, kept
    #
    # The P163 spike tried scoring from the RARE grams only (postings for a
    # low df band) and it was NOT exact: every gram under the engine's
    # common-gram cutoff contributes 1/df to a score, and dropping the
    # middle band moved scores and therefore rankings. So the store keeps
    # FULL postings below the cutoff; only the probe mechanism changed.
    #
    # == Two roles
    #
    # A scoring WORKER (built with +reader:+, no catalog) runs #prefetch! and
    # #pool_for over its slice of anchors; the COMMITTER (built with
    # +catalog:+) runs #resolve and #hits over the pools the workers return.
    # The split lets the pool's forked workers do the gram work with no
    # catalog handle at all.
    class ParallelsPostings < Parallels
      # The run's common-gram cutoff, computed exactly as Query::Parallels
      # snapshots it (D36-a: corpus-relative, floored).
      def self.cutoff(catalog)
        engine = Parallels.new(catalog: catalog, fulltext: nil)
        engine.send(:snapshot_cutoffs)
        engine.instance_variable_get(:@common_gram_df)
      end

      # +cutoff+ is the run's snapshot (fixed for the run, not re-read per
      # anchor); +lane+ whether the fulltext carried the CJK bigram lane
      # when the postings were built (the store's stamp).
      def initialize(cutoff:, lane:, catalog: nil, reader: nil, tokens: nil)
        super(catalog: catalog, fulltext: nil, lects: nil)
        @common_gram_df = cutoff
        @cjk_lane = lane
        @reader = reader
        @tokens = tokens
        @keys = {}
        @entries = {}
        @probe_cache = {}
      end

      # The probe keys of one gram: [main, lane]. +main+ is the gram's
      # tokens folded by the main lane's tokenizer and space-joined (what a
      # quoted phrase MATCH compares), nil when a token does not fold to one
      # indexed token (the arity a phrase would change — not emulable);
      # +lane+ the raw all-Han gram the CJK lane's bigram phrase answers,
      # present only when the lane exists (fts_probe's own condition).
      def keys_for(gram)
        folded = tokens.fold(gram)
        main = folded.any?(&:nil?) ? nil : folded.join(" ")
        lane = @cjk_lane && gram.all? { |token| token.match?(Grams::HAN_CHAR) } ? gram.join(" ") : nil
        [main, lane]
      end

      # Census pass 1: every probe key of each text's +gram_size+ grams
      # (stop grams included — the store is a superset), plus how many grams
      # had no main key. Returns [[keys per text], unkeyable_count].
      def anchor_keys(texts, gram_size:)
        grams = texts.map { |text| shingle(gram_tokens(text.to_s), gram_size).uniq }
        tokens.fold(grams.flatten.uniq)
        unkeyable = 0
        keys = grams.map do |text_grams|
          text_grams.flat_map do |gram|
            main, lane = keys_for(gram)
            unkeyable += 1 if main.nil?
            [main, lane]
          end.compact.uniq
        end
        [keys, unkeyable]
      end

      # Worker: look up every key the +anchors+' grams need, once per slice.
      # Anchors are [urn, passage_id, document_id, text] tuples.
      def prefetch!(anchors, gram_size:)
        grams = anchors.flat_map { |anchor| shingle(gram_tokens(anchor[3].to_s), gram_size) }.uniq
        tokens.fold(grams.flatten.uniq)
        @keys = grams.to_h { |gram| [gram, keys_for(gram)] }
        @entries = @reader.lookup(@keys.values.flatten.compact)
        @probe_cache = {}
        self
      end

      # Worker: one anchor's candidate POOL — the top-scored passage ids
      # exactly as assemble selects them (captured from assemble itself, so
      # the selection is the inherited code, not a copy), with their scores
      # and matched gram positions. [ids, scores, matched], parallel arrays.
      def pool_for(anchor, gram_size:, stop_tokens:, limit:, pool:)
        tokens = gram_tokens(anchor[3].to_s)
        gram_index = index_grams(shingle(tokens, gram_size), stop_tokens)
        scores, matched = probe_grams(gram_index, anchor_passage_id: anchor[1])
        ids = capture_pool do
          assemble(scores, matched, tokens: tokens, anchor_document_id: anchor[2], lang: nil, license: nil,
                                    limit: limit, gram_size: gram_size, pool: pool)
        end
        [ids, ids.map { |id| scores[id] }, ids.map { |id| matched[id] }]
      end

      # Committer: the visible candidate rows for +ids+ under the run's
      # filters — the inherited CatalogJoin query, once per chunk, in id
      # order. { passage_id => row }.
      def resolve(ids, lang:, license:)
        ids.uniq.sort.each_slice(RESOLVE_SLICE).with_object({}) do |slice, map|
          candidate_rows(slice, lang: lang, license: license)
            .sort_by { |row| row.fetch(:passage_id) }
            .each { |row| map[row.fetch(:passage_id)] = row }
        end
      end

      # Committer: one anchor's document-grain hits from its worker pool and
      # the chunk's resolved map — the inherited assemble over the pool.
      def hits(anchor, pool_entry, resolved:, limit:, gram_size:, pool:)
        ids, scores, matched = pool_entry
        @resolved = resolved
        assemble(ids.zip(scores).to_h, ids.zip(matched).to_h,
                 tokens: gram_tokens(anchor[3].to_s), anchor_document_id: anchor[2],
                 lang: nil, license: nil, limit: limit, gram_size: gram_size, pool: pool)
      ensure
        @resolved = nil
      end

      def close
        @reader&.close
        @tokens&.close
      end

      # Candidate ids per resolve query.
      # const: an IN-list bound under SQLite's 32,766 host-parameter limit —
      # an engine property, not a corpus count
      RESOLVE_SLICE = 5_000

      private

      def tokens = (@tokens ||= Store::Fts5Tokens.new)

      # The run's cutoff is fixed at construction.
      def snapshot_cutoffs; end

      def fts_probe(gram)
        @probe_cache[gram] ||= probe_rows(gram)
      end

      # The FTS probe's rows, rebuilt from postings: lane matches, then
      # main-lane matches, unioned by passage id (fts_probe's order).
      def probe_rows(gram)
        main_key, lane_key = @keys.fetch(gram) { keys_for(gram) }
        main = main_key && @entries[main_key]
        lane = lane_key && @entries[lane_key]
        return common_rows if main == :common || lane == :common

        lane_ids = lane ? lane.filter_map { |id, lanes| id if lanes.anybits?(Store::ReusePostings::LANE_CJK) } : []
        main_ids = main ? main.filter_map { |id, lanes| id if lanes.anybits?(Store::ReusePostings::LANE_MAIN) } : []
        ids = lane_ids.empty? ? main_ids : (lane_ids + main_ids).uniq
        ids.map { |id| { passage_id: id } }
      end

      # A cutoff-sized row set: probe_grams reads only its size and skips it.
      def common_rows = (@common_rows ||= Array.new(@common_gram_df).freeze)

      def capture_pool
        @capture = []
        yield
        @capture
      ensure
        @capture = nil
      end

      def candidate_rows(passage_ids, lang:, license:, scope: {})
        if @capture
          @capture.concat(passage_ids)
          return []
        end
        return passage_ids.filter_map { |id| @resolved[id] }.sort_by { |row| row.fetch(:passage_id) } if @resolved

        super
      end
    end
  end
end
