# frozen_string_literal: true

require_relative "../normalize"
require_relative "../translation_keys"

module Nabu
  module Store
    # The translations lane of the fulltext index (architecture §5): FTS
    # over the translations a source keeps INSIDE its passages'
    # annotations (Nabu::TranslationKeys — coptic-scriptorium, cdli/ebl
    # ATF #tr lines, hittite-glossed trans_de, corph, …). Translation
    # SIBLING documents need nothing here — they are passages and ride the
    # main passages_fts.
    #
    # == Shape
    #
    # passages_translations is CONTENTLESS FTS5 (the P93-1 shape): rowid =
    # the catalog passage id of the ORIGINAL passage, so a hit names the
    # passage the translation belongs to and the reader jumps straight to
    # it; nothing but the inverted index is stored (the translation text
    # lives once, in the catalog's annotations_json — the query side
    # re-extracts the matched layer for display, per displayed hit only).
    # One row per passage: every registered layer of the passage (English,
    # Arabic, German … all of them) is folded into the one `translation`
    # column, so a passage is one hit however many renderings it carries.
    # `language` (the ORIGINAL passage's language) and `source` hold the
    # main table's sentinel tokens (Indexer.language_token /
    # source_token), so --lang/--source/--axis filter INSIDE the MATCH —
    # never a starved post-filter.
    #
    # Folding: the GENERIC fold (Normalize.search_form with no language —
    # NFC, downcase, mark strip). The layer language is not a passage
    # language and carries no per-language rules worth guessing; the query
    # side folds the same one way (fold-both-sides).
    #
    # passages_translations_scope records, per source, how many passages
    # THIS build indexed — the surfaces' honest coverage line, never a
    # registry claim that may have drifted since.
    #
    # == Lifecycle (the clarify-lane contract)
    #
    # The reference rebuild derives it whole (stage "translations"); a sync
    # refreshes the synced source's slice when the lane exists (a pre-lane
    # index is left alone — never an incremental prerequisite, so no sync
    # bootstraps it); reconcile_stages! and `rake index:translations`
    # re-derive it standalone over a live catalog. Derived, disposable,
    # never migrated — same file and same stance as every Indexer table.
    module TranslationIndex
      TABLE = :passages_translations
      SCOPE_TABLE = :passages_translations_scope
      STAGE = "translations"

      # Raw FTS5 DDL — the Indexer's scoped raw-DDL exception (virtual
      # tables have no Sequel API).
      CREATE_TABLE = <<~SQL
        CREATE VIRTUAL TABLE passages_translations USING fts5(
          translation,
          language,
          source,
          content = '',
          contentless_delete = 1,
          tokenize = 'unicode61 remove_diacritics 2'
        )
      SQL

      # const: a write-batch size (statement bound), not a corpus claim
      BATCH_SIZE = 2_000

      module_function

      def built?(fulltext) = fulltext.table_exists?(TABLE) && fulltext.table_exists?(SCOPE_TABLE)

      # Drop and derive the whole lane over +slugs+ (default: the
      # registry). +stamp+ advances the stage stamp (the standalone/rake
      # path; the reference rebuild stamps every stage itself). Returns
      # {passages:, sources:}.
      def rebuild!(catalog:, fulltext:, slugs: TranslationKeys.slugs, stamp: false)
        fulltext.drop_table?(TABLE)
        fulltext.drop_table?(SCOPE_TABLE)
        fulltext.run(CREATE_TABLE)
        create_scope_table(fulltext)
        total = 0
        sources = 0
        fulltext.transaction do
          slugs.each do |slug|
            source_id = catalog[:sources].where(slug: slug).get(:id)
            next if source_id.nil?

            count = insert_rows(fulltext, source_passages(catalog, source_id), slug)
            fulltext[SCOPE_TABLE].insert(slug: slug, passages: count)
            total += count
            sources += 1
          end
        end
        Indexer.stamp_stages!(fulltext, versions: { STAGE => Indexer::STAGE_VERSIONS.fetch(STAGE) }) if stamp
        { passages: total, sources: sources }
      end

      # Re-derive ONE source's slice (sync time). Hands-off (nil) when the
      # lane does not exist or the source is neither registered nor in the
      # last build's scope. A registered source re-derives — by +delta+
      # (Store::IndexDelta: changed rowids out, upserted rows in) when one
      # is usable, else its whole slice (located through the source
      # sentinel — no catalog id scan); a source the registry has dropped
      # since the last build loses its rows and scope row. Returns the
      # source's indexed passage count (0 after a drop).
      def refresh_source!(catalog:, fulltext:, slug:, delta: nil, registry_slugs: TranslationKeys.slugs)
        return nil unless built?(fulltext)

        registered = registry_slugs.include?(slug)
        in_scope = !fulltext[SCOPE_TABLE].where(slug: slug).empty?
        return nil unless registered || in_scope

        source_id = catalog[:sources].where(slug: slug).get(:id)
        fulltext.transaction do
          if registered && in_scope && delta && !delta.overflowed? && source_id
            delete_rowids(fulltext, delta.changed_ids)
            insert_rows(fulltext, ids_scoped(source_passages(catalog, source_id), delta.upserted_ids), slug)
          else
            delete_rowids(fulltext, source_rowids(fulltext, slug))
            insert_rows(fulltext, source_passages(catalog, source_id), slug) if registered && source_id
          end
          fulltext[SCOPE_TABLE].where(slug: slug).delete
          next 0 unless registered && source_id

          count = source_rowids(fulltext, slug).size
          fulltext[SCOPE_TABLE].insert(slug: slug, passages: count)
          count
        end
      end

      # The FTS row for one catalog row, or nil when it carries no layer.
      def row(passage, slug)
        layers = TranslationKeys.layers(passage.fetch(:annotations_json), TranslationKeys.specs_for(slug))
        return nil if layers.empty?

        { rowid: passage.fetch(:passage_id),
          translation: fold(layers.map(&:last).join("\n")),
          language: Indexer.language_token(passage[:language]),
          source: Indexer.source_token(slug) }
      end

      # The one fold both sides share (class note).
      def fold(text) = Normalize.search_form(text, language: nil)

      def create_scope_table(fulltext)
        fulltext.create_table(SCOPE_TABLE) do
          String :slug, primary_key: true
          Integer :passages, null: false
        end
      end

      def insert_rows(fulltext, passages, slug)
        count = 0
        passages.each_slice(BATCH_SIZE) do |batch|
          rows = batch.filter_map { |passage| row(passage, slug) }
          fulltext[TABLE].multi_insert(rows)
          count += rows.size
        end
        count
      end

      # The source's live passages that MIGHT carry a layer: the two-level
      # visibility rule, plus a LIKE prefilter on the registered key names
      # so the big sources (cdli: 96k layer-bearing of 2.19M) stream only
      # their candidates out of SQLite. TranslationKeys.layers re-checks
      # exactly; the LIKE only narrows.
      def source_passages(catalog, source_id)
        slug = catalog[:sources].where(id: source_id).get(:slug)
        keys = TranslationKeys.specs_for(slug).map(&:key).uniq
        return [] if keys.empty?

        annotations = Sequel[:passages][:annotations_json]
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:documents][:source_id] => source_id,
                 Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .where(Sequel.|(*keys.map { |key| Sequel.like(annotations, "%\"#{key}\"%") }))
          .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:language], annotations)
      end

      # Chunked id-scoping of a catalog dataset (the Indexer.ids_scoped
      # shape), streamed for insert_rows.
      def ids_scoped(dataset, ids)
        Enumerator.new do |y|
          ids.to_a.each_slice(BATCH_SIZE) do |batch|
            dataset.where(Sequel[:passages][:id] => batch).each { |row| y << row }
          end
        end
      end

      # The rowids the lane holds for +slug+, found through the source
      # sentinel column (an FTS posting-list read — no catalog scan).
      def source_rowids(fulltext, slug)
        fulltext[TABLE].where(Sequel.lit("passages_translations MATCH ?",
                                         %(source : "#{Indexer.source_token(slug)}")))
                       .select_map(:rowid)
      end

      # contentless_delete=1 makes rowid DELETE real (absent rowids are a
      # no-op — the CJK lane's delta path relies on the same).
      def delete_rowids(fulltext, ids)
        ids.to_a.each_slice(BATCH_SIZE) { |batch| fulltext[TABLE].where(rowid: batch).delete }
      end
    end
  end
end
