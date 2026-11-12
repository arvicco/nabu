# frozen_string_literal: true

require_relative "reflex_descent"

module Nabu
  module Store
    # The cognate root-closure table (P15-3, intertext design §6, fable
    # closure review 2026-07-12; multi-hop rewrite P17-3): one row per
    # (gold language, folded lemma, reconstruction-entry urn) asserting the
    # lemma descends — within the bounded shelf-visited walk below — from
    # that entry, plus the OR-aggregated `borrowed` flag of the best-known
    # path. The P7-5 pattern again: derived from the catalog's stored
    # crosswalk, living in fulltext.sqlite3 beside passage_lemmas/
    # alignment_refs with the same drop-and-rebuild lifecycle, created here
    # imperatively, never migrated. Indexer.rebuild! is the single choke
    # point (sync's reindex + rebuild), so a recon re-sync and a treebank
    # sync both regenerate it — the review's staleness rider.
    #
    # == The walk (P17-3: the shelf-visited worklist closure)
    #
    # The original build took DIRECT edges plus ONE ascent hop, arguing "a
    # depth-3 chain needs an intermediate shelf … that does not exist in
    # the catalog; revisit the bound if one lands" (P15-3 review finding
    # 6). Proto-Balto-Slavic IS that shelf (PIE *per- → ine-bsl-pro
    # *pírštan → sla-pro *pь̃rstъ → chu прьстъ / orv пьрстъ), and
    # Proto-West Germanic is a second (gem-pro → gmw-pro → ang), so the
    # bound is now the generalization the old argument was a special case
    # of:
    #
    # DIRECT: every dictionary_reflexes row of a live entry maps
    # (language, word_folded) and (language, roman_folded) to its OWNING
    # entry — the roman fold is the script bridge (got 𐍃𐌰𐌻𐍄 joins the gold
    # lemma "salt"). ASCENT: from each direct target, a worklist walk — for
    # an entry owned by dictionary-language S, every entry of an UNVISITED
    # shelf whose reflexes name (S, headword_folded) joins the root set and
    # re-enters the worklist. Attested reflex-owning shelves (wiktionary-cu
    # today) ascend exactly like the -pro shelves — descent through an
    # attested intermediary is the same descent relation (this supersedes
    # P16-5's direct-only stance for the closure; renderers still star only
    # -pro headwords).
    #
    # BOUND & TERMINATION: each dictionary LANGUAGE (shelf) is enterable
    # once per walk — a visited set seeded with the direct target's own
    # shelf, which is the old same-language exclusion generalized (intra-
    # shelf derivational edges never ascend; a malformed proto-to-proto
    # cycle's return edge re-enters a visited shelf and dies). Expansion is
    # breadth-first in ROUNDS: a round expands the whole frontier, then
    # marks every newly reached shelf visited — so which entries a shelf
    # contributes depends only on the graph and the start entry, never on
    # iteration order. Every non-final round visits ≥1 new shelf, so the
    # walk terminates in ≤ (reflex-owning shelves − 1) rounds — no magic
    # depth constant — and when no intermediate shelf exists it degenerates
    # to EXACTLY the old one-hop walk (pinned by test). Longest real chain
    # measured in the P17-3 survey: 3 hops.
    #
    # == The borrowed flag (P17-3; P15-3 review finding 4)
    #
    # Each crosswalk edge carries migration 010's nullable `borrowed`
    # (true/false from the flag-aware parser, NULL for rows predating the
    # reparse). The flag ORs ALONG THE PATH — the design-load-bearing case
    # is *hlaibaz: the loan marker rides the proto-to-proto edge (gem-pro →
    # sla-pro *xlěbъ, flagged), not the chu leaf, so a direct-edge-only
    # flag would never fire for hlaifs ~ хлѣбъ. Three-valued, honest:
    # true if any edge on the path is flagged; else NULL if any edge is
    # not-yet-reparsed (the path cannot claim "inherited"); else false.
    # Several paths to one root deduplicate by max (true > false > NULL) —
    # commutative, so determinism survives. Unflagged stays the meet-shelf
    # heuristic's territory (upstream flags are high-precision/low-recall).
    #
    # == Roots are URNs, not row ids (the review's determinism finding)
    #
    # dictionary_entries ids re-mint whenever the shelf reloads, and a recon
    # re-sync does NOT drop this table — only the next reindex does. Stored
    # ids would go silently stale (or worse, point at since-withdrawn rows);
    # stored URNs are the project's cross-parse stability contract, and the
    # query resolves them against the CURRENT catalog with the withdrawn
    # filter applied, so a root withdrawn since the build drops out honestly.
    #
    # == Gold scoping
    #
    # Final rows are emitted only for languages present in passage_lemmas:
    # the table exists solely to join gold lemmas, and the ~250k modern-
    # language descendant keys (en, de, ru …) can never join. Proto shelves
    # still participate as build-time intermediates. Measured live at P15-3:
    # ~50k rows, < 5 MB, ~1.4 s; the P17-3 survey projects ~56–60k rows,
    # < 8 MB after the four new shelves land.
    #
    # Since P26-4 "gold" is literal tier scope, not just a synonym for
    # "annotated": the language scope and the stats denominators read only
    # tier-gold rows of passage_lemmas. The closure is RECONSTRUCTION
    # EVIDENCE (Cognates joins it to claim attested reflexes), and silver
    # (automatic-lemmatization) rows carry no such claim — a language whose
    # lemmas are all silver (Diorisis-only coverage) stays out of the
    # closure entirely, and a silver flood can never skew the suppression
    # denominator. Pre-tier fulltext files have no tier column and read
    # all-gold (the borrowed_column? precedent).
    #
    # The companion STATS_TABLE holds per-language gold passage counts —
    # what Query::Cognates' common-word suppression divides by (a fixed
    # absolute df threshold is percentile-incoherent across corpora spanning
    # 125 to 113k gold passages; the review's calibration finding).
    #
    # == The delta grain (the incrementality review)
    #
    # The corpus pass (#rebuild!) used to run on EVERY lemma-bearing sync:
    # a grouped distinct count over the whole gold lemma table (tens of
    # millions of rows) plus a full crosswalk walk — O(corpus) work re-done
    # for any slice. But the closure depends on passage_lemmas ONLY through
    # the gold language SET (closure_rows emits every crosswalk key of a
    # gold language, attested or not — no lemma VALUE enters it), and the
    # stats are a sum over passages (a passage contributes 1 to each gold
    # language it carries). So a lemma-bearing refresh now:
    #
    #   - moves the stats by its own rows' before/after gold languages
    #     (stats_snapshot / apply_stats_delta!, O(Δ), inside the slice's
    #     transaction so they can never drift from the lemma rows);
    #   - moves the closure by the languages that LEFT the gold set (their
    #     rows deleted — a point delete on the language index) or ENTERED
    #     it. An entering language's rows need the whole crosswalk walk
    #     (the ascent can route through any shelf), so instead of paying it
    #     inline the closure is flagged stale (Store::StaleAggregates) for
    #     the maintenance rail — unless the crosswalk names the language
    #     nowhere (an indexed probe), in which case it has no rows to mint.
    #
    # A crosswalk change (a dictionary sync) re-walks the closure ALONE
    # (#rebuild_closure!, gold set read from the stats — O(crosswalk), the
    # dictionary's own arrival work) and leaves the stats, which no
    # crosswalk edit can move. The corpus pass remains the reference: the
    # full rebuild and the maintenance rail run it, and the delta grain is
    # test-pinned row-identical to it.
    module ReflexRootsIndexer
      TABLE = :reflex_roots
      STATS_TABLE = :reflex_root_stats

      BATCH_SIZE = 2_000

      # The stale-flag name the closure carries (Store::StaleAggregates);
      # its scope is always "corpus" — the closure is one corpus-wide table.
      CLOSURE_AGGREGATE = "reflex_closure"

      module_function

      # Drop and rebuild the closure + stats tables from +catalog+ into
      # +fulltext+. A catalog without the crosswalk (pre-007, or no recon
      # sync yet) and a fulltext without gold lemmas both leave the tables
      # EMPTY, never missing — queries degrade to "no rows". Returns the
      # closure row count.
      def rebuild!(catalog:, fulltext:)
        fulltext.drop_table?(TABLE)
        fulltext.drop_table?(STATS_TABLE)
        create_tables(fulltext)
        write_stats(fulltext)
        StaleAggregates.clear!(fulltext, aggregate: CLOSURE_AGGREGATE, scope: "corpus")
        write_closure(catalog, fulltext, gold_languages(fulltext))
      end

      # Re-walk the closure ALONE over the gold set the stats record (class
      # note: a crosswalk change, and the maintenance rail's recompute of a
      # stale closure) — no passage_lemmas scan. Clears the stale flag.
      # Returns the closure row count.
      def rebuild_closure!(catalog:, fulltext:)
        fulltext.drop_table?(TABLE)
        create_closure_table(fulltext)
        StaleAggregates.clear!(fulltext, aggregate: CLOSURE_AGGREGATE, scope: "corpus")
        # Stats rows are pruned at zero, so every row IS a gold language.
        gold = (fulltext[STATS_TABLE].exclude(gold_passages: 0).select_map(:language) if
          fulltext.table_exists?(STATS_TABLE))
        write_closure(catalog, fulltext, Array(gold))
      end

      def write_closure(catalog, fulltext, gold)
        return 0 unless catalog.table_exists?(:dictionary_reflexes)
        return 0 if gold.empty?

        rows = closure_rows(entry_meta(catalog), reflex_edges(catalog), gold)
        count = 0
        fulltext.transaction do
          rows.each_slice(BATCH_SIZE) do |batch|
            fulltext[TABLE].multi_insert(batch)
            count += batch.size
          end
        end
        count
      end

      # -- the delta grain (class note) ---------------------------------------

      # The gold contribution of +ids+ to the stats: { language => distinct
      # (passage, language) pairs } — passage_id B-tree bounded, sliced.
      def stats_snapshot(fulltext, ids:)
        counts = Hash.new(0)
        return counts unless fulltext.table_exists?(Indexer::LEMMA_TABLE)

        ids.to_a.each_slice(BATCH_SIZE) do |batch|
          gold_rows(fulltext).where(passage_id: batch).distinct.select(:passage_id, :language)
                             .each { |row| counts[row[:language]] += 1 }
        end
        counts
      end

      # Apply a before → after stats delta; rows reaching zero are pruned
      # (the wholesale build's row set). Returns { entered:, left: } — the
      # languages whose gold count crossed zero, for apply_language_moves!.
      def apply_stats_delta!(fulltext, before:, after:)
        moves = { entered: [], left: [] }
        (before.keys | after.keys).sort.each do |language|
          net = after.fetch(language, 0) - before.fetch(language, 0)
          next if net.zero?

          scope = fulltext[STATS_TABLE].where(language: language)
          current = scope.get(:gold_passages)
          total = (current || 0) + net
          if total <= 0
            scope.delete
            moves[:left] << language if current
          elsif current
            scope.update(gold_passages: total)
          else
            fulltext[STATS_TABLE].insert(language: language, gold_passages: total)
            moves[:entered] << language
          end
        end
        moves
      end

      # Move the closure by the gold-set change (class note): a language
      # that left takes its rows; one that entered — and that the crosswalk
      # names at all — flags the closure stale for the maintenance rail.
      # Returns the languages flagged.
      def apply_language_moves!(catalog:, fulltext:, entered:, left:)
        fulltext[TABLE].where(language: left).delete unless left.empty?
        walk = entered.select do |language|
          catalog.table_exists?(:dictionary_reflexes) &&
            !catalog[:dictionary_reflexes].where(language: language).empty?
        end
        unless walk.empty?
          StaleAggregates.mark!(fulltext, aggregate: CLOSURE_AGGREGATE, scope: "corpus",
                                          reason: "gold language(s) #{walk.join(', ')} entered — the closure " \
                                                  "needs the whole crosswalk walk")
        end
        walk
      end

      def create_tables(fulltext)
        create_closure_table(fulltext)
        create_stats_table(fulltext)
      end

      def create_closure_table(fulltext)
        fulltext.create_table(TABLE) do
          String :language, null: false
          String :lemma_folded, null: false
          String :root_urn, null: false
          TrueClass :borrowed # NULL = a path edge predates the flag reparse
          index %i[language lemma_folded]
        end
      end

      def create_stats_table(fulltext)
        fulltext.create_table(STATS_TABLE) do
          String :language, null: false
          Integer :gold_passages, null: false
          index :language, unique: true
        end
      end

      # Per-language DISTINCT gold passage counts — the suppression
      # denominator, snapshotted from the passage_lemmas built in the same
      # rebuild pass (so the two can never drift). Tier-scoped (class note):
      # a silver passage is not a gold passage.
      def write_stats(fulltext)
        return unless fulltext.table_exists?(Indexer::LEMMA_TABLE)

        rows = gold_rows(fulltext)
               .group(:language)
               .select { [language, count(:passage_id).distinct.as(:gold_passages)] }
               .map { |row| { language: row.fetch(:language), gold_passages: row.fetch(:gold_passages) } }
        fulltext[STATS_TABLE].multi_insert(rows)
      end

      def gold_languages(fulltext)
        return [] unless fulltext.table_exists?(Indexer::LEMMA_TABLE)

        gold_rows(fulltext).distinct.select_map(:language).compact
      end

      # The tier-gold slice of passage_lemmas (class note; P26-4). A
      # pre-tier table has no tier column — and no silver rows — so the
      # unfiltered dataset is the same set.
      def gold_rows(fulltext)
        dataset = fulltext[Indexer::LEMMA_TABLE]
        return dataset unless dataset.columns.include?(:tier)

        dataset.where(tier: Indexer::GOLD_TIER)
      end

      # Live entries only (the withdrawn filter mirrors Etym#entry_dataset):
      # id => { language:, headword_folded:, urn: }.
      def entry_meta(catalog)
        catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionary_entries][:withdrawn] => false)
          .select(Sequel[:dictionary_entries][:id].as(:entry_id),
                  Sequel[:dictionaries][:language].as(:dict_language),
                  Sequel[:dictionary_entries][:headword_folded],
                  Sequel[:dictionary_entries][:urn])
          .to_h do |row|
            [row.fetch(:entry_id), { language: row.fetch(:dict_language),
                                     headword_folded: row.fetch(:headword_folded),
                                     urn: row.fetch(:urn) }]
          end
      end

      # (reflex language, folded form) => { owning entry id => borrowed },
      # over both the word and roman folds, several rows into one entry
      # merged by max_flag (a word/roman pair or duplicate tree nodes are
      # ONE edge). Rows with a nil catalog-side language are display-only,
      # never join candidates (§12); rows of withdrawn entries are filtered
      # by the caller's entry_meta lookup.
      def reflex_edges(catalog)
        edges = Hash.new { |hash, key| hash[key] = {} }
        columns = %i[language word_folded roman_folded dictionary_entry_id]
        # Pre-010 catalog: no flag column — every edge reads nil (unknown).
        columns << :borrowed if catalog[:dictionary_reflexes].columns.include?(:borrowed)
        # Descent rows only: an etymon row (migration 046) names its entry's
        # OWN ancestor — following it would invert the closure.
        descent = ReflexDescent.scope(catalog[:dictionary_reflexes], catalog: catalog)
        descent
          .exclude(language: nil)
          .select(*columns)
          .each do |row|
            [row.fetch(:word_folded), row.fetch(:roman_folded)].compact.uniq.each do |folded|
              next if folded.empty?

              slot = edges[[row.fetch(:language), folded]]
              entry_id = row.fetch(:dictionary_entry_id)
              slot[entry_id] = max_flag(slot.key?(entry_id) ? slot[entry_id] : row[:borrowed],
                                        row[:borrowed])
            end
          end
        edges
      end

      # The closure over the shelf-visited walk, gold-scoped, deduplicated
      # (borrowed by max_flag), and sorted (deterministic across identical
      # inputs — rebuild determinism is a review requirement, not a nicety).
      def closure_rows(meta, edges, gold)
        gold_set = gold.to_set
        rows = {}
        edges.each do |(language, folded), entries|
          next unless gold_set.include?(language)

          root_flags(entries, meta, edges).each do |urn, flag|
            key = [language, folded, urn]
            rows[key] = max_flag(rows.key?(key) ? rows[key] : flag, flag)
          end
        end
        rows.sort_by { |(language, folded, urn), _| [language, folded, urn] }
            .map do |(language, folded, urn), flag|
          { language: language, lemma_folded: folded, root_urn: urn, borrowed: flag }
        end
      end

      # root urn => path-ORed borrowed flag, over the shelf-visited walk
      # from every direct target entry. Withdrawn or unknown entry ids
      # resolve to nothing.
      def root_flags(entries, meta, edges)
        roots = {}
        entries.each do |entry_id, flag|
          entry = meta[entry_id] or next
          merge_root(roots, entry.fetch(:urn), flag)
          ascend(entry_id, entry, flag, meta: meta, edges: edges, roots: roots)
        end
        roots
      end

      # The worklist walk from one direct target: breadth-first ROUNDS, a
      # visited-shelf set seeded with the target's own dictionary language.
      # Newly reached shelves are marked visited only after the whole round,
      # so membership never depends on expansion order within a round.
      def ascend(entry_id, entry, flag, meta:, edges:, roots:)
        visited = Set[entry.fetch(:language)]
        frontier = [[entry_id, flag]]
        until frontier.empty?
          reached = expand_round(frontier, visited, meta: meta, edges: edges, roots: roots)
          visited.merge(reached.map { |id, _| meta.fetch(id).fetch(:language) })
          frontier = reached
        end
      end

      # One round: every (S, headword_folded) naming edge out of the
      # frontier into a not-yet-visited shelf. Returns the next frontier;
      # merges each reached root with its path-ORed flag.
      def expand_round(frontier, visited, meta:, edges:, roots:)
        reached = []
        frontier.each do |entry_id, path_flag|
          entry = meta.fetch(entry_id)
          headword = entry[:headword_folded]
          next if headword.nil? || headword.empty?

          edges.fetch([entry.fetch(:language), headword], {}).each do |ancestor_id, edge_flag|
            ancestor = meta[ancestor_id] or next
            next if visited.include?(ancestor.fetch(:language))

            combined = or_flag(path_flag, edge_flag)
            merge_root(roots, ancestor.fetch(:urn), combined)
            reached << [ancestor_id, combined]
          end
        end
        reached
      end

      def merge_root(roots, urn, flag)
        roots[urn] = max_flag(roots.key?(urn) ? roots[urn] : flag, flag)
      end

      # Path OR, three-valued: a flagged edge makes the path a loan; an
      # unreparsed (nil) edge keeps the path honestly unknown; only an
      # all-false path claims false.
      def or_flag(one, other)
        return true if one == true || other == true
        return nil if one.nil? || other.nil?

        false
      end

      # Cross-path dedup, three-valued max: true > false > nil (a path that
      # POSITIVELY parsed unflagged beats one that was never reparsed).
      # Commutative and associative — merge order cannot matter.
      def max_flag(one, other)
        return true if one == true || other == true
        return false if one == false || other == false

        nil
      end
    end
  end
end
