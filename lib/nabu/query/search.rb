# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  # Query surface over the derived store (architecture §2: lib/nabu/query/).
  module Query
    # Full-text search: FTS5 MATCH over the diacritic-folded index (P4-1), then
    # a catalog join for display text, language, and license filtering.
    #
    # == Why the query is folded the same way the index is
    #
    # The Indexer stores Normalize.fold_diacritics(text_normalized), because the
    # FTS tokenizer's `remove_diacritics 2` cannot fold precomposed polytonic
    # Greek (see Normalize.fold_diacritics). So the QUERY must pass through the
    # exact same fold — otherwise "μῆνιν" (indexed folded as "μηνιν") would not
    # be found by an accented query, nor an unaccented one by an accented index.
    # We also downcase; unicode61 case-folds both sides, but downcasing keeps the
    # MATCH term canonical regardless of tokenizer settings.
    #
    # == Two-step id join, not ATTACH
    #
    # The index lives in a separate SQLite file from the catalog (architecture
    # §2), so a cross-database JOIN would need ATTACH. Instead we take the FTS
    # hit's passage_ids (in bm25 rank order) and look them up in the catalog with
    # an ordinary Sequel dataset — no raw SQL, no ATTACH, and the catalog join is
    # needed anyway for language/license/withdrawn filtering and pristine text.
    #
    # == License filter semantics (v1)
    #
    # `license: "open"` means EXACTLY the open class — not "at least as open as".
    # A permissiveness ordering ("open ⊇ attribution ⊇ …") is deliberately out of
    # scope for v1; exact-match is predictable and easy to reason about. The
    # effective class is the document's license_override when present, else the
    # source's license_class (the P1-3 override column).
    class Search
      # One search hit. `text` is the pristine passage text (for display);
      # `snippet` is the FTS-generated highlight over the FOLDED index form, so
      # its accents are stripped — it marks WHERE the match is, not how the
      # source spelled it. `license_class` is the effective class after override.
      Result = Data.define(:urn, :language, :text, :snippet, :document_title, :license_class)

      # Snippet markers and window (FTS5 snippet(): table, column, start, end,
      # ellipsis, max tokens). column 0 is text_normalized, the only indexed one.
      SNIPPET_SQL = "snippet(passages_fts, 0, '[', ']', '…', 10)"
      # FTS5 default relevance rank; lower (more negative) is a better match.
      RANK_SQL = "bm25(passages_fts)"

      # Pull more FTS hits than the caller's limit so that catalog-side filtering
      # (language/license) can drop non-matching rows and still fill the page.
      INNER_LIMIT_FACTOR = 10

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      # Search +query+ and return up to +limit+ Result values in bm25 rank order.
      # +lang+ filters on passage language; +license+ on effective license class.
      def run(query, lang: nil, license: nil, limit: 20)
        folded = Nabu::Normalize.fold_diacritics(query.to_s).downcase
        return [] if folded.strip.empty?

        hits = fts_hits(folded, inner_limit: limit * INNER_LIMIT_FACTOR)
        return [] if hits.empty?

        ordered_ids = hits.map { |row| row.fetch(:passage_id) }
        snippets = hits.to_h { |row| [row.fetch(:passage_id), row.fetch(:snippet)] }
        rows = catalog_rows(ordered_ids, lang: lang, license: license)
               .to_h { |row| [row.fetch(:passage_id), row] }

        # Reassemble in FTS rank order (the catalog query returns no order),
        # dropping ids filtered out catalog-side, then trim to the page.
        ordered_ids.filter_map { |id| rows[id] }
                   .first(limit)
                   .map { |row| build_result(row, snippets.fetch(row.fetch(:passage_id))) }
      end

      private

      # FTS5 MATCH. The user's text reaches SQL only as a bound parameter in the
      # MATCH fragment (the one raw-SQL exception, per the Indexer class note);
      # bm25()/snippet() are FTS auxiliary functions with no Sequel dataset API,
      # so they ride along as literal fragments with no user input.
      def fts_hits(folded, inner_limit:)
        @fulltext[Store::Indexer::TABLE]
          .where(Sequel.lit("passages_fts MATCH ?", folded))
          .select(:passage_id, Sequel.lit(SNIPPET_SQL).as(:snippet))
          .order(Sequel.lit(RANK_SQL))
          .limit(inner_limit)
          .all
      end

      # Look the FTS passage_ids up in the catalog, applying the two-level
      # visibility rule (neither passage nor its document withdrawn) plus the
      # optional language and license filters. No ordering: the caller restores
      # the FTS rank order from +ordered_ids+.
      def catalog_rows(passage_ids, lang:, license:)
        dataset = @catalog[:passages]
                  .join(:documents, id: Sequel[:passages][:document_id])
                  .join(:sources, id: Sequel[:documents][:source_id])
                  .where(Sequel[:passages][:id] => passage_ids)
                  .where(Sequel[:passages][:withdrawn] => false,
                         Sequel[:documents][:withdrawn] => false)
        dataset = dataset.where(Sequel[:passages][:language] => lang) if lang
        dataset = dataset.where(license_expr => license) if license
        dataset.select(*catalog_columns).all
      end

      # Effective license class: document override wins over source class (P1-3).
      def license_expr
        Sequel.function(:coalesce,
                        Sequel[:documents][:license_override],
                        Sequel[:sources][:license_class])
      end

      def catalog_columns
        [
          Sequel[:passages][:id].as(:passage_id),
          Sequel[:passages][:urn],
          Sequel[:passages][:language],
          Sequel[:passages][:text],
          Sequel[:documents][:title].as(:document_title),
          license_expr.as(:license_class)
        ]
      end

      def build_result(row, snippet)
        Result.new(
          urn: row.fetch(:urn),
          language: row.fetch(:language),
          text: row.fetch(:text),
          snippet: snippet,
          document_title: row.fetch(:document_title),
          license_class: row.fetch(:license_class)
        )
      end
    end
  end
end
