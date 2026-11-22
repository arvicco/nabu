# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_concord tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      CONCORD_DESCRIPTION =
        "Concordance (KWIC — keyword-in-context) over the local nabu corpus: one row per hit as " \
        "left context / matched keyword / right context, the keyword located in the PRISTINE " \
        "edition text (accents intact). Give EXACTLY ONE of `query` (full-text, same syntax as " \
        "nabu_search: words AND, \"phrase\", prefix*, diacritics optional) or `lemma` (exact " \
        "dictionary form over the treebanks). Rows come in CORPUS order (urn/citation), not " \
        "relevance — this is for scanning a word's usage, not ranking. Context is trimmed to " \
        "`width` characters per side (default #{CONCORD_DEFAULT_WIDTH}, max #{CONCORD_MAX_WIDTH}; " \
        "… marks clipped context). Bounded (default #{CONCORD_DEFAULT_LIMIT}, max " \
        "#{CONCORD_MAX_LIMIT}) with an honest 'showing k' note; each row carries urn, language, " \
        "license_class, and source — PRESERVE the license fields when quoting. Use nabu_show for " \
        "a hit's full passage, nabu_search when you want ranked relevance rather than a scan.".freeze

      CONCORD_SCHEMA = {
        type: "object",
        properties: {
          query: { type: "string",
                   description: "Full-text query. Mutually exclusive with lemma." },
          lemma: { type: "string",
                   description: "Dictionary form for exact-lemma treebank concordance. " \
                                "Mutually exclusive with query." },
          lang: { type: "string",
                  description: "ISO-639-3 passage language filter: grc, lat, chu, got, orv, eng, …" },
          license: { type: "string", enum: LICENSE_CLASSES,
                     description: "Exact effective license class filter." },
          limit: { type: "integer", minimum: 1, maximum: CONCORD_MAX_LIMIT,
                   default: CONCORD_DEFAULT_LIMIT, description: "Maximum KWIC rows returned." },
          width: { type: "integer", minimum: 1, maximum: CONCORD_MAX_WIDTH,
                   default: CONCORD_DEFAULT_WIDTH,
                   description: "Context characters per side (left and right)." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        additionalProperties: false
      }.freeze

      private

      def concord(args)
        term, mode = search_term(args)
        license = license_arg(args)
        include_restricted = args["include_restricted"] == true
        if license && EXCLUDED_LICENSE_CLASSES.include?(license) && !include_restricted
          return note("license class #{license} is excluded by default from this surface " \
                      "(it must never leak casually); pass include_restricted: true to " \
                      "concord it deliberately")
        end

        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        fulltext = search_index(mode) or return note(mode == :lemma ? LEMMA_REBUILDING_NOTE : REBUILDING_NOTE)

        limit = clamp(args["limit"], default: CONCORD_DEFAULT_LIMIT, max: CONCORD_MAX_LIMIT)
        width = clamp(args["width"], default: CONCORD_DEFAULT_WIDTH, max: CONCORD_MAX_WIDTH)
        rows = Query::Concord.new(catalog: catalog, fulltext: fulltext).run(
          mode == :lemma ? nil : term, lemma: mode == :lemma ? term : nil,
                                       lang: args["lang"], license: license, limit: limit + 1, width: width
        )
        rows = rows.reject { |row| EXCLUDED_LICENSE_CLASSES.include?(row.license_class) } unless include_restricted
        render_concord(rows, limit: limit, width: width, catalog: catalog)
      end

      # -- concord internals -------------------------------------------------------

      def render_concord(rows, limit:, width:, catalog:)
        return json(rows: [], note: "no matches", coverage: coverage_hint(catalog)) if rows.empty?

        shown = rows.first(limit)
        sources = sources_by_urn(catalog, shown.map(&:urn))
        json(
          width: width,
          rows: shown.map { |row| concord_row_payload(row, sources) },
          note: if rows.size > limit
                  "more than #{limit} rows, showing #{limit} — raise limit " \
                    "(max #{CONCORD_MAX_LIMIT}) or refine"
                else
                  "#{shown.size} rows, showing #{shown.size}"
                end
        )
      end

      # Left/keyword/right are already width-trimmed by Concord; the model can
      # reassemble the KWIC line or read the keyword in isolation. license
      # fields ride on every row, per contract. tier (P26-4): present only on
      # NON-gold lemma-mode rows — the lemma-hit mirror (silver labeled, gold
      # and text-mode rows unlabeled as ever).
      def concord_row_payload(row, sources)
        payload = { urn: row.urn, language: row.language, license_class: row.license_class,
                    source: sources[row.urn], left: row.left, keyword: row.keyword, right: row.right }
        payload[:tier] = row.tier if row.tier && row.tier != "gold"
        payload
      end
    end
  end
end
