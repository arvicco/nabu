# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_parallels tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      PARALLELS_DESCRIPTION =
        "Passage-anchored intertext over the local nabu corpus: give ONE passage urn and get the " \
        "passages that QUOTE or ECHO it — reception discovery, not translation alignment (that is " \
        "nabu_align). Query-time over the same FTS index as nabu_search: the anchor is folded, cut " \
        "into overlapping 4-word grams, each probed as an exact phrase; passages sharing grams are " \
        "ranked by shared-gram count WEIGHTED BY RARITY (a rare shared phrase outweighs common " \
        "function-word grams). Elision is folded across editions (SBLGNT ἐπʼ ≡ Swete ἐπ’), which is " \
        "what lets Matthew 4:4 find LXX Deuteronomy 8:3. Each `hits` entry is one DOCUMENT " \
        "(duplicate witnesses grouped; loci = how many of its passages matched) with its best " \
        "passage urn, score, shared_grams, and the shared PHRASE spans (diacritic-folded — WHAT " \
        "matched; nabu_show gives pristine text). Only the anchor's OWN document is excluded; " \
        "translations self-exclude (no shared folded tokens). When the anchor carries gold treebank " \
        "lemmas, `lemma_echoes` adds passages sharing ≥2 of its RARE lemmas (re-inflected/reordered " \
        "allusion verbatim grams miss). Bounded (default #{PARALLELS_DEFAULT_LIMIT}, max " \
        "#{PARALLELS_MAX_LIMIT}) with an honest note; every hit carries urn, language, license_class, " \
        "and source — PRESERVE the license fields when quoting. `lang`/`license` scope candidates. " \
        "`explain: true` adds each hit's per-gram score decomposition (gram → df → weight → " \
        "contribution; rows sum to the score exactly, non-contributing grams as zero rows).".freeze

      PARALLELS_SCHEMA = {
        type: "object",
        properties: {
          urn: { type: "string",
                 description: "The anchor passage urn (from a nabu_search/nabu_show hit) whose " \
                              "quotations and echoes to find." },
          lang: { type: "string",
                  description: "ISO-639-3 passage language filter on the CANDIDATES: grc, lat, chu, …" },
          license: { type: "string", enum: LICENSE_CLASSES,
                     description: "Exact effective license class filter on the candidates." },
          limit: { type: "integer", minimum: 1, maximum: PARALLELS_MAX_LIMIT,
                   default: PARALLELS_DEFAULT_LIMIT,
                   description: "Maximum hits per signal (surface parallels and lemma echoes)." },
          lect: { type: "string",
                  description: "Lect filter on the candidates (P59-3, nabu-lects module): keep " \
                               "only hits whose resolution is this lect id or a more specific " \
                               "one under it — the same prefix semantics as nabu_search's lect " \
                               "(lect: \"grc:koi\" keeps Koine candidates, drops Classical and " \
                               "bare-grc ones). Errors if the module is not synced on this box." },
          explain: { type: "boolean", default: false,
                     description: "Attach each hit's score decomposition as `explain`: one row " \
                                  "per distinct anchor gram — gram, position, positions (anchor " \
                                  "occurrences), df (probe document frequency), weight (1/df), " \
                                  "contribution, status (shared · not_shared · too_common · " \
                                  "stop). Contributions sum to the hit's score EXACTLY; grams " \
                                  "adding nothing are explicit zero rows." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["urn"],
        additionalProperties: false
      }.freeze

      private

      # nabu_parallels (P15-1): the intertext engine, bounded + license-labeled.
      # The anchor urn is echoed back (like nabu_align's ref); candidates are
      # license-filtered exactly like search, so nothing restricted leaks.
      def parallels(args)
        urn = string_arg(args, "urn") or raise InvalidArguments, "nabu_parallels needs a urn (the anchor passage)"
        license = license_arg(args)
        include_restricted = args["include_restricted"] == true
        if license && EXCLUDED_LICENSE_CLASSES.include?(license) && !include_restricted
          return note("license class #{license} is excluded by default from this surface " \
                      "(it must never leak casually); pass include_restricted: true to " \
                      "search it deliberately")
        end

        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        fulltext = search_index(:text) or return note(REBUILDING_NOTE)

        limit = clamp(args["limit"], default: PARALLELS_DEFAULT_LIMIT, max: PARALLELS_MAX_LIMIT)
        # P59-3: the lect candidate filter, module pre-checked HERE (the
        # search_lect stance) so an absent module is a clean InvalidArguments.
        lect = string_arg(args, "lect")
        lects = nil
        if lect
          lects = lects_seam
          raise InvalidArguments, "lect needs the nabu-lects module — nabu-lects module not synced" unless lects
        end
        # explain: the same engine observed (Query::ParallelsExplain) — every
        # hit additionally decomposed; the plain engine otherwise.
        engine = args["explain"] == true ? Query::ParallelsExplain : Query::Parallels
        result = engine.new(catalog: catalog, fulltext: fulltext, lects: lects || :auto)
                       .run(urn, limit: limit + 1, lang: args["lang"], license: license, lect: lect)
        return urn_not_found(urn) if result.nil?

        render_parallels(result, limit: limit, catalog: catalog, include_restricted: include_restricted)
      end

      # -- parallels internals -----------------------------------------------------

      def render_parallels(result, limit:, catalog:, include_restricted:)
        hits = result.hits
        echoes = result.lemma_echoes
        unless include_restricted
          hits = hits.reject { |hit| EXCLUDED_LICENSE_CLASSES.include?(hit.license_class) }
          echoes = echoes.reject { |echo| EXCLUDED_LICENSE_CLASSES.include?(echo.license_class) }
        end
        shown_hits = hits.first(limit)
        shown_echoes = echoes.first(limit)
        sources = sources_by_urn(catalog, (shown_hits + shown_echoes).map(&:urn))
        json(
          type: "parallels",
          anchor: { urn: result.anchor_urn, document: result.anchor_title },
          gram_count: result.gram_count,
          hits: shown_hits.map { |hit| parallels_hit_payload(hit, sources) },
          lemma_echoes: shown_echoes.map { |echo| lemma_echo_payload(echo, sources) },
          note: parallels_note(result, hits: hits, echoes: echoes, limit: limit)
        )
      end

      def parallels_hit_payload(hit, sources)
        payload = {
          urn: hit.urn, language: hit.language, license_class: hit.license_class,
          source: sources[hit.urn], document: hit.document_title,
          score: hit.score, shared_grams: hit.shared_gram_count, loci: hit.loci,
          evidence: hit.evidence.first(PARALLELS_EVIDENCE_CAP)
        }
        payload[:evidence_truncated] = true if hit.evidence.size > PARALLELS_EVIDENCE_CAP
        # The explain surface, present-only (explain: true): the additive
        # per-gram decomposition of `score` — rows sum to it exactly.
        payload[:explain] = hit.contributions.map(&:to_h) if hit.respond_to?(:contributions)
        payload
      end

      def lemma_echo_payload(echo, sources)
        { urn: echo.urn, language: echo.language, license_class: echo.license_class,
          source: sources[echo.urn], score: echo.score, shared_lemmas: echo.shared_lemmas }
      end

      def parallels_note(result, hits:, echoes:, limit:)
        return "anchor too short for #{Query::Parallels::GRAM_SIZE}-word grams — no parallels" \
          if result.gram_count.zero?

        parts = [
          if hits.size > limit
            "more than #{limit} parallels, showing #{limit} — raise limit (max #{PARALLELS_MAX_LIMIT})"
          else
            "#{hits.size} #{hits.size == 1 ? 'parallel' : 'parallels'} from #{result.gram_count} grams"
          end,
          "evidence spans are the diacritic-folded shared phrases (WHAT matched); nabu_show gives pristine text",
          "each hit is one document (duplicate witnesses grouped; loci = matching passages); " \
          "PRESERVE the license fields when quoting"
        ]
        unless echoes.empty?
          parts << "lemma_echoes: rare-lemma co-occurrence for re-inflected/reordered allusion " \
                   "(present only when the anchor is gold-lemmatized)"
        end
        parts.join("; ")
      end
    end
  end
end
