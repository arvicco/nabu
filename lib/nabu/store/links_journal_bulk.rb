# frozen_string_literal: true

require_relative "links_journal"

module Nabu
  module Store
    # The links journal's BULK edge writer, in its own file on purpose: the
    # links stamps (Nabu::LinkStamps) digest each producer's require
    # closure, and store/links_journal.rb sits in EVERY producer's closure
    # — so this writer lives beside it, required only by the producers that
    # use it (place_mine.rb), and a change here re-mines only them.
    module LinksJournal
      module_function

      INSERT_SLICE = 500

      # Write many edges of one +kind+ for one run — EXACTLY what calling
      # write_edge! once per entry, in order, would leave behind (same rows,
      # same ids, same detail; the same {inserted:, refreshed:} tally), in a
      # few statements instead of three per edge. +edges+ are
      # [from_urn, to_urn, score, detail] tuples.
      #
      # How the per-edge semantics are kept: one probe finds the pairs the
      # journal ALREADY holds (either direction) — those rare entries go
      # through write_edge! itself, which refreshes them in place. Every
      # other pair is new: its first entry becomes an insert (in entry
      # order), and any later entry for the same pair, in either direction,
      # refreshes that pending row (later score/detail win, direction kept)
      # — write_edge!'s refresh rule, applied before the row is written.
      def write_edges!(db, edges, kind:, run_id:, chunk: nil, at: Time.now)
        counts = { inserted: 0, refreshed: 0 }
        return counts if edges.empty?

        held = held_pairs(db, edges, kind)
        pending = {}
        edges.each do |from, to, score, detail|
          if held.include?([from, to]) || held.include?([to, from])
            counts[write_edge!(db, from_urn: from, to_urn: to, kind: kind, score: score, run_id: run_id,
                                   detail: detail, chunk: chunk, at: at)] += 1
          elsif (row = pending[[from, to]] || pending[[to, from]])
            row[:score] = score
            row[:detail] = detail
            counts[:refreshed] += 1
          else
            pending[[from, to]] = { from_urn: from, to_urn: to, kind: kind, score: score, detail: detail,
                                    run_id: run_id, chunk: chunk, created_at: at }
            counts[:inserted] += 1
          end
        end
        pending.values.each_slice(INSERT_SLICE) { |rows| db[:links].multi_insert(rows) }
        counts
      end

      # The [from, to] pairs of +kind+ the journal already holds among
      # +edges+' endpoints, in either direction (two indexed probes).
      def held_pairs(db, edges, kind)
        froms = edges.map(&:first).uniq
        tos = edges.map { |edge| edge[1] }.uniq
        forward = db[:links].where(kind: kind, from_urn: froms, to_urn: tos).select_map(%i[from_urn to_urn])
        reverse = db[:links].where(kind: kind, from_urn: tos, to_urn: froms).select_map(%i[from_urn to_urn])
        (forward + reverse).to_set
      end
    end
  end
end
