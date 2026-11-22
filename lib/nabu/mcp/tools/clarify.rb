# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_clarify tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      CLARIFY_DESCRIPTION =
        "The reference normalizer: give a partial, misspelled, or half-remembered work or passage " \
        "reference — a title prefix (\"Ilia\"), a misspelling (\"Illiad\"), a title plus citation " \
        "(\"Iliad 1.1\"), or a full/partial urn — and get an honest reading of it: `is_ref` (does " \
        "it name held text: a urn, or an EXACT document title [+ citation]), `resolved_urn` ONLY " \
        "when it parses UNIQUELY (open it with nabu_show), `ref` (passage · document · " \
        "citation_prefix · range, with license fields), `structure` (what a deeper citation looks " \
        "like there: passage count, first/last citation, depth, an example urn and a range " \
        "example), and `completions` — typed CANDIDATES {title, key, type: " \
        "document|source|lemma|place, is_primary (the matched name is the primary title, not an " \
        "alias), match: exact|prefix|token|fuzzy (a misspelling guess, said so), source, " \
        "language, license_class; present-only detail, ref_urn}. Never a silent guess: two " \
        "editions sharing a title, or a citation several hold, resolve to NOTHING and list every " \
        "reading (ref_urn each). Diacritics optional (οδυσσεια finds Ὀδύσσεια). Backed by a " \
        "precompiled title index; when it is not built the note says so and urn input still " \
        "resolves. Bounded (default #{CLARIFY_DEFAULT_LIMIT}, max #{CLARIFY_MAX_LIMIT}).".freeze

      CLARIFY_SCHEMA = {
        type: "object",
        properties: {
          query: { type: "string",
                   description: "The reference to normalize: a title (or its prefix/misspelling), a " \
                                "title plus citation (\"Iliad 1.1\"), a source name/slug, a " \
                                "dictionary headword, a place name, or a full/partial urn." },
          limit: { type: "integer", minimum: 1, maximum: CLARIFY_MAX_LIMIT,
                   default: CLARIFY_DEFAULT_LIMIT, description: "Maximum candidates returned." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["query"],
        additionalProperties: false
      }.freeze

      private

      # nabu_clarify: the reference normalizer (Query::Clarify). Catalog
      # lookups for urns, the fulltext clarify lane for names; an absent
      # lane is a corpus STATE (the payload's note + index.present: false),
      # never isError.
      def clarify(args)
        query = string_arg(args, "query") or
          raise InvalidArguments, "nabu_clarify needs a query (a title or its prefix/misspelling, a " \
                                  "title plus citation, or a urn)"
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        limit = clamp(args["limit"], default: CLARIFY_DEFAULT_LIMIT, max: CLARIFY_MAX_LIMIT)
        result = Query::Clarify.new(catalog: catalog, fulltext: resolve(@fulltext))
                               .run(query, limit: limit, include_restricted: args["include_restricted"] == true)
        json(clarify_payload(result))
      end

      def clarify_payload(result)
        {
          type: "clarify", query: result.query, is_ref: result.is_ref, resolved_urn: result.resolved_urn,
          ref: result.ref&.to_h, structure: result.structure&.to_h,
          completions: result.completions.map { |candidate| clarify_candidate_payload(candidate) },
          index: { present: result.index_present, built_at: result.index_built_at },
          note: result.note
        }
      end

      # The typed candidate (frozen order: title, key, type, is_primary,
      # match, source, language, license_class), detail/ref_urn present-only.
      def clarify_candidate_payload(candidate)
        row = { title: candidate.title, key: candidate.key, type: candidate.type,
                is_primary: candidate.is_primary, match: candidate.match, source: candidate.source,
                language: candidate.language, license_class: candidate.license_class }
        row[:detail] = candidate.detail if candidate.detail
        row[:ref_urn] = candidate.ref_urn if candidate.ref_urn
        row
      end
    end
  end
end
