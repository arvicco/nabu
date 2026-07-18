# frozen_string_literal: true

require_relative "../../adapters/tla_hf"

module Nabu
  module Store
    module AxisBuilder
      # TLA Hugging Face sentence dates (P28-2): the pre-cooked
      # dateNotBefore/dateNotAfter integers every record carries — witness
      # dates for the text behind each sentence, varying record by record,
      # so the rows are PASSAGE-GRAIN (the ChronicleAnnals shape): one
      # document-grain envelope row first (min..max over the dated records,
      # passage_seq NULL) so document-grain consumers see each dataset once,
      # honestly wide, then one row per dated record anchored by
      # passage_seq_from = passage_seq_to = its sequence.
      #
      # Reading goes through the SAME TlaJsonlParser the adapter parses
      # with, and sequence = record.number - 1 mirrors the adapter's
      # passage mint (FROZEN; the drift pin lives in the test) — so axis
      # rows can never disagree with the catalog about which sentence they
      # date. Honest absences: an undated record (both fields empty — 710
      # in the demotic corpus, censused) gets no row, counted, never
      # guessed; -de siblings never join (their urns carry the -de suffix,
      # no dataset slug does).
      module TlaHfDates
        SLUG = "tla-hf"
        URN_PREFIX = Adapters::TlaHf::URN_PREFIX

        module_function

        # Walk canonical/tla-hf's datasets and insert the envelope + row per
        # dated record for each dataset document we hold. Returns
        # { documents:, sentences:, undated: }.
        def build(catalog:, canonical_dir:)
          workdir = File.join(canonical_dir, SLUG)
          return { documents: 0, sentences: 0, undated: 0 } unless Dir.exist?(workdir)

          documents = 0
          sentences = 0
          undated = 0
          parser = Adapters::TlaJsonlParser.new
          Adapters::TlaHf::DATASETS.each do |slug, dataset|
            outcome = build_dataset(catalog, workdir, parser, slug, dataset)
            next if outcome.nil?

            documents += 1
            sentences += outcome[:sentences]
            undated += outcome[:undated]
          end
          { documents: documents, sentences: sentences, undated: undated }
        end

        # One dataset → its axis rows, or nil when the file is absent or the
        # document is not in the catalog.
        def build_dataset(catalog, workdir, parser, slug, dataset)
          path = Dir.glob(File.join(workdir, dataset.fetch(:subdir), "**",
                                    Adapters::TlaHf::FILENAME)).first
          return nil if path.nil?

          document_id = catalog[:documents].where(urn: "#{URN_PREFIX}#{slug}").get(:id)
          return nil if document_id.nil?

          rows = []
          undated = 0
          parser.each_record(path) do |record|
            row = extract(record)
            row.nil? ? undated += 1 : rows << row
          end
          return { sentences: 0, undated: undated } if rows.empty?

          insert_envelope(catalog, document_id, rows)
          rows.each { |row| catalog[:document_axes].insert(row.merge(document_id: document_id)) }
          { sentences: rows.size, undated: undated }
        end

        # One dated record → its passage-grain row fields, or nil for an
        # undated record (skipped, counted, never guessed). Bounds are
        # upstream's own signed integers, verbatim; precision "year" for a
        # point, else "range" (honest envelope, never a midpoint).
        def extract(record)
          not_before = record.not_before
          not_after = record.not_after
          return nil if not_before.nil? && not_after.nil?

          sequence = record.number - 1 # the adapter's passage mint (FROZEN)
          {
            not_before: not_before, not_after: not_after,
            precision: not_before == not_after ? "year" : "range",
            date_raw: date_raw(not_before, not_after),
            passage_seq_from: sequence, passage_seq_to: sequence,
            axis_source: SLUG
          }
        end

        def date_raw(not_before, not_after)
          return not_before.to_s if not_before == not_after

          "#{not_before}–#{not_after}"
        end

        # The document-grain row: the dataset's full dated span, inserted
        # BEFORE the per-record rows so document-grain readers meet it first
        # (the ChronicleAnnals stance).
        def insert_envelope(catalog, document_id, rows)
          not_before = rows.filter_map { |row| row[:not_before] }.min
          not_after = rows.filter_map { |row| row[:not_after] }.max
          catalog[:document_axes].insert(
            document_id: document_id, not_before: not_before, not_after: not_after,
            precision: "range", date_raw: "#{not_before}–#{not_after}",
            axis_source: SLUG
          )
        end
      end
    end
  end
end
