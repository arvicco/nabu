# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_etym tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      ETYM_DESCRIPTION =
        "Walk the reconstruction crosswalk (the comparativist's join): give an ATTESTED " \
        "lemma (богъ, guþ, deus) and get every reconstructed ancestor whose Wiktionary " \
        "descendants name it — Proto-Slavic, PIE, Proto-Germanic, Proto-Balto-Slavic, " \
        "Proto-West Germanic, Proto-Italic, Proto-Indo-Iranian (kaikki.org " \
        "extracts, CC-BY-SA + GFDL; PRESERVE license fields when quoting). Each entry " \
        "carries the *headword, gloss, the reflex that matched (matched_via, incl. its " \
        "borrowed loan flag), its COGNATES " \
        "across languages with corpus attestation counts (attested_count = gold-lemma " \
        "passages in this catalog; null = not attested here, an absence not a zero) and " \
        "per-edge borrowed flags, and nested `ancestors` — the full chain up the proto " \
        "shelves (прьстъ→*pьrstъ→*pírštan→*per-), bounded because each shelf enters a " \
        "walk once; a loan edge carries edge_borrowed: true. Romanization " \
        "bridges scripts: guþ reaches *gudą through Gothic 𐌲𐌿𐌸. `lang` scopes the match " \
        "to one attested language; a leading asterisk (*bogъ) looks a reconstruction up " \
        "directly. A lemma with NO crosswalk path falls back to the dictionary shelf " \
        "(nabu_define's own lookup): the reply then carries `dictionary_entries` (the " \
        "nabu_define payload shape — a prose etymological article like Vasmer's still " \
        "answers) plus an explanatory note; a genuine total miss enumerates the " \
        "crosswalk's live shelves. Cognate lists are bounded (attested first, " \
        "#{ETYM_MAX_COGNATES} shown) " \
        "with honest totals; `nabu etym` (CLI) is unbounded.".freeze

      ETYM_SCHEMA = {
        type: "object",
        properties: {
          lemma: { type: "string",
                   description: "An attested lemma (богъ, guþ, deus) — or a reconstruction " \
                                "with a leading asterisk (*bogъ) for a direct lookup." },
          lang: { type: "string",
                  description: "Scope the reflex match to one attested language " \
                               "(ISO-639-3: chu, orv, got, grc, lat, ang, san, …)." },
          limit: { type: "integer", minimum: 1, maximum: ETYM_MAX_LIMIT,
                   default: ETYM_DEFAULT_LIMIT,
                   description: "Maximum reconstruction entries returned." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["lemma"],
        additionalProperties: false
      }.freeze

      private

      # The reconstruction walk (P14-1): attested lemma → proto entries with
      # cognates + one ascent hop. Same shelf guards and license stance as
      # nabu_define; the crosswalk table additionally needs migration 007.
      def etym(args)
        lemma = string_arg(args, "lemma") or raise InvalidArguments, "nabu_etym needs a lemma"
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        return note(NO_RECON_NOTE) unless catalog.table_exists?(:dictionary_reflexes)

        limit = clamp(args["limit"], default: ETYM_DEFAULT_LIMIT, max: ETYM_MAX_LIMIT)
        include_restricted = args["include_restricted"] == true
        query = Query::Etym.new(catalog: catalog, fulltext: resolve(@fulltext))
        results = query.run(lemma, lang: string_arg(args, "lang"), limit: limit + 1)
        results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        return render_etym(results, limit: limit) unless results.empty?

        # P24-2 coordination (the CLI's exact fallback): a crosswalk miss
        # consults the SAME Query::Define lookup nabu_define runs — a
        # prose etymological article (Vasmer) answers under an honest
        # note; hits above never mix with the fallback.
        entries = Query::Define.new(catalog: catalog, fulltext: resolve(@fulltext), scan_anchors: @scan_anchors)
                               .run(lemma, lang: string_arg(args, "lang"), limit: limit + 1)
        entries = entries.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        render_etym_fallback(entries, lemma: lemma, limit: limit, shelves: query.crosswalk_shelves)
      end

      # -- etym internals -----------------------------------------------------------

      # P24-2: the crosswalk-miss path — the CLI fallback's MCP mirror.
      # Dictionary entries answering the lemma ride define_payload (zero
      # payload divergence with nabu_define) under `dictionary_entries`
      # plus an explanatory note; a genuine total miss enumerates the
      # crosswalk shelves DB-DRIVEN (Query::Etym#crosswalk_shelves — the
      # P11 DEFINE_LANGS hardcoded-list lesson).
      def render_etym_fallback(entries, lemma:, limit:, shelves:)
        if entries.empty?
          covered = shelves.empty? ? "no shelves yet" : shelves.join(", ")
          return json(entries: [],
                      note: "no reconstruction names #{lemma.inspect} as a descendant, no " \
                            "reconstruction headword matches it, and no dictionary entry " \
                            "defines it — the crosswalk covers #{covered}. Try the lemma's " \
                            "dictionary form, or a quoted '*form' for a direct lookup (quote " \
                            "the star — a bare * is a shell glob)")
        end

        shown = entries.first(limit)
        json(
          entries: [],
          dictionary_entries: shown.map { |result| define_payload(result) },
          note: "no reconstruction path in the crosswalk for #{lemma.inspect} — the dictionary " \
                "shelf holds #{shown.size == 1 ? 'this entry' : "these #{shown.size} entries"} " \
                "(the nabu_define payload shape)" \
                "#{" — more exist; raise limit (max #{ETYM_MAX_LIMIT})" if entries.size > limit}"
        )
      end

      def render_etym(results, limit:)
        shown = results.first(limit)
        json(
          entries: shown.map { |result| etym_payload(result) },
          note: if results.size > limit
                  "more than #{limit} entries, showing #{limit} — raise limit (max #{ETYM_MAX_LIMIT})"
                else
                  "#{shown.size} #{shown.size == 1 ? 'entry' : 'entries'}"
                end
        )
      end

      # P17-3: ancestors nest recursively — the shelf-visited walk bounds
      # the depth (each dictionary language enters a walk once), so the
      # payload stays finite without a depth constant. edge_borrowed is the
      # loan flag of the edge that reached an ancestor (null = unflagged
      # top-level entry OR a row predating the flag reparse — an unknown,
      # never a claimed false).
      def etym_payload(result)
        base = {
          urn: result.urn, dictionary: result.dictionary_slug,
          dictionary_title: result.dictionary_title, headword: result.headword,
          language: result.language, gloss: result.gloss,
          license_class: result.license_class, license: result.license,
          source: result.source_slug
        }
        if result.matched_reflex
          base[:matched_via] = { language: result.matched_reflex.language,
                                 word: result.matched_reflex.word,
                                 roman: result.matched_reflex.roman,
                                 borrowed: result.matched_reflex.borrowed }
        end
        base[:edge_borrowed] = result.edge_borrowed unless result.edge_borrowed.nil?
        base.merge!(reflex_fields(result.cognates, cap: ETYM_MAX_COGNATES, key: :cognates))
        base[:ancestors] = result.ancestors.map { |a| etym_payload(a) }
        base
      end

      # Shared reflex/cognate list rendering (define + etym): gold-attested
      # first (by count, descending), then silver-only (P26-0 — labeled by
      # the silver_count key, attested_count honestly null), then
      # equivalence-only (P34-3 — the equivalence_count key:
      # scholar-curated Classical-Latin equivalents on non-Latin passages,
      # never attestation), then the rest, capped with an honest total.
      # attested_count stays GOLD-only; a silver_count / equivalence_count
      # key appears only where such rows exist — never summed into
      # attested_count, never a bare number.
      # Split note: also read by nabu_define (tools/define.rb); kept with its primary user.
      def reflex_fields(views, cap:, key: :reflexes)
        attested, uncounted = views.partition(&:attested_count)
        silver_only, unattested = uncounted.partition(&:silver_count)
        equivalence_only, rest = unattested.partition(&:equivalence_count)
        ordered = attested.sort_by { |view| -view.attested_count } +
                  silver_only.sort_by { |view| -view.silver_count } +
                  equivalence_only.sort_by { |view| -view.equivalence_count } + rest
        shown = ordered.first(cap).map do |view|
          row = { lang_code: view.lang_code, language: view.language, word: view.word,
                  roman: view.roman, attested_count: view.attested_count }
          row[:silver_count] = view.silver_count if view.silver_count
          row[:equivalence_count] = view.equivalence_count if view.equivalence_count
          row
        end
        fields = { key => shown, :"#{key}_total" => views.size }
        fields[:"#{key}_attested"] = attested.size
        fields
      end
    end
  end
end
