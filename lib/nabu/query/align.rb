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
      # :not_synced, sentences (empty unless :ok). A multi-document witness
      # (P11-5 `documents:` form) answers with the HIT book's document —
      # document_urn/title name the book that attests the ref; on a miss the
      # title stays nil (naming an arbitrary other book would mislead) while
      # language/license still come from the witness's live documents.
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
        ensure_registry!
        ensure_index!
        target = resolve_work(ref, work)
        normalized = resolve_ref(ref, target)
        Result.new(work: target.id, title: target.title, ref: normalized,
                   witnesses: witnesses(target, normalized))
      end

      private

      def ensure_registry!
        return unless @registry.empty?

        raise Error, "no alignment works registered — add one to config/alignments.yml " \
                     "(architecture §10)"
      end

      # Explicit --work wins; a sole registered work needs no choosing; with
      # several works a bare ref auto-resolves through the index — the whole
      # point of citation lookup is that "MARK 2.3" already says which work
      # it belongs to when exactly one attests it.
      def resolve_work(ref, id)
        return found_work(id) if id

        @registry.sole_work || attesting_work(ref)
      end

      # The works that actually attest +ref+ (registry order): one → picked;
      # several → the honest ambiguity (naming ONLY the attesters); none →
      # not found, with the --work hint for the fragmentary-coverage case.
      def attesting_work(ref)
        attesters = attesting_work_ids(ref)
        case attesters.size
        when 1 then found_work(attesters.first)
        when 0
          raise Error, "#{describe_ref(ref)} is not attested in any registered work " \
                       "(#{@registry.works.map(&:id).join(', ')}) — check the ref, or pick " \
                       "a work with --work"
        else
          raise Error, "several works attest #{describe_ref(ref)} " \
                       "(#{attesters.join(', ')}) — pick one with --work"
        end
      end

      def attesting_work_ids(ref)
        key = if ref.to_s.start_with?("urn:")
                { passage_urn: ref }
              else
                { ref: AlignmentRegistry.normalize_ref(ref) || raise(Error, "align: give a citation ref") }
              end
        attested = refs_table.where(key).distinct.select_map(:work)
        @registry.works.map(&:id).select { |id| attested.include?(id) }
      end

      def describe_ref(ref)
        ref.to_s.start_with?("urn:") ? ref : AlignmentRegistry.normalize_ref(ref).to_s
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
          build_witness(witness, documents,
                        hits.select { |hit| witness.document_urns.include?(hit.fetch(:document_urn)) },
                        rows_by_id, spans, ref)
        end
      end

      def build_witness(witness, documents, hits, rows_by_id, spans, ref)
        live = witness.document_urns.filter_map { |urn| documents[urn] }
        if live.empty?
          return Witness.new(label: witness.label, document_urn: not_synced_urn(witness, ref),
                             title: nil, language: nil, license_class: nil,
                             source_slug: nil, status: :not_synced, sentences: [])
        end

        sentences = hits.filter_map do |hit|
          row = rows_by_id[hit.fetch(:passage_id)]
          next nil if row.nil? # visibility changed since the index was built

          Sentence.new(urn: row.fetch(:urn), text: row.fetch(:text),
                       refs: spans.fetch(hit.fetch(:passage_id)))
        end
        attested_witness(witness, documents, hits, live, sentences)
      end

      # The not-synced example urn: the book the queried ref names, when the
      # witness's map has it — "PSA 22.1" cites the psa urn, never a random
      # first book. A multi-document witness whose map lacks the ref's book
      # has NO relevant urn to cite — nil, so renderers phrase the miss
      # neutrally; a single-document witness keeps its one urn.
      def not_synced_urn(witness, ref)
        book = ref.to_s.split.first
        match = witness.documents.find { |_urn, token| token == book }
        return match.first if match

        witness.document_urns.size == 1 ? witness.document_urn : nil
      end

      # The witness header names the document that ATTESTS the ref: the hit
      # book for a multi-document witness, the sole document otherwise. On a
      # multi-document miss no single book may honestly head the column —
      # title nil, language/license from the live documents (uniform per
      # edition).
      def attested_witness(witness, documents, hits, live, sentences)
        header = hits.first && documents[hits.first.fetch(:document_urn)]
        header ||= live.first if witness.document_urns.size == 1
        Witness.new(
          label: witness.label,
          document_urn: header ? header.fetch(:urn) : witness.document_urn,
          title: header&.fetch(:title),
          language: (header || live.first).fetch(:language),
          license_class: (header || live.first).fetch(:license_class),
          source_slug: (header || live.first).fetch(:source_slug),
          status: sentences.empty? ? :no_match : :ok, sentences: sentences
        )
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
      # per-witness header data (title, language, license label). Multi-
      # document witnesses (P11-5) contribute every book document they span.
      def documents_by_urn(work)
        @catalog[:documents]
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:documents][:urn] => work.witnesses.flat_map(&:document_urns))
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
