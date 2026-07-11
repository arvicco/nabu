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

      # One witness's sentence attesting the ref: urn, pristine text, every ref
      # the sentence covers (its verse span), and — for a witness whose
      # numbering differs from the work vocabulary (P13-5) — its WITNESS-NATIVE
      # ref (the psalter's own number, e.g. Hebrew "PSA 23.1" for work
      # "PSA 22.1"); nil when the witness numbers as the work does.
      Sentence = Data.define(:urn, :text, :refs, :native_ref)

      # One witness column: registry label, document identity (+ source slug
      # for attribution surfaces), effective license, :ok/:no_match/
      # :not_synced, sentences (empty unless :ok). A multi-document witness
      # (P11-5 `documents:` form) answers with the HIT book's document —
      # document_urn/title name the book that attests the ref; on a miss the
      # title stays nil (naming an arbitrary other book would mislead) while
      # language/license still come from the witness's live documents.
      Witness = Data.define(:label, :document_urn, :title, :language, :license_class,
                            :source_slug, :status, :sentences, :numbering)

      # work/title identify the registry work; ref is the NORMALIZED citation.
      Result = Data.define(:work, :title, :ref, :witnesses)

      # One ref of a range/chapter query with its witnesses (the single-ref
      # Result.witnesses shape, per ref). +witnesses+ carries only the
      # witnesses present somewhere in the range — those absent from EVERY ref
      # are lifted to RangeResult#absent (P11-9).
      RefGroup = Data.define(:ref, :witnesses)

      # A witness absent from every rendered ref of a range/chapter query
      # (P11-9): summarized ONCE in the header and dropped from the per-ref
      # groups, so a chapter does not repeat "not attested"/"not synced" down
      # the page (the owner's readability complaint). +reason+ is
      # :not_attested (live documents, but the range's verses are absent) or
      # :not_synced (registered, no live documents at all).
      AbsentWitness = Data.define(:label, :reason)

      # A range/chapter query (P11-8): the work/title, the NORMALIZED query
      # string ("JON 1", "JON 1.1-1.16"), the rendered ref groups in document
      # order, the TOTAL matching refs, whether the cap clipped them, and the
      # witnesses absent across the WHOLE range (P11-9 — summarized once, not
      # per ref).
      RangeResult = Data.define(:work, :title, :query, :groups, :total, :truncated, :absent)

      # Rendered-ref cap for a range/chapter query — an honest ceiling on one
      # screenful, mirroring nabu_define's body cap. Beyond it the result is
      # truncated with a note (narrow the range).
      MAX_REFS = 200

      # The range separator in a citation-range query. As in Query::Range, the
      # split is on the LAST hyphen: verse citations ("1.16") hold no hyphens,
      # so the tail is always a bare end suffix reconstructed against the
      # start's book.
      RANGE_SEP = "-"
      private_constant :RANGE_SEP

      # A parsed range/chapter query: the book token, the kind (:chapter or
      # :range), and the citation bounds (chapter number, or start/end verse
      # suffixes), plus the normalized query string for display.
      RangeSpec = Data.define(:book, :kind, :chapter, :start_cite, :end_cite, :query)
      private_constant :RangeSpec

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
        spec = range_spec(ref)
        return run_range(spec, work: work) if spec

        target = resolve_work(ref, work)
        normalized = resolve_ref(ref, target)
        Result.new(work: target.id, title: target.title, ref: normalized,
                   witnesses: witnesses(target, normalized))
      end

      private

      # -- range / chapter (P11-8) ---------------------------------------------

      # Parse +ref+ into a RangeSpec, or nil when it is a single ref / urn
      # pivot (the existing path). A range holds a hyphen ("JON 1.1-1.16"); a
      # chapter is a book plus a bare number ("JON 1"). A concrete verse ("JON
      # 1.1", dotted) and a urn are NOT ranges — they stay single.
      def range_spec(ref)
        return nil if ref.to_s.start_with?("urn:")

        norm = AlignmentRegistry.normalize_ref(ref)
        return nil if norm.nil?

        book, rest = norm.split(" ", 2)
        return nil if rest.nil? || book.empty?

        if rest.include?(RANGE_SEP)
          start_cite, _sep, end_cite = rest.rpartition(RANGE_SEP)
          return nil if start_cite.empty? || end_cite.empty?

          RangeSpec.new(book: book, kind: :range, chapter: nil,
                        start_cite: start_cite, end_cite: end_cite, query: norm)
        elsif rest.match?(/\A\d+\z/)
          RangeSpec.new(book: book, kind: :chapter, chapter: rest,
                        start_cite: nil, end_cite: nil, query: norm)
        end
      end

      def run_range(spec, work:)
        validate_range!(spec)
        target = resolve_range_work(spec, work)
        cites = ordered_cites(target, spec)
        if cites.empty?
          raise Error, "no attested refs for #{spec.query} in work #{target.id.inspect} — check the " \
                       "book/chapter, or that its witnesses are synced (nabu status)"
        end

        total = cites.size
        truncated = total > MAX_REFS
        documents = documents_by_urn(target)
        groups = (truncated ? cites.first(MAX_REFS) : cites).map do |cite|
          ref = "#{spec.book} #{cite}"
          RefGroup.new(ref: ref, witnesses: witnesses(target, ref, documents))
        end
        present_groups, absent = lift_absent_witnesses(groups)
        RangeResult.new(work: target.id, title: target.title, query: spec.query,
                        groups: present_groups, total: total, truncated: truncated, absent: absent)
      end

      # Partition the range's witnesses into those present somewhere (:ok in at
      # least one ref — kept per-ref, "— not attested" lines and all) and those
      # absent from EVERY ref (lifted to the header summary and dropped from the
      # per-ref groups). Witness order is the registry order the groups carry.
      def lift_absent_witnesses(groups)
        return [groups, []] if groups.empty?

        absent = []
        present_labels = groups.first.witnesses.filter_map do |column|
          views = groups.map { |group| group.witnesses.find { |witness| witness.label == column.label } }
          next column.label if views.any? { |witness| witness.status == :ok }

          reason = views.all? { |witness| witness.status == :not_synced } ? :not_synced : :not_attested
          absent << AbsentWitness.new(label: column.label, reason: reason)
          nil
        end
        present_groups = groups.map do |group|
          RefGroup.new(ref: group.ref,
                       witnesses: group.witnesses.select { |witness| present_labels.include?(witness.label) })
        end
        [present_groups, absent]
      end

      # A reversed verse range is a caller error, named as Query::Range names
      # it (endpoint order is independent of which work attests it).
      def validate_range!(spec)
        return unless spec.kind == :range
        return if cite_compare(cite_key(spec.start_cite), cite_key(spec.end_cite)) <= 0

        raise Error, "reversed range: #{spec.book} #{spec.start_cite} comes after " \
                     "#{spec.book} #{spec.end_cite}; swap the endpoints"
      end

      # Explicit --work wins; a sole work needs no choosing; otherwise the
      # query auto-resolves through the index (the works with any matching ref)
      # — the same three honest outcomes as the single-ref path.
      def resolve_range_work(spec, id)
        return found_work(id) if id
        return @registry.sole_work if @registry.sole_work

        attesters = @registry.works.select { |work| ordered_cites(work, spec).any? }.map(&:id)
        case attesters.size
        when 1 then found_work(attesters.first)
        when 0
          raise Error, "#{spec.query} is not attested in any registered work " \
                       "(#{@registry.works.map(&:id).join(', ')}) — check the ref, or pick " \
                       "a work with --work"
        else
          raise Error, "several works attest #{spec.query} " \
                       "(#{attesters.join(', ')}) — pick one with --work"
        end
      end

      # The work's citation suffixes matching +spec+ (chapter members, or the
      # inclusive verse range), distinct and in document (numeric-citation)
      # order. Only refs at least one witness attests exist in the index — a
      # verse no witness holds simply does not appear, which is the honest
      # coverage of the range.
      def ordered_cites(work, spec)
        candidates = candidate_cites(work, spec.book)
        selected =
          case spec.kind
          when :chapter
            candidates.select { |cite| chapter_member?(cite, spec.chapter) }
          when :range
            lo = cite_key(spec.start_cite)
            hi = cite_key(spec.end_cite)
            candidates.select do |cite|
              key = cite_key(cite)
              cite_compare(lo, key) <= 0 && cite_compare(key, hi) <= 0
            end
          end
        selected.sort { |a, b| cite_compare(cite_key(a), cite_key(b)) }
      end

      # Distinct citation suffixes (the part after "BOOK ") of the work's refs
      # for +book+. Book tokens are alphanumeric, so the LIKE pattern carries no
      # metacharacters of its own.
      def candidate_cites(work, book)
        refs_table
          .where(work: work.id)
          .where(Sequel.like(:ref, "#{book} %"))
          .distinct
          .select_map(:ref)
          .map { |ref| ref.delete_prefix("#{book} ") }
      end

      def chapter_member?(cite, chapter)
        cite == chapter || cite.start_with?("#{chapter}.")
      end

      # A citation suffix as a comparable key: dot-separated segments, numeric
      # where they are all digits ("1.16" → [1, 16]), so verses sort in true
      # numeric (document) order rather than lexically ("1.9" before "1.10").
      def cite_key(cite)
        cite.split(".").map { |seg| seg.match?(/\A\d+\z/) ? Integer(seg) : seg }
      end

      # Element-wise compare of two citation keys, tolerant of mixed segment
      # types (a subverse "12a" stays a String) — numeric where both segments
      # are integers, string otherwise; the shorter shared-prefix key sorts
      # first ("1" before "1.1").
      def cite_compare(first, second)
        first.each_index do |i|
          return 1 if i >= second.length

          cmp = compare_segment(first[i], second[i])
          return cmp unless cmp.zero?
        end
        first.length <=> second.length
      end

      def compare_segment(left, right)
        return left <=> right if left.is_a?(Integer) && right.is_a?(Integer)

        left.to_s <=> right.to_s
      end

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

      # +documents+ is hoisted by the range path (constant across a work's
      # refs) and defaults to a fresh fetch for the single-ref path.
      def witnesses(work, ref, documents = documents_by_urn(work))
        hits = refs_table.where(work: work.id, ref: ref).order(:seq).all
        rows_by_id = catalog_rows(hits.map { |hit| hit.fetch(:passage_id) }, lang: nil, license: nil)
                     .to_h { |row| [row.fetch(:passage_id), row] }
        spans = ref_spans(work, hits.map { |hit| hit.fetch(:passage_id) })

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
                             source_slug: nil, status: :not_synced, sentences: [],
                             numbering: witness.numbering&.system)
        end

        sentences = hits.filter_map do |hit|
          row = rows_by_id[hit.fetch(:passage_id)]
          next nil if row.nil? # visibility changed since the index was built

          Sentence.new(urn: row.fetch(:urn), text: row.fetch(:text),
                       refs: spans.fetch(hit.fetch(:passage_id)),
                       native_ref: native_ref(witness, hit.fetch(:document_urn), row.fetch(:urn), ref))
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
          status: sentences.empty? ? :no_match : :ok, sentences: sentences,
          numbering: witness.numbering&.system
        )
      end

      # The witness-native ref for a sentence when the witness renumbers (the
      # psalter's own psalm.verse from the passage urn, e.g. Hebrew "PSA 23.1"
      # under work-vocabulary "PSA 22.1") — nil for a witness that numbers as
      # the work does, or when the native ref happens to equal the work ref (an
      # identity-mapped psalm: nothing diverges, nothing to flag).
      def native_ref(witness, document_urn, passage_urn, work_ref)
        return nil unless witness.numbering

        tail = passage_urn.delete_prefix("#{document_urn}:")
        return nil if tail == passage_urn || tail.empty?

        native = AlignmentRegistry.normalize_ref("#{witness.book_for(document_urn)} #{tail}")
        native == work_ref ? nil : native
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
