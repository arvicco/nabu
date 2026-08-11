# frozen_string_literal: true

require_relative "catalog_join"

module Nabu
  module Query
    # The graded-reading lane (P72-1, Edubba FR-1): `search --charset "…"
    # [--max-foreign N]` — passages whose distinct Han characters fall
    # inside the given set, allowing at most N outsiders. The candidate
    # path is the P72 coverage index (fulltext `passage_chars`): a passage
    # with ≤N foreign chars must carry one of its N+1 RAREST chars inside
    # the charset, so candidates come from indexed r1..r(N+1) IN (charset)
    # lookups — selectivity tracks the ANSWER size, never a corpus scan —
    # and the exact subset check verifies each survivor. Fold-both-sides:
    # every charset member expands through Normalize.query_forms, so 學
    # covers the folded 学 the index stores and vice versa.
    #
    # A text query composes as SUBSTRING containment over the candidate
    # set (never via FTS: a spaceless CJK run is ONE FTS token — the
    # survey's clause-run finding — so 子曰 would match only exact-clause
    # passages there). Hits are ordered by nchars ASC (the cleanest,
    # shortest readings first — the pedagogical order), and each hit
    # NAMES its foreign characters: the ≤N strangers are the lesson,
    # not noise.
    class Graded
      include CatalogJoin

      # One reading candidate; +foreign+ = the chars outside the set.
      Result = Data.define(:urn, :language, :text, :document_title, :license_class,
                           :nchars, :foreign)

      # +indexed+ false = the coverage index is absent (honest hint, no
      # scan); +capped+ true = the candidate window filled before the
      # corpus was exhausted (more may exist).
      Outcome = Data.define(:results, :charset_size, :indexed, :capped)

      # const: the r-slice candidate window — a fetch bound, not a corpus
      # count; announced via +capped+ when reached.
      CANDIDATE_CAP = 200_000

      # --max-foreign ceiling: the index stores RAREST_SLOTS rarest chars,
      # and the candidate argument needs N+1 of them.
      MAX_FOREIGN_CEILING = Nabu::Store::Indexer::RAREST_SLOTS - 1

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      def run(query = nil, charset:, max_foreign: 0, lang: nil, license: nil,
              source: nil, limit: 20)
        if max_foreign.negative? || max_foreign > MAX_FOREIGN_CEILING
          raise Nabu::Error, "search: --max-foreign must be 0..#{MAX_FOREIGN_CEILING} " \
                             "(the coverage index carries #{MAX_FOREIGN_CEILING + 1} rarest-char slots)"
        end

        set = expand_charset(charset)
        raise Nabu::Error, "search: --charset carries no Han characters" if set.empty?
        return Outcome.new(results: [], charset_size: set.size, indexed: false, capped: false) unless indexed?

        rows, capped = candidate_rows(set, max_foreign, lang: lang, source: source)
        rows = query_narrowed(rows, query) unless query.to_s.strip.empty?
        Outcome.new(results: hydrate(rows, lang: lang, license: license, source: source, limit: limit),
                    charset_size: set.size, indexed: true, capped: capped)
      end

      private

      def indexed?
        @fulltext.table_exists?(Nabu::Store::Indexer::PASSAGE_CHARS_TABLE)
      end

      def table = @fulltext[Nabu::Store::Indexer::PASSAGE_CHARS_TABLE]

      # Fold-both-sides membership: each input char joins the set along with
      # every fold variant a query would match under (Han only; spaces and
      # punctuation in the input are ignored).
      def expand_charset(charset)
        charset.to_s.scan(Nabu::Store::Indexer::HAN).flat_map do |char|
          Nabu::Normalize.query_forms(char).flat_map { |form| form.scan(Nabu::Store::Indexer::HAN) } << char
        end.to_set
      end

      # The index path: union of r1..r(N+1) IN charset slices, deduped by
      # rowid, exact-verified. Source/lang narrow in SQL (the index carries
      # both); license needs the catalog join and rides in hydrate.
      def candidate_rows(set, max_foreign, lang:, source:)
        scope = table
        scope = scope.where(language: lang) if lang
        scope = scope.where(source_id: source_ids(source)) if source
        members = set.to_a
        seen = {}
        capped = false
        (0..max_foreign).each do |slot|
          scope.where("r#{slot + 1}": members).select(:rowid, :nchars, :chars).each do |row|
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

      # The query-composed narrow: keep candidates whose FOLDED text
      # contains any fold variant of the query — one bounded id-set LIKE,
      # never an FTS term match (class doc).
      def query_narrowed(rows, query)
        variants = Nabu::Normalize.query_forms(query.to_s).reject { |v| v.strip.empty? }
        return rows if variants.empty?

        containment = Sequel.|(*variants.map do |variant|
          Sequel.like(Sequel[:passages][:text_normalized], "%#{escape_like(variant)}%")
        end)
        ids = @catalog[:passages].where(id: rows.map { |row| row.fetch(:rowid) })
                                 .where(containment).select_map(:id).to_set
        rows.select { |row| ids.include?(row.fetch(:rowid)) }
      end

      def escape_like(text) = text.gsub(/[\\%_]/) { |ch| "\\#{ch}" }

      def verify(rows, set, max_foreign)
        rows.filter_map do |row|
          foreign = row.fetch(:chars).each_char.reject { |char| set.include?(char) }
          next if foreign.size > max_foreign

          row.merge(foreign: foreign)
        end
      end

      # Pull the display rows through the shared visibility join (license
      # applies as the effective class there); order = nchars ASC, the
      # cleanest reading first.
      def hydrate(rows, lang:, license:, source:, limit:)
        by_id = rows.to_h { |row| [row.fetch(:rowid), row] }
        catalog_rows(by_id.keys, lang: lang, license: license, source: source)
          .sort_by { |row| [by_id.fetch(row[:passage_id]).fetch(:nchars), row[:passage_id]] }
          .first(limit)
          .map do |row|
            meta = by_id.fetch(row[:passage_id])
            Result.new(urn: row[:urn], language: row[:language], text: row[:text],
                       document_title: row[:document_title], license_class: row[:license_class],
                       nchars: meta.fetch(:nchars), foreign: meta.fetch(:foreign))
          end
      end

      def source_ids(slug)
        @catalog[:sources].where(slug: slug).select_map(:id)
      end
    end
  end
end
