# frozen_string_literal: true

require_relative "types"
require_relative "align_hub"
require_relative "../query/collation"

module Nabu
  module Export
    # `nabu export collation` (P145): the `align --collate` apparatus
    # (Query::Collation, intertext-design §2) as rows — per anchor ref,
    # every attesting witness's reading, one row each, in the apparatus's
    # own order: each (language, script) cell's base then its variants,
    # then the uncollated witnesses. Collation is RAW-token and cell-bound
    # (Collation's class note): a witness alone in its language
    # (collation "sole") or alone in its script among same-language
    # witnesses ("cross_script") is a row with role "uncollated" and no
    # apparatus — aligned, never diffed across a transcription boundary.
    #
    # The reading is the witness's raw token stream (punctuation-only tokens
    # dropped, every marker kept verbatim) for a collated row, the stored
    # text for an uncollated one. A variant's apparatus renders its edits
    # against the cell base exactly as `align --collate` prints them
    # ("base → variant", "om. base", "add. variant"; "; "-joined), so it
    # QUOTES the base: a variant row draws on its own source AND the
    # base's, and under --license-class survives only when both are
    # allowed. Witnesses absent from a ref (not attested / not synced) have
    # no reading and no row; the manifest counts them by status.
    #
    # --base heads each cell with that witness wherever it attests (a
    # whole-work walk falls back to registry order where it does not); the
    # label must name a witness of the work.
    class CollationReadings
      NAME = "collation"
      SUMMARY = "The collation apparatus as rows: per anchor ref, each witness reading with its passage urns, " \
                "(language, script) cell, role (base / variant / uncollated), apparatus against the cell " \
                "base, source and license"

      COLUMNS = [
        Column.new(name: "work", description: "alignment work id (config/alignments.yml)"),
        Column.new(name: "ref", description: "the anchor citation (normalized) the readings attest"),
        Column.new(name: "language", description: "the witness's document language"),
        Column.new(name: "script", description: "majority Unicode script of the reading's text (the cell axis)"),
        Column.new(name: "witness", description: "the witness's registry label"),
        Column.new(name: "urns", description: "the witness's passage urns for the ref, |-joined, in order"),
        Column.new(name: "role", description: "base (the cell's base reading), variant (collated against " \
                                              "it), or uncollated (alone in its cell)"),
        Column.new(name: "base_witness", description: "the cell's base witness; NULL on an uncollated row"),
        Column.new(name: "reading", description: "raw tokens space-joined (collated rows; punctuation-only " \
                                                 "tokens dropped) or the stored text (uncollated rows)"),
        Column.new(name: "agrees", description: "variant rows: true when identical to the base; NULL otherwise"),
        Column.new(name: "apparatus", description: "variant rows: the edits against the base " \
                                                   "(\"base → variant\", \"om. base\", \"add. variant\"), " \
                                                   "\"; \"-joined; empty when it agrees; NULL otherwise"),
        Column.new(name: "collation", description: "collated, cross_script (a same-language witness in " \
                                                   "another script exists) or sole (alone in its language)"),
        Column.new(name: "source", description: "the witness's source slug"),
        Column.new(name: "license_class", description: "the witness's effective license class")
      ].freeze

      def initialize(catalog:, fulltext:, registry:, ref: nil, work: nil, base: nil)
        @hub = AlignHub.new(catalog: catalog, fulltext: fulltext, registry: registry, ref: ref, work: work)
        @collation = Query::Collation.new(catalog: catalog, fulltext: fulltext, registry: registry)
        @base = base.to_s.strip.empty? ? nil : base.to_s.strip
        @refs = 0
        @missing = Hash.new(0)
      end

      def columns = COLUMNS

      def filters = { "ref" => @hub.scope, "base" => @base }

      def notes = { "refs" => @refs, "missing_witnesses" => @missing.sort.to_h }

      # +license_classes+ is enforced by the frame (a variant draws on its base).
      def each_row(license_classes: nil, &block)
        _ = license_classes
        @hub.each_group(on_work: ->(work) { validate_base!(work) }) do |group|
          @refs += 1
          collated = @collation.collate(group.ref, group.witnesses, base: @base)
          collated.missing.each { |missing| @missing[missing.status.to_s] += 1 }
          collated.cells.each { |cell| cell_rows(group.ref, cell).each(&block) }
          collated.asides.each { |aside| yield aside_row(group.ref, aside) }
        end
      end

      private

      def validate_base!(work)
        return if @base.nil? || work.witnesses.any? { |witness| AlignHub.witness_match?(witness, @base) }

        raise Error, "no witness #{@base.inspect} in work #{work.id} — witnesses: " \
                     "#{work.witnesses.map(&:label).join(', ')}"
      end

      def cell_rows(ref, cell)
        base = cell.readings.find(&:is_base)
        cell.readings.map do |reading|
          variant = !reading.is_base
          values = [@hub.work.id, ref, cell.language, cell.script, reading.label, reading.urns.join("|"),
                    variant ? "variant" : "base", cell.base_label, reading.tokens.join(" "),
                    variant ? reading.edits.empty? : nil, variant ? apparatus(reading.edits) : nil, "collated",
                    reading.source_slug, reading.license_class]
          draws = [[reading.source_slug, reading.license_class]]
          draws << [base.source_slug, base.license_class] if variant
          Row.new(values: values, draws: draws)
        end
      end

      def aside_row(ref, aside)
        values = [@hub.work.id, ref, aside.language, aside.script, aside.label, aside.urns.join("|"), "uncollated",
                  nil, aside.text, nil, nil, aside.reason.to_s, aside.source_slug, aside.license_class]
        Row.new(values: values, draws: [[aside.source_slug, aside.license_class]])
      end

      # The `align --collate` marks, as plain text.
      def apparatus(edits)
        edits.map do |edit|
          case edit.op
          when :sub then "#{edit.base.join(' ')} → #{edit.witness.join(' ')}"
          when :del then "om. #{edit.base.join(' ')}"
          else "add. #{edit.witness.join(' ')}"
          end
        end.join("; ")
      end
    end
  end
end
