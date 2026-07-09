# frozen_string_literal: true

require "json"

module Nabu
  module Store
    # The alignment-hub citation-ref index (P11-3, architecture §10): one row
    # per (work, normalized ref, passage) for every witness document the
    # alignment registry (config/alignments.yml) names. The P7-5 pattern, third
    # instance: derived from the catalog's STORED annotations_json — never by
    # re-parsing canonical — living in fulltext.sqlite3 with the same
    # drop-and-rebuild lifecycle as the FTS and lemma tables, created here
    # imperatively, never migrated. Rebuild-safety follows: the registry is
    # config, the index is f(catalog, registry), and Indexer.rebuild! (both
    # call sites: sync's reindex, rebuild) regenerates it with re-minted
    # passage ids every time.
    #
    # Why refs and not materialized pairs: pairs are O(witnesses²) rows that go
    # stale the day a sixth witness lands; ref rows are O(passages), and the
    # N-way alignment is Query::Align's GROUP BY ref at query time.
    #
    # Extractors are the CLOSED set AlignmentRegistry::EXTRACTORS validates
    # against. proiel-citation (P11-3): the distinct per-token
    # "citation_part" values of a stored PROIEL/TOROT sentence (the passage-
    # level "citation" field is only the FIRST token's part — a sentence
    # spanning a verse boundary indexes one row per verse covered, which is
    # what makes the verse↔sentence many-to-many honest). cts-verse (P11-5):
    # the witness's registry book token + the passage urn's citation tail
    # ("…tlg001.1st1K-grc1:1.2" under GEN → "GEN 1.2") — verse-grain editions
    # (LXX/Vulgate/SBLGNT) whose verse identity IS the passage urn, no
    # annotations needed. Rows carry NO license and no witness label: both
    # stay query-time lookups (license coalesce in the catalog, label in the
    # registry) so the index can never serve them stale.
    module AlignmentIndexer
      TABLE = :alignment_refs

      BATCH_SIZE = 2_000

      module_function

      # Drop and rebuild the ref table from +catalog+ into +fulltext+ for the
      # witnesses +registry+ names. Registered documents absent from the
      # catalog contribute nothing, silently — a registry may legitimately
      # name a witness before its first sync (the OE Mark day-one state).
      # An empty/nil registry still creates the empty table so queries degrade
      # to "no rows", never "index missing". Returns the row count.
      def rebuild!(catalog:, fulltext:, registry: nil)
        fulltext.drop_table?(TABLE)
        create_table(fulltext)
        return 0 if registry.nil? || registry.empty?

        count = 0
        fulltext.transaction do
          registry.works.each do |work|
            work.witnesses.each do |witness|
              count += index_witness(catalog, fulltext, work, witness)
            end
          end
        end
        count
      end

      def create_table(fulltext)
        fulltext.create_table(TABLE) do
          String :work, null: false
          String :ref, null: false
          String :document_urn, null: false
          Integer :passage_id, null: false
          String :passage_urn, null: false
          Integer :seq, null: false
          index %i[work ref]
          index :passage_urn
        end
      end

      # All (ref, passage) rows for one witness, batched — every document the
      # witness spans (one for the single-`document:` form, one per book for
      # the `documents:` form). Two-level visibility as everywhere: a
      # withdrawn passage or document is not aligned.
      def index_witness(catalog, fulltext, work, witness)
        count = 0
        witness.documents.each do |document_urn, book|
          witness_passages(catalog, document_urn).each_slice(BATCH_SIZE) do |batch|
            rows = batch.flat_map do |row|
              ref_rows(row, work: work, witness: witness, document_urn: document_urn, book: book)
            end
            fulltext[TABLE].multi_insert(rows)
            count += rows.size
          end
        end
        count
      end

      def witness_passages(catalog, document_urn)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:documents][:urn] => document_urn)
          .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .select(
            Sequel[:passages][:id].as(:passage_id),
            Sequel[:passages][:urn],
            Sequel[:passages][:sequence],
            Sequel[:passages][:annotations_json]
          )
      end

      def ref_rows(row, work:, witness:, document_urn:, book:)
        extract_refs(row, witness, document_urn, book).map do |ref|
          {
            work: work.id, ref: ref,
            document_urn: document_urn,
            passage_id: row.fetch(:passage_id),
            passage_urn: row.fetch(:urn),
            seq: row.fetch(:sequence)
          }
        end
      end

      # The witness's extractor, dispatched by name. The registry already
      # validated the name against the closed set; an unknown name here would
      # mean the two lists drifted — fail loudly, not silently empty.
      def extract_refs(row, witness, document_urn, book)
        case witness.extractor
        when "proiel-citation" then proiel_citation_refs(row.fetch(:annotations_json), witness)
        when "cts-verse" then cts_verse_refs(row.fetch(:urn), witness, document_urn, book)
        else
          raise Nabu::Error, "alignment extractor #{witness.extractor.inspect} is not implemented"
        end
      end

      # The passage urn's citation tail, prefixed with the registry book
      # token and folded ("1.2" under GEN → "GEN 1.2"; a single-chapter
      # book's flat tail folds to "LJE 5" and stays addressable). A passage
      # urn that does not extend its document urn has no citation tail —
      # skipped, never guessed.
      def cts_verse_refs(passage_urn, witness, document_urn, book)
        tail = passage_urn.delete_prefix("#{document_urn}:")
        return [] if tail == passage_urn || tail.empty?

        [witness.normalize_ref("#{book} #{tail}")].compact
      end

      # The distinct normalized citation_part values of the stored tokens.
      # The cheap substring probe skips the JSON parse for non-annotated
      # passages (the Indexer's established trick); annotations_json is our own
      # canonical output, so a parse failure is corruption and raises.
      def proiel_citation_refs(json, witness)
        return [] if json.nil? || !json.include?('"citation_part"')

        tokens = JSON.parse(json)["tokens"]
        return [] unless tokens.is_a?(Array)

        tokens.filter_map { |token| witness.normalize_ref(token["citation_part"]) if token.is_a?(Hash) }
              .uniq
      end
    end
  end
end
