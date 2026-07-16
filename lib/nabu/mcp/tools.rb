# frozen_string_literal: true

require "json"

require_relative "../errors"
require_relative "../model/validation"
require_relative "../store"
require_relative "../query/search"
require_relative "../query/lemma_search"
require_relative "../query/proximity"
require_relative "../query/morph_facets"
require_relative "../query/concord"
require_relative "../query/show"
require_relative "../query/parallel"
require_relative "../query/parallels"
require_relative "../query/align"
require_relative "../query/collation"
require_relative "../query/define"
require_relative "../query/etym"
require_relative "../query/cognates"

module Nabu
  module MCP
    # The MCP tool table (P8-1, extended P8-3): name + description + JSON Schema
    # + handler for the read-only tools. Pure translation — all query logic stays
    # in the Query classes; this layer only validates arguments, applies the
    # conversational-surface contract, and shapes JSON for a model to read.
    #
    # == The contract (fixed points, docs/backlog.md P8-1)
    #
    # - Every passage in every response carries urn + language + license_class
    #   (+ source slug — attribution is one cheap join away). The descriptions
    #   tell the model to preserve those fields when quoting.
    # - license classes research_private/restricted are DEFAULT-EXCLUDED from
    #   every tool. First real occupant: freising (CC BY-ND 2.5 SI, P13-11) —
    #   a conversational surface must never leak restricted or ad-hoc
    #   material casually. include_restricted: true opts in, per call,
    #   explicitly.
    # - Bounded outputs with honest truncation notes ("N total, showing k").
    #   No-match search responses carry a one-line coverage hint.
    # - Degradation is a normal tool response, never a crash and never
    #   isError (these are corpus STATES, not faults): missing catalog →
    #   "no corpus"; missing FTS table (mid-reindex window) → "index
    #   rebuilding — retry shortly"; SQLITE_BUSY → brief retry, then the same
    #   graceful shape.
    #
    # == Wiring
    #
    # catalog:/fulltext: accept a Sequel database, nil (absent), or a callable
    # returning either — resolved PER CALL, so the P8-2 entrypoint can hand us
    # lazy read-only openers and a corpus appearing (or rebuilding) mid-session
    # is picked up without a restart. Connections must be opened read-only
    # (Store.connect readonly: true) by the caller; nothing here writes.
    #
    # == P8-3: nabu_concord
    #
    # One more TOOLS entry + handler, the same bounded/license contract as
    # nabu_search: query XOR lemma, default-excluded restricted classes,
    # bounded rows with an honest truncation note, urn + language +
    # license_class + source on every row. It is a KWIC formatter over the same
    # Query::Search / Query::LemmaSearch, exposed as structured left/keyword/
    # right rows in corpus order.
    class Tools
      # tools/call with a name not in the table. The SERVER maps this to a
      # JSON-RPC -32602 protocol error (spec: unknown tools are protocol
      # errors, not tool results).
      class UnknownTool < Nabu::Error; end

      # Semantically invalid arguments (query XOR lemma violated, unknown
      # license class, missing urn). The SERVER maps this to a tool RESULT
      # with isError:true — per MCP 2025-11-25 (SEP-1303), input validation
      # errors are tool execution errors so the model can self-correct.
      class InvalidArguments < Nabu::Error; end

      LICENSE_CLASSES = Nabu::Model::Validation::LICENSE_CLASSES

      # Never served unless include_restricted: true names them explicitly.
      EXCLUDED_LICENSE_CLASSES = %w[research_private restricted].freeze

      SEARCH_DEFAULT_LIMIT = 10
      SEARCH_MAX_LIMIT = 50
      SEARCH_DEFAULT_WINDOW = Query::Proximity::DEFAULT_WINDOW
      # A generous proximity ceiling: beyond this the NEAR window spans most
      # passages and stops meaning "near". Clamps the arg, honest note.
      SEARCH_MAX_WINDOW = 50
      SHOW_DEFAULT_MAX_PASSAGES = 50
      SHOW_MAX_PASSAGES_CAP = 200
      CONCORD_DEFAULT_LIMIT = 10
      CONCORD_MAX_LIMIT = 50
      CONCORD_DEFAULT_WIDTH = Query::Concord::DEFAULT_WIDTH
      CONCORD_MAX_WIDTH = 120
      PARALLELS_DEFAULT_LIMIT = 10
      PARALLELS_MAX_LIMIT = 50
      LINKS_DEFAULT_LIMIT = 20
      LINKS_MAX_LIMIT = 100
      # Per-hit evidence spans carried in the payload (this surface is bounded;
      # a hit sharing more spans notes the truncation, the CLI is unbounded).
      PARALLELS_EVIDENCE_CAP = 12
      DEFINE_DEFAULT_LIMIT = 3
      DEFINE_MAX_LIMIT = 10
      # LSJ entries run to hundreds of KB (λόγος); this surface is bounded.
      DEFINE_BODY_CAP = 6_000
      DEFINE_MAX_CITATIONS = 40
      # The reconstruction walk (P14-1): proto entries per query, and the
      # cognate cap per entry (attested first — gem-pro trees run to ~150
      # reflexes; the CLI is the unbounded surface).
      ETYM_DEFAULT_LIMIT = 3
      ETYM_MAX_LIMIT = 10
      ETYM_MAX_COGNATES = 20
      DEFINE_MAX_REFLEXES = ETYM_MAX_COGNATES
      DEFINE_LANGS = %w[grc lat ang chu sla-pro ine-pro gem-pro
                        ine-bsl-pro gmw-pro itc-pro iir-pro].freeze
      # Rendered-ref ceiling for a range/chapter nabu_align (the query enforces it).
      MAX_ALIGN_REFS = Query::Align::MAX_REFS
      # Cognates-in-parallel (P15-3): (verse, root) groups per response — a
      # whole-work batch can hold thousands; this surface stays bounded.
      COGNATES_DEFAULT_LIMIT = 10
      COGNATES_MAX_LIMIT = 50

      # SQLITE_BUSY grace: total attempts before degrading to "busy — retry".
      BUSY_ATTEMPTS = 3

      NO_CORPUS_NOTE = "no corpus here yet — run `nabu sync <source>` or `nabu rebuild` " \
                       "to build it, then retry"
      NO_ALIGNMENTS_NOTE = "no alignment works registered — the owner adds works/witnesses " \
                           "to config/alignments.yml (architecture §10)"
      NO_SHELF_NOTE = "no dictionary shelf in this catalog yet — run `nabu sync lexica` (or " \
                      "`nabu rebuild` after one) to build it, then retry"
      NO_RECON_NOTE = "no reconstruction shelf in this catalog yet — run `nabu sync " \
                      "wiktionary-recon` (or `nabu rebuild` after one) to build it, then retry"
      ALIGN_REBUILDING_NOTE = "alignment index rebuilding (or the fulltext index predates the " \
                              "alignment hub) — retry shortly, or run `nabu rebuild`"
      COGNATES_REBUILDING_NOTE = "cognate root index rebuilding (or the fulltext index predates " \
                                 "it) — retry shortly, or run `nabu rebuild` (and `nabu sync " \
                                 "wiktionary-recon` if the reconstruction shelf is missing)"
      REBUILDING_NOTE = "search index rebuilding — retry shortly"
      LEMMA_REBUILDING_NOTE = "lemma index rebuilding (or the fulltext index predates lemma " \
                              "search) — retry shortly, or run `nabu rebuild`"
      BUSY_NOTE = "corpus is busy (a sync or rebuild may be running) — retry shortly"

      INCLUDE_RESTRICTED_SCHEMA = {
        type: "boolean", default: false,
        description: "Also serve research_private/restricted material. Default false and " \
                     "deliberately so: this surface must never leak private or " \
                     "license-restricted texts casually. Set true only when the requester " \
                     "understands and will honor the restriction."
      }.freeze

      SEARCH_DESCRIPTION =
        "Search nabu, a local corpus of ancient texts (polytonic Greek, Latin, Old Church " \
        "Slavonic, Gothic, and more: literary editions, documentary papyri, gold treebanks, " \
        "parallel English translations). Give EXACTLY ONE of: `query` — full-text FTS5 " \
        "(words AND by default, \"quoted phrase\", prefix*; diacritics optional, μηνιν finds " \
        "μῆνιν) — or `lemma` — exact dictionary form over the treebanks (λέγω finds εἶπας, " \
        "εἰπεῖν, every inflection; add `morph` — e.g. \"case=dat,number=pl\" — to keep only " \
        "attestations with that morphology, each hit showing the decoded evidence). Add `near` " \
        "for PROXIMITY — keep only hits where that term sits within `window` words (default " \
        "#{SEARCH_DEFAULT_WINDOW}, 0=adjacent) of query (or lemma, expanded to its surface " \
        "forms) in the SAME passage, order-independent; both matched terms are bracketed in the " \
        "snippet (near does not compose with morph). Hits are " \
        "relevance-ranked and bounded (default " \
        "#{SEARCH_DEFAULT_LIMIT}, max #{SEARCH_MAX_LIMIT}) with an honest 'showing k' note; " \
        "each carries urn, language, license_class, and source — PRESERVE the license fields " \
        "when quoting. Use nabu_show with a hit's urn for the full passage, nabu_status for " \
        "what the corpus covers.".freeze

      SHOW_DESCRIPTION =
        "Read the nabu corpus by urn: one passage, a whole document, an inclusive range, or " \
        "a parallel-aligned translation. urn shapes — passage: " \
        "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1 · document: " \
        "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2 · range: <document-urn>:1.1-1.10 " \
        "(inclusive slice) · papyrus: urn:nabu:ddbdp:aegyptus:89:240:b2:5 · treebank " \
        "sentence: urn:nabu:proiel:afnik:194690. `parallel: true` aligns the same work's " \
        "`parallel_lang` (default eng) edition line by line. Passage lists are bounded by " \
        "max_passages (default #{SHOW_DEFAULT_MAX_PASSAGES}, cap #{SHOW_MAX_PASSAGES_CAP}) " \
        "with an honest truncation note. Every passage carries urn, language, and " \
        "license_class — preserve them when quoting. Withdrawn/retired items appear, flagged.".freeze

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

      ALIGN_DESCRIPTION =
        "Cross-source alignment over the local nabu corpus: one citation of a registered work " \
        "rendered across EVERY witness the alignment registry names — e.g. the same New " \
        "Testament verse in Greek, Latin, Gothic, Classical Armenian, and Old Church Slavonic " \
        "at once. `ref` is a citation in the work's scheme (\"MARK 2.3\"; case/spacing/" \
        "chapter:verse colons normalize) or a passage urn to pivot from a search/show hit. " \
        "`work` picks the registry work when several exist (optional with one). Witnesses come " \
        "in registry order; each carries its language and license_class (the NT witnesses are " \
        "nc — PRESERVE the license fields when quoting), and every sentence row carries urn + " \
        "language + license_class + source. Sentence≠verse: a sentence spanning a verse " \
        "boundary lists every ref it covers. Honest absence: a witness lacking the verse reads " \
        "status no_match; a registered-but-unsynced witness reads not_synced. `ref` may also be " \
        "a whole CHAPTER (\"JON 1\") or an inclusive same-book verse RANGE (\"JON 1.1-1.16\"): " \
        "the reply is a `refs` array, one entry per ref in document order (each with the same " \
        "witness columns), capped at #{MAX_ALIGN_REFS} with an honest truncation note. Witnesses " \
        "absent from EVERY ref of a range are summarized once in `absent_witnesses` " \
        "(reason not_attested|not_synced) and omitted from the per-ref columns, so a chapter stays " \
        "readable. `collate: true` returns a witness DIFF instead: a raw-token apparatus per " \
        "(language, script) cell (base reading + each witness's divergences), with cross-script " \
        "witnesses rendered undiffed and labelled honestly — the fold cannot bridge e.g. the " \
        "Cyrillic Marianus and the Helsinki-ASCII CCMH codices.".freeze

      DEFINE_DESCRIPTION =
        "Look up a lemma (dictionary form) in the lexica nabu holds locally — LSJ for " \
        "ancient Greek, Lewis & Short for Latin (CC BY-SA, Perseus Digital Library), " \
        "Bosworth-Toller for Old English (CC BY 4.0, LINDAT dump; æ/þ/ð typeable in ASCII: " \
        "aethele finds æðele), Wiktionary for Old Church Slavonic (kaikki.org extract, " \
        "CC-BY-SA + GFDL; etymologies with Proto-Slavic/PIE chains kept in the body), and " \
        "the Wiktionary RECONSTRUCTION shelves (Proto-Slavic/PIE/Proto-Germanic/" \
        "Proto-Balto-Slavic/Proto-West Germanic/Proto-Italic/Proto-Indo-Iranian, same " \
        "extract family): a LEADING ASTERISK scopes to reconstructions (*bogъ), whose " \
        "entries also list their descendant reflexes with corpus attestation counts " \
        "(nabu_etym walks the same crosswalk from an attested lemma). " \
        "Diacritics optional (μηνις finds μῆνις); `lang` (grc|lat|ang|chu|or a -pro shelf " \
        "code) picks a shelf when the spelling is ambiguous. Each entry carries headword, " \
        "dictionary, license fields " \
        "(PRESERVE them when quoting), a short gloss, the entry body as structured plain " \
        "text (senses labeled; bounded at #{DEFINE_BODY_CAP} chars with an honest note — the " \
        "CLI `nabu define` is unbounded), and the entry's citations: where the cited work is " \
        "in the local catalog the citation carries a resolved passage urn (open it with " \
        "nabu_show); otherwise resolved_urn is null and the display text stands. Bounded " \
        "(default #{DEFINE_DEFAULT_LIMIT} entries, max #{DEFINE_MAX_LIMIT}; homographs are " \
        "separate entries).".freeze

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
        "directly. Cognate lists are bounded (attested first, #{ETYM_MAX_COGNATES} shown) " \
        "with honest totals; `nabu etym` (CLI) is unbounded.".freeze

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
        "and source — PRESERVE the license fields when quoting. `lang`/`license` scope candidates.".freeze

      STATUS_DESCRIPTION =
        "Coverage of the local nabu corpus: per-source document/passage counts and last-sync " \
        "recency, passage counts by language and by license class, index state, and what is " \
        "excluded by default (research_private/restricted). Call this to interpret an empty " \
        "search — is the language, source, or period even ingested here? — before concluding " \
        "a text is unattested. Takes no arguments."

      LINKS_DESCRIPTION =
        "Batch-mined cross-reference edges touching a passage/document urn — the links journal " \
        "(kind=parallel from `nabu parallels --batch`; kind=formula from `formulas --batch`, a " \
        "star per refrain whose detail carries the gram and score its count; kind=cognate from " \
        "`cognates --batch`, cross-language witness pairs whose detail carries the meet: " \
        "ref · root [shelf] — a gem-pro shelf under a Slavic witness suggests a borrowing). " \
        "READS ONLY what a batch run already persisted: for on-the-fly discovery use " \
        "nabu_parallels; an empty result means no batch has covered this urn, NOT that no " \
        "parallel exists. Edges come back grouped by kind, both directions (direction=out: this " \
        "urn's anchor probe discovered the counterpart; in: another anchor found this urn), each " \
        "counterpart resolved to document title/language/license_class (null when no longer in " \
        "the catalog — edges are urn-keyed and outlive rebuilds). `runs` cites the producer " \
        "run(s): producer, scope, params, code_version, date — every edge's provenance. Bounded " \
        "per kind (default #{LINKS_DEFAULT_LIMIT}, max #{LINKS_MAX_LIMIT}) with an honest note; " \
        "PRESERVE the license fields when quoting.".freeze

      SEARCH_SCHEMA = {
        type: "object",
        properties: {
          query: { type: "string",
                   description: "Full-text query. Mutually exclusive with lemma." },
          lemma: { type: "string",
                   description: "Dictionary form for exact-lemma treebank search. " \
                                "Mutually exclusive with query." },
          morph: { type: "string",
                   description: "Morphology facets, only WITH lemma: comma-joined key=value in " \
                                "Universal Dependencies vocabulary (case, number, gender, person, " \
                                "tense, mood, voice, degree; values dat, pl/sg, masc, aor, opt, " \
                                "sub…), all required. E.g. \"case=dat,number=pl\". UD treebanks " \
                                "match on feats, PROIEL/TOROT are decoded to the same names; ORACC " \
                                "has no inflectional morphology so these facets never match it." },
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
          from: { type: "integer",
                  description: "Earliest date: signed HISTORICAL year, negative = BCE, no year 0 " \
                               "(-300 = 300 BCE, 14 = 14 CE). Filters the document date/place axis " \
                               "(dated papyri via HGV, Slovene goo300k/IMP); most of the corpus is " \
                               "undated and absent under a date filter. Text search only (not lemma)." },
          to: { type: "integer",
                description: "Latest date: signed historical year; composes with from." },
          century: { type: "integer",
                     description: "Shorthand for one century's from/to (6 = 6th c. CE, -2 = 2nd c. " \
                                  "BCE); mutually exclusive with from/to." },
          place: { type: "string",
                   description: "Provenance place LIKE filter (Oxyrhynchus, oxyrhynch%) — dated papyri." },
          limit: { type: "integer", minimum: 1, maximum: SEARCH_MAX_LIMIT,
                   default: SEARCH_DEFAULT_LIMIT, description: "Maximum hits returned." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        additionalProperties: false
      }.freeze

      SHOW_SCHEMA = {
        type: "object",
        properties: {
          urn: { type: "string",
                 description: "Passage, document, or range urn (see the tool description " \
                              "for the shapes)." },
          parallel: { type: "boolean", default: false,
                      description: "Align with the same work's parallel_lang edition by " \
                                   "citation suffix." },
          parallel_lang: { type: "string", default: "eng",
                           description: "Language of the parallel edition (with parallel: true)." },
          max_passages: { type: "integer", minimum: 1, maximum: SHOW_MAX_PASSAGES_CAP,
                          default: SHOW_DEFAULT_MAX_PASSAGES,
                          description: "Bound on listed passages/rows; truncation is noted " \
                                       "honestly." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["urn"],
        additionalProperties: false
      }.freeze

      STATUS_SCHEMA = { type: "object", properties: {}, additionalProperties: false }.freeze

      ALIGN_SCHEMA = {
        type: "object",
        properties: {
          ref: { type: "string",
                 description: "Citation in the work's scheme (e.g. \"MARK 2.3\"), a whole " \
                              "chapter (\"JON 1\"), an inclusive same-book verse range " \
                              "(\"JON 1.1-1.16\"), or a passage urn to pivot from." },
          work: { type: "string",
                  description: "Alignment work id from the registry (optional when exactly " \
                               "one work is registered)." },
          collate: { type: "boolean",
                     description: "Diff the witnesses instead of listing them: a raw-token " \
                                  "apparatus per (language, script) cell — base reading plus each " \
                                  "witness's divergences only; cross-script witnesses rendered " \
                                  "undiffed and labelled honestly (the fold cannot bridge e.g. the " \
                                  "Cyrillic Marianus and the Helsinki-ASCII CCMH codices)." },
          base: { type: "string",
                  description: "With collate: the base witness (label or document urn) each cell " \
                               "diffs against (default: the first witness in registry order)." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["ref"],
        additionalProperties: false
      }.freeze

      DEFINE_SCHEMA = {
        type: "object",
        properties: {
          lemma: { type: "string",
                   description: "Dictionary form to look up (e.g. λόγος, virtus)." },
          lang: { type: "string", enum: DEFINE_LANGS,
                  description: "Dictionary language: grc → LSJ, lat → Lewis & Short, " \
                               "ang → Bosworth-Toller (Old English), chu → Wiktionary " \
                               "(Old Church Slavonic), sla-pro/ine-pro/gem-pro → the " \
                               "Wiktionary reconstruction shelves." },
          limit: { type: "integer", minimum: 1, maximum: DEFINE_MAX_LIMIT,
                   default: DEFINE_DEFAULT_LIMIT, description: "Maximum entries returned." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["lemma"],
        additionalProperties: false
      }.freeze

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
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["urn"],
        additionalProperties: false
      }.freeze

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
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["target"],
        additionalProperties: false
      }.freeze

      # The tool table. P8-3 adds nabu_concord (a KWIC formatter over the same
      # Query classes) as a fourth entry with its own handler; P15-1 adds
      # nabu_parallels (the intertext engine) as the eighth; P15-3 adds
      # nabu_cognates (the hub × crosswalk join) as the ninth; P16-1 adds
      # nabu_links (the links-journal reader) as the tenth.
      TOOLS = {
        "nabu_search" => { description: SEARCH_DESCRIPTION, input_schema: SEARCH_SCHEMA,
                           handler: :search },
        "nabu_show" => { description: SHOW_DESCRIPTION, input_schema: SHOW_SCHEMA,
                         handler: :show },
        "nabu_concord" => { description: CONCORD_DESCRIPTION, input_schema: CONCORD_SCHEMA,
                            handler: :concord },
        "nabu_align" => { description: ALIGN_DESCRIPTION, input_schema: ALIGN_SCHEMA,
                          handler: :align },
        "nabu_define" => { description: DEFINE_DESCRIPTION, input_schema: DEFINE_SCHEMA,
                           handler: :define },
        "nabu_etym" => { description: ETYM_DESCRIPTION, input_schema: ETYM_SCHEMA,
                         handler: :etym },
        "nabu_parallels" => { description: PARALLELS_DESCRIPTION, input_schema: PARALLELS_SCHEMA,
                              handler: :parallels },
        "nabu_cognates" => { description: COGNATES_DESCRIPTION, input_schema: COGNATES_SCHEMA,
                             handler: :cognates },
        "nabu_links" => { description: LINKS_DESCRIPTION, input_schema: LINKS_SCHEMA,
                          handler: :links },
        "nabu_status" => { description: STATUS_DESCRIPTION, input_schema: STATUS_SCHEMA,
                           handler: :status }
      }.freeze

      # +alignments+ (P11-3): the Nabu::AlignmentRegistry (or a callable
      # returning one, or nil when the hub is unconfigured) — config-loaded by
      # the entrypoint, resolved per call like the connection slots.
      def initialize(catalog:, fulltext:, alignments: nil, ledger: nil, links: nil, registry: nil)
        @catalog = catalog
        @fulltext = fulltext
        @alignments = alignments
        # The source registry (P23-3b): AUTHORITATIVE for enablement. The db
        # sources row mirrors a sources.yml flip only at that source's next
        # sync, so nabu_status reads enabled from the registry for registered
        # slugs (the db value stays for unregistered catalog orphans). nil
        # (unconfigured entrypoint, older callers) degrades to db values.
        @registry = registry
        # The history ledger, read-only (P14-12): nabu_status surfaces the
        # CACHED upstream-drift verdicts from it. nil when unconfigured or
        # absent — every source then reports upstream "never_probed". MCP NEVER
        # probes upstreams live: this is a bounded status read, nothing more.
        @ledger = ledger
        # The links journal, read-only (P16-1): nabu_links reads batch-mined
        # edges. nil when unconfigured or absent (no batch producer has run) —
        # a graceful state, never an error. MCP NEVER mines: batch runs are
        # owner-fired through the CLI.
        @links = links
      end

      # tools/list shape: [{name:, description:, inputSchema:}].
      def definitions
        TOOLS.map do |name, tool|
          { name: name, description: tool.fetch(:description), inputSchema: tool.fetch(:input_schema) }
        end
      end

      # Run tool +name+ with +arguments+ (string-keyed hash, as parsed from the
      # wire). Returns an MCP tool result: { content: [{type:, text:}], isError: }.
      def call(name, arguments)
        tool = TOOLS[name] or raise UnknownTool, "Unknown tool: #{name}"
        raise InvalidArguments, "arguments must be an object" unless arguments.is_a?(Hash)

        with_grace { send(tool.fetch(:handler), arguments) }
      end

      private

      # -- handlers --------------------------------------------------------------

      def search(args)
        term, mode = search_term(args)
        morph = search_morph(args, mode)
        near = search_near(args, morph)
        license = license_arg(args)
        include_restricted = args["include_restricted"] == true
        if license && EXCLUDED_LICENSE_CLASSES.include?(license) && !include_restricted
          return note("license class #{license} is excluded by default from this surface " \
                      "(it must never leak casually); pass include_restricted: true to " \
                      "search it deliberately")
        end

        from, to, place = search_date(args, mode, near)
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        fulltext = search_index(mode) or return note(mode == :lemma ? LEMMA_REBUILDING_NOTE : REBUILDING_NOTE)

        limit = clamp(args["limit"], default: SEARCH_DEFAULT_LIMIT, max: SEARCH_MAX_LIMIT)
        window = clamp(args["window"], default: SEARCH_DEFAULT_WINDOW, max: SEARCH_MAX_WINDOW, min: 0)
        results = run_search(mode, term, catalog: catalog, fulltext: fulltext, near: near, window: window,
                                         lang: args["lang"], license: license, limit: limit + 1, morph: morph,
                                         from: from, to: to, place: place)
        results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        render_search(results, limit: limit, catalog: catalog)
      rescue Query::MorphFacets::Error => e
        raise InvalidArguments, e.message
      end

      def show(args)
        urn = string_arg(args, "urn") or raise InvalidArguments, "nabu_show needs a urn"
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        bound = clamp(args["max_passages"], default: SHOW_DEFAULT_MAX_PASSAGES, max: SHOW_MAX_PASSAGES_CAP)
        include_restricted = args["include_restricted"] == true
        return show_parallel(catalog, urn, args, bound, include_restricted) if args["parallel"] == true

        result = Query::Show.new(catalog: catalog).run(urn)
        if result.nil?
          return note("urn not found: #{urn} — nabu_search finds passages, nabu_status shows " \
                      "what this corpus holds")
        end
        return withheld(urn, result.license_class) if withhold?(result.license_class, include_restricted)

        case result
        when Query::Show::PassageResult then json(passage_payload(result))
        when Query::Show::DocumentResult then json(document_payload(result, bound))
        when Query::Show::RangeResult then json(range_payload(result, bound))
        # A dictionary-entry urn (the ones nabu_define prints) resolves to the
        # define payload shape (P22-2), license-withheld by the same rule.
        when Query::Define::Result then json(define_payload(result))
        end
      rescue Query::Range::Error => e
        tool_error(e.message)
      end

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
        result = Query::Parallels.new(catalog: catalog, fulltext: fulltext)
                                 .run(urn, limit: limit + 1, lang: args["lang"], license: license)
        if result.nil?
          return note("urn not found: #{urn} — nabu_search finds passages, nabu_status shows " \
                      "what this corpus holds")
        end

        render_parallels(result, limit: limit, catalog: catalog, include_restricted: include_restricted)
      end

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

        render_links(result, limit: limit, include_restricted: args["include_restricted"] == true)
      end

      def align(args)
        ref = string_arg(args, "ref") or
          raise InvalidArguments, "nabu_align needs a ref (a citation like MARK 2.3, or a passage urn)"
        registry = resolve(@alignments)
        return note(NO_ALIGNMENTS_NOTE) if registry.nil? || registry.empty?

        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        fulltext = resolve(@fulltext)
        return note(ALIGN_REBUILDING_NOTE) unless fulltext&.table_exists?(Store::AlignmentIndexer::TABLE)

        include_restricted = args["include_restricted"] == true
        return collate(args, catalog, fulltext, registry, include_restricted) if args["collate"] == true

        result = Query::Align.new(catalog: catalog, fulltext: fulltext, registry: registry)
                             .run(ref, work: string_arg(args, "work"))
        json(if result.is_a?(Query::Align::RangeResult)
               align_range_payload(result, include_restricted: include_restricted)
             else
               align_payload(result, include_restricted: include_restricted)
             end)
      rescue Query::Align::Error => e
        # Caller-fixable (unknown work, unaligned urn): isError so the model
        # self-corrects (SEP-1303), same stance as bad arguments.
        tool_error(e.message)
      end

      # `collate: true` on nabu_align (P15-4): the witness DIFF apparatus. Same
      # index/registry contract as align; the license gate WITHHOLDS excluded
      # witnesses from the diff bodily (they cannot leak through a divergence
      # line) unless include_restricted.
      def collate(args, catalog, fulltext, registry, include_restricted)
        exclude = include_restricted ? [] : EXCLUDED_LICENSE_CLASSES
        collation = Query::Collation.new(catalog: catalog, fulltext: fulltext, registry: registry)
        result = collation.run(string_arg(args, "ref"), work: string_arg(args, "work"),
                                                        base: string_arg(args, "base"), exclude_licenses: exclude)
        json(collation_payload(result))
      end

      def define(args)
        lemma = string_arg(args, "lemma") or raise InvalidArguments, "nabu_define needs a lemma"
        lang = string_arg(args, "lang")
        if lang && !DEFINE_LANGS.include?(lang)
          raise InvalidArguments, "lang must be one of #{DEFINE_LANGS.join(', ')} " \
                                  "(the shelves this corpus holds)"
        end

        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        return note(NO_SHELF_NOTE) unless catalog.table_exists?(:dictionary_entries)

        limit = clamp(args["limit"], default: DEFINE_DEFAULT_LIMIT, max: DEFINE_MAX_LIMIT)
        include_restricted = args["include_restricted"] == true
        results = Query::Define.new(catalog: catalog, fulltext: resolve(@fulltext))
                               .run(lemma, lang: lang, limit: limit + 1)
        results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        render_define(results, lemma: lemma, limit: limit)
      end

      # The reconstruction walk (P14-1): attested lemma → proto entries with
      # cognates + one ascent hop. Same shelf guards and license stance as
      # nabu_define; the crosswalk table additionally needs migration 007.
      def etym(args)
        lemma = string_arg(args, "lemma") or raise InvalidArguments, "nabu_etym needs a lemma"
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        return note(NO_RECON_NOTE) unless catalog.table_exists?(:dictionary_reflexes)

        limit = clamp(args["limit"], default: ETYM_DEFAULT_LIMIT, max: ETYM_MAX_LIMIT)
        include_restricted = args["include_restricted"] == true
        results = Query::Etym.new(catalog: catalog, fulltext: resolve(@fulltext))
                             .run(lemma, lang: string_arg(args, "lang"), limit: limit + 1)
        results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        render_etym(results, lemma: lemma, limit: limit)
      end

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
        result = Query::Cognates.new(catalog: catalog, fulltext: fulltext, registry: registry)
                                .run(target, work: string_arg(args, "work"), langs: args["langs"],
                                             all: args["all"] == true, long: true, exclude_license: exclude)
        render_cognates(result, limit: limit)
      rescue Query::Cognates::Error => e
        tool_error(e.message)
      end

      def status(_args)
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)

        json(
          sources: source_rows(catalog),
          languages: language_counts(catalog),
          license_classes: license_counts(catalog, excluded: false),
          excluded_by_default: license_counts(catalog, excluded: true),
          totals: { documents: visible_documents(catalog).count,
                    passages: visible_passages(catalog).count,
                    dictionary_entries: dictionary_entry_counts(catalog).values.sum },
          index: index_state,
          note: "counts are live passages/documents (withdrawn excluded); " \
                "research_private/restricted material is excluded from these counts and " \
                "from every tool by default (see excluded_by_default). each source's " \
                "upstream.* fields are the CACHED verdict of the last `nabu health --remote` " \
                "/ `nabu status --remote` run (drift = has upstream moved past our pin; " \
                "checked_at = when) — MCP never probes upstreams live"
        )
      end

      # -- search internals --------------------------------------------------------

      # [term, :text | :lemma], enforcing the XOR.
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

      # The proximity term (P14-8), or nil. Composes with query OR lemma anchor
      # but NOT with morph (morphology-narrowed proximity is out of scope), so a
      # near+morph combination is a clear usage error like the CLI's.
      def search_near(args, morph)
        near = string_arg(args, "near")
        return nil if near.nil?
        if morph
          raise InvalidArguments,
                "near does not compose with morph (morphology-narrowed proximity is out of scope)"
        end

        near
      end

      # The fulltext handle when the index this mode needs is present; nil
      # during the mid-reindex window (Indexer.rebuild! drops the tables first).
      def search_index(mode)
        fulltext = resolve(@fulltext)
        return nil unless fulltext&.table_exists?(Store::Indexer::TABLE)
        return nil if mode == :lemma && !fulltext.table_exists?(Store::Indexer::LEMMA_TABLE)

        fulltext
      end

      # Resolve the date/place axis args (P15-2), honestly scoped to plain text
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

          from, to = Nabu::DateAxis.century_bounds(century)
        end
        raise InvalidArguments, "there is no year 0 (1 BCE is -1, 1 CE is 1)" if from&.zero? || to&.zero?
        raise InvalidArguments, "from #{from} is after to #{to} (BCE years are negative)" if from && to && from > to

        [from, to, place]
      end

      def run_search(mode, term, catalog:, fulltext:, lang:, license:, limit:, near: nil, window: nil, morph: nil,
                     from: nil, to: nil, place: nil)
        if near
          return Query::Proximity.new(catalog: catalog, fulltext: fulltext).run(
            query: mode == :lemma ? nil : term, lemma: mode == :lemma ? term : nil,
            near: near, window: window, lang: lang, license: license, limit: limit
          )
        end
        if mode == :lemma
          return Query::LemmaSearch.new(catalog: catalog, fulltext: fulltext)
                                   .run(term, lang: lang, license: license, limit: limit, morph: morph)
        end

        Query::Search.new(catalog: catalog, fulltext: fulltext)
                     .run(term, lang: lang, license: license, limit: limit, from: from, to: to, place: place)
      end

      def render_search(results, limit:, catalog:)
        return json(matches: [], note: "no matches", coverage: coverage_hint(catalog)) if results.empty?

        shown = results.first(limit)
        sources = sources_by_urn(catalog, shown.map(&:urn))
        json(
          matches: shown.map { |result| match_payload(result, sources) },
          note: if results.size > limit
                  "more than #{limit} matches, showing #{limit} — raise limit " \
                    "(max #{SEARCH_MAX_LIMIT}) or refine"
                else
                  "#{shown.size} matches, showing #{shown.size}"
                end
        )
      end

      def match_payload(result, sources)
        base = {
          urn: result.urn, language: result.language, license_class: result.license_class,
          source: sources[result.urn], document: result.document_title,
          text: truncate(result.text)
        }
        if result.respond_to?(:lemma)
          # gloss (P11-4): the dictionary-shelf short gloss, nil-honest.
          # morph (P13-6): decoded morphology evidence, present only on a
          # --morph-filtered hit (nil otherwise, so ordinary lemma hits are
          # unchanged).
          lemma_hit = base.merge(lemma: result.lemma, surface_forms: result.surface_forms,
                                 gloss: result.gloss)
          result.morph ? lemma_hit.merge(morph: result.morph) : lemma_hit
        else
          base.merge(snippet: result.snippet)
        end
      end

      # -- define internals ---------------------------------------------------------

      def define_miss_note(lemma)
        langs = @catalog[:dictionaries].distinct.order(:language).select_map(:language)
        "no dictionary entry for #{lemma.inspect} — the shelf holds " \
          "#{@catalog[:dictionaries].count} dictionaries (#{langs.join(', ')}); " \
          "diacritics are optional; the lemma must be a dictionary form " \
          "(nabu_search with lemma: finds attestations)"
      end

      def render_define(results, lemma:, limit:)
        if results.empty?
          return json(entries: [],
                      note: define_miss_note(lemma))
        end

        shown = results.first(limit)
        json(
          entries: shown.map { |result| define_payload(result) },
          note: if results.size > limit
                  "more than #{limit} entries, showing #{limit} — raise limit (max #{DEFINE_MAX_LIMIT})"
                else
                  "#{shown.size} #{shown.size == 1 ? 'entry' : 'entries'}"
                end
        )
      end

      def define_payload(result)
        body = result.body
        truncated = body.length > DEFINE_BODY_CAP
        base = {
          urn: result.urn, dictionary: result.dictionary_slug,
          dictionary_title: result.dictionary_title, headword: result.headword,
          language: result.language, license_class: result.license_class,
          license: result.license, source: result.source_slug, gloss: result.gloss,
          body: truncated ? "#{body[0, DEFINE_BODY_CAP]}…" : body,
          body_truncated: truncated,
          citations: define_citations(result)
        }
        base = base.merge(reflex_fields(result.reflexes, cap: DEFINE_MAX_REFLEXES)) unless result.reflexes.empty?
        return base unless truncated

        base.merge(note: "entry body truncated at #{DEFINE_BODY_CAP} chars — " \
                         "`nabu define #{result.headword}` (CLI) renders it whole")
      end

      # Resolved citations first (they are the actionable ones), capped.
      def define_citations(result)
        ordered = result.citations.partition(&:resolved_urn).flatten(1)
        ordered.first(DEFINE_MAX_CITATIONS).map do |citation|
          { label: citation.label, resolved_urn: citation.resolved_urn }
        end
      end

      # -- etym internals -----------------------------------------------------------

      def render_etym(results, lemma:, limit:)
        if results.empty?
          return json(entries: [],
                      note: "no reconstruction names #{lemma.inspect} as a descendant, and no " \
                            "reconstruction headword matches it — the crosswalk covers " \
                            "Proto-Slavic/PIE/Proto-Germanic (Wiktionary). Try the lemma's " \
                            "dictionary form, or a quoted '*form' for a direct lookup (quote the " \
                            "star — a bare * is a shell glob)")
        end

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

      # Shared reflex/cognate list rendering (define + etym): attested first
      # (by count, descending), capped with an honest total.
      def reflex_fields(views, cap:, key: :reflexes)
        attested, rest = views.partition(&:attested_count)
        ordered = attested.sort_by { |view| -view.attested_count } + rest
        shown = ordered.first(cap).map do |view|
          { lang_code: view.lang_code, language: view.language, word: view.word,
            roman: view.roman, attested_count: view.attested_count }
        end
        fields = { key => shown, :"#{key}_total" => views.size }
        fields[:"#{key}_attested"] = attested.size
        fields
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
      # fields ride on every row, per contract.
      def concord_row_payload(row, sources)
        { urn: row.urn, language: row.language, license_class: row.license_class,
          source: sources[row.urn], left: row.left, keyword: row.keyword, right: row.right }
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
        payload
      end

      def lemma_echo_payload(echo, sources)
        { urn: echo.urn, language: echo.language, license_class: echo.license_class,
          source: sources[echo.urn], score: echo.score, shared_lemmas: echo.shared_lemmas }
      end

      def render_links(result, limit:, include_restricted:)
        kinds = result.groups.transform_values do |edges|
          include_restricted ? edges : edges.reject { |e| EXCLUDED_LICENSE_CLASSES.include?(e.license_class) }
        end
        json(
          type: "links",
          urn: result.urn, document: result.title,
          kinds: kinds.sort.to_h { |kind, edges| [kind, edges.first(limit).map { |e| link_edge_payload(e) }] },
          runs: result.runs.map do |run|
            { id: run.id, producer: run.producer, scope: run.scope, params: run.params,
              code_version: run.code_version, created_at: run.created_at.to_s }
          end,
          note: links_note(result, kinds: kinds, limit: limit)
        )
      end

      # detail (P16-2): per-edge evidence — the formula gram, the cognate
      # meet (ref · root [shelf]); nil on parallel edges.
      def link_edge_payload(edge)
        { direction: edge.direction, urn: edge.urn, document: edge.title,
          language: edge.language, license_class: edge.license_class,
          score: edge.score, detail: edge.detail }
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
        parts.join("; ")
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

      # One line that makes "no matches" interpretable without a second call.
      def coverage_hint(catalog)
        languages = language_counts(catalog)
        "corpus: #{catalog[:sources].count} sources, #{languages.values.sum} passages; " \
          "languages: #{languages.keys.join(', ')} — the term may be absent, in an uncovered " \
          "language, or spelled differently; nabu_status shows full coverage"
      end

      # -- show internals ------------------------------------------------------------

      def passage_payload(result)
        {
          type: "passage", urn: result.urn, language: result.language,
          license_class: result.license_class, source: result.source_slug,
          document_urn: result.document_urn, document_title: result.document_title,
          text: result.text, sequence: result.sequence, revision: result.revision,
          withdrawn: result.withdrawn,
          provenance: result.provenance.map { |e| { event: e.event, tool: e.tool, at: e.at.to_s } }
        }
      end

      def document_payload(result, bound)
        total = result.passages.size
        header(result).merge(
          type: "document",
          passages: passage_lines(result, result.passages.first(bound)),
          note: if total > bound
                  "showing #{bound} of #{total} passages — use a range urn " \
                    "#{result.urn}:<start>-<end> to slice the rest"
                else
                  "#{total} passages"
                end
        )
      end

      def range_payload(result, bound)
        shown = result.passages.first(bound)
        header(result).merge(
          type: "range", start_urn: result.start_urn, end_urn: result.end_urn,
          total: result.total, passages: passage_lines(result, shown),
          note: "#{shown.size} of #{result.total} document passages" +
                (result.passages.size > bound ? " (range truncated at #{bound} — narrow the range)" : "")
        )
      end

      def header(result)
        {
          urn: result.urn, title: result.title, language: result.language,
          license_class: result.license_class, source: result.source_slug,
          revision: result.revision, withdrawn: result.withdrawn,
          retired_upstream: result.retired_upstream
        }
      end

      # Every listed passage carries language + license_class: both are
      # document-effective values (a passage's effective license IS its
      # document's), so the contract holds mechanically.
      def passage_lines(document, lines)
        lines.map do |line|
          { urn: line.urn, language: document.language, license_class: document.license_class,
            text: line.text, withdrawn: line.withdrawn }
        end
      end

      def show_parallel(catalog, urn, args, bound, include_restricted)
        lang = string_arg(args, "parallel_lang") || "eng"
        result = Query::Parallel.new(catalog: catalog).run(urn, lang: lang)
        if result.nil?
          return note("urn not found: #{urn} — nabu_search finds passages, nabu_status shows " \
                      "what this corpus holds")
        end

        left_license = document_license(catalog, result.left.urn)
        return withheld(result.left.urn, left_license) if withhold?(left_license, include_restricted)
        return note("no #{lang} parallel edition of this work in the catalog for #{urn}") if result.right.nil?

        right_license = document_license(catalog, result.right.urn)
        return withheld(result.right.urn, right_license) if withhold?(right_license, include_restricted)

        json(parallel_payload(result, bound, left_license, right_license))
      rescue Query::Range::Error => e
        tool_error(e.message)
      end

      def parallel_payload(result, bound, left_license, right_license)
        shown = result.groups.first(bound)
        {
          type: "parallel",
          left: side_payload(result.left, left_license),
          right: side_payload(result.right, right_license),
          rows: shown.map { |group| parallel_row(group, result, left_license, right_license) },
          note: "#{shown.size} of #{result.groups.size} aligned rows" +
            (result.groups.size > bound ? " (truncated at #{bound} — use a range urn to slice)" : "")
        }
      end

      def side_payload(side, license)
        { urn: side.urn, title: side.title, language: side.language, license_class: license }
      end

      # One aligned row per span-group (P8-1b). left is the anchor/original
      # line, right the translation; a coarse block also carries the coverage
      # fields (anchor + the covered original suffix span, and the clip note
      # when a slice shows only part of it) so a model knows one translation
      # block owns the whole Greek span, not just the one line quoted as left.
      def parallel_row(group, result, left_license, right_license)
        original = group.originals.first
        row = {
          suffix: original&.suffix || group.anchor,
          left: parallel_line(original, result.left.language, left_license),
          right: parallel_line(group.translation, result.right.language, right_license)
        }
        return row unless group.kind == :block

        row.merge!(anchor: group.anchor, covers_first: group.covers_first,
                   covers_last: group.covers_last, clipped: group.clipped)
        row.merge!(shown_first: group.shown_first, shown_last: group.shown_last) if group.clipped
        row
      end

      def parallel_line(line, language, license)
        return nil if line.nil?

        { urn: line.urn, language: language, license_class: license,
          text: line.text, withdrawn: line.withdrawn }
      end

      # -- align internals ---------------------------------------------------------

      def align_payload(result, include_restricted:)
        attesting = result.witnesses.count { |witness| witness.status == :ok }
        {
          type: "alignment", work: result.work, title: result.title, ref: result.ref,
          witnesses: result.witnesses.map { |witness| align_witness_payload(witness, include_restricted) },
          note: "#{attesting} of #{result.witnesses.size} registered witnesses attest #{result.ref}; " \
                "statuses: ok (sentences follow), no_match (verse absent from that witness), " \
                "not_synced (registered, no data yet), withheld (license-excluded)"
        }
      end

      # A range/chapter query: the query string, the ref groups in document
      # order (each carrying the same witness columns as a single-ref reply),
      # and the honest cap accounting — total refs, how many are shown, whether
      # the ceiling clipped them (nabu_define's cap style).
      def align_range_payload(result, include_restricted:)
        {
          type: "alignment_range", work: result.work, title: result.title, query: result.query,
          total_refs: result.total, shown_refs: result.groups.size, truncated: result.truncated,
          # P11-9: witnesses absent from EVERY ref are summarized here once and
          # dropped from the per-ref witness arrays (the per-ref columns stay
          # readable). reason: not_attested (live, verses absent) | not_synced.
          absent_witnesses: result.absent.map { |witness| { label: witness.label, reason: witness.reason.to_s } },
          refs: result.groups.map do |group|
            { ref: group.ref,
              witnesses: group.witnesses.map { |witness| align_witness_payload(witness, include_restricted) } }
          end,
          note: range_note(result)
        }
      end

      def range_note(result)
        base = "#{result.query}: #{result.groups.size} refs in document order, each with its witness " \
               "columns (statuses: ok, no_match, not_synced, withheld)#{absent_note(result.absent)}"
        return base unless result.truncated

        "#{base} — TRUNCATED at #{MAX_ALIGN_REFS} of #{result.total} refs; narrow the range"
      end

      # The absent-witness clause (P11-9): present only when witnesses were
      # lifted out of the per-ref columns, so the model knows to read them off
      # absent_witnesses rather than expecting them per ref.
      def absent_note(absent)
        return "" if absent.empty?

        "; #{absent.size} witness(es) absent from every ref are summarized in absent_witnesses " \
          "(reason: not_attested|not_synced) and omitted from the per-ref columns"
      end

      # One witness column. A witness whose effective license class is
      # default-excluded is WITHHELD bodily (status + license class only, no
      # urns, no text) unless include_restricted — the same never-leak stance
      # as everywhere else on this surface.
      def align_witness_payload(witness, include_restricted)
        base = { label: witness.label, document_urn: witness.document_urn,
                 title: witness.title, language: witness.language,
                 license_class: witness.license_class, source: witness.source_slug }
        # P13-5: a witness whose psalter is numbered in another system (the WEB
        # Hebrew/Masoretic numbering) flags it so the model knows its refs were
        # remapped into the work vocabulary.
        base[:numbering] = witness.numbering if witness.numbering
        return base.merge(status: "withheld", sentences: []) if withhold?(witness.license_class, include_restricted)

        base.merge(status: witness.status.to_s,
                   sentences: witness.sentences.map { |sentence| align_sentence_payload(witness, sentence) })
      end

      # Every sentence row carries the full contract fields (urn + language +
      # license_class + source) plus the refs it covers — sentence≠verse,
      # stated per row. A remapped witness (P13-5) also reports its WITNESS-
      # NATIVE ref (Hebrew "PSA 23.1" under work "PSA 22.1") when it diverges.
      def align_sentence_payload(witness, sentence)
        row = { urn: sentence.urn, language: witness.language,
                license_class: witness.license_class, source: witness.source_slug,
                text: sentence.text, refs: sentence.refs }
        row[:native_ref] = sentence.native_ref if sentence.native_ref
        row
      end

      # -- align --collate internals (P15-4) ---------------------------------------

      def collation_payload(result)
        {
          type: "collation", work: result.work, title: result.title, query: result.query,
          total_refs: result.total, shown_refs: result.refs.size, truncated: result.truncated,
          refs: result.refs.map { |ref_collation| collation_ref_payload(ref_collation) },
          note: "raw-token apparatus per (language, script) cell: each cell diffs its witnesses " \
                "against a base (agreements elided; substitutions/omissions/insertions marked). " \
                "asides are witnesses rendered UNDIFFED — reason cross_script (a same-language " \
                "witness exists in another script the fold cannot bridge) or sole (the only witness " \
                "of its language here). missing lists no_match/not_synced/withheld witnesses."
        }
      end

      def collation_ref_payload(ref_collation)
        {
          ref: ref_collation.ref,
          cells: ref_collation.cells.map { |cell| collation_cell_payload(cell) },
          asides: ref_collation.asides.map do |aside|
            { label: aside.label, language: aside.language, script: aside.script,
              license_class: aside.license_class, source: aside.source_slug,
              reason: aside.reason.to_s, text: aside.text }
          end,
          missing: ref_collation.missing.map { |witness| { label: witness.label, status: witness.status.to_s } }
        }
      end

      def collation_cell_payload(cell)
        base = cell.readings.find(&:is_base)
        {
          language: cell.language, script: cell.script, base: cell.base_label,
          base_tokens: base.tokens,
          witnesses: cell.readings.reject(&:is_base).map do |reading|
            { label: reading.label, license_class: reading.license_class, source: reading.source_slug,
              agrees: reading.edits.empty?, tokens: reading.tokens,
              edits: reading.edits.map { |edit| { op: edit.op.to_s, base: edit.base, witness: edit.witness } } }
          end
        }
      end

      # -- the exclusion gate ------------------------------------------------------

      def withhold?(license_class, include_restricted)
        EXCLUDED_LICENSE_CLASSES.include?(license_class) && !include_restricted
      end

      def withheld(urn, license_class)
        note("#{urn} exists but its license class is #{license_class}, which this surface " \
             "excludes by default (private/restricted material must never leak casually). " \
             "Pass include_restricted: true only if the requester understands and will honor " \
             "the restriction.")
      end

      # Effective license class of the document at +urn+ (override beats source).
      def document_license(catalog, urn)
        catalog[:documents]
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:documents][:urn] => urn)
          .get(license_expr)
      end

      # -- status internals -----------------------------------------------------------

      def source_rows(catalog)
        entries = dictionary_entry_counts(catalog)
        descriptions = source_descriptions(catalog)
        probes = probe_cache
        catalog[:sources].order(:slug).map do |source|
          live_docs = catalog[:documents].where(source_id: source[:id], withdrawn: false)
          row = { slug: source[:slug], enabled: enabled_field(source),
                  license_class: source[:license_class],
                  documents: live_docs.count,
                  passages: catalog[:passages].where(withdrawn: false)
                                              .where(document_id: live_docs.select(:id)).count,
                  # P11-10: a dictionary source's content is entries, not docs/passages;
                  # surfacing the entry count here stops the reference shelf (lexica,
                  # 168k entries) from reading as an empty docs=0 passages=0 source.
                  entries: entries[source[:id]] || 0,
                  last_sync_at: source[:last_sync_at]&.to_s,
                  upstream: upstream_field(probes[source[:slug]]) }
          # P24-0: the source's dossier description rides by default — the
          # owner's own library metadata is useful context for a model
          # deciding where to search. Absent dossier/table = absent key.
          description = descriptions[source[:slug]]
          row[:description] = description if description
          row
        end
      end

      # { slug => description } from the derived source_records
      # (canonical/local-source dossiers, P24-0); {} on a catalog predating
      # migration 015 or before the owner seeded the shelf.
      def source_descriptions(catalog)
        return {} unless catalog.table_exists?(:source_records)

        catalog[:source_records].where(kind: "description").select_hash(:slug, :body)
      end

      # Registry truth for registered slugs (class note at @registry), the db
      # value for orphans / an unconfigured registry.
      def enabled_field(source)
        entry = @registry && @registry[source[:slug]]
        return entry.enabled unless entry.nil?

        [true, 1].include?(source[:enabled])
      end

      # { slug => source_probes row } from the read-only ledger (P14-12), or {}
      # when the ledger is unconfigured/absent or predates the source_probes
      # table (guarded). This is a cache read — never a live probe.
      def probe_cache
        ledger = resolve(@ledger)
        return {} unless ledger&.table_exists?(:source_probes)

        ledger[:source_probes].to_hash(:source_slug)
      end

      # The cached upstream-drift verdict for one source, or the honest
      # never_probed placeholder when this source has no cache row yet.
      def upstream_field(row)
        return { drift: "never_probed", checked_at: nil } unless row

        { drift: row[:drift], license: row[:license],
          checked_at: row[:checked_at]&.to_s, detail: row[:detail] }
      end

      # Live dictionary-entry counts keyed by owning source id — empty when this
      # catalog has no reference shelf yet (the dictionary tables land with the
      # first lexica sync, P11-4).
      def dictionary_entry_counts(catalog)
        return {} unless catalog.table_exists?(:dictionaries) && catalog.table_exists?(:dictionary_entries)

        catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionary_entries][:withdrawn] => false)
          .group_and_count(Sequel[:dictionaries][:source_id])
          .to_h { |row| [row[:source_id], row[:count]] }
      end

      def language_counts(catalog)
        visible_passages(catalog)
          .group_and_count(Sequel[:passages][:language])
          .to_h { |row| [row[:language], row[:count]] }
      end

      # Live passage counts grouped by effective license class — the visible
      # classes, or (excluded: true) the default-hidden ones, counted honestly
      # (aggregate numbers only; no urns, titles, or text).
      def license_counts(catalog, excluded:)
        dataset = live_passages(catalog)
        dataset = if excluded
                    dataset.where(license_expr => EXCLUDED_LICENSE_CLASSES)
                  else
                    dataset.exclude(license_expr => EXCLUDED_LICENSE_CLASSES)
                  end
        dataset.group_and_count(license_expr.as(:license_class))
               .to_h { |row| [row[:license_class], row[:count]] }
      end

      def index_state
        fulltext = resolve(@fulltext)
        fulltext&.table_exists?(Store::Indexer::TABLE) ? "present" : "unavailable (rebuilding or not built)"
      end

      # Live (two-level visibility) passages, all license classes.
      def live_passages(catalog)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
      end

      # Live AND default-visible (excluded classes filtered out).
      def visible_passages(catalog)
        live_passages(catalog).exclude(license_expr => EXCLUDED_LICENSE_CLASSES)
      end

      def visible_documents(catalog)
        catalog[:documents]
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:documents][:withdrawn] => false)
          .exclude(license_expr => EXCLUDED_LICENSE_CLASSES)
      end

      def license_expr
        Sequel.function(:coalesce,
                        Sequel[:documents][:license_override],
                        Sequel[:sources][:license_class])
      end

      def sources_by_urn(catalog, urns)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:urn] => urns)
          .select_hash(Sequel[:passages][:urn], Sequel[:sources][:slug])
      end

      # -- argument plumbing -------------------------------------------------------------

      def string_arg(args, key)
        value = args[key]
        return nil if value.nil?
        raise InvalidArguments, "#{key} must be a string" unless value.is_a?(String)

        stripped = value.strip
        stripped.empty? ? nil : stripped
      end

      # A signed-integer arg (the date/place axis years, P15-2), or nil. A
      # JSON number that isn't an integer is a usage error, not a silent coerce.
      def int_arg(args, key)
        value = args[key]
        return nil if value.nil?
        raise InvalidArguments, "#{key} must be an integer" unless value.is_a?(Integer)

        value
      end

      def license_arg(args)
        license = string_arg(args, "license")
        return license if license.nil? || LICENSE_CLASSES.include?(license)

        raise InvalidArguments,
              "unknown license #{license.inspect} (choose from #{LICENSE_CLASSES.join(', ')})"
      end

      # One bounded hit-text line (papyri passages run long): the full
      # passage is one nabu_show away, and the description says so.
      def truncate(text, max = 300)
        text.length > max ? "#{text[0, max]}…" : text
      end

      def clamp(value, default:, max:, min: 1)
        return default unless value.is_a?(Integer)

        value.clamp(min, max)
      end

      # -- response shapes + degradation ----------------------------------------------------

      def json(payload)
        ok(JSON.generate(payload))
      end

      # A corpus STATE (no corpus, rebuilding, busy, withheld, not-found):
      # a normal informative response, never isError.
      def note(text)
        ok(text)
      end

      def ok(text)
        { content: [{ type: "text", text: text }], isError: false }
      end

      def tool_error(text)
        { content: [{ type: "text", text: text }], isError: true }
      end

      # SQLITE_BUSY tolerance (brief retry, then a graceful state response) and
      # the mid-reindex race (the table_exists? probe passed but the Indexer
      # dropped the table before our query ran) — both are states, not faults.
      def with_grace
        attempts = 0
        begin
          yield
        rescue Sequel::DatabaseError => e
          return note(REBUILDING_NOTE) if e.message.match?(/no such table/i)
          raise unless e.message.match?(/busy|locked/i)

          attempts += 1
          if attempts < BUSY_ATTEMPTS
            sleep(0.05 * attempts)
            retry
          end
          note(BUSY_NOTE)
        end
      end

      # Resolve a connection slot: a Sequel database, nil, or a Proc/lambda
      # returning either (called per tool invocation — see the class note).
      # An explicit Proc check, not respond_to?(:call): Sequel::Database has
      # its own #call (prepared statements) and must pass through as a handle.
      def resolve(slot)
        slot.is_a?(Proc) ? slot.call : slot
      end
    end
  end
end
