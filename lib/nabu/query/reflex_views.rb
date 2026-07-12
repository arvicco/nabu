# frozen_string_literal: true

require_relative "../store/indexer"

module Nabu
  module Query
    # The reconstruction crosswalk's read side (P14-1, architecture §12),
    # shared by Define (reflex display on reconstruction entries) and Etym
    # (cognate lists): fetch an entry's stored reflex edges and resolve
    # attestation counts against the fulltext lemma index AT QUERY TIME —
    # nothing resolved is ever stored (the §10/§11 stance).
    #
    # +attested_count+ is the number of gold-lemma passages whose folded
    # lemma equals the reflex's word_folded — or, failing that, its
    # roman_folded (the script bridge: Gothic 𐌲𐌿𐌸 counts via "guþ").
    # nil means "not in this catalog / not countable" — an honest absence,
    # never a zero claim (no fulltext handle, display-only language, or the
    # lemma simply is not attested here).
    class ReflexViews
      View = Data.define(:lang_code, :language, :word, :roman, :attested_count)

      def initialize(catalog:, fulltext: nil)
        @catalog = catalog
        @fulltext = fulltext
      end

      def available?
        @catalog.table_exists?(:dictionary_reflexes)
      end

      # The entry's reflexes in stored (depth-first) order, counts resolved.
      def for_entry(entry_row_id)
        return [] unless available?

        rows = @catalog[:dictionary_reflexes]
               .where(dictionary_entry_id: entry_row_id)
               .order(:seq)
               .select(:lang_code, :language, :word, :roman, :word_folded, :roman_folded)
               .all
        counts = attestation_counts(rows)
        rows.map do |row|
          View.new(
            lang_code: row.fetch(:lang_code), language: row.fetch(:language),
            word: row.fetch(:word), roman: row.fetch(:roman),
            attested_count: counts[[row.fetch(:language), row.fetch(:word_folded)]] ||
                            counts[[row.fetch(:language), row.fetch(:roman_folded)]]
          )
        end
      end

      private

      # One grouped count query per distinct language among the rows.
      # Display-only rows (language nil) and unfolded forms never join.
      def attestation_counts(rows)
        return {} unless lemma_index?

        rows.group_by { |row| row.fetch(:language) }.each_with_object({}) do |(language, group), out|
          next if language.nil?

          folded = group.flat_map { |row| [row.fetch(:word_folded), row.fetch(:roman_folded)] }.compact.uniq
          next if folded.empty?

          @fulltext[Store::Indexer::LEMMA_TABLE]
            .where(language: language, lemma_folded: folded)
            .group_and_count(:lemma_folded)
            .each { |row| out[[language, row.fetch(:lemma_folded)]] = row.fetch(:count) }
        end
      end

      def lemma_index?
        !@fulltext.nil? && @fulltext.table_exists?(Store::Indexer::LEMMA_TABLE)
      end
    end
  end
end
