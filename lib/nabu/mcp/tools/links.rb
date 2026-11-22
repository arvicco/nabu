# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_links tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      LINKS_DESCRIPTION =
        "Batch-mined cross-reference edges touching a passage/document urn — the links journal " \
        "(kind=parallel from `nabu parallels --batch`; kind=formula from `formulas --batch`, a " \
        "star per refrain whose detail carries the gram and score its count; kind=cognate from " \
        "`cognates --batch`, cross-language witness pairs whose detail carries the meet: " \
        "ref · root [shelf] — a gem-pro shelf under a Slavic witness suggests a borrowing; " \
        "kind=reuse from the KITAB text-reuse import, UPSTREAM-computed pairwise Arabic " \
        "alignments whose detail carries the milestone/offset spans verbatim). " \
        "READS ONLY what a batch run already persisted: for on-the-fly discovery use " \
        "nabu_parallels; an empty result means no batch has covered this urn, NOT that no " \
        "parallel exists. Edges come back grouped by kind, both directions (direction=out: this " \
        "urn's anchor probe discovered the counterpart; in: another anchor found this urn), each " \
        "counterpart resolved to document title/language/license_class/source (null when no longer in " \
        "the catalog — edges are urn-keyed and outlive rebuilds). `runs` cites the producer " \
        "run(s): producer, scope, params, code_version, date — every edge's provenance. Bounded " \
        "per kind (default #{LINKS_DEFAULT_LIMIT}, max #{LINKS_MAX_LIMIT}) with an honest note; " \
        "PRESERVE the license fields when quoting.".freeze

      LINKS_SCHEMA = {
        type: "object",
        properties: {
          urn: { type: "string",
                 description: "The passage or document urn whose mined edges to read." },
          limit: { type: "integer", minimum: 1, maximum: LINKS_MAX_LIMIT,
                   default: LINKS_DEFAULT_LIMIT,
                   description: "Maximum edges returned per kind." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["urn"],
        additionalProperties: false
      }.freeze

      private

      # nabu_links (P16-1): the links-journal reader, bounded + license-labeled.
      # Reads ONLY persisted batch output — never mines (batch runs are
      # owner-fired). Restricted-class counterparts are excluded by default
      # exactly like every other surface, with an honest per-kind count.
      def links(args)
        urn = string_arg(args, "urn") or raise InvalidArguments, "nabu_links needs a urn"
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        journal = resolve(@links) or
          return note("no links journal — edges appear after the owner runs a batch producer " \
                      "(nabu parallels --batch); nabu_parallels discovers parallels on the fly")

        limit = clamp(args["limit"], default: LINKS_DEFAULT_LIMIT, max: LINKS_MAX_LIMIT)
        result = Query::Links.new(catalog: catalog, journal: journal).run(urn)
        if result.nil?
          return note("urn not found: #{urn} — no catalog entry and no edges; nabu_search finds " \
                      "passages, nabu_parallels discovers parallels on the fly")
        end

        render_links(result, limit: limit, include_restricted: args["include_restricted"] == true,
                             catalog: catalog)
      end

      def render_links(result, limit:, include_restricted:, catalog:)
        kinds = result.groups.transform_values do |edges|
          include_restricted ? edges : edges.reject { |e| EXCLUDED_LICENSE_CLASSES.include?(e.license_class) }
        end
        shown = kinds.transform_values { |edges| edges.first(limit) }
        sources = counterpart_sources(catalog, shown.values.flatten.map(&:urn).uniq)
        json(
          type: "links",
          urn: result.urn, document: result.title,
          kinds: shown.sort.to_h { |kind, edges| [kind, edges.map { |e| link_edge_payload(e, sources) }] },
          runs: result.runs.map do |run|
            row = { id: run.id, producer: run.producer, scope: run.scope, params: run.params,
                    code_version: run.code_version, created_at: run.created_at.to_s }
            run.mined? ? row.merge(mined_at: run.mined_at.to_s) : row
          end,
          note: links_note(result, kinds: kinds, limit: limit)
        )
      end

      # detail (P16-2): per-edge evidence — the formula gram, the cognate
      # meet (ref · root [shelf]); nil on parallel edges. source (the
      # reference envelope): the counterpart's source slug, null when the
      # counterpart no longer resolves in the catalog. mined_at (additive,
      # present ONLY on a mined layer's edge — the heavy class, local/
      # mined-links.sqlite3): the date its layer was mined.
      def link_edge_payload(edge, sources = {})
        payload = { direction: edge.direction, urn: edge.urn, document: edge.title,
                    language: edge.language, license_class: edge.license_class,
                    source: sources[edge.urn], score: edge.score, detail: edge.detail }
        edge.mined_at ? payload.merge(mined_at: edge.mined_at.to_s) : payload
      end

      # { urn => source slug } across the three grains a links counterpart
      # can name — passage, document, dictionary entry — each one indexed
      # urn lookup batch (Query::Links' own resolution order).
      def counterpart_sources(catalog, urns)
        return {} if urns.empty?

        found = sources_by_urn(catalog, urns)
        rest = urns - found.keys
        unless rest.empty?
          found = found.merge(catalog[:documents].join(:sources, id: Sequel[:documents][:source_id])
                                                 .where(Sequel[:documents][:urn] => rest)
                                                 .select_hash(Sequel[:documents][:urn], Sequel[:sources][:slug]))
        end
        rest = urns - found.keys
        return found if rest.empty? || !catalog.table_exists?(:dictionary_entries)

        found.merge(catalog[:dictionary_entries]
                      .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
                      .join(:sources, id: Sequel[:dictionaries][:source_id])
                      .where(Sequel[:dictionary_entries][:urn] => rest)
                      .select_hash(Sequel[:dictionary_entries][:urn], Sequel[:sources][:slug]))
      end

      def links_note(result, kinds:, limit:)
        shown = kinds.values.sum { |edges| edges.first(limit).size }
        if shown.zero?
          return "no persisted edges touch this urn — no batch run has covered it " \
                 "(NOT proof no parallel exists; try nabu_parallels)"
        end

        parts = ["#{shown} of #{result.total} edges shown (per-kind limit #{limit})"]
        parts << "direction out = this urn's batch anchor discovered the counterpart; in = the reverse"
        parts << "edges are persisted batch output (see runs for provenance); PRESERVE license fields"
        if kinds.values.flatten.any?(&:mined_at)
          parts << "an edge carrying mined_at comes from a mined layer — re-mined only on demand, " \
                   "so it reflects the catalog as of that date"
        end
        parts.join("; ")
      end
    end
  end
end
