# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_search tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      SEARCH_DESCRIPTION =
        "Search nabu, a local corpus of ancient texts (polytonic Greek, Latin, Old Church " \
        "Slavonic, Gothic, and more: literary editions, documentary papyri, gold treebanks, " \
        "parallel English translations). Give EXACTLY ONE of: `query` — full-text FTS5 " \
        "(words AND by default, \"quoted phrase\", prefix*; diacritics optional, μηνιν finds " \
        "μῆνιν) — or `lemma` — exact dictionary form over the lemma index, every tier it holds: " \
        "gold treebank annotation unlabeled, silver/equivalence hits labeled by a `tier` field " \
        "(λέγω finds εἶπας, " \
        "εἰπεῖν, every inflection; add `morph` — e.g. \"case=dat,number=pl\" — to keep only " \
        "attestations with that morphology, each hit showing the decoded evidence). Add `near` " \
        "for PROXIMITY — keep only hits where that term sits within `window` words (default " \
        "#{SEARCH_DEFAULT_WINDOW}, 0=adjacent) of query (or lemma, expanded to its surface " \
        "forms) in the SAME passage, order-independent; both matched terms are bracketed in the " \
        "snippet (near does not compose with morph). Hits are " \
        "relevance-ranked and bounded (default " \
        "#{SEARCH_DEFAULT_LIMIT}, max #{SEARCH_MAX_LIMIT}) with an honest 'showing k' note; " \
        "each carries urn, language, license_class, and source — PRESERVE the license fields " \
        "when quoting. `meter`/`meter_pattern` (text search only) restrict hits to metrically " \
        "SCANNED passages — the pedecerto (Latin) / hypotactic (Greek) meter enrichment layer; " \
        "the note names that layer or explains an empty one. `words` (text search only) is the " \
        "Tibetan word-grain filter: keep only hits whose match aligns with word boundaries per " \
        "the nabu-data segmentation dataset (degrades honestly for non-Tibetan queries or an " \
        "unsynced module). Four further LANES replace the ranked text search (each composes " \
        "with the args its schema line names, nothing else): `fuzzy: true` — substring/fragment " \
        "search over the documentary trigram index (]μηνιν αει[, the CLI's --fuzzy); " \
        "`translations: true` — the query matched against the translations held in passage " \
        "annotations, hits being the ORIGINAL passages with the matched `layer` (the CLI's " \
        "--translations); `annotations: true` — the query matched against the DECLARED " \
        "annotation layers (standardized/regularized spellings, readings, margin notes, footnotes, " \
        "editors' notes), hits being the passages with the matched `layer` (the CLI's " \
        "--annotations); `sense` — the word-sense desk (a DCS WordSem id or sense name → the " \
        "passages whose tokens cite it, each with its citing tokens; the CLI's `nabu sense`). " \
        "`betacode: true` reads query/lemma/near as TLG Beta Code (mh=nin → μῆνιν). " \
        "Use nabu_show with a hit's urn for " \
        "the full passage, nabu_status for what the corpus covers.".freeze

      SEARCH_SCHEMA = {
        type: "object",
        properties: {
          query: { type: "string",
                   description: "Full-text query. Mutually exclusive with lemma." },
          similar_to: { type: "string",
                        description: "A passage URN: return its SEMANTIC neighbors instead of a " \
                                     "text search (same-language cross-edition retrieval over " \
                                     "the local vector store — other witnesses of a verse, " \
                                     "passages saying the same thing). Banded close/near/loose, " \
                                     "never raw scores; same-language ONLY (cross-language " \
                                     "measured unreliable and not served); model named in the " \
                                     "payload — statistical similarity, never a curated " \
                                     "alignment (nabu_align/nabu_parallels serve those). " \
                                     "Replaces query/lemma; composes with limit/include_restricted/" \
                                     "lang only (lang must be the anchor's own language — another " \
                                     "is answered with a same-language note); any other filter " \
                                     "is refused." },
          lemma: { type: "string",
                   description: "Dictionary form for exact-lemma search over the lemma index " \
                                "(every tier; non-gold hits carry `tier`). Mutually exclusive " \
                                "with query." },
          morph: { type: "string",
                   description: "Morphology facets, only WITH lemma: comma-joined key=value in " \
                                "Universal Dependencies vocabulary (case, number, gender, person, " \
                                "tense, mood, voice, degree; values dat, pl/sg, masc, aor, opt, " \
                                "sub…), all required. E.g. \"case=dat,number=pl\". UD treebanks " \
                                "match on feats; PROIEL/TOROT positional tags, GLAUx's AGDT " \
                                "postags, Diorisis analyses, BHSA/DSS (ETCBC/Abegg) features, " \
                                "OSHB morph codes, CorA msd (ReM/ReN) and morph (REF), IMP msd (goo300k), " \
                                "Menota msa, CEIPoM AGDT pos_code (via its Latin-equivalent lemmas), " \
                                "HeliPaD pos^morph tags, CorPH analyses, AES/TraCES explicit fields, " \
                                "tla-hf grammatical glossing and " \
                                "Coptic Scriptorium pos tags (polarity, prontype, " \
                                "definite, verbform) are decoded to the same names (Hebrew/Aramaic add " \
                                "state, stem, conjugation: e.g. \"stem=piel,conjugation=wayq\"); " \
                                "ORACC has no inflectional morphology so these facets never match it." },
          gloss: { type: "string",
                   description: "Token-gloss filter WITH lemma: keep attestations whose upstream " \
                                "token gloss contains this word (whole word, case-insensitive) — " \
                                "bhsa/achemenet/ceipom (English), aes/tlhdig (German). E.g. lemma \"דבר\" + " \
                                "gloss \"word\" splits BHSA's consonantal homograph from \"speak\". " \
                                "Composes with morph; not with near. Lemma hits from those sources " \
                                "always carry token_gloss. WITHOUT lemma (and no query): the gloss " \
                                "lane — every WORD some source glosses this (\"king\" → BHSA מלך, " \
                                "achemenet šarru, …) across lemmas; words AND, \"phrase\", prefix*, " \
                                "diacritic-insensitive. Each hit is a word {lemma, form, gloss, " \
                                "source, language, tokens, passages} with urn = its first " \
                                "attestation; `coverage` lists the indexed sources. Composes with " \
                                "lang/license/limit only." },
          near: { type: "string",
                  description: "Proximity: keep only hits where this term occurs within `window` " \
                               "words of query (or lemma) in the SAME passage. FTS5 NEAR over the " \
                               "folded search forms, order-independent; expands a lemma anchor to " \
                               "its attested surface forms first. Does NOT compose with morph." },
          window: { type: "integer", minimum: 0, maximum: SEARCH_MAX_WINDOW,
                    default: SEARCH_DEFAULT_WINDOW,
                    description: "With near: max words between the two terms (default " \
                                 "#{SEARCH_DEFAULT_WINDOW}; 0 = adjacent)." },
          lang: { type: "string",
                  description: "ISO-639-3 passage language filter: grc, lat, chu, got, orv, eng, …" },
          license: { type: "string", enum: LICENSE_CLASSES,
                     description: "Exact effective license class filter." },
          source: { type: "string",
                    description: "Scope hits to ONE source, by its source slug (the `source` field every " \
                                 "hit carries; nabu_status lists the held slugs) — the CLI's --source. " \
                                 "Composes with every lane except similar_to; an unknown slug is refused " \
                                 "naming the held ones (never an empty page)." },
          axis: { type: "string",
                  description: "Scope hits to the member sources of a research axis (config/axes.yml — " \
                               "the library's desks, e.g. classical, slavic, epigraphy) or a functional " \
                               "set (core, signs, quickstart); comma-join several names for their union " \
                               "(\"slavic,celtic\") — the CLI's --axis, the multi-source generalization of " \
                               "source. Composes with every lane except sense/similar_to; an unknown name " \
                               "is refused naming the known axes." },
          from: { type: "integer",
                  description: "Earliest date: signed HISTORICAL year, negative = BCE, no year 0 " \
                               "(-300 = 300 BCE, 14 = 14 CE). Filters the document timeline — the " \
                               "dated documents of most sources, every date class (see date_basis to " \
                               "pick one); a document the timeline does not date is absent under a " \
                               "date filter. Text search only (not lemma)." },
          to: { type: "integer",
                description: "Latest date: signed historical year; composes with from." },
          century: { type: "integer",
                     description: "Shorthand for one century's from/to (6 = 6th c. CE, -2 = 2nd c. " \
                                  "BCE); mutually exclusive with from/to." },
          date_basis: { type: "string",
                        description: "Date-basis filter (CLI --date-basis parity, text search only): " \
                                     "keep only documents whose PRIMARY dated row is of one of these " \
                                     "classes, comma-joined — artifact (the source's own artifact/" \
                                     "typed date), composition (attributed author-era dating), " \
                                     "edition (a print/edition year), silver (a model ESTIMATE, " \
                                     "never an upstream claim). Composes with from/to/century: " \
                                     "`date_basis: \"artifact\"` holds out author-era datings. An " \
                                     "unknown class is refused naming the known set." },
          place: { type: "string",
                   description: "Provenance filter (P75 C-1): a namespaced place ref (tm:2810, " \
                                "cigs:GIR) matches identity claims on the document's place_ref " \
                                "axis; a place NAME resolves through the derived place index and " \
                                "registry decisions (name recall kept); a LIKE pattern " \
                                "(oxyrhynch%) stays the name lane. The note names the lane that " \
                                "answered. Localized documents only." },
          script: { type: "string",
                    description: "Script filter (P75 C-2), ISO 15924-style registry tag (latn, " \
                                 "xsux, egyd): keeps documents whose held text carries the " \
                                 "~script lect axis OR whose artifact-script axis claims the tag " \
                                 "(\"Latin-script Gaulish\"). Text search only." },
          kind: { type: "string",
                  description: "Document-kind filter (P99, text search only): the ruled " \
                               "cross-corpus classification classes (config/kind_classes.yml — " \
                               "funerary, letter, literary, divination, …). FAMILY matching at " \
                               "any depth: a path prefix matches its whole family (funerary ⊇ " \
                               "funerary/epitaph; literary/narrative ⊇ literary/narrative/epic), " \
                               "a full path narrows, an explicit % pattern matches as " \
                               "given. The honesty buckets are first-class values: `unknown` " \
                               "(upstream's own \"cannot determine\") and `unmapped` (a raw " \
                               "value awaiting a fold rule). Only classified documents can " \
                               "match — most of the corpus carries no kind facet and falls " \
                               "out under the filter (`nabu kind census` lists the classes)." },
          facets: { type: "object", additionalProperties: { type: "string" },
                    description: "Facet filters (text search only), an object of facet name → " \
                                 "pattern, all required (AND): any facet the catalog carries, at " \
                                 "document grain (genre, province, material, collection, author…) " \
                                 "or passage grain (sillok subject, itkc genre) — " \
                                 "{\"subject\": \"왕실-%\"}. The pattern matches the value or its " \
                                 "ref case-insensitively; LIKE % patterns pass through. At most " \
                                 "#{MAX_FACET_FILTERS} pairs; composes with kind (both must hold). " \
                                 "Unfaceted documents fall out under it." },
          meter: { type: "string",
                   description: "Meter facet (P45-5): only passages carrying a meter enrichment " \
                                "(the pedecerto/hypotactic scansion layer) whose meter code/name " \
                                "matches case-insensitively (pedecerto codes H, P, …; hypotactic " \
                                "names like 'dactylic hexameter'). Text search only (not lemma/" \
                                "near); most of the corpus is unscanned and absent under it. The " \
                                "note names the source layer, or explains an empty/unknown one." },
          meter_pattern: { type: "string",
                           description: "Meter facet: exact foot/scansion pattern, case-insensitive " \
                                        "(pedecerto DSDS, hypotactic '-u u -uu …'); composes with " \
                                        "meter or stands alone. Text search only." },
          words: { type: "boolean", default: false,
                   description: "Tibetan word-grain filter (P54-4, text search only): Tibetan is " \
                                "indexed at syllable grain, so a multi-syllable query also matches " \
                                "an accidental syllable run crossing a word boundary — words: true " \
                                "keeps only hits whose matched span aligns with word boundaries per " \
                                "the nabu-data xct/segmentation dataset (present-only word_grain " \
                                "key when applied). Non-Tibetan queries or an unsynced module " \
                                "degrade to plain search with a word_grain_note, never an error." },
          lect: { type: "string",
                  description: "Lect filter (P57-4, nabu-lects module, text search only): keep only " \
                               "hits whose (language, source) resolves to this lect id or a more " \
                               "specific one under it — prefix semantics over the nabu-lects " \
                               "anchor[:stage][/variety][@ortho] grammar (lect: \"lat\" matches " \
                               "lat:med; lect: \"lat:med\" matches lat:med and lat:med/xyz, not " \
                               "lat:cla). Errors if the nabu-lects module is not synced on this box." },
          fuzzy: { type: "boolean", default: false,
                   description: "Fragment lane (the CLI's search --fuzzy): `query` is a literal " \
                                "substring/fragment matched over the documentary trigram index " \
                                "(editorial [ ] stripped, diacritics folded, at least 3 characters " \
                                "after folding) — not FTS syntax. Hits carry a folded `snippet` " \
                                "with the match bracketed; `coverage` lists the sources the index " \
                                "covers. Composes with lang/license/from/to/century/date_basis/" \
                                "place/kind/facets/limit only." },
          translations: { type: "boolean", default: false,
                          description: "Translations lane (the CLI's search --translations): " \
                                       "`query` (words AND, \"phrase\", prefix*) is matched " \
                                       "against the translations held in passage ANNOTATIONS " \
                                       "(coptic, cdli/ebl #tr, hittite-glossed trans_de, corph, …); " \
                                       "hits are the ORIGINAL passages, each naming the matched " \
                                       "`layer` with a bracketed `snippet` of it. Composes with " \
                                       "lang (the original's language)/license/limit only." },
          annotations: { type: "boolean", default: false,
                         description: "Annotation-layer lane (the CLI's search --annotations): " \
                                      "`query` (words AND, \"phrase\", prefix*) is matched against " \
                                      "the searchable text layers sources keep in passage " \
                                      "ANNOTATIONS, declared per source (cantus standardized " \
                                      "spellings, regularized/normalized/diplomatic spellings, " \
                                      "margin notes, footnotes, editors' notes — each folded by " \
                                      "its own language); hits are the passages, each naming the " \
                                      "matched `layer` with a bracketed `snippet` of it. Composes " \
                                      "with lang (the passage's language)/license/limit only." },
          sense: { type: "string",
                   description: "Sense desk (the CLI's `nabu sense TERM`): a sense id (59344, or " \
                                "comma-joined ids) or a sense NAME matched case-insensitively " \
                                "against the sense shelf (finger; LIKE wildcards: circum%). " \
                                "Returns the matched senses (id, headword, gloss, passage count) " \
                                "and the passages citing them, each with its citing tokens " \
                                "(form, lemma, ids). Replaces query/lemma; composes with " \
                                "sense_gloss/limit only." },
          sense_gloss: { type: "boolean", default: false,
                         description: "With sense: also match the term inside the sense's gloss " \
                                      "(\"linear measure\")." },
          betacode: { type: "boolean", default: false,
                      description: "Beta Code input (the CLI's search --betacode): query, lemma and " \
                                   "near are TLG Beta Code, transliterated to Greek before matching " \
                                   "(mh=nin → μῆνιν; case-blind, *capitals, FTS quotes and prefix* " \
                                   "pass through). The decoded terms come back in a present-only " \
                                   "`betacode` object. A deliberate flag — never auto-detected; " \
                                   "not with sense/similar_to." },
          limit: { type: "integer", minimum: 1, maximum: SEARCH_MAX_LIMIT,
                   default: SEARCH_DEFAULT_LIMIT, description: "Maximum hits returned." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        additionalProperties: false
      }.freeze

      # The search lanes (fuzzy / translations / sense): each composes with
      # exactly the args its CLI flag composes with (the MCP-available
      # subset) — anything else is a usage error, never a silent drop.
      # const: argument vocabularies mirroring the CLI flags, not corpus claims
      FUZZY_ARGS = %w[fuzzy query lang license source axis from to century date_basis place kind facets limit
                      include_restricted].freeze
      # const: the --translations composition set
      TRANSLATIONS_ARGS = %w[translations query lang license source axis limit include_restricted].freeze
      # const: the --annotations composition set
      ANNOTATIONS_ARGS = %w[annotations query lang license source axis limit include_restricted].freeze
      # const: the --gloss-alone composition set (gloss with no lemma)
      GLOSS_ARGS = %w[gloss lang license source axis limit include_restricted].freeze
      # const: the sense desk composition set (`nabu sense` takes --source, not --axis)
      SENSE_ARGS = %w[sense sense_gloss source limit include_restricted].freeze
      # const: the similar_to composition set — the neighbor scan is
      # same-language and unscoped, so lang (checked against the anchor's
      # pinned language) is the only filter it can honor; every other
      # search filter is refused, never silently dropped
      SIMILAR_ARGS = %w[similar_to limit include_restricted lang].freeze

      private

      # -- handlers --------------------------------------------------------------

      # The betacode flag (contract bump 2026-10-22, the CLI's --betacode)
      # wraps every search lane: decode query/lemma/near from Beta Code,
      # run the lane on the Greek, and echo the decode in a present-only
      # `betacode` key (flag off: the frozen payload, byte-identical).
      def search(args)
        decoded = betacode_terms(args)
        return search_lanes(args) if decoded.nil?

        echo_betacode(search_lanes(args.merge(decoded).except("betacode")), decoded)
      end

      # {term key => Greek} for a betacode: true call, nil when the flag is
      # off. Sense ids and similar_to urns are not Greek text: refused.
      def betacode_terms(args)
        flag = args["betacode"]
        return nil if flag.nil? || flag == false
        raise InvalidArguments, "betacode must be a boolean" unless flag == true
        if !args["sense"].nil? || args["similar_to"]
          raise InvalidArguments, "betacode decodes query/lemma/near — not sense or similar_to"
        end

        terms = %w[query lemma near].filter_map { |key| (raw = string_arg(args, key)) && [key, raw] }.to_h
        raise InvalidArguments, "betacode needs a query, lemma or near term to decode" if terms.empty?

        terms.transform_values { |raw| Betacode.decode_query(raw) }
      end

      # Merge the decode into a JSON payload; a plain-text note (a corpus
      # state) is prefixed instead, so the decode is never lost.
      def echo_betacode(result, decoded)
        text = result[:content].fetch(0).fetch(:text)
        payload = JSON.parse(text)
        return result unless payload.is_a?(Hash)

        json(payload.merge("betacode" => decoded))
      rescue JSON::ParserError
        echo = decoded.map { |key, greek| "#{key}=#{greek}" }.join(", ")
        note("beta code decoded: #{echo} — #{text}")
      end

      def search_lanes(args)
        return similar_neighbors(args) if args["similar_to"]
        return sense_search(args) unless args["sense"].nil?
        raise InvalidArguments, "sense_gloss applies with sense only" if args["sense_gloss"] == true
        return translations_search(args) if args["translations"] == true
        return annotations_search(args) if args["annotations"] == true
        return fuzzy_search(args) if args["fuzzy"] == true
        return gloss_search(args) if !args["gloss"].nil? && args["lemma"].nil?

        term, mode = search_term(args)
        morph = search_morph(args, mode)
        gloss = search_gloss(args, mode)
        near = search_near(args, morph || gloss)
        license = license_arg(args)
        include_restricted = args["include_restricted"] == true
        if license && EXCLUDED_LICENSE_CLASSES.include?(license) && !include_restricted
          return note("license class #{license} is excluded by default from this surface " \
                      "(it must never leak casually); pass include_restricted: true to " \
                      "search it deliberately")
        end

        from, to, place = search_date(args, mode, near)
        date_basis = search_date_basis(args, mode, near)
        kind = search_kind(args, mode, near)
        facets = search_facets(args, mode, near)
        meter, meter_pattern = search_meter(args, mode, near)
        words = search_words?(args, mode, near)
        lect, lects = search_lect(args, mode, near)
        script = search_script(args, mode, near)
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        source, sources = search_scope(args, catalog)
        fulltext = search_index(mode) or return note(mode == :lemma ? LEMMA_REBUILDING_NOTE : REBUILDING_NOTE)

        limit = clamp(args["limit"], default: SEARCH_DEFAULT_LIMIT, max: SEARCH_MAX_LIMIT)
        window = clamp(args["window"], default: SEARCH_DEFAULT_WINDOW, max: SEARCH_MAX_WINDOW, min: 0)
        results, incomplete, rank_note, meter_note, words_note, word_grain, place_note =
          run_search(mode, term, catalog: catalog, fulltext: fulltext, near: near,
                                 window: window, lang: args["lang"], license: license,
                                 limit: limit + 1, morph: morph, from: from, to: to, place: place,
                                 kind: kind, facets: facets, meter: meter, meter_pattern: meter_pattern, words: words,
                                 lect: lect, lects: lects, script: script, date_basis: date_basis, gloss: gloss,
                                 source: source, sources: sources)
        results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        render_search(results, limit: limit, catalog: catalog, incomplete: incomplete, rank_note: rank_note,
                               meter_note: meter_note, word_grain: word_grain, word_grain_note: words_note,
                               place_note: place_note)
      rescue Query::MorphFacets::Error, Query::TokenGlosses::Error => e
        raise InvalidArguments, e.message
      end

      # The similar_to lane (P93-5): URN-anchored semantic neighbors from
      # the vector store — no model at serve time, one sqlite-vec scan.
      # Every absent-machinery case (store unbuilt, anchor unembedded,
      # extension missing, lane unconfigured) answers as an honest NOTE the
      # model can act on, never a protocol error. Restricted license
      # classes are excluded exactly as the text-search page excludes them.
      def similar_neighbors(args)
        raise InvalidArguments, "similar_to replaces query/lemma — give exactly one" if args["query"] || args["lemma"]

        lane_conflicts!(args, "similar_to", SIMILAR_ARGS)
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        vectors = resolve(@vectors)
        if vectors.nil?
          return note("no vector store on this box — `nabu embed` builds it " \
                      "(docs/manual/embed-venv.md); similar_to serves nothing until then")
        end

        limit = clamp(args["limit"], default: SEARCH_DEFAULT_LIMIT, max: SEARCH_MAX_LIMIT)
        include_restricted = args["include_restricted"] == true
        page = Query::Similar.new(catalog: catalog, vectors: vectors)
                             .run(args["similar_to"], limit: limit, language: string_arg(args, "lang"))
        results = page.results
        results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        sources = sources_by_urn(catalog, results.map(&:urn))
        json({
               anchor: page.anchor_urn, language: page.language, model: page.model,
               note: "banded semantic similarity (close/near/loose), same-language only — " \
                     "statistical, never a curated alignment",
               results: results.map do |result|
                 {
                   urn: result.urn, language: result.language, band: result.band,
                   snippet: result.snippet, document_title: result.document_title,
                   license_class: result.license_class, source: sources[result.urn],
                   credit: result.credit
                 }.compact
               end
             })
      rescue InvalidArguments
        raise # the server's isError contract — never folded into a note
      rescue Nabu::Error => e
        note(e.message)
      end

      # The fragment lane (the CLI's search --fuzzy, Query::Fuzzy): literal
      # substring matching over the documentary trigram index, with the
      # CLI's composition set. An index-less fulltext is a corpus STATE
      # (note); a sub-trigram fragment is a usage error.
      def fuzzy_search(args)
        lane_conflicts!(args, "fuzzy", FUZZY_ARGS)
        fragment = string_arg(args, "query") or raise InvalidArguments, "fuzzy needs a query (the fragment)"
        license = license_arg(args)
        include_restricted = args["include_restricted"] == true
        refused = restricted_license_note(license, include_restricted) and return refused

        from, to, place = search_date(args, :text, nil)
        date_basis = search_date_basis(args, :text, nil)
        kind = search_kind(args, :text, nil)
        facets = (search_facets(args, :text, nil) || {}).merge(kind ? { "kind" => kind } : {})
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        source, sources = search_scope(args, catalog)
        fulltext = resolve(@fulltext)
        return note(NO_FUZZY_INDEX_NOTE) unless fulltext&.table_exists?(Store::Indexer::TRIGRAM_TABLE)

        limit = clamp(args["limit"], default: SEARCH_DEFAULT_LIMIT, max: SEARCH_MAX_LIMIT)
        searcher = Query::Fuzzy.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run(fragment, lang: args["lang"], license: license, limit: limit + 1,
                                         from: from, to: to, place: place, date_basis: date_basis,
                                         facets: facets.empty? ? nil : facets, source: source, sources: sources)
        results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        shown = results.first(limit)
        sources = sources_by_urn(catalog, shown.map(&:urn))
        json(matches: shown.map do |result|
          { urn: result.urn, language: result.language, license_class: result.license_class,
            source: sources[result.urn], document: result.document_title, text: truncate(result.text),
            snippet: result.snippet }
        end,
             note: lane_note(results, limit, "fuzzy substring; snippets are diacritic-folded",
                             searcher.incomplete_hint),
             coverage: searcher.scope || [])
      rescue Query::Fuzzy::QueryTooShort => e
        raise InvalidArguments, e.message
      end

      # The translations lane (the CLI's search --translations,
      # Query::TranslationSearch): the annotation-held translations, hits
      # the ORIGINAL passages. Desk rule: an unbuilt lane is the honest
      # build-hint note, never a scan.
      def translations_search(args)
        lane_conflicts!(args, "translations", TRANSLATIONS_ARGS)
        query = string_arg(args, "query") or raise InvalidArguments, "translations needs a query"
        license = license_arg(args)
        include_restricted = args["include_restricted"] == true
        refused = restricted_license_note(license, include_restricted) and return refused

        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        source, sources = search_scope(args, catalog)
        limit = clamp(args["limit"], default: SEARCH_DEFAULT_LIMIT, max: SEARCH_MAX_LIMIT)
        searcher = Query::TranslationSearch.new(catalog: catalog, fulltext: resolve(@fulltext))
        results = searcher.run(query, lang: args["lang"], license: license, source: source, sources: sources,
                                      limit: limit + 1)
        results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        shown = results.first(limit)
        sources = sources_by_urn(catalog, shown.map(&:urn))
        json(matches: shown.map do |result|
          { urn: result.urn, language: result.language, license_class: result.license_class,
            source: sources[result.urn], document: result.document_title, layer: result.layer,
            snippet: result.snippet, text: truncate(result.text) }.merge(credit_field(result))
        end,
             note: lane_note(results, limit, "annotation-held translations; hits are the original passages",
                             searcher.incomplete_hint),
             coverage: searcher.scope.map { |slug, passages| { source: slug, passages: passages } })
      rescue Query::TranslationSearch::IndexMissing => e
        note(e.message)
      end

      # The annotation-layer lane (the CLI's search --annotations,
      # Query::AnnotationSearch): the declared searchable layers held in
      # passage annotations, hits the passages themselves. Desk rule: an
      # unbuilt lane is the honest build-hint note, never a scan.
      def annotations_search(args)
        lane_conflicts!(args, "annotations", ANNOTATIONS_ARGS)
        query = string_arg(args, "query") or raise InvalidArguments, "annotations needs a query"
        license = license_arg(args)
        include_restricted = args["include_restricted"] == true
        refused = restricted_license_note(license, include_restricted) and return refused

        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        source, sources = search_scope(args, catalog)
        limit = clamp(args["limit"], default: SEARCH_DEFAULT_LIMIT, max: SEARCH_MAX_LIMIT)
        searcher = Query::AnnotationSearch.new(catalog: catalog, fulltext: resolve(@fulltext))
        results = searcher.run(query, lang: args["lang"], license: license, source: source, sources: sources,
                                      limit: limit + 1)
        results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        shown = results.first(limit)
        sources = sources_by_urn(catalog, shown.map(&:urn))
        json(matches: shown.map do |result|
          { urn: result.urn, language: result.language, license_class: result.license_class,
            source: sources[result.urn], document: result.document_title, layer: result.layer,
            snippet: result.snippet, text: truncate(result.text) }.merge(credit_field(result))
        end,
             note: lane_note(results, limit, "declared annotation layers; hits are the layer-bearing passages",
                             searcher.incomplete_hint),
             coverage: searcher.scope.map { |slug, passages| { source: slug, passages: passages } })
      rescue Query::AnnotationSearch::IndexMissing => e
        note(e.message)
      end

      # The token-gloss lane (the CLI's search --gloss WORD with no query,
      # Query::GlossSearch): every word upstream glosses WORD, across
      # lemmas — one hit per word with its first attestation. Desk rule: an
      # unbuilt lane is the honest build-hint note, never a scan.
      def gloss_search(args)
        lane_conflicts!(args, "gloss", GLOSS_ARGS)
        gloss = string_arg(args, "gloss") or raise InvalidArguments, "gloss needs a word, e.g. king"
        license = license_arg(args)
        include_restricted = args["include_restricted"] == true
        refused = restricted_license_note(license, include_restricted) and return refused

        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        source, sources = search_scope(args, catalog)
        limit = clamp(args["limit"], default: SEARCH_DEFAULT_LIMIT, max: SEARCH_MAX_LIMIT)
        searcher = Query::GlossSearch.new(catalog: catalog, fulltext: resolve(@fulltext))
        results = searcher.run(gloss, lang: args["lang"], license: license, source: source, sources: sources,
                                      limit: limit + 1)
        results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        json(matches: results.first(limit).map do |result|
          { lemma: result.lemma, form: result.form, gloss: result.gloss, source: result.source,
            language: result.language, tokens: result.tokens, passages: result.passages, urn: result.urn,
            license_class: result.license_class, document: result.document_title }.merge(credit_field(result))
        end,
             note: lane_note(results, limit, "upstream token glosses across lemmas; urn = the word's first " \
                                             "attestation — every attestation: lemma + gloss",
                             searcher.incomplete_hint),
             coverage: searcher.scope.map { |slug, words, tokens| { source: slug, words: words, tokens: tokens } })
      rescue Query::GlossSearch::IndexMissing => e
        note(e.message)
      end

      # The sense desk (the CLI's `nabu sense TERM`, Query::Senses): the
      # matched senses and the passages citing them, each hit with its
      # citing tokens. Precompiled pairs only — an unbuilt index or an
      # absent shelf is a corpus STATE (note), never a scan.
      def sense_search(args)
        lane_conflicts!(args, "sense", SENSE_ARGS)
        term = string_arg(args, "sense") or raise InvalidArguments, "sense needs a sense id or a sense name"
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        return note(NO_FACET_MAP_NOTE) unless @facet_map

        include_restricted = args["include_restricted"] == true
        limit = clamp(args["limit"], default: Query::Senses::DEFAULT_LIMIT, max: SEARCH_MAX_LIMIT)
        source, = search_scope(args, catalog)
        result = Query::Senses.new(catalog: catalog, facet_map: @facet_map)
                              .run(term, gloss: args["sense_gloss"] == true, source: source, limit: limit)
        licenses = licenses_by_urn(catalog, result.hits.map(&:urn))
        hits = result.hits.reject { |hit| withhold?(licenses[hit.urn], include_restricted) }
        json(type: "sense", query: result.query, sense_total: result.sense_total,
             passage_total: result.passage_total,
             senses: result.senses.map do |sense|
               { id: sense.id, shelf: sense.shelf, urn: sense.urn, headword: sense.headword,
                 gloss: sense.gloss, passages: sense.passages }
             end,
             matches: hits.map do |hit|
               { urn: hit.urn, language: hit.language, license_class: licenses[hit.urn], source: hit.source,
                 text: truncate(hit.text), tokens: hit.tokens.map { |token| sense_token_row(token) } }
             end,
             note: sense_note(result, hits))
      rescue Query::Senses::Error => e
        note(e.message)
      end

      # -- search internals --------------------------------------------------------

      # [term, :text | :lemma], enforcing the XOR.
      # Split note: also read by nabu_concord (tools/concord.rb); kept with its primary user.
      def search_term(args)
        query = string_arg(args, "query")
        lemma = string_arg(args, "lemma")
        unless [query, lemma].compact.size == 1
          raise InvalidArguments, "give exactly one of query (full-text) or lemma (dictionary form)"
        end

        lemma ? [lemma, :lemma] : [query, :text]
      end

      # The morph facet string, only valid WITH a lemma (bare morphology search
      # is out of scope — it would scan every annotated passage). nil when
      # absent. Malformed facets raise via the query layer (rescued in #search).
      def search_morph(args, mode)
        morph = string_arg(args, "morph")
        return nil if morph.nil?
        raise InvalidArguments, "morph requires lemma (morphology search is anchored on a lemma)" unless mode == :lemma

        morph
      end

      # The token-gloss word (Query::TokenGlosses), only valid WITH a lemma —
      # it filters the lemma-anchored token pass, exactly like morph.
      def search_gloss(args, mode)
        gloss = string_arg(args, "gloss")
        return nil if gloss.nil?
        raise InvalidArguments, "gloss requires lemma (the gloss filter is anchored on a lemma)" unless mode == :lemma

        gloss
      end

      # The proximity term (P14-8), or nil. Composes with query OR lemma anchor
      # but NOT with the token filters (morph/gloss: token-narrowed proximity
      # is out of scope), so such a combination is a clear usage error like
      # the CLI's.
      def search_near(args, token_filter)
        near = string_arg(args, "near")
        return nil if near.nil?
        if token_filter
          raise InvalidArguments,
                "near does not compose with morph/gloss (token-narrowed proximity is out of scope)"
        end

        near
      end

      # The fulltext handle when the index this mode needs is present; nil
      # during the mid-reindex window (Indexer.rebuild! drops the tables first).
      # Split note: also read by nabu_concord and nabu_parallels; kept with its primary user.
      def search_index(mode)
        fulltext = resolve(@fulltext)
        return nil unless fulltext&.table_exists?(Store::Indexer::TABLE)
        return nil if mode == :lemma && !fulltext.table_exists?(Store::Indexer::LEMMA_TABLE)

        fulltext
      end

      # Resolve the timeline args (P15-2), honestly scoped to plain text
      # search — the dated corpus (papyri) is not lemmatized, and proximity is a
      # different index path — so date/place with lemma or near is a usage error.
      # `century` is shorthand for a from/to window; year 0 and from>to are
      # rejected with a clear message (the reviewed guards).
      def search_date(args, mode, near)
        from = int_arg(args, "from")
        to = int_arg(args, "to")
        century = int_arg(args, "century")
        place = string_arg(args, "place")
        return [nil, nil, nil] unless from || to || century || place

        if mode == :lemma || near
          raise InvalidArguments, "from/to/century/place compose with text search only, not lemma/near"
        end

        if century
          raise InvalidArguments, "century is shorthand for from/to — use one or the other" if from || to
          raise InvalidArguments, "there is no century 0 (1st c. CE is 1, 1st c. BCE is -1)" if century.zero?

          from, to = Nabu::Timeline.century_bounds(century)
        end
        raise InvalidArguments, "there is no year 0 (1 BCE is -1, 1 CE is 1)" if from&.zero? || to&.zero?
        raise InvalidArguments, "from #{from} is after to #{to} (BCE years are negative)" if from && to && from > to

        [from, to, place]
      end

      # The date-basis arg (P123-4, the P122-1 CLI --date-basis's exact
      # semantics) — text search only, like the timeline. The class list is
      # parsed once here, so an unknown (or empty) class is refused as an
      # argument error naming the known set, never a silent empty page.
      def search_date_basis(args, mode, near)
        value = string_arg(args, "date_basis")
        return nil if value.nil?
        raise InvalidArguments, "date_basis composes with text search only, not lemma/near" if mode == :lemma || near

        Query::DateBasis.parse(value)
      rescue InvalidArguments
        raise
      rescue Nabu::Error => e
        raise InvalidArguments, e.message
      end

      # The kind facet arg (P100-5, the P99 CLI --kind's exact semantics) —
      # text search only, refusal parity with the meter facet. Threaded as
      # the facets hash entry the CLI's facet_filters builds, so the family
      # matching lives once, in CatalogJoin#kind_exists.
      def search_kind(args, mode, near)
        kind = string_arg(args, "kind")
        return nil if kind.nil?
        raise InvalidArguments, "kind composes with text search only, not lemma/near" if mode == :lemma || near

        kind
      end

      # The generic facet filter (the CLI search --facet parity) — text
      # search only, the kind refusal. Threaded into the same facets hash
      # kind rides (run_search), so the document-or-passage grain matching
      # lives once, in Query::Search.
      def search_facets(args, mode, near)
        facets = facets_arg(args)
        return nil if facets.nil?
        raise InvalidArguments, "facets compose with text search only, not lemma/near" if mode == :lemma || near

        facets
      end

      # The script filter arg (P75 C-2) — text search only, like the
      # timeline; tag shape/fold is enforced once in Search#script_code.
      def search_script(args, mode, near)
        script = string_arg(args, "script")
        return nil if script.nil?
        raise InvalidArguments, "script composes with text search only, not lemma/near" if mode == :lemma || near

        script
      end

      # Returns [results, incomplete_hint, rank_note] — the hint is the query
      # layer's exhausted-inner-window announcement (P35-6), nil on an honest
      # page; rank_note (P42-2) is Search's skipped-rank clause when the term
      # was too common to rank (plain text mode only — the other searchers
      # never guard, so theirs is always nil).
      def run_search(mode, term, catalog:, fulltext:, lang:, license:, limit:, near: nil, window: nil, morph: nil,
                     from: nil, to: nil, place: nil, kind: nil, facets: nil, meter: nil, meter_pattern: nil,
                     words: false, lect: nil, lects: nil, script: nil, date_basis: nil, gloss: nil,
                     source: nil, sources: nil)
        # kind is one more named facet (the CLI's facet_filters shape); an
        # explicit kind arg wins over a facets "kind" key.
        facets = (facets || {}).merge(kind ? { "kind" => kind } : {})
        results, searcher =
          if near
            searcher = Query::Proximity.new(catalog: catalog, fulltext: fulltext)
            [searcher.run(query: mode == :lemma ? nil : term, lemma: mode == :lemma ? term : nil,
                          near: near, window: window, lang: lang, license: license, limit: limit,
                          source: source, sources: sources), searcher]
          elsif mode == :lemma
            searcher = Query::LemmaSearch.new(catalog: catalog, fulltext: fulltext)
            [searcher.run(term, lang: lang, license: license, limit: limit, morph: morph, gloss: gloss,
                                source: source, sources: sources), searcher]
          else
            searcher = Query::Search.new(catalog: catalog, fulltext: fulltext,
                                         tibetan_words: words ? tibetan_words_seam : nil,
                                         lects: lects || :auto)
            [searcher.run(term, lang: lang, license: license, limit: limit,
                                from: from, to: to, place: place, script: script, date_basis: date_basis,
                                facets: facets.empty? ? nil : facets,
                                meter: meter, meter_pattern: meter_pattern, words: words, lect: lect,
                                source: source, sources: sources), searcher]
          end
        rank_note = searcher.respond_to?(:rank_note) ? searcher.rank_note : nil
        meter_note = searcher.respond_to?(:meter_note) ? searcher.meter_note : nil
        words_note = searcher.respond_to?(:words_note) ? searcher.words_note : nil
        word_grain = searcher.respond_to?(:word_grain) ? searcher.word_grain : nil
        place_note = searcher.respond_to?(:place_note) ? searcher.place_note : nil
        [results, searcher.incomplete_hint, rank_note, meter_note, words_note, word_grain, place_note]
      end

      # The word-grain seam behind nabu_search's words flag (P54-4): resolve
      # :auto lazily and memoize only a LOADED seam (the class comment on
      # @tibetan_words — re-detect while absent, load the CSV once).
      def tibetan_words_seam
        return @tibetan_words unless @tibetan_words == :auto

        loaded = Nabu::TibetanWords.load_default
        @tibetan_words = loaded if loaded
        loaded
      end

      # The meter facet args (P45-5), text mode only — the lemma/proximity
      # query classes do not carry the filter, so it is refused, never
      # silently ignored (the refusal-parity rule).
      def search_meter(args, mode, near)
        meter = string_arg(args, "meter")
        pattern = string_arg(args, "meter_pattern")
        return [nil, nil] unless meter || pattern

        raise InvalidArguments, "meter/meter_pattern compose with text search only, not lemma/near" if
          mode == :lemma || near

        [meter, pattern]
      end

      # The Tibetan word-grain flag (P54-4), text mode only — refusal parity
      # with the meter facet.
      def search_words?(args, mode, near)
        return false unless args["words"] == true

        raise InvalidArguments, "words composes with text search only, not lemma/near" if mode == :lemma || near

        true
      end

      # The lect filter arg (P57-4), text mode only — refusal parity with
      # the meter facet. Resolves the module HERE (not inside Query::Search)
      # so an absent module is a clean caller-fixable InvalidArguments,
      # mirroring the CLI's require_lects! pre-check; returns [lect, lects]
      # so run_search never re-resolves the seam.
      def search_lect(args, mode, near)
        lect = string_arg(args, "lect")
        return [nil, nil] unless lect

        raise InvalidArguments, "lect composes with text search only, not lemma/near" if mode == :lemma || near

        lects = lects_seam
        raise InvalidArguments, "lect needs the nabu-lects module — nabu-lects module not synced" unless lects

        [lect, lects]
      end

      def render_search(results, limit:, catalog:, incomplete: nil, rank_note: nil, meter_note: nil,
                        word_grain: nil, word_grain_note: nil, place_note: nil)
        # P54-4, present-only keys (additive to the frozen shape): word_grain
        # marks a page the Tibetan word-grain filter actually thinned
        # (filtered-out hits are simply absent); word_grain_note mirrors the
        # CLI degrade note when the flag could not filter.
        extra = {}
        extra[:word_grain] = true if word_grain
        extra[:word_grain_note] = word_grain_note if word_grain_note
        if results.empty?
          return json({ matches: [],
                        note: ["no matches", rank_note, meter_note, place_note, incomplete,
                               "looking for a work by name? #{CLARIFY_HINT}"].compact.join(" — "),
                        coverage: coverage_hint(catalog) }.merge(extra))
        end

        shown = results.first(limit)
        sources = sources_by_urn(catalog, shown.map(&:urn))
        note = if results.size > limit
                 "more than #{limit} matches, showing #{limit} — raise limit " \
                   "(max #{SEARCH_MAX_LIMIT}) or refine"
               else
                 "#{shown.size} matches, showing #{shown.size}"
               end
        # P42-2: the skipped-rank clause rides the existing free-text note —
        # additive, the frozen response shape gains no key. The meter facet's
        # source line (P45-5) rides the same way.
        note = "#{note} — #{rank_note}" if rank_note
        note = "#{note} — #{meter_note}" if meter_note
        note = "#{note} — #{place_note}" if place_note
        note = "#{note} — #{incomplete}" if incomplete
        json({ matches: shown.map { |result| match_payload(result, sources) }, note: note }.merge(extra))
      end

      def match_payload(result, sources)
        base = {
          urn: result.urn, language: result.language, license_class: result.license_class,
          source: sources[result.urn], document: result.document_title,
          text: truncate(result.text)
        }.merge(credit_field(result))
        if result.respond_to?(:lemma)
          # gloss (P11-4): the dictionary-shelf short gloss, nil-honest.
          # morph (P13-6): decoded morphology evidence, present only on a
          # --morph-filtered hit (nil otherwise, so ordinary lemma hits are
          # unchanged).
          # tier (P26-0, P34-3): present only on NON-gold hits — the CLI
          # mirror (silver/equivalence labeled per hit, gold unlabeled as
          # ever).
          lemma_hit = base.merge(lemma: result.lemma, surface_forms: result.surface_forms,
                                 gloss: result.gloss)
          lemma_hit = lemma_hit.merge(tier: result.tier) unless result.tier == "gold"
          # token_gloss: upstream's own token-level gloss, present only for a
          # source carrying a registered gloss layer (Query::TokenGlosses).
          lemma_hit = lemma_hit.merge(token_gloss: result.token_gloss) if result.token_gloss
          result.morph ? lemma_hit.merge(morph: result.morph) : lemma_hit
        else
          base.merge(snippet: result.snippet)
        end
      end

      # One line that makes "no matches" interpretable without a second call.
      # Split note: also read by nabu_concord (tools/concord.rb); kept with its primary user.
      def coverage_hint(catalog)
        languages = language_counts(catalog)
        "corpus: #{catalog[:sources].count} sources, #{languages.values.sum} passages; " \
          "languages: #{languages.keys.join(', ')} — the term may be absent, in an uncovered " \
          "language, or spelled differently; nabu_status shows full coverage"
      end

      def sense_note(result, hits)
        return "no indexed sense matches #{result.query.inspect} (an id, or a sense name)" if result.sense_total.zero?

        parts = ["#{result.sense_total} sense(s), #{result.passage_total} passage(s)"]
        listed = result.senses.size
        parts << "showing the #{listed} most-attested senses" if listed < result.sense_total
        parts << "showing #{result.hits.size} passage(s) — raise limit" if result.hits.size < result.passage_total
        withheld = result.hits.size - hits.size
        parts << "#{withheld} withheld (restricted license class)" if withheld.positive?
        parts.join(" — ")
      end

      # The lane composition check: any arg outside +allowed+ that is
      # actually set (not nil/false) is refused, named.
      def lane_conflicts!(args, lane, allowed)
        clash = args.reject { |key, value| allowed.include?(key) || value.nil? || value == false }.keys
        return if clash.empty?

        raise InvalidArguments, "#{lane} composes with #{(allowed - [lane]).join('/')} only (not #{clash.join(', ')})"
      end

      def restricted_license_note(license, include_restricted)
        return nil unless license && EXCLUDED_LICENSE_CLASSES.include?(license) && !include_restricted

        note("license class #{license} is excluded by default from this surface (it must never leak " \
             "casually); pass include_restricted: true to search it deliberately")
      end

      def lane_note(results, limit, lane, incomplete)
        line = if results.empty?
                 "no matches (#{lane})"
               elsif results.size > limit
                 "more than #{limit} matches, showing #{limit} — raise limit (max #{SEARCH_MAX_LIMIT}) or refine " \
                   "(#{lane})"
               else
                 "#{results.size} matches, showing #{results.size} (#{lane})"
               end
        incomplete ? "#{line} — #{incomplete}" : line
      end

      # Effective license class per passage urn (override beats source).
      def licenses_by_urn(catalog, urns)
        return {} if urns.empty?

        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:urn] => urns)
          .select(Sequel[:passages][:urn].as(:urn), license_expr.as(:license_class))
          .as_hash(:urn, :license_class)
      end
    end
  end
end
