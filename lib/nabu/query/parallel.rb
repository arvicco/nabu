# frozen_string_literal: true

module Nabu
  module Query
    # `nabu show URN --parallel [LANG]` (P7-4): resolve a document or passage
    # urn to the sibling edition of the same CTS work in a target language and
    # align the two passage lists by citation suffix.
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
    # == The pairing rule (documented behavior, tested)
    #
    # Rows follow the QUERIED (left) document's passage order. Each left
    # passage pairs with the right passage of identical suffix when one
    # exists; otherwise the row is honestly one-sided (translations often
    # merge lines — Hymn 13's English is a single line over the Greek's
    # three). Right passages whose suffix never occurs on the left are
    # interleaved one-sided by their own sequence, before the next pair they
    # precede (a two-pointer merge: both editions' reading orders are
    # preserved). Suffixes are exact-match only — no numeric fuzzing, no
    # range splitting; what is not alignable is shown as such.
    #
    # == Sibling selection
    #
    # Sibling = same work prefix (urn:cts:<ns>:<tg>.<work>.), document
    # language = LANG, different urn. When several qualify the highest
    # version wins, mirroring the adapter's per-work edition rule (numeric
    # then letter: eng10 > eng2). Non-CTS urns (papyri, treebanks) have no
    # work prefix and therefore no siblings — Result#right is nil and the CLI
    # says so.
    #
    # Show-family semantics: withdrawn passages are included, flagged — this
    # is an inspection surface (see Show's header for the rationale).
    class Parallel
      # One aligned row: the shared citation suffix, and a Line for each side
      # (nil when that edition lacks the suffix).
      Row = Data.define(:suffix, :left, :right)

      # One side's passage: urn, text, withdrawn flag.
      Line = Data.define(:urn, :text, :withdrawn)

      # One document header: urn, title, language.
      Side = Data.define(:urn, :title, :language)

      # left is always the queried document; right is the LANG sibling (nil
      # when none exists). scope is the queried passage's suffix (nil for a
      # document urn); rows are pre-filtered to it.
      Result = Data.define(:left, :right, :rows, :scope)

      # Document urn shape alignment can work with: the work prefix is
      # everything up to the edition segment (the last dot-component of the
      # fourth colon field).
      CTS_DOCUMENT = /\A(?<work>urn:cts:[^:]+:[^:]+\.[^:]+)\.[^:.]+\z/
      private_constant :CTS_DOCUMENT

      def initialize(catalog:)
        @catalog = catalog
      end

      # Resolve +urn+ (document, passage, or a range urn — P7-6) and align
      # against the +lang+ sibling. Returns a Result, or nil when the urn is
      # unknown. A range urn slices the QUERIED document; the pairing then
      # applies to the sliced rows only (unmatched suffixes stay one-sided). A
      # range with a bad endpoint raises Range::Error (CLI → exit 1).
      def run(urn, lang: "eng")
        document, scope, slice = locate(urn)
        return nil if document.nil?

        sibling = sibling_edition(document, lang)
        return Result.new(left: side(document), right: nil, rows: [], scope: scope) if sibling.nil?

        rows = align(document, sibling)
        rows = rows.select { |row| row.suffix == scope } if scope
        rows = rows.select { |row| slice.include?(row.suffix) } if slice
        Result.new(left: side(document), right: side(sibling), rows: rows, scope: scope)
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

      # A range urn → its document + the set of in-slice suffixes to filter the
      # aligned rows by, or nil when the urn is not a range.
      def locate_range(urn)
        slice = Range.new(catalog: @catalog).resolve(urn)
        return nil if slice.nil?

        document = document_by(id: slice.document_id)
        suffixes = @catalog[:passages]
                   .where(document_id: slice.document_id)
                   .where(sequence: slice.start_seq..slice.end_seq)
                   .select_map(:urn)
                   .map { |passage_urn| passage_urn.delete_prefix(document.fetch(:urn)) }
        [document, nil, suffixes]
      end

      def document_by(criteria)
        @catalog[:documents].where(criteria).select(:id, :urn, :title, :language).first
      end

      # The highest-version LANG edition of the same work, or nil. LIKE over
      # the work prefix (edition slugs never contain dots or colons), language
      # filter, self excluded; version-aware max among several.
      def sibling_edition(document, lang)
        match = document.fetch(:urn).match(CTS_DOCUMENT)
        return nil if match.nil?

        rows = @catalog[:documents]
               .where(Sequel.like(:urn, "#{match[:work]}.%"))
               .where(language: lang)
               .exclude(urn: document.fetch(:urn))
               .select(:id, :urn, :title, :language)
               .all
        rows.max_by { |row| version_key(row.fetch(:urn)) }
      end

      # Order siblings by trailing version token, numeric before letter
      # (eng10 > eng2, grc2a > grc2), falling back to plain urn order for
      # unversioned shapes. The [rank, digits, letter, urn] array keeps the
      # comparison total.
      def version_key(urn)
        match = urn.match(/(?<digits>\d+)(?<letter>[a-z]?)\z/)
        match ? [1, match[:digits].to_i, match[:letter], urn] : [0, 0, "", urn]
      end

      def side(document)
        Side.new(urn: document.fetch(:urn), title: document.fetch(:title),
                 language: document.fetch(:language))
      end

      # The two-pointer merge described in the header: left order drives;
      # unmatched right passages flush one-sided before the pair that follows
      # them, and any tail after the last pair.
      def align(left_doc, right_doc)
        left = lines(left_doc)
        right = lines(right_doc)
        right_position = right.each_with_index.to_h { |(suffix, _line), index| [suffix, index] }

        rows = []
        cursor = 0
        left.each do |suffix, line|
          index = right_position[suffix]
          if index && index >= cursor
            right[cursor...index].each { |s, r| rows << Row.new(suffix: s, left: nil, right: r) }
            rows << Row.new(suffix: suffix, left: line, right: right[index][1])
            cursor = index + 1
          else
            rows << Row.new(suffix: suffix, left: line, right: nil)
          end
        end
        right[cursor..].each { |s, r| rows << Row.new(suffix: s, left: nil, right: r) }
        rows
      end

      # [suffix, Line] pairs in sequence order.
      def lines(document)
        urn = document.fetch(:urn)
        @catalog[:passages]
          .where(document_id: document.fetch(:id))
          .order(:sequence)
          .select(:urn, :text, :withdrawn)
          .map do |row|
            line = Line.new(urn: row.fetch(:urn), text: row.fetch(:text),
                            withdrawn: [true, 1].include?(row.fetch(:withdrawn)))
            [row.fetch(:urn).delete_prefix(urn), line]
          end
      end
    end
  end
end
