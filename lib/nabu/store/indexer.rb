# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Store
    # Builds the FTS5 fulltext index (architecture §2/§5) from the catalog.
    #
    # == Why the index is not a numbered migration
    #
    # Numbered migrations in db/migrate/ own the CATALOG only — the small,
    # precious, forward-only source of truth. The fulltext index is
    # derived-of-derived (catalog ⇐ canonical): fully disposable, rebuilt at
    # will, and living in its OWN SQLite file (Config#fulltext_path). So its
    # schema is created here, imperatively, on every rebuild — never migrated.
    # Drop the file and re-run and you lose nothing.
    #
    # == The one place a raw SQL string is allowed
    #
    # CLAUDE.md forbids SQL strings outside Sequel datasets. That rule governs
    # QUERY paths (which stay on db[:passages_fts] datasets — see #rebuild!'s
    # multi_insert, and P4-2's MATCH). FTS5 virtual-table DDL has no Sequel
    # dataset API, so CREATE_TABLE below is a raw db.run heredoc. This is scoped
    # to DDL only; no query logic is ever hand-written in SQL.
    #
    # == Diacritic folding (the search form)
    #
    # We index Normalize.fold_diacritics(text_normalized), NOT the raw
    # text_normalized. The tokenizer's `remove_diacritics 2` cannot fold
    # precomposed polytonic Greek (see Normalize.fold_diacritics); folding the
    # content application-side is what actually makes "μῆνιν" findable by
    # "μηνιν". P4-2 search MUST fold the query with the same function.
    module Indexer
      TABLE = :passages_fts

      # Insert in slices so a 238k-passage corpus never materializes at once.
      BATCH_SIZE = 2_000

      # FTS5 DDL (see class note). text_normalized is the sole indexed column;
      # urn + passage_id ride along UNINDEXED so a hit joins back to the catalog
      # (where the pristine text and annotations stay) without duplicating them.
      CREATE_TABLE = <<~SQL
        CREATE VIRTUAL TABLE passages_fts USING fts5(
          text_normalized,
          urn UNINDEXED,
          passage_id UNINDEXED,
          tokenize = 'unicode61 remove_diacritics 2'
        )
      SQL

      module_function

      # Drop and rebuild the whole index from +catalog+ into +fulltext+. Indexes
      # every passage that is itself live AND whose document is live (the
      # two-level visibility rule from P1-4). Bulk + transactional. Returns the
      # number of passages indexed.
      #
      # Reads the catalog through raw datasets (not the Store models) so it is
      # independent of whichever db the global models are currently bound to.
      def rebuild!(catalog:, fulltext:)
        fulltext.drop_table?(TABLE)
        fulltext.run(CREATE_TABLE)

        count = 0
        fulltext.transaction do
          live_passages(catalog).each_slice(BATCH_SIZE) do |batch|
            fulltext[TABLE].multi_insert(batch.map { |row| index_row(row) })
            count += batch.size
          end
        end
        count
      end

      # Streaming dataset of catalog rows for every live passage under a live
      # document. Qualified selects avoid the passages/documents column-name
      # collisions (both carry urn, withdrawn, revision, id). The dataset is
      # Enumerable and streams; #each_slice buffers only one batch at a time.
      def live_passages(catalog)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .select(
            Sequel[:passages][:text_normalized],
            Sequel[:passages][:urn],
            Sequel[:passages][:id].as(:passage_id)
          )
      end

      # Turn a catalog row into an index row, folding diacritics into the
      # search form (class note). Kept separate so the mapping is testable and
      # obviously the only transform applied.
      def index_row(row)
        {
          text_normalized: Nabu::Normalize.fold_diacritics(row.fetch(:text_normalized)),
          urn: row.fetch(:urn),
          passage_id: row.fetch(:passage_id)
        }
      end
    end
  end
end
