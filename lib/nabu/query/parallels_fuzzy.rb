# frozen_string_literal: true

require_relative "parallels"

module Nabu
  module Query
    # The fuzzy 2-of-3 positional gram tier (architecture §13 "Measuring
    # the engine" — the first of the parallels borrowings, admitted one at
    # a time through `rake bench:parallels`). The exact tier needs an
    # anchor of at least GRAM_SIZE tokens AND an undamaged run of them; a
    # short or lacunose inscription ("dis manibus gaio", "gai caecinae
    # […]") yields no gram or matches none, and is invisible.
    #
    # This tier reads the anchor as positional WINDOWS of three tokens
    # (a, b, c) and accepts a candidate holding a window in which any TWO
    # of the three slots agree — one mismatched or lost slot tolerated:
    #
    #   (a, b, _)  and  (_, b, c)  — an ADJACENT pair, probed as the FTS
    #                                 phrase "a b" (a missing edge slot is
    #                                 tolerated too: damage often IS the
    #                                 edge of a line);
    #   (a, _, c)                  — a GAP pair: a, exactly one token, c —
    #                                 probed as NEAR("a" "c", 1) and then
    #                                 VERIFIED positionally against the
    #                                 candidate's stored search form (NEAR
    #                                 is unordered and also admits adjacency).
    #
    # A two-token anchor is a window with one lost slot (its one adjacent
    # pair); a one-token anchor has no two slots to agree and stays out of
    # reach. Every distinct pair is probed once; a pair made entirely of
    # stop tokens is neither probed nor scored, and the df cap of the exact
    # tier applies unchanged. A matched pair scores FUZZY_WEIGHT × anchor
    # positions / df — so a candidate carrying the whole window (all three
    # masks) outranks one carrying two of its three slots (one mask).
    #
    # == Scope
    #
    # +scope: :fallback+ (default) fires the tier only for an anchor the
    # exact tier scored NOTHING for — so a query the exact engine already
    # answers is byte-identical, and the cost is paid only where the exact
    # tier is blind. +scope: :all+ adds the tier to every anchor (the
    # measured alternative; see the bench report).
    #
    # == Why a subclass, not a flag on Parallels
    #
    # The ParallelsExplain argument: query/parallels.rb sits inside the
    # batch miner's links-stamp closure (LinkStamps.code_files), so a flag
    # there would re-mine every persisted parallels scope for a change that
    # cannot alter one edge while the tier is off. This file sits OUTSIDE
    # that closure (only the bench requires it), observing the engine
    # through its private seams; its cost and yield stay attributable.
    class ParallelsFuzzy < Parallels
      SCOPES = %i[fallback all].freeze

      # A 2-of-3 window is weaker evidence than an exact gram of the same
      # rarity; half weight keeps a fuzzy-only candidate below an exact one
      # whenever their grams are equally rare.
      # const: a scoring ratio between two tiers, not a corpus claim
      FUZZY_WEIGHT = 0.5

      # The verification read's batch width (an IN-list over catalog ids).
      # const: an SQLite bound-parameter batch size, not a corpus claim
      VERIFY_BATCH = 500

      def initialize(catalog:, fulltext:, lects: :auto, scope: :fallback)
        raise ArgumentError, "fuzzy scope must be one of #{SCOPES.join(', ')}, got #{scope.inspect}" \
          unless SCOPES.include?(scope)

        super(catalog: catalog, fulltext: fulltext, lects: lects)
        @scope = scope
      end

      def run(urn, stop_tokens: nil, **)
        @tokens = []
        @stop = stop_tokens.nil? || stop_tokens.empty? ? nil : stop_tokens.to_set
        @fuzzy_matched = Hash.new { |hash, key| hash[key] = [] }
        result = super
        return result if result.nil?

        result.with(gram_count: result.gram_count + @fuzzy_probed.to_i)
      end

      private

      # -- observation seams -------------------------------------------------

      def shingle(tokens, size)
        @tokens = tokens
        super
      end

      def probe_grams(gram_index, anchor_passage_id:)
        scores, matched = super
        @fuzzy_probed = 0
        return [scores, matched] if @scope == :fallback && !scores.empty?

        fuzzy_scores(anchor_passage_id).each { |pid, score| scores[pid] += score }
        [scores, matched]
      end

      # The exact evidence spans, then the fuzzy windows this passage
      # matched — each marked "~", the tolerated slot of a gap pair "_".
      def document_hit(doc_rows, scores, matched, tokens, gram_size)
        hit = super
        best = doc_rows.max_by { |row| scores[row.fetch(:passage_id)] }
        windows = @fuzzy_matched.fetch(best.fetch(:passage_id), [])
        return hit if windows.empty?

        hit.with(evidence: hit.evidence + windows.uniq.sort.map { |kind, position| fuzzy_span(kind, position) })
      end

      # -- the tier ----------------------------------------------------------

      # { [kind, a, b] => [anchor positions] } — kind :adjacent (a b) or
      # :gap (a _ b).
      def fuzzy_pairs
        pairs = {}
        @tokens.each_cons(2).with_index { |(a, b), i| add_pair(pairs, [:adjacent, a, b], i) }
        @tokens.each_cons(3).with_index { |(a, _, c), i| add_pair(pairs, [:gap, a, c], i) }
        pairs
      end

      def add_pair(pairs, key, position)
        return if @stop && key.drop(1).all? { |token| @stop.include?(token) }

        (pairs[key] ||= []) << position
      end

      def fuzzy_scores(anchor_passage_id)
        scores = Hash.new(0.0)
        fuzzy_pairs.each do |key, positions|
          @fuzzy_probed += 1
          pids = fuzzy_probe(key) - [anchor_passage_id]
          next if pids.empty? || pids.size >= @common_gram_df

          weight = FUZZY_WEIGHT * positions.size / pids.size
          pids.each do |pid|
            scores[pid] += weight
            positions.each { |position| @fuzzy_matched[pid] << [key.first, position] }
          end
        end
        scores
      end

      # Passage ids holding the pair. An adjacent pair is the exact tier's
      # own phrase probe; a gap pair is a NEAR superset, verified.
      def fuzzy_probe(key)
        kind, a, b = key
        return fts_probe([a, b]).map { |row| row.fetch(:passage_id) }.uniq if kind == :adjacent

        rows = @fulltext[Store::Indexer::TABLE]
               .where(Sequel.lit("passages_fts MATCH ?", "NEAR(#{phrase([a])} #{phrase([b])}, 1)"))
               .select(Store::Indexer.fts_passage_id_expression(@fulltext))
               .limit(@common_gram_df)
               .all.map { |row| row.fetch(:passage_id) }
        return rows if rows.size >= @common_gram_df # too common either way; the caller drops it

        verify_gap(rows, a, b)
      end

      # Keep the passages whose stored search form holds a, ONE token, b —
      # in that order (tokenized exactly as the anchor was).
      def verify_gap(pids, first, last)
        pids.sort.each_slice(VERIFY_BATCH).flat_map do |slice|
          @catalog[:passages].where(id: slice).select_map(%i[id text_search]).filter_map do |id, text|
            tokens = gram_tokens(text.to_s)
            id if tokens.each_cons(3).any? { |x, _, z| x == first && z == last }
          end
        end
      end

      def fuzzy_span(kind, position)
        return "~#{Grams.join(@tokens[position, 2])}" if kind == :adjacent

        "~#{@tokens[position]} _ #{@tokens[position + 2]}"
      end
    end
  end
end
