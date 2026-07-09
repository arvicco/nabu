# frozen_string_literal: true

require_relative "catalog_join"

module Nabu
  module Query
    # `nabu align REF [--work ID]` (P11-3, architecture §10): render one
    # citation of a registered work across every witness the alignment
    # registry names — the five-way parallel New Testament is the flagship.
    #
    # == Why this is Parallel's sibling, not its extension
    #
    # Query::Parallel pairs CTS editions of one work WITHIN a source by
    # citation-suffix equality — a document-lookup mechanism that needs no
    # stored links. The alignment witnesses have nothing suffix-shaped to
    # pair: PROIEL passage urns are sentence ids, and verse identity lives in
    # the stored token annotations. So Align resolves a REGISTRY (which
    # witnesses) plus a derived REF INDEX (which sentences attest the ref;
    # Store::AlignmentIndexer) — a citation-lookup mechanism. Two lookup
    # models, two classes.
    #
    # == Shape of an answer
    #
    # Witnesses come in REGISTRY order (the registry is the display order),
    # each carrying its effective license class (document override ∘ source
    # class — resolved at query time, never stored in the index; the NT
    # witnesses are all `nc`, and the labels are the point) and one of three
    # honest states: :ok with its sentences in sequence order (each labeled
    # with the FULL list of refs it covers — a sentence spanning a verse
    # boundary says so), :no_match (synced, verse not attested — Armenian
    # holds only sampled chapters; never fuzzed), or :not_synced (registered
    # but absent from the catalog — the day-one state of a new witness entry
    # like OE Mark).
    #
    # REF may also be a passage urn (pivot from a show/search hit): the
    # passage's first indexed ref is aligned, and Sentence#refs tells the
    # caller when the sentence covers more.
    #
    # Alignment is a READING surface: two-level visibility applies (the
    # indexer only indexes live passages of live documents), unlike Show's
    # inspection stance.
    class Align
      # A caller-fixable problem (unknown work, ref not found, index not
      # built): the CLI/MCP layers turn the message into exit 1 / isError.
      class Error < Nabu::Error; end

      # One witness's sentence attesting the ref: urn, pristine text, and
      # every ref the sentence covers (its verse span).
      Sentence = Data.define(:urn, :text, :refs)

      # One witness column: registry label, document identity (+ source slug
      # for attribution surfaces), effective license, :ok/:no_match/
      # :not_synced, sentences (empty unless :ok).
      Witness = Data.define(:label, :document_urn, :title, :language, :license_class,
                            :source_slug, :status, :sentences)

      # work/title identify the registry work; ref is the NORMALIZED citation.
      Result = Data.define(:work, :title, :ref, :witnesses)

      include CatalogJoin

      def initialize(catalog:, fulltext:, registry:)
        @catalog = catalog
        @fulltext = fulltext
        @registry = registry
      end

      # Align +ref+ (a citation like "MARK 2.3", or a passage urn to pivot
      # from) across the witnesses of +work+ (default: the sole registered
      # work). Raises Align::Error on every caller-fixable state.
      def run(ref, work: nil)
        target = resolve_work(work)
        ensure_index!
        normalized = resolve_ref(ref, target)
        Result.new(work: target.id, title: target.title, ref: normalized,
                   witnesses: witnesses(target, normalized))
      end

      private

      def resolve_work(id)
        if @registry.empty?
          raise Error, "no alignment works registered — add one to config/alignments.yml " \
                       "(architecture §10)"
        end
        return found_work(id) if id

        @registry.sole_work ||
          raise(Error, "several alignment works are registered " \
                       "(#{@registry.works.map(&:id).join(', ')}) — pick one with --work")
      end

      def found_work(id)
        @registry.work(id) ||
          raise(Error, "unknown alignment work #{id.inspect} — registered: " \
                       "#{@registry.works.map(&:id).join(', ')}")
      end

      def ensure_index!
        return if @fulltext.table_exists?(Store::AlignmentIndexer::TABLE)

        raise Error, "alignment index not built — run nabu sync or nabu rebuild"
      end

      # A urn pivots to the passage's first indexed ref; anything else is
      # folded by the generic normal form (witness book aliases are an INDEX-
      # side mapping into the work vocabulary, which queries speak directly).
      def resolve_ref(ref, work)
        return pivot_ref(ref, work) if ref.to_s.start_with?("urn:")

        AlignmentRegistry.normalize_ref(ref) || raise(Error, "align: give a citation ref")
      end

      def pivot_ref(urn, work)
        refs_table
          .where(work: work.id, passage_urn: urn)
          .order(:ref)
          .get(:ref) ||
          raise(Error, "#{urn} is not aligned under work #{work.id.inspect} — it is either " \
                       "not a known passage urn or not a registered witness's sentence")
      end

      def witnesses(work, ref)
        hits = refs_table.where(work: work.id, ref: ref).order(:seq).all
        rows_by_id = catalog_rows(hits.map { |hit| hit.fetch(:passage_id) }, lang: nil, license: nil)
                     .to_h { |row| [row.fetch(:passage_id), row] }
        spans = ref_spans(work, hits.map { |hit| hit.fetch(:passage_id) })
        documents = documents_by_urn(work)

        work.witnesses.map do |witness|
          build_witness(witness, documents[witness.document_urn],
                        hits.select { |hit| hit.fetch(:document_urn) == witness.document_urn },
                        rows_by_id, spans)
        end
      end

      def build_witness(witness, document, hits, rows_by_id, spans)
        base = { label: witness.label, document_urn: witness.document_urn }
        if document.nil?
          return Witness.new(**base, title: nil, language: nil, license_class: nil,
                                     source_slug: nil, status: :not_synced, sentences: [])
        end

        sentences = hits.filter_map do |hit|
          row = rows_by_id[hit.fetch(:passage_id)]
          next nil if row.nil? # visibility changed since the index was built

          Sentence.new(urn: row.fetch(:urn), text: row.fetch(:text),
                       refs: spans.fetch(hit.fetch(:passage_id)))
        end
        Witness.new(**base, title: document.fetch(:title), language: document.fetch(:language),
                            license_class: document.fetch(:license_class),
                            source_slug: document.fetch(:source_slug),
                            status: sentences.empty? ? :no_match : :ok, sentences: sentences)
      end

      # passage_id => every ref that passage covers under this work, in ref
      # order — what labels a sentence spanning a verse boundary honestly.
      def ref_spans(work, passage_ids)
        refs_table
          .where(work: work.id, passage_id: passage_ids)
          .order(:ref)
          .select_hash_groups(:passage_id, :ref)
      end

      # Live witness documents by urn, with the effective license class — the
      # per-witness header data (title, language, license label).
      def documents_by_urn(work)
        @catalog[:documents]
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:documents][:urn] => work.witnesses.map(&:document_urn))
          .where(Sequel[:documents][:withdrawn] => false)
          .select(Sequel[:documents][:urn], Sequel[:documents][:title],
                  Sequel[:documents][:language], Sequel[:sources][:slug].as(:source_slug),
                  license_expr.as(:license_class))
          .to_h { |row| [row.fetch(:urn), row] }
      end

      def refs_table
        @fulltext[Store::AlignmentIndexer::TABLE]
      end
    end
  end
end
