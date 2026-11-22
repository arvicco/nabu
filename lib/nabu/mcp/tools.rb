# frozen_string_literal: true

require "json"

require_relative "../errors"
require_relative "../betacode"
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
require_relative "../query/parallels_explain"
require_relative "../query/clarify"
require_relative "../query/fuzzy"
require_relative "../query/translation_search"
require_relative "../query/annotation_search"
require_relative "../query/gloss_search"
require_relative "../query/senses"
require_relative "../query/align"
require_relative "../query/collation"
require_relative "../query/define"
require_relative "../query/etym"
require_relative "../query/cognates"
require_relative "../query/place"
require_relative "../query/signs"
require_relative "../query/source_scope"
require_relative "../lects"
require_relative "../pleiades"
require_relative "../sign_list"
require_relative "envelope"

module Nabu
  module MCP
    # The MCP tool table (P8-1, extended P8-3): name + description + JSON Schema
    # + handler for the read-only tools. Pure translation — all query logic stays
    # in the Query classes; this layer only validates arguments, applies the
    # conversational-surface contract, and shapes JSON for a model to read.
    #
    # == The contract (fixed points, the early backlog's P8-1 record)
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
      # const: the license model's private classes (Model::Validation) — code,
      # not corpus
      EXCLUDED_LICENSE_CLASSES = %w[research_private restricted].freeze

      # The MCP response caps (H5/H6): era-bound to MODEL-CONTEXT norms, not
      # to the corpus — a bounded surface serving a model's context window,
      # every truncation carrying an honest note, the CLI unbounded. Re-affirm
      # when the era's context norms shift, not when the corpus grows.
      # census: 200000, 2026-07-20, tokens — the era's typical model context; caps re-affirmed
      SEARCH_DEFAULT_LIMIT = 10
      SEARCH_MAX_LIMIT = 50
      SEARCH_DEFAULT_WINDOW = Query::Proximity::DEFAULT_WINDOW
      # A generous proximity ceiling: beyond this the NEAR window spans most
      # passages and stops meaning "near". Clamps the arg, honest note.
      # census: 33, 2026-08-04, papyri-ddbdp mean passage length in chars (re-
      # measured at the P57 full rebuild, N=921,611; claim holds) (lit
      # passages run longer) — 50 tokens still spans most passages
      SEARCH_MAX_WINDOW = 50
      # The `facets` arg's pair ceiling (nabu_search / nabu_define): each
      # pair is one AND'd subquery.
      # const: a request-shape guard, not a census — no real query ANDs more
      # than a handful of facets.
      MAX_FACET_FILTERS = 8
      # census: 200000, 2026-07-20, tokens — model-context norms (H5/H6, above)
      SHOW_DEFAULT_MAX_PASSAGES = 50
      SHOW_MAX_PASSAGES_CAP = 200
      CONCORD_DEFAULT_LIMIT = 10
      CONCORD_MAX_LIMIT = 50
      CONCORD_DEFAULT_WIDTH = Query::Concord::DEFAULT_WIDTH
      # census: 200000, 2026-07-20, tokens — model-context norms (H5/H6, above)
      CONCORD_MAX_WIDTH = 120
      PARALLELS_DEFAULT_LIMIT = 10
      PARALLELS_MAX_LIMIT = 50
      LINKS_DEFAULT_LIMIT = 20
      LINKS_MAX_LIMIT = 100
      # Per-hit evidence spans carried in the payload (this surface is bounded;
      # a hit sharing more spans notes the truncation, the CLI is unbounded).
      # census: 200000, 2026-07-20, tokens — model-context norms (H5/H6, above)
      PARALLELS_EVIDENCE_CAP = 12
      DEFINE_DEFAULT_LIMIT = 3
      DEFINE_MAX_LIMIT = 10
      # LSJ entries run to hundreds of KB (λόγος); this surface is bounded.
      # census: 200000, 2026-07-20, tokens — model-context norms (H5/H6, above)
      DEFINE_BODY_CAP = 6_000
      DEFINE_MAX_CITATIONS = 40
      # P123-1: entry→entry cross-references per entry (resolved first).
      # census: 200000, 2026-07-20, tokens — model-context norms (H5/H6, above)
      DEFINE_MAX_CROSSREFS = 20
      # The reconstruction walk (P14-1): proto entries per query, and the
      # cognate cap per entry (attested first — gem-pro trees run to ~150
      # reflexes; the CLI is the unbounded surface).
      # census: 200000, 2026-07-20, tokens — model-context norms (H5/H6, above)
      ETYM_DEFAULT_LIMIT = 3
      ETYM_MAX_LIMIT = 10
      ETYM_MAX_COGNATES = 20
      DEFINE_MAX_REFLEXES = ETYM_MAX_COGNATES
      # The define lang set is NOT a constant: it is live-derived from the
      # catalog's dictionaries table at serve time (#define_langs — P35-6 L4,
      # retiring the last survivor of the P11 hardcoded-list lesson).
      # Rendered-ref ceiling for a range/chapter nabu_align (the query enforces it).
      MAX_ALIGN_REFS = Query::Align::MAX_REFS
      # Cognates-in-parallel (P15-3): (verse, root) groups per response — a
      # whole-work batch can hold thousands; this surface stays bounded.
      # census: 200000, 2026-07-20, tokens — model-context norms (H5/H6, above)
      COGNATES_DEFAULT_LIMIT = 10
      COGNATES_MAX_LIMIT = 50
      # nabu_signs (P53-2): transliteration lines per response — a cdli
      # document urn can carry hundreds; this surface stays bounded.
      # census: 200000, 2026-07-29, tokens — model-context norms (H5/H6, above)
      SIGNS_DEFAULT_MAX_LINES = 40
      SIGNS_MAX_LINES_CAP = 200
      # nabu_clarify: candidates per response.
      # census: 200000, 2026-10-20, tokens — model-context norms (H5/H6, above)
      CLARIFY_DEFAULT_LIMIT = 10
      CLARIFY_MAX_LIMIT = 50

      # The self-correction pointer every not-found / no-match answer carries
      # (one round trip to a candidate urn).
      CLARIFY_HINT = "nabu_clarify normalizes a partial or misspelled title/reference into " \
                     "candidate urns plus the citation shape"

      # The answering spine's role line in a char card's attribution list.
      # const: display labels, not a corpus claim
      CHAR_SPINE_ROLES = { "osl" => "sign list", "unikemet" => "sign spine" }.freeze

      # SQLITE_BUSY grace: total attempts before degrading to "busy — retry".
      # const: a retry-grace choice, not a corpus claim
      BUSY_ATTEMPTS = 3

      NO_CORPUS_NOTE = "no corpus here yet — run `nabu sync <source>` or `nabu rebuild` " \
                       "to build it, then retry"
      NO_ALIGNMENTS_NOTE = "no alignment works registered — the owner adds works/witnesses " \
                           "to config/alignments.yml (architecture §10)"
      NO_SHELF_NOTE = "no dictionary shelf in this catalog yet — run `nabu sync lexica` (or " \
                      "`nabu rebuild` after one) to build it, then retry"
      NO_RECON_NOTE = "no reconstruction shelf in this catalog yet — run `nabu sync " \
                      "wiktionary-recon` (or `nabu rebuild` after one) to build it, then retry"
      NO_GAZETTEER_NOTE = "place NAME lookup needs the Pleiades gazetteer dump on disk — the " \
                          "owner runs `nabu sync pleiades` to add it; a numeric Pleiades id " \
                          "(or a pleiades.stoa.org/places URL) still counts holdings without it"
      HAN_CHAR_NOTE = "the Han character card is CLI-only for now (nabu char --json, contract " \
                      "frozen P72-2; MCP exposure pending) — nabu_define serves " \
                      "Han dictionary entries meanwhile; cuneiform and hieroglyph input answer " \
                      "here with the frozen sign-card contracts"

      NO_UNIKEMET_NOTE = "the Egyptian sign card needs the Unikemet spine on disk — the owner " \
                         "runs `nabu sync unikemet` to add it"

      NO_SIGN_LIST_NOTE = "sign lookup needs the Oracc Sign List on disk — the owner runs " \
                          "`nabu sync osl` (the osl feature module) to add it"
      ALIGN_REBUILDING_NOTE = "alignment index rebuilding (or the fulltext index predates the " \
                              "alignment hub) — retry shortly, or run `nabu rebuild`"
      COGNATES_REBUILDING_NOTE = "cognate root index rebuilding (or the fulltext index predates " \
                                 "it) — retry shortly, or run `nabu rebuild` (and `nabu sync " \
                                 "wiktionary-recon` if the reconstruction shelf is missing)"
      REBUILDING_NOTE = "search index rebuilding — retry shortly"
      LEMMA_REBUILDING_NOTE = "lemma index rebuilding (or the fulltext index predates lemma " \
                              "search) — retry shortly, or run `nabu rebuild`"
      BUSY_NOTE = "corpus is busy (a sync or rebuild may be running) — retry shortly"
      NO_FUZZY_INDEX_NOTE = "no fuzzy index (the fulltext index predates fragment search, or is " \
                            "rebuilding) — retry shortly, or run `nabu sync` / `nabu rebuild`"
      NO_FACET_MAP_NOTE = "token senses need the facet map (config/facet_map.yml), which this " \
                          "server was started without"

      INCLUDE_RESTRICTED_SCHEMA = {
        type: "boolean", default: false,
        description: "Also serve research_private/restricted material. Default false and " \
                     "deliberately so: this surface must never leak private or " \
                     "license-restricted texts casually. Set true only when the requester " \
                     "understands and will honor the restriction."
      }.freeze

      # The per-tool partials (description + schema + handler + its internals),
      # loaded here because their constants read the shared limits above and
      # the TOOLS registry below reads their constants.
      require_relative "tools/search"
      require_relative "tools/show"
      require_relative "tools/concord"
      require_relative "tools/align"
      require_relative "tools/define"
      require_relative "tools/etym"
      require_relative "tools/cognates"
      require_relative "tools/parallels"
      require_relative "tools/links"
      require_relative "tools/char"
      require_relative "tools/place"
      require_relative "tools/signs"
      require_relative "tools/clarify"
      require_relative "tools/status"

      # The tool table. P8-3 adds nabu_concord (a KWIC formatter over the same
      # Query classes) as a fourth entry with its own handler; P15-1 adds
      # nabu_parallels (the intertext engine) as the eighth; P15-3 adds
      # nabu_cognates (the hub × crosswalk join) as the ninth; P16-1 adds
      # nabu_links (the links-journal reader) as the tenth; P44-3 adds
      # nabu_place (the place desk over Query::Place) as the eleventh; P53-2
      # adds nabu_signs (the sign desk over Query::Signs) as the twelfth —
      # nabu_status stays last, the coverage epilogue.
      #
      # +title+ (contract bump 2026-10-22): the human-readable display name
      # the MCP spec's tool metadata carries; #definitions serves it top-level
      # and inside the `annotations` object beside readOnlyHint.
      TOOLS = {
        "nabu_search" => { title: "Search the corpus", description: SEARCH_DESCRIPTION,
                           input_schema: SEARCH_SCHEMA, handler: :search },
        "nabu_show" => { title: "Read passages by URN", description: SHOW_DESCRIPTION,
                         input_schema: SHOW_SCHEMA, handler: :show },
        "nabu_concord" => { title: "Concordance (keyword in context)", description: CONCORD_DESCRIPTION,
                            input_schema: CONCORD_SCHEMA, handler: :concord },
        "nabu_align" => { title: "Cross-source alignment", description: ALIGN_DESCRIPTION,
                          input_schema: ALIGN_SCHEMA, handler: :align },
        "nabu_define" => { title: "Dictionary lookup", description: DEFINE_DESCRIPTION,
                           input_schema: DEFINE_SCHEMA, handler: :define },
        "nabu_etym" => { title: "Reconstruction walk", description: ETYM_DESCRIPTION,
                         input_schema: ETYM_SCHEMA, handler: :etym },
        "nabu_parallels" => { title: "Intertext parallels", description: PARALLELS_DESCRIPTION,
                              input_schema: PARALLELS_SCHEMA, handler: :parallels },
        "nabu_cognates" => { title: "Cognates in parallel", description: COGNATES_DESCRIPTION,
                             input_schema: COGNATES_SCHEMA, handler: :cognates },
        "nabu_links" => { title: "Mined links graph", description: LINKS_DESCRIPTION,
                          input_schema: LINKS_SCHEMA, handler: :links },
        "nabu_char" => { title: "Character card", description: CHAR_DESCRIPTION,
                         input_schema: CHAR_SCHEMA, handler: :char_card },
        "nabu_place" => { title: "Place desk", description: PLACE_DESCRIPTION,
                          input_schema: PLACE_SCHEMA, handler: :place },
        "nabu_signs" => { title: "Cuneiform sign desk", description: SIGNS_DESCRIPTION,
                          input_schema: SIGNS_SCHEMA, handler: :signs },
        "nabu_clarify" => { title: "Reference normalizer", description: CLARIFY_DESCRIPTION,
                            input_schema: CLARIFY_SCHEMA, handler: :clarify },
        "nabu_status" => { title: "Corpus coverage status", description: STATUS_DESCRIPTION,
                           input_schema: STATUS_SCHEMA, handler: :status }
      }.freeze

      # +alignments+ (P11-3): the Nabu::AlignmentRegistry (or a callable
      # returning one, or nil when the hub is unconfigured) — config-loaded by
      # the entrypoint, resolved per call like the connection slots.
      def initialize(catalog:, fulltext:, alignments: nil, ledger: nil, links: nil, registry: nil,
                     enabled_slugs: nil, pleiades: nil, sign_list: nil, tibetan_words: nil, lects: nil,
                     readings: nil, hieroglyphs: nil, lect_rules: nil, lect_override_tiers: nil,
                     vectors: nil, facet_map: nil, scan_anchors: nil)
        @catalog = catalog
        # The reference-scan anchors (config/scan_anchors.yml — static,
        # loaded once by the entrypoint): nabu_define/nabu_show citations a
        # configured print work claims gain a present-only `scan` object.
        # nil = every citation payload byte-identical (the lane-off rule).
        @scan_anchors = scan_anchors
        # The facet map (config/facet_map.yml — static, loaded once by the
        # entrypoint): the token-sense rules behind nabu_search's `sense`
        # desk and nabu_show's `senses` flag. nil = both answer their honest
        # note, every other payload byte-identical (the lane-off rule).
        @facet_map = facet_map
        @fulltext = fulltext
        @alignments = alignments
        # The vector store (P93-5, nabu_search's similar_to): nil
        # (unconfigured — similar_to answers its honest build-hint note,
        # every other call byte-identical: the lane-off rule) or a
        # resolvable opener like @catalog.
        @vectors = vectors
        # The P81 U-5 lect-provenance gloss seams: the compiled rules (their
        # tier: words) and the {slug => {code => tier}} override map. Static
        # config, loaded once by the entrypoint (the alignments posture);
        # nil = untiered rendering — payloads carry the bare basis only.
        @lect_rules = lect_rules
        @lect_override_tiers = lect_override_tiers
        # The Tibetan words slot, shared by TWO consumers (P54-2 show's
        # `segmented` flag, P54-4 search's `words` flag): nil (unconfigured —
        # each flag answers with its honest sync-hint note, every other
        # payload byte-identical: the lane-off rule), a loaded
        # Nabu::TibetanWords (tests), or :auto — the entrypoint's setting.
        # :auto resolves lazily at use: Query::Show does its own resolution
        # for segmented renders; search goes through #tibetan_words_seam,
        # memoized once LOADED (the CSV read is the expensive part; while
        # absent it re-detects per call, so a mid-session `nabu sync
        # nabu-data` is picked up without a restart — the sign-list posture).
        @tibetan_words = tibetan_words
        # The nabu-lects slot (P57-4, nabu_search's `lect` filter): nil
        # (unconfigured — `lect` errors naming the module, every other tool
        # byte-identical: the lane-off rule), a loaded Nabu::Lects (tests),
        # or :auto — the entrypoint's setting, feature-detecting
        # canonical/nabu-lects lazily per call through #lects_seam, memoized
        # once LOADED (the tibetan_words/sign_list posture).
        @lects = lects
        # The sign-list slot (P53-2): nil (unconfigured — nabu_signs notes
        # the sync hint, every other tool byte-identical: the lane-off rule),
        # a loaded Nabu::SignList (tests), or :auto — the entrypoint's
        # setting, feature-detecting canonical/osl per call through
        # SignList.load_default (memoized per path, so the ~1 MB parse is
        # paid once per server process, and a mid-session `nabu sync osl`
        # is picked up without a restart).
        @sign_list = sign_list
        # The P68-3 nabu_char seams, same posture as @sign_list: nil
        # (unconfigured — the affected section is simply absent), a loaded
        # instance (tests), or :auto — lazy feature-detect per call through
        # each seam's memoized load_default.
        @readings = readings
        @hieroglyphs = hieroglyphs
        # The Pleiades gazetteer slot (P44-3): nil (gazetteer-less —
        # nabu_place id queries still count holdings, nabu_show serves no
        # findspot key, byte-identical to the pre-P44 payloads), a loaded
        # resolver (tests), or :auto — the entrypoint's setting, which
        # feature-detects LAZILY per call (Query::Show's own :auto for
        # findspot; #place_resolver for nabu_place). Since P45-6 :auto
        # prefers the derived catalog place index (instant, per-call, no
        # memoization needed); the in-memory dump load (~3 s / ~3.9 GB peak
        # on the real dump) is paid — per invocation, released after,
        # deliberately NOT memoized on this long-lived server object — only
        # while the index is not yet derived.
        @pleiades = pleiades
        # The enabled-slug set (P44-r3b): nabu_status's sources array defaults to
        # the box's ENABLED sources (the CLI list/status default), plus the
        # owner's own shelves (always) and any catalog orphans. nil = no
        # enablement config resolved (older callers / unconfigured) → the full
        # catalog, unfiltered (the pre-r3b behavior).
        @enabled_slugs = enabled_slugs
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

      # tools/list shape: [{name:, title:, description:, inputSchema:,
      # annotations:}]. nabu_define's lang enum is injected LIVE
      # (#define_langs) so the advertised language set can never rot into a
      # hand-frozen list again (P35-6 L4). The annotations (contract bump
      # 2026-10-22) follow the MCP spec's ToolAnnotations shape: every tool is
      # readOnlyHint true — the surface opens the stores read-only and has no
      # write tools — and the title rides there too for clients that read the
      # display name only from the annotations.
      def definitions
        TOOLS.map do |name, tool|
          title = tool.fetch(:title)
          { name: name, title: title, description: tool.fetch(:description),
            inputSchema: input_schema(name, tool), annotations: { title: title, readOnlyHint: true } }
        end
      end

      # Run tool +name+ with +arguments+ (string-keyed hash, as parsed from the
      # wire). Returns an MCP tool result: { content: [{type:, text:}], isError: }.
      def call(name, arguments)
        tool = TOOLS[name] or raise UnknownTool, "Unknown tool: #{name}"
        raise InvalidArguments, "arguments must be an object" unless arguments.is_a?(Hash)

        reject_unknown_arguments!(name, tool, arguments)
        with_grace { send(tool.fetch(:handler), arguments) }
      end

      private

      # The ONE unknown-argument gate, for every tool (contract bump
      # 2026-11-10): MCP transports do not enforce a schema's
      # additionalProperties: false, so an undeclared argument would
      # otherwise be silently dropped — an unimplemented filter no-op'ing
      # invisibly. Keyed off the tool's declared schema properties (the
      # frozen constant; the live define enum adds no names); the refusal
      # names the stranger(s) and the valid set so a model self-corrects.
      def reject_unknown_arguments!(name, tool, arguments)
        valid = tool.fetch(:input_schema).fetch(:properties).keys.map(&:to_s)
        unknown = arguments.keys.map(&:to_s) - valid
        return if unknown.empty?

        takes = valid.empty? ? "it takes no arguments" : "valid arguments: #{valid.join(', ')}"
        raise InvalidArguments, "#{name} does not take #{unknown.sort.join(', ')} — #{takes}"
      end

      # The nabu_search `lect` seam (P57-4), same :auto/loaded/nil contract.
      def lects_seam
        return @lects unless @lects == :auto

        loaded = Nabu::Lects.load_default
        @lects = loaded if loaded
        loaded
      end

      # The served input schema for one tool: nabu_define's lang enum is
      # injected from the live shelf set (absent when there is none to
      # advertise); every other schema is the frozen constant.
      def input_schema(name, tool)
        schema = tool.fetch(:input_schema)
        return schema unless name == "nabu_define"

        langs = define_langs
        return schema if langs.empty?

        lang = schema.dig(:properties, :lang).merge(enum: langs)
        schema.merge(properties: schema.fetch(:properties).merge(lang: lang))
      end

      # -- the exclusion gate ------------------------------------------------------

      def withhold?(license_class, include_restricted)
        EXCLUDED_LICENSE_CLASSES.include?(license_class) && !include_restricted
      end

      # The not-found answer every urn-taking tool shares — it names the
      # normalizer so a caller holding a half-right urn corrects in one hop.
      def urn_not_found(urn)
        note("urn not found: #{urn} — #{CLARIFY_HINT}; nabu_search finds passages, nabu_status " \
             "shows what this corpus holds")
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

      def sources_by_urn(catalog, urns)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:urn] => urns)
          .select_hash(Sequel[:passages][:urn], Sequel[:sources][:slug])
      end

      # -- argument plumbing -------------------------------------------------------------

      # The facet-filter arg (nabu_search / nabu_define `facets`, the CLI's
      # repeatable --facet NAME=PATTERN): a JSON object of facet name →
      # pattern, every pair non-empty strings, at most MAX_FACET_FILTERS.
      # nil when absent or {} (no filter); anything else is a usage error,
      # never a silent widening.
      def facets_arg(args)
        raw = args["facets"]
        return nil if raw.nil? || raw == {}

        valid = raw.is_a?(Hash) && raw.size <= MAX_FACET_FILTERS &&
                raw.all? { |name, pattern| [name, pattern].all? { |s| s.is_a?(String) && !s.strip.empty? } }
        unless valid
          raise InvalidArguments, "facets must be an object of facet name → pattern (non-empty strings, at most " \
                                  "#{MAX_FACET_FILTERS}), e.g. {\"domain\": \"medicine\"}"
        end

        raw.to_h { |name, pattern| [name.strip, pattern.strip] }
      end

      def string_arg(args, key)
        value = args[key]
        return nil if value.nil?
        raise InvalidArguments, "#{key} must be a string" unless value.is_a?(String)

        stripped = value.strip
        stripped.empty? ? nil : stripped
      end

      # A signed-integer arg (the timeline years, P15-2), or nil. A
      # JSON number that isn't an integer is a usage error, not a silent coerce.
      def int_arg(args, key)
        value = args[key]
        return nil if value.nil?
        raise InvalidArguments, "#{key} must be an integer" unless value.is_a?(Integer)

        value
      end

      # The source/axis scoping pair (the CLI's --source/--axis), resolved
      # through the SAME Query::SourceScope the CLI search family uses:
      # [source slug or nil, axis member slugs or nil] for the query
      # classes' source:/sources: filters. An unknown slug/axis is a
      # caller-fixable refusal naming the valid set — never an empty page.
      def search_scope(args, catalog)
        source = string_arg(args, "source")
        axis = string_arg(args, "axis")
        Query::SourceScope.validate_source!(catalog, source)
        return [source, nil] if axis.nil?

        registry = resolve(@registry)
        unless registry
          raise InvalidArguments, "axis needs the source registry (config/sources.yml + config/axes.yml), " \
                                  "which this server was started without — scope by source instead"
        end
        _names, sources = Query::SourceScope.axis_membership(registry, axis, command: "search")
        [source, sources]
      rescue Query::SourceScope::Error => e
        raise InvalidArguments, e.message
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
