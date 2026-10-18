# frozen_string_literal: true

require "json"

require_relative "metadata_dates"

module Nabu
  module Store
    module TimelineBuilder
      # The TLG concordance lane: an in-library JOIN that dates the Greek
      # CTS editions by the composition envelopes two sibling corpora
      # already carry for the same works.
      #
      # glaux (start_date/end_date) and diorisis (creation_date) key their
      # per-work composition dates by TLG author.work ids — glaux's urn
      # "urn:nabu:glaux:0012-001", diorisis' "urn:nabu:diorisis:0012:001" —
      # and the Perseus/First1K CTS urns carry the same pair
      # ("urn:cts:greekLit:tlg0012.tlg001.perseus-grc2"). The editions'
      # own headers date only their printed source (the edition-class rows
      # MetadataDates projects); this lane adds the WORK's era as a
      # derived, labeled row: axis_source "tlg-concordance", date_class
      # "composition", date_raw "dated by the glaux concordance
      # (tlg0012.tlg001): -800–-701" — the witness and the key always
      # visible, never passed off as the edition's own claim.
      #
      # Precedence: glaux first (bounded ranges; lettered work parts —
      # 0007-051a/-051b — envelope onto the shared work), else diorisis
      # (its single signed year). Only ORIGINAL-language editions (grc*)
      # row; translations date nothing here (the MetadataDates
      # translation-sibling stance). Census 2026-10-18: 758 of 769
      # perseus-greek grc editions and 479 of 1,088 first1k-greek join.
      # Catalog-only (metadata_json + urns): rebuild-safe, no canonical walk.
      module TlgConcordanceDates
        AXIS_SOURCE = "tlg-concordance"
        TARGETS = %w[perseus-greek first1k-greek].freeze
        # In precedence order.
        WITNESSES = %w[glaux diorisis].freeze

        GLAUX_URN = /\Aurn:nabu:glaux:(\d{4})-(\d{3})[a-z]?\z/
        DIORISIS_URN = /\Aurn:nabu:diorisis:(\d{4}):(\d{3})\z/
        TARGET_URN = /\Aurn:cts:greekLit:(tlg\d{4})\.(tlg\d{3})\./
        ORIGINAL_LANGUAGE = "grc"
        BATCH = 2_000

        module_function

        # {target slug => rows minted}.
        def build(catalog:)
          table = concordance(catalog)
          TARGETS.to_h { |slug| [slug, build_target(catalog, slug, table)] }
        end

        # The per-source seam: a sync of a target OR a witness re-derives
        # the whole (small) lane; any other slug is a no-op. Returns rows.
        def refresh_source!(catalog:, slug:)
          return 0 unless TARGETS.include?(slug) || WITNESSES.include?(slug)

          catalog[:document_axes].where(axis_source: AXIS_SOURCE).delete
          build(catalog: catalog).values.sum
        end

        # {"tlg0012.tlg001" => {bounds: [nb, na], witness: "glaux"}}.
        def concordance(catalog)
          diorisis = witness_rows(catalog, "diorisis", DIORISIS_URN) do |meta|
            year = MetadataDates.signed_year(meta["creation_date"])
            year && [year, year]
          end
          glaux = witness_rows(catalog, "glaux", GLAUX_URN) do |meta|
            bounds = [MetadataDates.signed_year(meta["start_date"]), MetadataDates.signed_year(meta["end_date"])]
            bounds.compact.empty? ? nil : bounds
          end
          diorisis.transform_values { |bounds| { bounds: bounds, witness: "diorisis" } }
                  .merge(glaux.transform_values { |bounds| { bounds: bounds, witness: "glaux" } })
        end

        # {key => envelope} for one witness source: every live document
        # whose urn decodes, its bounds enveloped per key (min lower, max
        # upper; an open side stays open only if every part leaves it open).
        def witness_rows(catalog, slug, pattern)
          source_id = catalog[:sources].where(slug: slug).get(:id)
          return {} if source_id.nil?

          envelopes = {}
          catalog[:documents].where(source_id: source_id, withdrawn: false)
                             .select_map(%i[urn metadata_json]).each do |urn, json|
            match = pattern.match(urn) or next
            bounds = yield(JSON.parse(json.to_s.empty? ? "{}" : json)) or next

            key = "tlg#{match[1]}.tlg#{match[2]}"
            envelopes[key] = envelope(envelopes[key], bounds)
          end
          envelopes
        end

        def envelope(current, bounds)
          return bounds if current.nil?

          [[current[0], bounds[0]].compact.min, [current[1], bounds[1]].compact.max]
        end

        def build_target(catalog, slug, table)
          source_id = catalog[:sources].where(slug: slug).get(:id)
          return 0 if source_id.nil?

          rows = catalog[:documents]
                 .where(source_id: source_id, withdrawn: false)
                 .where(Sequel.like(:language, "#{ORIGINAL_LANGUAGE}%"))
                 .select_map(%i[id urn]).filter_map do |id, urn|
                   match = TARGET_URN.match(urn) or next
                   key = "#{match[1]}.#{match[2]}"
                   hit = table[key] or next

                   row(id, key, hit)
                 end
          rows.each_slice(BATCH) { |slice| catalog[:document_axes].multi_insert(slice) }
          rows.size
        end

        def row(document_id, key, hit)
          not_before, not_after = Timeline.normalize_interval(*hit[:bounds], raw: key)
          span = not_before == not_after ? not_before.to_s : [not_before, not_after].compact.join("–")
          { document_id: document_id, not_before: not_before, not_after: not_after,
            precision: nil, date_class: "composition", axis_source: AXIS_SOURCE,
            date_raw: "dated by the #{hit[:witness]} concordance (#{key}): #{span}" }
        end
      end
    end
  end
end
