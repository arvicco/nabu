# frozen_string_literal: true

module Nabu
  module Query
    # `nabu show URN --parallel [LANG]` (P7-4, span-grouped P8-1b): resolve a
    # document or passage urn to the sibling edition of the same CTS work in a
    # target language and align the two passage lists by citation suffix.
    #
    # == Why citation suffixes are enough
    #
    # CTS editions of one work share the work's citation scheme
    # (conventions.md §2): urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1
    # and …perseus-eng4:1.1 cite the same Iliad line. So alignment needs no
    # stored links — a passage urn minus its document urn (":1.1") is the
    # alignment key, and any two editions of the work pair wherever those
    # suffixes are equal.
    #
    # == Span grouping (P8-1b — the owner feedback)
    #
    # Pure suffix-equality pairing works for verse-for-verse translations, but
    # card-cited prose translations (both English Homers) anchor ONE block of
    # text at a card's first line — e.g. the eng card :1.1 renders the whole
    # of Greek lines 1.1..1.43. The old pair-only rendering paired that block
    # with :1.1 and dashed every following line "—" ("frankly, not that
    # parallel," the owner). So alignment is now SPAN-GROUPED:
    #
    #   * Each translation suffix that also exists in the original is an ANCHOR.
    #     It OWNS the original passages from its own position up to (not
    #     including) the next anchor's position, computed over the FULL original
    #     document's suffix order — not just the queried slice. So a range
    #     1.5-1.10 is still covered by the card anchored at 1.1 even though 1.1
    #     lies outside the slice (the case that used to render all-"—").
    #   * A 1:1 anchor — owning exactly ONE original whose suffix equals the
    #     anchor — is a verse pair (:pair), rendered in the compact pair form.
    #     Verse-for-verse translations are all pairs and render byte-identically
    #     to the pre-P8-1b output.
    #   * An anchor owning a SPAN (more than one original, or one whose suffix
    #     differs from the anchor) is a coarse block (:block): the original
    #     lines first, then the translation once, labeled with its full coverage
    #     in the original's numbering and — when a slice shows only part of it —
    #     an explicit clip note.
    #   * Original passages that no anchor owns (they precede the first anchor)
    #     stay honest one-sided rows (:original). Translation suffixes absent
    #     from the original entirely stay one-sided the other way
    #     (:translation) — a translation-only block never becomes an owning
    #     anchor. An anchor suffix the original somehow lacks simply is not an
    #     anchor, so its block degrades to a one-sided :translation row.
    #
    # == The queried slice
    #
    # A range urn (P7-6) slices the QUERIED (original) document. Ownership is
    # still computed over the full documents; a group then RENDERS iff its
    # coverage intersects the slice, the original rows shown are those inside
    # the slice, and a block is flagged `clipped` (with the shown sub-range)
    # when its coverage runs past the slice on either end.
    #
    # == Sibling selection
    #
    # Sibling = same work prefix (urn:cts:<ns>:<tg>.<work>.), document
    # language = LANG, different urn. When several qualify the highest version
    # wins (numeric then letter: eng10 > eng2).
    #
    # ORACC tablets (P13-4) are the second sibling family: the tablet urn
    # (urn:nabu:oracc:<project>:<textid>) IS the work, and its aligned
    # translations are `<work>-<variant>` documents (…:P224395-en) whose
    # passage suffixes are the tablet's own line labels (:o.1) — so the same
    # suffix span-grouping applies unchanged, and the paragraph-grained SAA
    # units render exactly like the card-cited English Homers. Both
    # directions resolve (tablet → -en; -en → tablet via lang "akk"/"sux").
    # P/Q textids never contain a hyphen, so the -variant split is exact.
    #
    # Other non-CTS urns (papyri, treebanks) have no work prefix and
    # therefore no siblings — Result#right is nil and the CLI says so.
    #
    # Show-family semantics: withdrawn passages are included, flagged — this is
    # an inspection surface (see Show's header for the rationale).
    class Parallel
      # One side's passage: its citation suffix, urn, text, withdrawn flag.
      Line = Data.define(:suffix, :urn, :text, :withdrawn)

      # One aligned group. +kind+ is one of:
      #   :pair        1:1 verse — a single original whose suffix == anchor,
      #                with its translation. Compact pair form.
      #   :block       coarse — an anchor owning a SPAN of originals; renders
      #                the originals then the translation once + coverage label.
      #   :original    an original passage no anchor owns (one-sided).
      #   :translation a translation suffix absent from the original (one-sided).
      #
      # anchor is the owning translation suffix (nil for :original).
      # covers_first/covers_last are the full ownership span in the original's
      # numbering (nil for :translation). originals are the original Lines IN
      # THE RENDERED SLICE (all of them when unsliced); translation is the
      # translation Line (nil for :original). clipped is true when the slice
      # shows only part of the coverage; shown_first/shown_last name the shown
      # sub-range then (== covers_first/last when not clipped).
      Group = Data.define(
        :kind, :anchor, :covers_first, :covers_last,
        :originals, :translation, :clipped, :shown_first, :shown_last
      )

      # One document header: urn, title, language.
      Side = Data.define(:urn, :title, :language)

      # left is always the queried document; right is the LANG sibling (nil
      # when none exists). scope is the queried passage's suffix (nil for a
      # document/range urn); groups are pre-filtered to the scope/slice.
      Result = Data.define(:left, :right, :groups, :scope)

      CTS_DOCUMENT = /\A(?<work>urn:cts:[^:]+:[^:]+\.[^:]+)\.[^:.]+\z/
      private_constant :CTS_DOCUMENT

      # An ORACC document urn: the tablet itself (the work) or one of its
      # translation variants (work-en, …). See "Sibling selection".
      ORACC_DOCUMENT = /\A(?<work>urn:nabu:oracc:[^:]+:[^:-]+)(?:-[a-z]+)?\z/
      private_constant :ORACC_DOCUMENT

      # A Freising monument urn (P13-11): the critical transcription IS the
      # work (urn:nabu:freising:bs1), its layers are "-" variants (bs1-dt,
      # bs1-pt, bs1-tr-eng, …). Same suffix span-grouping as ORACC; the
      # layers are line-for-line, so every anchor is a verse pair.
      FREISING_DOCUMENT = /\A(?<work>urn:nabu:freising:bs\d+)(?:-[a-z-]+)?\z/
      private_constant :FREISING_DOCUMENT

      # A Damaskini witness urn (P23-1): the witness IS the work
      # (urn:nabu:damaskini:veles--trojanskata), its aligned English is the
      # -en variant, suffix = the sentence number — verse pairs throughout.
      # Doc ids are hyphen-rich ("berlinski--slovo-petki"), so unlike ORACC
      # the variant split anchors on the literal -en tail (the only variant
      # this source mints; no upstream id ends in "-en" — censused, frozen).
      DAMASKINI_DOCUMENT = /\A(?<work>urn:nabu:damaskini:[^:]+?)(?:-en)?\z/
      private_constant :DAMASKINI_DOCUMENT

      # A SuttaCentral text urn (P26-1): the root text IS the work
      # (urn:nabu:suttacentral:mn1), its aligned English is the -en variant,
      # suffix = the shared bilara segment id — verse pairs on every shared
      # segment, honest one-sided rows where a translation expands or skips.
      # Stems are hyphen-rich (dhp21-32, pli-tv-bu-vb-as1-7), so the split
      # anchors on the literal -en tail, exactly the Damaskini stance (no
      # upstream stem ends in "-en" — censused, frozen).
      SUTTACENTRAL_DOCUMENT = /\A(?<work>urn:nabu:suttacentral:[^:]+?)(?:-en)?\z/
      private_constant :SUTTACENTRAL_DOCUMENT

      # A TLA-HF dataset urn (P28-2): the dataset IS the work
      # (urn:nabu:tla-hf:demotic-v18), its aligned GERMAN translation is the
      # -de variant, suffix = the record's line number — verse pairs
      # throughout. Stems are hyphen-rich (late-egyptian-v19), so the split
      # anchors on the literal -de tail, the Damaskini stance (no dataset
      # slug ends in "-de" — censused, frozen).
      TLA_HF_DOCUMENT = /\A(?<work>urn:nabu:tla-hf:[^:]+?)(?:-de)?\z/
      private_constant :TLA_HF_DOCUMENT
      # An AES text urn (P28-0): the Egyptian text IS the work
      # (urn:nabu:aes:tuebingerstelen:3F5K…), its aligned German is the -de
      # variant, suffix = the shared sentence id — verse pairs on every
      # translated sentence, honest one-sided rows where the editor left a
      # sentence untranslated (or translated a token-less one). Text ids
      # are uppercase [A-Z0-9] (censused, frozen) — none ends in "-de".
      AES_DOCUMENT = /\A(?<work>urn:nabu:aes:[^:]+:[^:]+?)(?:-de)?\z/
      private_constant :AES_DOCUMENT

      def initialize(catalog:)
        @catalog = catalog
      end

      # Resolve +urn+ (document, passage, or range) and align against the +lang+
      # sibling. Returns a Result, or nil when the urn is unknown. A range with
      # a bad endpoint raises Range::Error (CLI → exit 1).
      def run(urn, lang: "eng")
        document, scope, slice = locate(urn)
        return nil if document.nil?

        sibling = sibling_edition(document, lang)
        return Result.new(left: side(document), right: nil, groups: [], scope: scope) if sibling.nil?

        groups = build_groups(document, sibling)
        groups = clip(groups, scope ? [scope] : slice) if scope || slice
        Result.new(left: side(document), right: side(sibling), groups: groups, scope: scope)
      end

      private

      # [document row, scope suffix, slice suffixes]: the urn itself as a
      # document ([doc, nil, nil]); a passage ([doc, its-suffix, nil]); or a
      # range ([doc, nil, the slice's suffixes]). nil when unknown.
      def locate(urn)
        row = document_by(urn: urn)
        return [row, nil, nil] if row

        passage = @catalog[:passages].where(urn: urn).select(:urn, :document_id).first
        if passage
          document = document_by(id: passage.fetch(:document_id))
          return [document, passage.fetch(:urn).delete_prefix(document.fetch(:urn)), nil]
        end

        locate_range(urn)
      end

      # A range urn → its document + the ordered list of in-slice suffixes, or
      # nil when the urn is not a range.
      def locate_range(urn)
        slice = Range.new(catalog: @catalog).resolve(urn)
        return nil if slice.nil?

        document = document_by(id: slice.document_id)
        suffixes = @catalog[:passages]
                   .where(document_id: slice.document_id)
                   .where(sequence: slice.start_seq..slice.end_seq)
                   .order(:sequence)
                   .select_map(:urn)
                   .map { |passage_urn| passage_urn.delete_prefix(document.fetch(:urn)) }
        [document, nil, suffixes]
      end

      def document_by(criteria)
        @catalog[:documents].where(criteria).select(:id, :urn, :title, :language).first
      end

      # The LANG edition of the same work, or nil. Three work families: CTS
      # editions (work prefix + "." + edition slug), ORACC tablets and
      # Freising monuments (the work urn itself + "-" variants). The work's
      # OWN document outranks its variants when it qualifies (bs1-tr-eng →
      # sl resolves to the critical bs1, not the highest-sorting -tr-slv);
      # otherwise the highest version wins.
      def sibling_edition(document, lang)
        work, candidates = work_candidates(document.fetch(:urn))
        return nil if candidates.nil?

        rows = candidates
               .where(language: lang)
               .exclude(urn: document.fetch(:urn))
               .select(:id, :urn, :title, :language)
               .all
        rows.find { |row| row.fetch(:urn) == work } ||
          rows.max_by { |row| version_key(row.fetch(:urn)) }
      end

      # [work urn, dataset of documents sharing it], or nil for a urn with
      # no work notion (papyri, treebanks).
      def work_candidates(urn)
        if (match = urn.match(CTS_DOCUMENT))
          [match[:work], @catalog[:documents].where(Sequel.like(:urn, "#{match[:work]}.%"))]
        elsif (match = urn.match(ORACC_DOCUMENT) || urn.match(FREISING_DOCUMENT) ||
                       urn.match(DAMASKINI_DOCUMENT) || urn.match(SUTTACENTRAL_DOCUMENT) ||
                       urn.match(TLA_HF_DOCUMENT) || urn.match(AES_DOCUMENT))
          [match[:work], @catalog[:documents].where(
            Sequel.|(Sequel.like(:urn, "#{match[:work]}-%"), { urn: match[:work] })
          )]
        end
      end

      # Order siblings by trailing version token, numeric before letter.
      def version_key(urn)
        match = urn.match(/(?<digits>\d+)(?<letter>[a-z]?)\z/)
        match ? [1, match[:digits].to_i, match[:letter], urn] : [0, 0, "", urn]
      end

      def side(document)
        Side.new(urn: document.fetch(:urn), title: document.fetch(:title),
                 language: document.fetch(:language))
      end

      # Span-group the two editions. The original (left) drives order; each
      # translation anchor owns the original passages from its position up to
      # the next anchor's. See the class header for the full rule.
      def build_groups(left_doc, right_doc)
        original = lines(left_doc)
        translation = lines(right_doc)

        # First position of each original suffix — the anchor target.
        position = {}
        original.each_with_index { |line, index| position[line.suffix] ||= index }

        anchors = anchor_slices(translation, original, position)
        groups = []
        # Original passages before the first anchor own no translation.
        first = anchors.empty? ? original.size : anchors.first.fetch(:pos)
        groups.concat(original[0...first].map { |line| one_sided_original(line) })
        # Walk the translation in its own order: an anchor emits its group, a
        # translation-only suffix emits a one-sided row, preserving both
        # editions' reading orders.
        anchor_by_index = anchors.to_h { |anchor| [anchor.fetch(:ti), anchor] }
        translation.each_with_index do |line, ti|
          anchor = anchor_by_index[ti]
          groups << (anchor ? anchor_group(anchor) : one_sided_translation(line))
        end
        groups
      end

      # The translation anchors (suffix present in the original), each carrying
      # its original position, translation index, translation Line, and the
      # original Lines it owns (its position up to the next anchor's). Ordered
      # by original position so ownership intervals partition the original.
      def anchor_slices(translation, original, position)
        anchors = translation.each_with_index.filter_map do |line, ti|
          pos = position[line.suffix]
          { suffix: line.suffix, line: line, pos: pos, ti: ti } if pos
        end
        anchors.sort_by! { |anchor| anchor.fetch(:pos) }
        anchors.each_with_index do |anchor, k|
          stop = k + 1 < anchors.size ? anchors[k + 1].fetch(:pos) : original.size
          anchor[:owned] = original[anchor.fetch(:pos)...stop]
        end
        anchors
      end

      # An anchor → a :pair (1:1 verse) or a :block (coarse span).
      def anchor_group(anchor)
        owned = anchor.fetch(:owned)
        suffix = anchor.fetch(:suffix)
        if owned.size == 1 && owned.first.suffix == suffix
          verse_pair(owned.first, anchor.fetch(:line))
        else
          Group.new(
            kind: :block, anchor: suffix,
            covers_first: owned.first.suffix, covers_last: owned.last.suffix,
            originals: owned, translation: anchor.fetch(:line),
            clipped: false, shown_first: owned.first.suffix, shown_last: owned.last.suffix
          )
        end
      end

      def verse_pair(original_line, translation_line)
        Group.new(
          kind: :pair, anchor: original_line.suffix,
          covers_first: original_line.suffix, covers_last: original_line.suffix,
          originals: [original_line], translation: translation_line,
          clipped: false, shown_first: original_line.suffix, shown_last: original_line.suffix
        )
      end

      def one_sided_original(line)
        Group.new(
          kind: :original, anchor: nil, covers_first: line.suffix, covers_last: line.suffix,
          originals: [line], translation: nil,
          clipped: false, shown_first: line.suffix, shown_last: line.suffix
        )
      end

      def one_sided_translation(line)
        Group.new(
          kind: :translation, anchor: line.suffix, covers_first: nil, covers_last: nil,
          originals: [], translation: line,
          clipped: false, shown_first: nil, shown_last: nil
        )
      end

      # Filter groups to a slice (an ordered list of in-slice original
      # suffixes; a passage scope is a one-element slice). A group renders iff
      # its coverage intersects the slice; a block keeps only its in-slice
      # originals and is flagged clipped when its coverage runs past them.
      def clip(groups, suffixes)
        wanted = suffixes.to_set
        groups.filter_map do |group|
          case group.kind
          when :translation
            group if wanted.include?(group.anchor)
          else
            shown = group.originals.select { |line| wanted.include?(line.suffix) }
            next nil if shown.empty?

            clipped = shown.size < group.originals.size
            group.with(originals: shown, clipped: clipped,
                       shown_first: shown.first.suffix, shown_last: shown.last.suffix)
          end
        end
      end

      # [Line] in sequence order.
      def lines(document)
        urn = document.fetch(:urn)
        @catalog[:passages]
          .where(document_id: document.fetch(:id))
          .order(:sequence)
          .select(:urn, :text, :withdrawn)
          .map do |row|
            Line.new(suffix: row.fetch(:urn).delete_prefix(urn), urn: row.fetch(:urn),
                     text: row.fetch(:text), withdrawn: [true, 1].include?(row.fetch(:withdrawn)))
          end
      end
    end
  end
end
