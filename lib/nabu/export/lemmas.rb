# frozen_string_literal: true

require_relative "types"

module Nabu
  module Export
    # `nabu export lemmas` (P121 assembly): the lemma × century attestation
    # matrix — one row per (lemma, language, century, basis, grade, source)
    # straight out of the precompiled lemma_rollup (Store::LemmaRollup,
    # migration 038), the same rows the `nabu lemma` desk reads. No live
    # scan ever: a catalog without the rollup tables refuses with the
    # migration hint, and an empty rollup exports honestly with a manifest
    # note naming the refresh command.
    #
    # lemma is the FOLDED key (the fold-both-sides lookup contract);
    # century is the signed century index of the document envelope's
    # midpoint (NULL = undated) with basis the envelope's date class;
    # grade separates gold (upstream/treebank) from silver (machine)
    # attestations; occurrences counts passage attestations (one per
    # distinct lemma per passage — the index grain), documents the
    # distinct documents.
    class Lemmas
      NAME = "lemmas"
      SUMMARY = "The lemma attestation matrix: one row per lemma, language, century, date basis, grade " \
                "(gold|silver) and source, with passage-attestation and document counts"

      # const: keyset page over the rollup's rowid
      PAGE_SIZE = 10_000

      COLUMNS = [
        Column.new(name: "lemma", description: "the folded lemma key (the index's fold-both-sides form)"),
        Column.new(name: "language", description: "the attesting passage's stored language code"),
        Column.new(name: "century", description: "signed century index of the document envelope's midpoint " \
                                                 "(-1 = the first century BCE); NULL = undated"),
        Column.new(name: "basis", description: "the envelope's date class (artifact | composition); NULL = undated"),
        Column.new(name: "grade", description: "gold (upstream annotation) or silver (machine lemmas, flagged)"),
        Column.new(name: "source", description: "the attesting source's slug"),
        Column.new(name: "occurrences", description: "passage attestations (one per distinct lemma per passage)"),
        Column.new(name: "documents", description: "distinct documents attesting the lemma in this cell"),
        Column.new(name: "license_class", description: "the source's license class")
      ].freeze

      def initialize(catalog:, langs: nil, grades: nil, page_size: PAGE_SIZE)
        @catalog = catalog
        langs = Array(langs).map(&:to_s).map(&:strip).reject(&:empty?).uniq
        @langs = langs.empty? ? nil : langs
        grades = Array(grades).map(&:to_s).map(&:strip).reject(&:empty?).uniq
        bad = grades - %w[gold silver]
        raise Error, "unknown grade #{bad.first.inspect} (gold or silver)" unless bad.empty?

        @grades = grades.empty? ? nil : grades
        @page_size = page_size
        @rows = 0
      end

      def columns = COLUMNS

      def filters = { "language" => @langs, "grade" => @grades }

      def notes
        return { "rollup_empty" => true, "hint" => "bundle exec rake builders:refresh" } if @rows.zero?

        {}
      end

      def each_row(license_classes: nil)
        _ = license_classes
        unless @catalog.table_exists?(:lemma_rollup)
          raise Error, "the lemma rollup is not in this catalog yet (migration 038) — " \
                       "it arrives with the next owner-fired rebuild"
        end

        last = 0
        loop do
          page = dataset.where(Sequel.lit("lemma_rollup.rowid") > last).limit(@page_size).all
          break if page.empty?

          page.each do |row|
            @rows += 1
            yield Row.new(values: [row[:lemma], row[:language], row[:century], row[:basis], row[:grade],
                                   row[:slug], row[:occurrences], row[:documents], row[:license_class]],
                          draws: [[row[:slug], row[:license_class]]])
          end
          last = page.last[:rid]
        end
      end

      private

      def dataset
        rollup = Sequel[:lemma_rollup]
        scope = @catalog[:lemma_rollup]
                .join(:sources, id: rollup[:source_id])
                .order(Sequel.lit("lemma_rollup.rowid"))
                .select(Sequel.lit("lemma_rollup.rowid").as(:rid), rollup[:lemma], rollup[:language],
                        rollup[:century], rollup[:basis], rollup[:grade], rollup[:occurrences],
                        rollup[:documents], Sequel[:sources][:slug].as(:slug),
                        Sequel[:sources][:license_class].as(:license_class))
        scope = scope.where(rollup[:language] => @langs) if @langs
        scope = scope.where(rollup[:grade] => @grades) if @grades
        scope
      end
    end
  end
end
