# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_align tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      ALIGN_DESCRIPTION =
        "Cross-source alignment over the local nabu corpus: one citation of a registered work " \
        "rendered across EVERY witness the alignment registry names — e.g. the same New " \
        "Testament verse in Greek, Latin, Gothic, Classical Armenian, and Old Church Slavonic " \
        "at once. `ref` is a citation in the work's scheme (\"MARK 2.3\"; case/spacing/" \
        "chapter:verse colons normalize) or a passage urn to pivot from a search/show hit. " \
        "`work` picks the registry work when several exist (optional with one). Witnesses come " \
        "in registry order; each carries its language and license_class (the NT witnesses are " \
        "nc — PRESERVE the license fields when quoting), and every sentence row carries urn + " \
        "language + license_class + source. Sentence≠verse: a sentence spanning a verse " \
        "boundary lists every ref it covers. Honest absence: a witness lacking the verse reads " \
        "status no_match; a registered-but-unsynced witness reads not_synced. `ref` may also be " \
        "a whole CHAPTER (\"JON 1\") or an inclusive same-book verse RANGE (\"JON 1.1-1.16\"): " \
        "the reply is a `refs` array, one entry per ref in document order (each with the same " \
        "witness columns), capped at #{MAX_ALIGN_REFS} with an honest truncation note. Witnesses " \
        "absent from EVERY ref of a range are summarized once in `absent_witnesses` " \
        "(reason not_attested|not_synced) and omitted from the per-ref columns, so a chapter stays " \
        "readable. A SINGLE ref folds the same way by default: witnesses with nothing at the ref " \
        "(no_match / not_synced) collapse into `absent_witnesses` (label + reason) with " \
        "`absent_counts`, and only attesting/withheld witnesses keep full blocks; `long: true` " \
        "restores every witness column. `collate: true` returns a witness DIFF instead: a raw-token apparatus per " \
        "(language, script) cell (base reading + each witness's divergences), with cross-script " \
        "witnesses rendered undiffed and labelled honestly — the fold cannot bridge e.g. the " \
        "Cyrillic Marianus and the Helsinki-ASCII CCMH codices.".freeze

      ALIGN_SCHEMA = {
        type: "object",
        properties: {
          ref: { type: "string",
                 description: "Citation in the work's scheme (e.g. \"MARK 2.3\"), a whole " \
                              "chapter (\"JON 1\"), an inclusive same-book verse range " \
                              "(\"JON 1.1-1.16\"), or a passage urn to pivot from." },
          work: { type: "string",
                  description: "Alignment work id from the registry (optional when exactly " \
                               "one work is registered)." },
          collate: { type: "boolean",
                     description: "Diff the witnesses instead of listing them: a raw-token " \
                                  "apparatus per (language, script) cell — base reading plus each " \
                                  "witness's divergences only; cross-script witnesses rendered " \
                                  "undiffed and labelled honestly (the fold cannot bridge e.g. the " \
                                  "Cyrillic Marianus and the Helsinki-ASCII CCMH codices)." },
          base: { type: "string",
                  description: "With collate: the base witness (label or document urn) each cell " \
                               "diffs against (default: the first witness in registry order)." },
          long: { type: "boolean", default: false,
                  description: "Single ref: list EVERY registered witness in full (no_match / " \
                               "not_synced columns included) instead of folding the absent ones " \
                               "into absent_witnesses + absent_counts (the default — the nt hub " \
                               "registers ~189 manuscripts, most absent at any verse). Ranges " \
                               "keep their own absent-from-every-ref summary either way." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["ref"],
        additionalProperties: false
      }.freeze

      private

      def align(args)
        ref = string_arg(args, "ref") or
          raise InvalidArguments, "nabu_align needs a ref (a citation like MARK 2.3, or a passage urn)"
        registry = resolve(@alignments)
        return note(NO_ALIGNMENTS_NOTE) if registry.nil? || registry.empty?

        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        fulltext = resolve(@fulltext)
        return note(ALIGN_REBUILDING_NOTE) unless fulltext&.table_exists?(Store::AlignmentIndexer::TABLE)

        include_restricted = args["include_restricted"] == true
        return collate(args, catalog, fulltext, registry, include_restricted) if args["collate"] == true

        result = Query::Align.new(catalog: catalog, fulltext: fulltext, registry: registry)
                             .run(ref, work: string_arg(args, "work"))
        json(if result.is_a?(Query::Align::RangeResult)
               align_range_payload(result, include_restricted: include_restricted)
             else
               align_payload(result, include_restricted: include_restricted, long: args["long"] == true)
             end)
      rescue Query::Align::Error => e
        # Caller-fixable (unknown work, unaligned urn): isError so the model
        # self-corrects (SEP-1303), same stance as bad arguments.
        tool_error(e.message)
      end

      # `collate: true` on nabu_align (P15-4): the witness DIFF apparatus. Same
      # index/registry contract as align; the license gate WITHHOLDS excluded
      # witnesses from the diff bodily (they cannot leak through a divergence
      # line) unless include_restricted.
      def collate(args, catalog, fulltext, registry, include_restricted)
        exclude = include_restricted ? [] : EXCLUDED_LICENSE_CLASSES
        collation = Query::Collation.new(catalog: catalog, fulltext: fulltext, registry: registry)
        result = collation.run(string_arg(args, "ref"), work: string_arg(args, "work"),
                                                        base: string_arg(args, "base"), exclude_licenses: exclude)
        json(collation_payload(result))
      end

      # -- align internals ---------------------------------------------------------

      # A single ref (compact by default, mirroring `nabu align`): witnesses
      # with nothing at the ref are folded through the SAME seam the CLI and
      # the range view use (Query::Align.lift_absent_witnesses) into
      # absent_witnesses (the range payload's row shape) + absent_counts;
      # long: true keeps every column. The attestation count in the note
      # always names the full registered roster.
      def align_payload(result, include_restricted:, long: false)
        attesting = result.witnesses.count { |witness| witness.status == :ok }
        shown, absent = fold_single_ref(result, long: long)
        {
          type: "alignment", work: result.work, title: result.title, ref: result.ref,
          witnesses: shown.map { |witness| align_witness_payload(witness, include_restricted) },
          absent_witnesses: absent.map { |witness| { label: witness.label, reason: witness.reason.to_s } },
          absent_counts: absent_counts(absent),
          note: "#{attesting} of #{result.witnesses.size} registered witnesses attest #{result.ref}; " \
                "statuses: ok (sentences follow), no_match (verse absent from that witness), " \
                "not_synced (registered, no data yet), withheld (license-excluded)#{single_fold_note(absent)}"
        }
      end

      def fold_single_ref(result, long:)
        return [result.witnesses, []] if long

        group = Query::Align::RefGroup.new(ref: result.ref, witnesses: result.witnesses)
        (present,), absent = Query::Align.lift_absent_witnesses([group])
        [present.witnesses, absent]
      end

      def absent_counts(absent)
        { not_attested: absent.count { |witness| witness.reason == :not_attested },
          not_synced: absent.count { |witness| witness.reason == :not_synced },
          total: absent.size }
      end

      def single_fold_note(absent)
        return "" if absent.empty?

        "; #{absent.size} witness(es) with nothing at this ref are folded into absent_witnesses " \
          "(reason: not_attested|not_synced) — pass long: true to list every witness column"
      end

      # A range/chapter query: the query string, the ref groups in document
      # order (each carrying the same witness columns as a single-ref reply),
      # and the honest cap accounting — total refs, how many are shown, whether
      # the ceiling clipped them (nabu_define's cap style).
      def align_range_payload(result, include_restricted:)
        {
          type: "alignment_range", work: result.work, title: result.title, query: result.query,
          total_refs: result.total, shown_refs: result.groups.size, truncated: result.truncated,
          # P11-9: witnesses absent from EVERY ref are summarized here once and
          # dropped from the per-ref witness arrays (the per-ref columns stay
          # readable). reason: not_attested (live, verses absent) | not_synced.
          absent_witnesses: result.absent.map { |witness| { label: witness.label, reason: witness.reason.to_s } },
          refs: result.groups.map do |group|
            { ref: group.ref,
              witnesses: group.witnesses.map { |witness| align_witness_payload(witness, include_restricted) } }
          end,
          note: range_note(result)
        }
      end

      def range_note(result)
        base = "#{result.query}: #{result.groups.size} refs in document order, each with its witness " \
               "columns (statuses: ok, no_match, not_synced, withheld)#{absent_note(result.absent)}"
        return base unless result.truncated

        "#{base} — TRUNCATED at #{MAX_ALIGN_REFS} of #{result.total} refs; narrow the range"
      end

      # The absent-witness clause (P11-9): present only when witnesses were
      # lifted out of the per-ref columns, so the model knows to read them off
      # absent_witnesses rather than expecting them per ref.
      def absent_note(absent)
        return "" if absent.empty?

        "; #{absent.size} witness(es) absent from every ref are summarized in absent_witnesses " \
          "(reason: not_attested|not_synced) and omitted from the per-ref columns"
      end

      # One witness column. A witness whose effective license class is
      # default-excluded is WITHHELD bodily (status + license class only, no
      # urns, no text) unless include_restricted — the same never-leak stance
      # as everywhere else on this surface.
      def align_witness_payload(witness, include_restricted)
        base = { label: witness.label, document_urn: witness.document_urn,
                 title: witness.title, language: witness.language,
                 license_class: witness.license_class, source: witness.source_slug }
        # P13-5: a witness whose psalter is numbered in another system (the WEB
        # Hebrew/Masoretic numbering) flags it so the model knows its refs were
        # remapped into the work vocabulary.
        base[:numbering] = witness.numbering if witness.numbering
        return base.merge(status: "withheld", sentences: []) if withhold?(witness.license_class, include_restricted)

        base.merge(status: witness.status.to_s,
                   sentences: witness.sentences.map { |sentence| align_sentence_payload(witness, sentence) })
      end

      # Every sentence row carries the full contract fields (urn + language +
      # license_class + source) plus the refs it covers — sentence≠verse,
      # stated per row. A remapped witness (P13-5) also reports its WITNESS-
      # NATIVE ref (Hebrew "PSA 23.1" under work "PSA 22.1") when it diverges.
      def align_sentence_payload(witness, sentence)
        row = { urn: sentence.urn, language: witness.language,
                license_class: witness.license_class, source: witness.source_slug,
                text: sentence.text, refs: sentence.refs }
        row[:native_ref] = sentence.native_ref if sentence.native_ref
        row
      end

      # -- align --collate internals (P15-4) ---------------------------------------

      def collation_payload(result)
        {
          type: "collation", work: result.work, title: result.title, query: result.query,
          total_refs: result.total, shown_refs: result.refs.size, truncated: result.truncated,
          refs: result.refs.map { |ref_collation| collation_ref_payload(ref_collation) },
          note: "raw-token apparatus per (language, script) cell: each cell diffs its witnesses " \
                "against a base (agreements elided; substitutions/omissions/insertions marked). " \
                "asides are witnesses rendered UNDIFFED — reason cross_script (a same-language " \
                "witness exists in another script the fold cannot bridge) or sole (the only witness " \
                "of its language here). missing lists no_match/not_synced/withheld witnesses."
        }
      end

      def collation_ref_payload(ref_collation)
        {
          ref: ref_collation.ref,
          cells: ref_collation.cells.map { |cell| collation_cell_payload(cell) },
          asides: ref_collation.asides.map do |aside|
            { label: aside.label, language: aside.language, script: aside.script,
              license_class: aside.license_class, source: aside.source_slug,
              reason: aside.reason.to_s, text: aside.text }
          end,
          missing: ref_collation.missing.map { |witness| { label: witness.label, status: witness.status.to_s } }
        }
      end

      def collation_cell_payload(cell)
        base = cell.readings.find(&:is_base)
        {
          language: cell.language, script: cell.script, base: cell.base_label,
          base_tokens: base.tokens,
          witnesses: cell.readings.reject(&:is_base).map do |reading|
            { label: reading.label, license_class: reading.license_class, source: reading.source_slug,
              agrees: reading.edits.empty?, tokens: reading.tokens,
              edits: reading.edits.map { |edit| { op: edit.op.to_s, base: edit.base, witness: edit.witness } } }
          end
        }
      end
    end
  end
end
