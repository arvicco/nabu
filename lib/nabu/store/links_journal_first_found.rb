# frozen_string_literal: true

require_relative "links_journal"

module Nabu
  module Store
    # The links journal's bulk FIRST-FOUND writer — the postings engine's
    # single committer (Nabu::BatchParallelsPostings). Its own file for the
    # links_journal_bulk.rb reason: the links stamps digest each producer's
    # require closure, so a writer lives beside the journal and is required
    # only by the producer that uses it.
    module LinksJournal
      module_function

      FIRST_FOUND_SLICE = 500

      # Write many edges of one +kind+ for one run with EXACTLY the outcome
      # of calling write_edge!(first_in_run: true) once per entry, in
      # order — the batch parallels contract — in a handful of statements:
      #
      # - an unordered pair THIS run already holds is :kept untouched;
      # - a pair another run holds is :refreshed in place (score, detail,
      #   run, chunk, time; its discovery direction kept) — after which this
      #   run owns it, so a later entry for it is :kept;
      # - a new pair is :inserted in the direction of its FIRST entry; every
      #   later entry for it, in either direction, is :kept.
      #
      # Pairs are keyed SORTED ([a, b].minmax), so the rule is deterministic
      # whatever direction an entry names; "first" is entry order, which the
      # committer delivers in anchor urn order. +edges+ are [from_urn,
      # to_urn, score, detail] tuples. Returns {inserted:, refreshed:, kept:}.
      def write_edges_first_found!(db, edges, kind:, run_id:, chunk: nil, at: Time.now)
        counts = { inserted: 0, refreshed: 0, kept: 0 }
        return counts if edges.empty?

        held = held_edges(db, edges, kind)
        pending = {}
        edges.each do |from, to, score, detail|
          pair = [from, to].minmax
          if (row = held[pair])
            if row[:run_id] == run_id
              counts[:kept] += 1
            else
              db[:links].where(id: row[:id]).update(score: score, detail: detail, run_id: run_id, chunk: chunk,
                                                    created_at: at)
              row[:run_id] = run_id
              counts[:refreshed] += 1
            end
          elsif pending.key?(pair)
            counts[:kept] += 1
          else
            pending[pair] = { from_urn: from, to_urn: to, kind: kind, score: score, detail: detail,
                              run_id: run_id, chunk: chunk, created_at: at }
            counts[:inserted] += 1
          end
        end
        pending.values.each_slice(FIRST_FOUND_SLICE) { |rows| db[:links].multi_insert(rows) }
        counts
      end

      # { sorted pair => {id:, run_id:} } for the pairs of +kind+ the
      # journal holds among +edges+' endpoints. Both ends of a held pair are
      # endpoints, so probing by from_urn alone (the from_urn/kind index)
      # finds it in whichever direction it was stored.
      def held_edges(db, edges, kind)
        ends = edges.flat_map { |edge| edge.first(2) }.uniq
        wanted = ends.to_set
        ends.each_slice(FIRST_FOUND_SLICE).with_object({}) do |slice, held|
          db[:links].where(kind: kind, from_urn: slice).select(:id, :from_urn, :to_urn, :run_id).each do |row|
            next unless wanted.include?(row[:to_urn])

            held[[row[:from_urn], row[:to_urn]].minmax] = { id: row[:id], run_id: row[:run_id] }
          end
        end
      end
    end
  end
end
