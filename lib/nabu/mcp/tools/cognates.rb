# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_cognates tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      COGNATES_DESCRIPTION =
        "Cognates-in-parallel over the local nabu corpus: verses of a registered alignment work " \
        "where witnesses in TWO OR MORE languages use reflexes of the SAME reconstruction root — " \
        "Gothic salt ~ OCS соль under PIE *sḗh₂l in the salt saying (Luke 14:34). The alignment " \
        "hub (nabu_align) supplies the verse columns; the Wiktionary reconstruction crosswalk " \
        "(nabu_etym) supplies the lemma→root closure over the shelf-visited multi-hop walk " \
        "(got→*saltą→*sḗh₂l←*solь←chu). `target` is a work id (batch the work) or a " \
        "citation/chapter/book ref; `langs` restricts to ≥2 named languages (e.g. " \
        "[\"got\",\"chu\"]). Each group carries the verse ref, the root (headword, SHELF " \
        "language, gloss, license — PRESERVE license fields when quoting), and per-language " \
        "witness words (lemma, attested surface forms, attesting documents with licenses, and " \
        "a `borrowed` flag: true = the crosswalk marks this witness's descent a loan — " \
        "hlaifs ~ хлѣбъ(borrowed:true) at *hlaibaz; null = not yet flagged either way). READ " \
        "THE SHELF for unflagged edges: a meet at gem-pro involving a Slavic witness is very " \
        "possibly a BORROWING, not common descent; " \
        "ine-pro meets are the inheritance signal. Corpus-common words are suppressed with an " \
        "honest count (`all` lifts; frequency is a coarse proxy and some common words survive). " \
        "Recall is bounded by Wiktionary coverage (~1/3 of Gothic, ~1/5 of OCS gold lemma types " \
        "reach any proto entry) and by gold lemmatization (~10% of the corpus): no hit is " \
        "absence of evidence, not evidence of unrelatedness. Bounded (default " \
        "#{COGNATES_DEFAULT_LIMIT} groups, max #{COGNATES_MAX_LIMIT}) with honest totals.".freeze

      COGNATES_SCHEMA = {
        type: "object",
        properties: {
          target: { type: "string",
                    description: "A registered alignment work id (nt|ot|psalms — batches the " \
                                 "whole work) or a citation ref: verse (\"LUKE 14.34\"), " \
                                 "chapter (\"LUKE 14\"), or book (\"LUKE\")." },
          work: { type: "string",
                  description: "Alignment work id, when a bare ref is ambiguous across works." },
          langs: { type: "array", items: { type: "string" }, minItems: 2,
                   description: "Restrict the comparison to these languages (ISO-639-3, at " \
                                "least two: [\"got\",\"chu\"]). Default: every gold language." },
          all: { type: "boolean", default: false,
                 description: "Also return the corpus-common-word matches the default " \
                              "suppresses." },
          limit: { type: "integer", minimum: 1, maximum: COGNATES_MAX_LIMIT,
                   default: COGNATES_DEFAULT_LIMIT,
                   description: "Maximum (verse, root) groups returned." },
          lect: { type: "string",
                  description: "Scope witnesses OF THIS LECT'S ANCHOR LANGUAGE to the lect " \
                               "(P59-3: lect: \"grc:koi\" keeps cognate sets whose Greek " \
                               "witness is Koine; other-language witnesses pass untouched). " \
                               "Errors if the nabu-lects module is not synced on this box." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["target"],
        additionalProperties: false
      }.freeze

      private

      # Cognates-in-parallel (P15-3): the hub × crosswalk join, bounded and
      # license-labeled per witness document. Restricted witnesses are
      # excluded INSIDE the query (their words never join, and a root left
      # with one language falls out) unless include_restricted.
      def cognates(args)
        target = string_arg(args, "target") or
          raise InvalidArguments, "nabu_cognates needs a target (a work id like nt, or a ref like LUKE 14.34)"
        registry = resolve(@alignments)
        return note(NO_ALIGNMENTS_NOTE) if registry.nil? || registry.empty?

        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        fulltext = resolve(@fulltext)
        return note(COGNATES_REBUILDING_NOTE) unless fulltext&.table_exists?(Store::ReflexRootsIndexer::TABLE)

        limit = clamp(args["limit"], default: COGNATES_DEFAULT_LIMIT, max: COGNATES_MAX_LIMIT)
        exclude = args["include_restricted"] == true ? [] : EXCLUDED_LICENSE_CLASSES
        # P59-3: the anchor-scoped lect filter, module pre-checked HERE.
        lect = string_arg(args, "lect")
        lects = nil
        if lect
          lects = lects_seam
          raise InvalidArguments, "lect needs the nabu-lects module — nabu-lects module not synced" unless lects
        end
        result = Query::Cognates.new(catalog: catalog, fulltext: fulltext, registry: registry,
                                     lects: lects || :auto)
                                .run(target, work: string_arg(args, "work"), langs: args["langs"],
                                             all: args["all"] == true, long: true, exclude_license: exclude,
                                             lect: lect)
        render_cognates(result, limit: limit)
      rescue Query::Cognates::Error => e
        tool_error(e.message)
      end

      # nabu_cognates (P15-3): bounded groups, the meet SHELF on every root,
      # license labels on the root and on every attesting witness document.
      def render_cognates(result, limit:)
        shown = result.groups.first(limit)
        json(
          work: result.work, query: result.query, total: result.total,
          suppressed_common_word_hits: result.suppressed,
          groups: shown.map { |group| cognates_group_payload(group, result.documents) },
          note: cognates_note(result, shown: shown)
        )
      end

      def cognates_group_payload(group, documents)
        {
          ref: group.ref,
          root: { urn: group.root.urn, headword: group.root.headword,
                  shelf: group.root.shelf, dictionary: group.root.dictionary_title,
                  gloss: group.root.gloss, license: group.root.license,
                  license_class: group.root.license_class, source: group.root.source_slug },
          witnesses: group.witnesses.map do |witness|
            # borrowed (P17-3): true = the crosswalk flags this witness's
            # descent a loan; false = parsed unflagged; null = closure
            # predates the flag (unknown, not a claimed false).
            { language: witness.language, lemma: witness.lemma, borrowed: witness.borrowed,
              surfaces: witness.surfaces,
              documents: witness.document_urns.map do |urn|
                doc = documents.fetch(urn, {})
                { urn: urn, license_class: doc[:license_class], source: doc[:source_slug] }
              end }
          end
        }
      end

      def cognates_note(result, shown:)
        parts = [if result.total > shown.size
                   "#{result.total} (verse, root) hits, showing #{shown.size} — raise limit " \
                     "(max #{COGNATES_MAX_LIMIT}) or narrow the target"
                 else
                   "#{shown.size} (verse, root) #{shown.size == 1 ? 'hit' : 'hits'}"
                 end]
        if result.suppressed.positive?
          parts << "#{result.suppressed} common-word hits suppressed (all: true shows them)"
        end
        parts << "a gem-pro meet with a Slavic witness is likely a borrowing, not common descent"
        parts.join("; ")
      end
    end
  end
end
