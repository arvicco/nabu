# frozen_string_literal: true

require_relative "align"

module Nabu
  module Query
    # `align REF --collate [--base LABEL]` (docs/intertext-design.md §2, P15-4):
    # witness DIFF over the alignment hub. Align renders the witness columns;
    # the eye still does the diffing. Collation does it mechanically, in the
    # compact APPARATUS style of textual criticism: the base reading in full,
    # then per witness ONLY the divergences (substitutions/omissions/
    # insertions marked, agreements elided). It is a renderer over Align's
    # aligned rows — not a new lookup model, so the P11-8 range grammar and the
    # P15-8 --long rule compose for free.
    #
    # == Why RAW tokens, within one (language, script) cell only
    #
    # The conventions-§9 search fold does NOT bridge scripts: Cyrillic stays
    # Cyrillic while a Helsinki-ASCII transliteration merely downcases — and
    # downcasing DESTROYS information (Helsinki S=š vs s, E=ę vs e collapse).
    # A folded-token diff across the Cyrillic-vs-Helsinki boundary would be 100%
    # noise; a folded diff even between two Helsinki witnesses conflates real
    # variants. So collation diffs RAW tokens (punctuation-only tokens dropped,
    # every diacritic marker kept verbatim), and only between witnesses that
    # share BOTH language AND Unicode script — the measured collatable cell.
    # A same-work witness in a DIFFERENT script (the PROIEL Cyrillic Marianus
    # beside the Helsinki CCMH codices) renders undiffed, aligned but honestly
    # labelled "not collated — different transcription system".
    #
    # == Grouping: (language, script), argued
    #
    # Language ALONE is not enough (chu holds both the Cyrillic Marianus and the
    # Helsinki-ASCII CCMH codices — the same language in two scripts that cannot
    # be folded together). Script ALONE is not enough either (Gothic, Latin,
    # English and the Helsinki CCMH are all written in the Latin script but are
    # four different languages). So the collatable cell is the PAIR: witnesses
    # that share the language (the measured collatable axis — grc 7,643 /
    # lat 6,974 / chu 3,764 same-language verses) AND the majority Unicode
    # script of their rendered text. Script is detected from the TEXT, not from
    # metadata, because the metadata language code (chu) does not record which
    # transcription a witness uses.
    #
    # == Base witness
    #
    # The base of a cell is its FIRST witness in REGISTRY ORDER (the registry is
    # the curated display order — see Align), unless `--base` names one by label
    # or document urn, in which case that witness heads the cell it belongs to.
    class Collation
      # Same caller-fixable surface as Align (unknown work, ref not found, index
      # not built) plus the --base miss — the CLI/MCP layers turn it into
      # exit 1 / isError.
      Error = Align::Error

      # The Unicode scripts collation can name (majority wins; anything else is
      # "Other"). Order is irrelevant — the counts decide.
      SCRIPTS = {
        "Greek" => /\p{Greek}/, "Latin" => /\p{Latin}/, "Cyrillic" => /\p{Cyrillic}/,
        "Armenian" => /\p{Armenian}/, "Hebrew" => /\p{Hebrew}/, "Arabic" => /\p{Arabic}/,
        "Georgian" => /\p{Georgian}/, "Coptic" => /\p{Coptic}/, "Syriac" => /\p{Syriac}/,
        "Devanagari" => /\p{Devanagari}/, "Han" => /\p{Han}/,
        "Hiragana" => /\p{Hiragana}/, "Katakana" => /\p{Katakana}/
      }.freeze
      private_constant :SCRIPTS

      # A token that is ENTIRELY punctuation/separator — dropped before the diff
      # (a bare "." between words). A token carrying even one letter/digit is
      # kept verbatim, markers and all ("k&", "Cetyr$mi" stay whole — stripping
      # their markers would destroy information exactly as folding does).
      PUNCT_ONLY = /\A[\p{P}\p{S}\p{Z}]+\z/
      private_constant :PUNCT_ONLY

      # One word-level edit of a witness against its cell's base, in base order:
      #   :sub  base tokens the witness REPLACES (with `witness` tokens)
      #   :del  base tokens the witness OMITS (nothing in their place)
      #   :ins  tokens the witness INSERTS (absent from the base)
      Edit = Data.define(:op, :base, :witness)

      # A witness collated against the base: its label + effective license +
      # source, its divergences (empty ⇒ identical to base), its full raw tokens
      # (rendered only under --long), and whether it IS the base row.
      Reading = Data.define(:label, :license_class, :source_slug, :is_base, :edits, :tokens)

      # A same-(language, script) cell of ≥2 witnesses collated against a base.
      # `readings` lead with the base row, then the rest in registry order.
      Cell = Data.define(:language, :script, :base_label, :readings)

      # A witness that could NOT be collated, rendered undiffed and honestly:
      #   :cross_script — a same-language witness in a DIFFERENT script exists,
      #                   and the fold cannot bridge them (Cyrillic vs Helsinki)
      #   :sole         — the only witness of its (language, script) at this ref
      Aside = Data.define(:label, :language, :script, :license_class, :source_slug, :text, :reason)

      # A witness with no collatable text here — named, never diffed. `status` is
      # :no_match / :not_synced (from Align) or :withheld (license-excluded on a
      # gated surface).
      Missing = Data.define(:label, :status)

      # One ref's apparatus: the ref, its collated cells, its uncollated asides,
      # and its missing witnesses.
      RefCollation = Data.define(:ref, :cells, :asides, :missing)

      # The whole answer: work/title, the normalized query, one RefCollation per
      # ref (a single ref → one entry; a range → one per attested ref, capped as
      # Align caps unless --long), plus the range cap accounting.
      Result = Data.define(:work, :title, :query, :refs, :truncated, :total)

      def initialize(catalog:, fulltext:, registry:)
        @align = Align.new(catalog: catalog, fulltext: fulltext, registry: registry)
      end

      # Collate +ref+ (a citation, a range/chapter, or a passage urn) across the
      # witnesses of +work+. `base` overrides the per-cell base by label/urn;
      # `long` lifts the range cap AND asks the renderer for full tokens;
      # `exclude_licenses` withholds those license classes from the diff (the
      # MCP gate — the CLI, an owner-local surface, passes none).
      def run(ref, work: nil, base: nil, long: false, exclude_licenses: [])
        aligned = @align.run(ref, work: work, long: long)
        validate_base!(aligned, base)
        case aligned
        when Align::RangeResult
          refs = aligned.groups.map { |group| collate_ref(group.ref, group.witnesses, base, exclude_licenses) }
          Result.new(work: aligned.work, title: aligned.title, query: aligned.query,
                     refs: refs, truncated: aligned.truncated, total: aligned.total)
        else
          rc = collate_ref(aligned.ref, aligned.witnesses, base, exclude_licenses)
          Result.new(work: aligned.work, title: aligned.title, query: aligned.ref,
                     refs: [rc], truncated: false, total: 1)
        end
      end

      private

      # -- per-ref collation -------------------------------------------------------

      def collate_ref(ref, witnesses, base, exclude_licenses)
        attesting = witnesses.select { |witness| witness.status == :ok }
        withheld, present = attesting.partition { |witness| exclude_licenses.include?(witness.license_class) }
        missing = witnesses.reject { |witness| witness.status == :ok }
                           .map { |witness| Missing.new(label: witness.label, status: witness.status) }
        missing += withheld.map { |witness| Missing.new(label: witness.label, status: :withheld) }

        cells, asides = partition_cells(present, base)
        RefCollation.new(ref: ref, cells: cells, asides: asides, missing: missing)
      end

      # Group the present witnesses (registry order) by (language, script). A
      # cell of ≥2 collates; a lone witness becomes an aside — :cross_script when
      # its language has another (differently-scripted) witness here, :sole
      # otherwise.
      def partition_cells(present, base)
        by_language = present.group_by(&:language)
        cells = []
        asides = []
        present.group_by { |witness| [witness.language, script_of(witness_text(witness))] }
               .each do |(language, script), members|
          if members.size >= 2
            cells << build_cell(language, script, members, base)
          else
            witness = members.first
            reason = by_language[language].size > 1 ? :cross_script : :sole
            asides << Aside.new(label: witness.label, language: language, script: script,
                                license_class: witness.license_class, source_slug: witness.source_slug,
                                text: witness_text(witness), reason: reason)
          end
        end
        [cells, asides]
      end

      def build_cell(language, script, members, base)
        base_witness = members.find { |witness| base_match?(witness, base) } || members.first
        base_tokens = tokens_of(base_witness)
        readings = members.map do |witness|
          is_base = witness.equal?(base_witness)
          Reading.new(label: witness.label, license_class: witness.license_class,
                      source_slug: witness.source_slug, is_base: is_base,
                      edits: is_base ? [] : diff(base_tokens, tokens_of(witness)),
                      tokens: tokens_of(witness))
        end
        ordered = readings.select(&:is_base) + readings.reject(&:is_base)
        Cell.new(language: language, script: script, base_label: base_witness.label, readings: ordered)
      end

      # -- tokens & scripts --------------------------------------------------------

      def witness_text(witness)
        witness.sentences.map(&:text).join(" ")
      end

      def tokens_of(witness)
        witness_text(witness).split(/\s+/).reject { |token| token.empty? || token.match?(PUNCT_ONLY) }
      end

      # The majority Unicode script of +text+ (counting characters), or "Other"
      # when none of the named scripts appear — the honest fallback rather than a
      # wrong guess.
      def script_of(text)
        name, count = SCRIPTS.map { |script, pattern| [script, text.scan(pattern).size] }.max_by(&:last)
        count.positive? ? name : "Other"
      end

      # -- word-level LCS diff -----------------------------------------------------

      # The apparatus of +other+ against +base+: a list of Edits (agreements
      # elided). A classic LCS backtrack yields per-token equal/delete/insert
      # ops; adjacent non-equal ops coalesce into one Edit (a run of deletes +
      # inserts is a substitution; deletes alone an omission; inserts alone an
      # insertion).
      def diff(base, other)
        coalesce(lcs_ops(base, other))
      end

      def lcs_ops(base, other)
        table = lcs_table(base, other)
        ops = []
        i = base.length
        j = other.length
        while i.positive? && j.positive?
          if base[i - 1] == other[j - 1]
            ops << [:eq, base[i - 1], other[j - 1]]
            i -= 1
            j -= 1
          elsif table[i - 1][j] >= table[i][j - 1]
            ops << [:del, base[i - 1], nil]
            i -= 1
          else
            ops << [:ins, nil, other[j - 1]]
            j -= 1
          end
        end
        (ops << [:del, base[i - 1], nil]) && (i -= 1) while i.positive?
        (ops << [:ins, nil, other[j - 1]]) && (j -= 1) while j.positive?
        ops.reverse
      end

      def lcs_table(base, other)
        table = Array.new(base.length + 1) { Array.new(other.length + 1, 0) }
        (1..base.length).each do |i|
          (1..other.length).each do |j|
            table[i][j] = if base[i - 1] == other[j - 1]
                            table[i - 1][j - 1] + 1
                          else
                            [table[i - 1][j], table[i][j - 1]].max
                          end
          end
        end
        table
      end

      def coalesce(ops)
        edits = []
        run = []
        ops.each do |op|
          if op.first == :eq
            edits << edit_of(run) unless run.empty?
            run = []
          else
            run << op
          end
        end
        edits << edit_of(run) unless run.empty?
        edits
      end

      def edit_of(run)
        base = run.filter_map { |op| op[1] if op.first == :del }
        witness = run.filter_map { |op| op[2] if op.first == :ins }
        op = if base.any? && witness.any? then :sub
             elsif base.any? then :del
             else :ins
             end
        Edit.new(op: op, base: base, witness: witness)
      end

      # -- --base resolution -------------------------------------------------------

      def validate_base!(aligned, base)
        return if base.nil?

        witnesses = aligned.is_a?(Align::RangeResult) ? aligned.groups.flat_map(&:witnesses) : aligned.witnesses
        return if witnesses.any? { |witness| base_match?(witness, base) }

        labels = witnesses.map(&:label).uniq
        raise Error, "no witness matches --base #{base.inspect} — witnesses here: #{labels.join(', ')}"
      end

      def base_match?(witness, base)
        return false if base.nil?

        wanted = base.to_s.strip.downcase
        witness.label.to_s.downcase == wanted || witness.document_urn.to_s.downcase == wanted
      end
    end
  end
end
