# frozen_string_literal: true

require_relative "../model/dictionary_entry"
require_relative "../store/reflex_descent"

module Nabu
  module Query
    # The reading surface of the reflex table's ETYMON rows (migration 047:
    # relation inherited / derived / borrowed / learned-borrowing — the
    # kaikki etymology templates). Such a row names the OWNING entry's own
    # ancestor or donor: an UP edge, which every descent walk skips
    # (Store::ReflexDescent). This walks them the other way — the entry's
    # stated etymology, then UP through the shelf:
    #
    # - hop 0: the entry's own etymon rows, in stored order (upstream states
    #   the chain nearest-first: *suka ← *śaukāˀ ← *ḱowk-eh₂).
    # - an etymon the shelf holds as exactly ONE live entry (dictionary
    #   language = the row's catalog language, headword_folded = its
    #   word_folded — the crosswalk's join keys) resolves to that entry's
    #   urn; a homograph-ambiguous or unheld etymon stays nil (the
    #   crossrefs unique-match rule — never a guessed link).
    # - hop n+1: every resolved entry's OWN etymon rows continue the chain
    #   (gmw-pro *hlaib ← gem-pro *hlaibaz ← whatever *hlaibaz states).
    #
    # Termination: a (language, folded word) already on the chain — the
    # start entry's own included — never repeats, an entry is entered once,
    # and the walk is capped at MAX_HOPS rounds / MAX_STEPS steps, so a
    # cyclic or runaway statement set always ends. One indexed query per
    # round for the rows (dictionary_entry_id) and one for the resolution
    # (headword_folded) — no scans.
    #
    # A catalog predating migration 047 has no relation column: every
    # ascent is [] (a READ surface never migrates — the ReflexDescent rule).
    class EtymonAscent
      # One step up. +hop+ is 0 for the entry's own statement, n for a row
      # stated by an entry the walk reached n resolutions up. +urn+ is the
      # etymon's own shelf entry when uniquely held, else nil.
      Step = Data.define(:relation, :lang_code, :language, :word, :roman, :urn, :hop)

      # Termination guards for the climb (rounds of resolution, and the
      # steps one card can carry).
      # const: a walk bound, not a census — kaikki states each entry's
      # chain nearest-first already, so a climb past a few rounds only ever
      # re-reaches what is seen; the step cap keeps a pathological
      # statement set off the card.
      MAX_HOPS = 4
      # const: see MAX_HOPS — the card-length bound of the same walk.
      MAX_STEPS = 16

      def initialize(catalog:)
        @catalog = catalog
      end

      def available?
        return @available unless @available.nil?

        @available = Store::ReflexDescent.relation_column?(@catalog)
      end

      def for_entry(entry_row_id)
        return [] unless available?

        own = etymon_rows([entry_row_id])
        return [] if own.empty? # the common case: one indexed probe, done

        seen = Set[start_key(entry_row_id)]
        entered = Set[entry_row_id]
        frontier = [entry_row_id]
        steps = []
        (0..MAX_HOPS).each do |hop|
          break if frontier.empty? || steps.size >= MAX_STEPS

          rows = (hop.zero? ? own : etymon_rows(frontier)).select { |row| seen.add?(key(row)) }
          targets = resolve(rows)
          rows.each { |row| steps << step(row, urn: targets.dig(key(row), :urn), hop: hop) }
          frontier = targets.values.map { |target| target[:id] }.select { |id| entered.add?(id) }
        end
        steps.first(MAX_STEPS)
      end

      private

      def key(row) = [row[:language], row[:word_folded] || row[:word]]

      # The start entry's own (dictionary language, folded headword): seeds
      # the seen set, so an etymon naming the entry itself never re-enters.
      def start_key(entry_row_id)
        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionary_entries][:id] => entry_row_id)
          .get([Sequel[:dictionaries][:language], Sequel[:dictionary_entries][:headword_folded]])
      end

      # +entry_ids+' etymon rows: per entry in frontier order, each entry's
      # rows in stored order.
      def etymon_rows(entry_ids)
        order = entry_ids.each_with_index.to_h
        @catalog[:dictionary_reflexes]
          .where(dictionary_entry_id: entry_ids, relation: Nabu::DictionaryReflex::ETYMON_RELATIONS)
          .select(:dictionary_entry_id, :seq, :relation, :lang_code, :language, :word, :roman, :word_folded)
          .all
          .sort_by { |row| [order.fetch(row[:dictionary_entry_id]), row[:seq]] }
      end

      # {key => {id:, urn:}} for each row whose (language, word_folded) the
      # shelf holds as exactly one live entry.
      def resolve(rows)
        keyed = rows.select { |row| row[:language] && row[:word_folded] }
        return {} if keyed.empty?

        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionary_entries][:headword_folded] => keyed.map { |row| row[:word_folded] }.uniq,
                 Sequel[:dictionaries][:language] => keyed.map { |row| row[:language] }.uniq,
                 Sequel[:dictionary_entries][:withdrawn] => false)
          .select(Sequel[:dictionary_entries][:id], Sequel[:dictionary_entries][:urn],
                  Sequel[:dictionaries][:language], Sequel[:dictionary_entries][:headword_folded])
          .all
          .group_by { |entry| [entry[:language], entry[:headword_folded]] }
          .select { |_, entries| entries.size == 1 }
          .transform_values { |(entry)| { id: entry[:id], urn: entry[:urn] } }
      end

      def step(row, urn:, hop:)
        Step.new(relation: row[:relation], lang_code: row[:lang_code], language: row[:language],
                 word: row[:word], roman: row[:roman], urn: urn, hop: hop)
      end
    end
  end
end
