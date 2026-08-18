# frozen_string_literal: true

require_relative "catalog_join"

module Nabu
  module Query
    # The sign-coverage graded lane (P77-r16, sign-learning survey P-3):
    # `search --signset "ŠEŠ, AK, DIŠ" [--max-foreign N]` — ATF passages
    # whose resolved sign inventory falls inside the taught set, allowing
    # at most N stranger signs. The Graded (P72-1) architecture verbatim,
    # keyed on OSL top-level sign names: candidates come from the
    # passage_signs rarest-sign columns (r1..r(N+1) IN set — selectivity
    # tracks the answer, never a corpus scan), then the exact subset check
    # verifies each survivor. Inventory entries may be sign names (aliases
    # and form names fold under their parents) or reading values (teaching
    # `ses` implies knowing ŠEŠ — every candidate sign of an ambiguous
    # value joins the set).
    #
    # Passages with STRAY tokens (broken/damaged or unresolvable — the
    # SignInventory census) are excluded: graded reading wants passages
    # the learner can actually finish. Hits order nsigns ASC (cleanest
    # first) and each names its foreign signs — the lesson, not noise.
    class SignGraded
      include CatalogJoin

      # One reading candidate; +foreign+ = signs outside the taught set.
      Result = Data.define(:urn, :language, :text, :document_title, :license_class,
                           :nsigns, :foreign)

      # +indexed+ false = the sign-coverage index is absent (no osl sync,
      # or a pre-r16 fulltext) — honest hint, no scan.
      Outcome = Data.define(:results, :signset_size, :indexed, :capped)

      CANDIDATE_CAP = Graded::CANDIDATE_CAP
      MAX_FOREIGN_CEILING = Graded::MAX_FOREIGN_CEILING

      def initialize(catalog:, fulltext:, sign_list:)
        @catalog = catalog
        @fulltext = fulltext
        @inventory = Nabu::SignInventory.new(sign_list)
      end

      def run(signset:, max_foreign: 0, lang: nil, license: nil, source: nil, limit: 20)
        if max_foreign.negative? || max_foreign > MAX_FOREIGN_CEILING
          raise Nabu::Error, "search: --max-foreign must be 0..#{MAX_FOREIGN_CEILING} " \
                             "(the coverage index carries #{MAX_FOREIGN_CEILING + 1} rarest-sign slots)"
        end

        set = expand_signset(signset)
        return Outcome.new(results: [], signset_size: set.size, indexed: false, capped: false) unless indexed?

        rows, capped = candidate_rows(set, max_foreign, lang: lang, source: source)
        Outcome.new(results: hydrate(rows, lang: lang, license: license, source: source, limit: limit),
                    signset_size: set.size, indexed: true, capped: capped)
      end

      private

      def indexed?
        @fulltext.table_exists?(Nabu::Store::Indexer::PASSAGE_SIGNS_TABLE)
      end

      def table = @fulltext[Nabu::Store::Indexer::PASSAGE_SIGNS_TABLE]

      # Comma/whitespace-separated names and values → the set of top-level
      # sign names. Unknown entries are an ERROR naming each one — a typo
      # in a curriculum must never silently shrink coverage.
      def expand_signset(signset)
        entries = signset.to_s.split(/[,\s]+/).reject(&:empty?)
        raise Nabu::Error, "search: --signset carries no sign names or values" if entries.empty?

        unknown = []
        set = entries.each_with_object(Set.new) do |entry, acc|
          names = @inventory.signs_for(entry)
          names ? names.each { |name| acc << name } : unknown << entry
        end
        unless unknown.empty?
          raise Nabu::Error, "search: --signset entries not in the sign list: #{unknown.join(', ')} " \
                             "(names, aliases, and reading values all resolve; check the spelling)"
        end
        set
      end

      def candidate_rows(set, max_foreign, lang:, source:)
        scope = table
        scope = scope.where(language: lang) if lang
        scope = scope.where(source_id: source_ids(source)) if source
        members = set.to_a
        seen = {}
        capped = false
        (0..max_foreign).each do |slot|
          scope.where("r#{slot + 1}": members).select(:rowid, :nsigns, :signs, :strays).each do |row|
            seen[row[:rowid]] ||= row
            if seen.size >= CANDIDATE_CAP
              capped = true
              break
            end
          end
          break if capped
        end
        [verify(seen.values, set, max_foreign), capped]
      end

      def verify(rows, set, max_foreign)
        rows.filter_map do |row|
          next if row.fetch(:strays).positive?

          foreign = row.fetch(:signs).split(Nabu::Store::Indexer::SIGN_SEP)
                       .reject { |name| set.include?(name) }
          next if foreign.size > max_foreign

          row.merge(foreign: foreign)
        end
      end

      def hydrate(rows, lang:, license:, source:, limit:)
        by_id = rows.to_h { |row| [row.fetch(:rowid), row] }
        catalog_rows(by_id.keys, lang: lang, license: license, source: source)
          .sort_by { |row| [by_id.fetch(row[:passage_id]).fetch(:nsigns), row[:passage_id]] }
          .first(limit)
          .map do |row|
            meta = by_id.fetch(row[:passage_id])
            Result.new(urn: row[:urn], language: row[:language], text: row[:text],
                       document_title: row[:document_title], license_class: row[:license_class],
                       nsigns: meta.fetch(:nsigns), foreign: meta.fetch(:foreign))
          end
      end

      def source_ids(slug)
        @catalog[:sources].where(slug: slug).select_map(:id)
      end
    end
  end
end
