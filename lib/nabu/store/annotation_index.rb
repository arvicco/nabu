# frozen_string_literal: true

require_relative "../normalize"
require_relative "../annotation_keys"

module Nabu
  module Store
    # The annotations lane of the fulltext index (architecture §5): FTS
    # over the searchable text layers a source keeps INSIDE its passages'
    # annotations (Nabu::AnnotationKeys — cantus' standardized spelling,
    # korpus16's marginal notes), the second search surface behind
    # `search --annotations`. The sibling of Store::TranslationIndex, same
    # shape and lifecycle; it differs only in its fold.
    #
    # == Shape
    #
    # passages_annotations is CONTENTLESS FTS5: rowid = the catalog
    # passage id of the passage that carries the layer, so a hit names the
    # passage itself; nothing but the inverted index is stored (the layer
    # text lives once, in annotations_json — the query side re-extracts
    # the matched layer per displayed hit only). One row per passage: every
    # declared layer of the passage (each korpus16 note) is folded into
    # the one `annotation` column. `language` and `source` hold the main
    # table's sentinel tokens (Indexer.language_token / source_token), so
    # --lang/--source/--axis filter INSIDE the MATCH.
    #
    # Folding: per the key's declared fold (AnnotationKeys::Spec#fold) —
    # for most keys the PASSAGE's own language (search_form with the
    # passage language: cantus folds Latin, j→i and v→u, korpus16
    # Slovene, ſ→s), exactly as the passage's own text_normalized folds;
    # a metalanguage layer by its declared language (the Socinian
    # letters' German notes keep their j on a Latin letter).
    # The query side folds the main search's way (Normalize.query_forms,
    # the per-language union — fold-both-sides by the P6-4 argument).
    #
    # passages_annotations_scope records, per source, how many passages
    # THIS build indexed — the surface's honest coverage line.
    #
    # == Lifecycle (the translations-lane contract)
    #
    # The reference rebuild derives it whole (stage "annotations"); a sync
    # refreshes the synced source's slice when the lane exists (never
    # bootstraps it); reconcile_stages! and `rake index:annotations`
    # re-derive it standalone over a live catalog, and
    # `rake index:annotations[slug]` (build_source!) derives ONE declared
    # source's slice — creating the lane if absent — without touching the
    # rest. Derived, disposable, never migrated — the Indexer stance.
    module AnnotationIndex
      TABLE = :passages_annotations
      SCOPE_TABLE = :passages_annotations_scope
      STAGE = "annotations"

      # Raw FTS5 DDL — the Indexer's scoped raw-DDL exception (virtual
      # tables have no Sequel API).
      CREATE_TABLE = <<~SQL
        CREATE VIRTUAL TABLE passages_annotations USING fts5(
          annotation,
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
      def rebuild!(catalog:, fulltext:, slugs: AnnotationKeys.slugs, stamp: false)
        fulltext.drop_table?(TABLE)
        fulltext.drop_table?(SCOPE_TABLE)
        create_tables(fulltext)
        total = 0
        sources = 0
        fulltext.transaction do
          slugs.each do |slug|
            source_id = catalog[:sources].where(slug: slug).get(:id)
            next if source_id.nil?

            count = insert_rows(fulltext, source_passages(catalog, source_id, slug), slug)
            fulltext[SCOPE_TABLE].insert(slug: slug, passages: count)
            total += count
            sources += 1
          end
        end
        Indexer.stamp_stages!(fulltext, versions: { STAGE => Indexer::STAGE_VERSIONS.fetch(STAGE) }) if stamp
        { passages: total, sources: sources }
      end

      # The targeted builder: derive ONE declared source's slice without a
      # rebuild, creating the (empty) lane first when the fulltext file
      # predates it. Leaves every other source's rows alone and never
      # advances the stage stamp (a partial lane is not the stage's whole
      # derivation — the next incremental rebuild re-derives it whole).
      # Returns the source's indexed passage count.
      def build_source!(catalog:, fulltext:, slug:)
        unless AnnotationKeys.registered?(slug)
          raise ArgumentError, "#{slug}: not declared in Nabu::AnnotationKeys (declared: " \
                               "#{AnnotationKeys.slugs.join(', ')})"
        end

        create_tables(fulltext) unless built?(fulltext)
        refresh_source!(catalog: catalog, fulltext: fulltext, slug: slug)
      end

      # Re-derive ONE source's slice (sync time). Hands-off (nil) when the
      # lane does not exist or the source is neither registered nor in the
      # last build's scope — the TranslationIndex.refresh_source! contract
      # (delta grain when usable, else the whole slice; a source dropped
      # from the registry loses its rows and scope row). Returns the
      # source's indexed passage count (0 after a drop).
      def refresh_source!(catalog:, fulltext:, slug:, delta: nil, registry_slugs: AnnotationKeys.slugs)
        return nil unless built?(fulltext)

        registered = registry_slugs.include?(slug)
        in_scope = !fulltext[SCOPE_TABLE].where(slug: slug).empty?
        return nil unless registered || in_scope

        source_id = catalog[:sources].where(slug: slug).get(:id)
        fulltext.transaction do
          if registered && in_scope && delta && !delta.overflowed? && source_id
            delete_rowids(fulltext, delta.changed_ids)
            insert_rows(fulltext, ids_scoped(source_passages(catalog, source_id, slug), delta.upserted_ids), slug)
          else
            delete_rowids(fulltext, source_rowids(fulltext, slug))
            insert_rows(fulltext, source_passages(catalog, source_id, slug), slug) if registered && source_id
          end
          fulltext[SCOPE_TABLE].where(slug: slug).delete
          next 0 unless registered && source_id

          count = source_rowids(fulltext, slug).size
          fulltext[SCOPE_TABLE].insert(slug: slug, passages: count)
          count
        end
      end

      # The FTS row for one catalog row, or nil when it carries no layer.
      # Each layer folds by its key's declared choice (class note).
      def row(passage, slug)
        language = passage[:language]
        layers = AnnotationKeys.spec_layers(passage.fetch(:annotations_json), AnnotationKeys.specs_for(slug))
        return nil if layers.empty?

        { rowid: passage.fetch(:passage_id),
          annotation: layers.map { |_label, text, spec| AnnotationKeys.fold(text, spec, language) }.join("\n"),
          language: Indexer.language_token(language),
          source: Indexer.source_token(slug) }
      end

      def create_tables(fulltext)
        fulltext.run(CREATE_TABLE)
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
      # visibility rule plus a LIKE prefilter on the declared key names
      # (AnnotationKeys.spec_layers re-checks exactly; the LIKE only
      # narrows — cantus' "standardized" also matches its text_form value).
      def source_passages(catalog, source_id, slug)
        keys = AnnotationKeys.specs_for(slug).map(&:key).uniq
        return [] if keys.empty?

        annotations = Sequel[:passages][:annotations_json]
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:documents][:source_id] => source_id,
                 Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .where(Sequel.|(*keys.map { |key| Sequel.like(annotations, "%\"#{key}\"%") }))
          .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:language], annotations)
      end

      # Chunked id-scoping of a catalog dataset, streamed for insert_rows.
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
        fulltext[TABLE].where(Sequel.lit("passages_annotations MATCH ?",
                                         %(source : "#{Indexer.source_token(slug)}")))
                       .select_map(:rowid)
      end

      # contentless_delete=1 makes rowid DELETE real (absent rowids no-op).
      def delete_rowids(fulltext, ids)
        ids.to_a.each_slice(BATCH_SIZE) { |batch| fulltext[TABLE].where(rowid: batch).delete }
      end
    end
  end
end
