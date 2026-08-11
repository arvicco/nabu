# frozen_string_literal: true

module Nabu
  module Query
    # The character-grain vocab profile (P72-4, Edubba FR-4): `nabu vocab
    # URN --chars` — the per-document Han-character frequency profile for
    # UNLEMMATIZED CJK documents (kanripo/cbeta/aozora carry no gold
    # lemmas, so the lemma-grain vocab honestly refuses them; at char
    # grain every sinograph document profiles). On-demand and bounded:
    # one document's live passages, one streaming tally — no index, no
    # scan beyond the document itself.
    #
    # +coverage+ (a charset, fold-expanded exactly as the graded-reading
    # lane's) adds the "which witness do we read next" instrument: what
    # share of the document's character OCCURRENCES the set covers, how
    # many DISTINCT characters fall outside it, and the highest-frequency
    # strangers — the teach-next signal.
    class CharVocab
      Row = Data.define(:char, :count)
      Coverage = Data.define(:charset_size, :occurrence_pct, :distinct_covered,
                             :distinct_total, :strangers)
      Profile = Data.define(:urn, :title, :language, :passages, :total, :distinct,
                            :top, :hapax_count, :hapax, :coverage)

      DEFAULT_LIMIT = 20

      def initialize(catalog:)
        @catalog = catalog
      end

      # nil when no such document; a Han-less document returns an honest
      # zero profile (total 0), never an error.
      def run(urn, limit: DEFAULT_LIMIT, coverage: nil)
        doc = @catalog[:documents].where(urn: urn, withdrawn: false).first
        return nil unless doc

        counts = Hash.new(0)
        passages = 0
        @catalog[:passages].where(document_id: doc[:id], withdrawn: false)
                           .select_map(:text_normalized).each do |text|
          passages += 1
          text.to_s.scan(Nabu::Store::Indexer::HAN).each { |char| counts[char] += 1 }
        end
        build(doc, counts, passages, limit, coverage)
      end

      # The frozen machine contract (the P65/P72-2 pattern): the payload
      # mirrors the Profile shape one-to-one.
      def self.json_payload(urn, profile)
        { "urn" => urn, "profile" => profile && Char.serialize(profile) }
      end

      private

      def build(doc, counts, passages, limit, coverage)
        sorted = counts.sort_by { |char, count| [-count, char] }
        hapax = sorted.select { |_, count| count == 1 }.map(&:first)
        Profile.new(
          urn: doc[:urn], title: doc[:title], language: doc[:language],
          passages: passages, total: counts.values.sum, distinct: counts.size,
          top: sorted.first(limit).map { |char, count| Row.new(char: char, count: count) },
          hapax_count: hapax.size, hapax: hapax.first(limit),
          coverage: coverage && coverage_of(counts, coverage)
        )
      end

      def coverage_of(counts, charset)
        set = charset.to_s.scan(Nabu::Store::Indexer::HAN).flat_map do |char|
          Nabu::Normalize.query_forms(char).flat_map { |form| form.scan(Nabu::Store::Indexer::HAN) } << char
        end.to_set
        raise Nabu::Error, "vocab: --coverage carries no Han characters" if set.empty?

        total = counts.values.sum
        covered_occurrences = counts.sum { |char, count| set.include?(char) ? count : 0 }
        strangers = counts.except(*set)
                          .sort_by { |char, count| [-count, char] }
                          .first(10).map { |char, count| Row.new(char: char, count: count) }
        Coverage.new(
          charset_size: set.size,
          occurrence_pct: total.zero? ? 0.0 : (100.0 * covered_occurrences / total).round(1),
          distinct_covered: counts.count { |char, _| set.include?(char) },
          distinct_total: counts.size, strangers: strangers
        )
      end
    end
  end
end
