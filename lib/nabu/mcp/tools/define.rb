# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_define tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      DEFINE_DESCRIPTION =
        "Look up a lemma (dictionary form) in the dictionary shelves nabu holds locally — " \
        "hundreds of lexica across many languages (LSJ, Lewis & Short, Bosworth-Toller, the " \
        "Wiktionary extracts, and far more; the `lang` enum in this schema is the LIVE set of " \
        "shelf languages, nabu_status counts the entries). The Wiktionary RECONSTRUCTION " \
        "shelves (*-pro codes) are included: a LEADING ASTERISK scopes to reconstructions " \
        "(*bogъ), whose entries also list their descendant reflexes with corpus attestation " \
        "counts (nabu_etym walks the same crosswalk from an attested lemma). " \
        "Diacritics optional (μηνις finds μῆνις); `lang` picks a shelf language when the " \
        "spelling is ambiguous. Each entry carries headword, " \
        "dictionary, license fields " \
        "(PRESERVE them when quoting), a short gloss, the entry body as structured plain " \
        "text (senses labeled; bounded at #{DEFINE_BODY_CAP} chars with an honest note — the " \
        "CLI `nabu define` is unbounded), and the entry's citations: where the cited work is " \
        "in the local catalog the citation carries a resolved passage urn (open it with " \
        "nabu_show); otherwise resolved_urn is null and the display text stands. A PRINT " \
        "citation of a reference work (a BDB page, a Wb volume/page/line, a Holder AcS " \
        "volume/column) may carry `scan`: " \
        "status (anchored/held/uncalibrated/out_of_range/not_held/unconfigured), urn (the " \
        "held scan's page passage or document — null when not held), leaf, pointer. Entries " \
        "may carry `crossrefs` — pointers to other entries, usually of the same dictionary, " \
        "sometimes of another (the Strong shelf's BDB ids) (kind, label verbatim, resolved_urn " \
        "of the target entry or null — open it with nabu_show). Bounded " \
        "(default #{DEFINE_DEFAULT_LIMIT} entries, max #{DEFINE_MAX_LIMIT}; homographs are " \
        "separate entries). The owner's own notes on an entry ride along in `notes` — " \
        "useful curatorial context.".freeze

      ROOT_SCHEMES = %w[buckwalter dmg arabic].freeze
      ROOT_KEYS_UNBUILT_NOTE = "the root keys are not built in this catalog yet — the next nabu rebuild " \
                               "or `bundle exec rake builders:refresh` projects them"

      DEFINE_SCHEMA = {
        type: "object",
        properties: {
          lemma: { type: "string",
                   description: "Dictionary form to look up (e.g. λόγος, virtus). Required unless " \
                                "root is given." },
          lang: { type: "string",
                  description: "Dictionary language. The enum (when present) is the LIVE set " \
                               "of shelves this catalog holds — e.g. grc → LSJ, lat → Lewis & " \
                               "Short, ang → Bosworth-Toller (Old English), chu → Wiktionary " \
                               "(Old Church Slavonic), *-pro → the Wiktionary reconstruction " \
                               "shelves." },
          limit: { type: "integer", minimum: 1, maximum: DEFINE_MAX_LIMIT,
                   default: DEFINE_DEFAULT_LIMIT, description: "Maximum entries returned." },
          lect: { type: "string",
                  description: "Restrict to shelves whose (language, source) RESOLUTION is this " \
                               "lect id or a more specific one under it (P59-3, nabu-lects " \
                               "module; dictionary grain — per-source overrides included, so " \
                               "derom's la-vul scopes under roa, never lat). Errors if the " \
                               "module is not synced on this box." },
          facets: { type: "object", additionalProperties: { type: "string" },
                    description: "Entry facet filters, an object of facet name → pattern, all " \
                                 "required (AND) — the categorical labels dictionaries attach " \
                                 "per entry: JMdict's domain / usage / dialect / loan_source, " \
                                 "WOLD's semantic_field / word_class / borrowed_status, TLS's " \
                                 "concept. {\"domain\": \"Buddhism\"} keeps only Buddhist-domain " \
                                 "senses. The pattern matches the value or its ref " \
                                 "case-insensitively; LIKE % patterns pass through. At most " \
                                 "#{MAX_FACET_FILTERS} pairs; untagged entries fall out." },
          root: { type: "string",
                  description: "INSTEAD of lemma: a consonantal Arabic root — Arabic script (رحم), " \
                               "Buckwalter as the Quranic Arabic Corpus writes it (rHm, Amn) or DMG " \
                               "as Corpus Coranicum writes it (rḥm, ʾmn) — returning the entries " \
                               "Lane's Lexicon files under it, with the root's Arabic form, the " \
                               "heading(s) hit, the total, and the tier that answered (strict; " \
                               "loose = weak radicals/reduplication folded, may over-merge; null = " \
                               "miss). The CLI twin is `nabu define --root`." },
          scheme: { type: "string", enum: ROOT_SCHEMES,
                    description: "With root: its notation (default: detected from its characters)." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        additionalProperties: false
      }.freeze

      private

      def define(args)
        lemma = string_arg(args, "lemma")
        root = string_arg(args, "root")
        raise InvalidArguments, "nabu_define takes a lemma or a root, not both" if lemma && root
        raise InvalidArguments, "nabu_define needs a lemma (or a root)" unless lemma || root

        lang = string_arg(args, "lang")
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        return note(NO_SHELF_NOTE) unless catalog.table_exists?(:dictionary_entries)
        return define_root(catalog, root, args) if root

        if lang && (langs = define_langs).any? && !langs.include?(lang)
          raise InvalidArguments, "lang must be one of #{langs.join(', ')} " \
                                  "(the dictionary shelves this catalog holds)"
        end

        limit = clamp(args["limit"], default: DEFINE_DEFAULT_LIMIT, max: DEFINE_MAX_LIMIT)
        include_restricted = args["include_restricted"] == true
        # P59-3: the shelf-grain lect scope, module pre-checked HERE (the
        # search_lect stance) so an absent module is a clean InvalidArguments.
        lect = string_arg(args, "lect")
        lects = nil
        if lect
          lects = lects_seam
          raise InvalidArguments, "lect needs the nabu-lects module — nabu-lects module not synced" unless lects
        end
        results = Query::Define.new(catalog: catalog, fulltext: resolve(@fulltext), lects: lects || :auto,
                                    scan_anchors: @scan_anchors)
                               .run(lemma, lang: lang, limit: limit + 1, lect: lect, facets: facets_arg(args))
        results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) } unless include_restricted
        render_define(results, lemma: lemma, limit: limit, catalog: catalog)
      end

      # The root lookup (Query::Define#by_root): the link's facts, then the
      # reached entries bounded like any define answer.
      def define_root(catalog, root, args)
        scheme = string_arg(args, "scheme")
        if scheme && !ROOT_SCHEMES.include?(scheme)
          raise InvalidArguments, "scheme must be one of #{ROOT_SCHEMES.join(', ')}"
        end
        return note(ROOT_KEYS_UNBUILT_NOTE) unless Query::RootLink.new(catalog: catalog).built?

        limit = clamp(args["limit"], default: DEFINE_DEFAULT_LIMIT, max: DEFINE_MAX_LIMIT)
        link, results = Query::Define.new(catalog: catalog, lila: nil, scan_anchors: @scan_anchors)
                                     .by_root(root, scheme: scheme&.to_sym, limit: limit)
        unless args["include_restricted"] == true
          results = results.reject { |r| EXCLUDED_LICENSE_CLASSES.include?(r.license_class) }
        end
        json(root: link.root, scheme: link.scheme.to_s, arabic: link.arabic, tier: link.tier&.to_s,
             headings: link.headings, total: link.total,
             entries: results.map { |result| attach_notes(catalog, result, define_payload(result)) },
             note: root_note(link, results.size))
      end

      def root_note(link, shown)
        return "not a consonantal root in the #{link.scheme} notation — no lookup" if link.arabic.nil?
        return "no dictionary heading carries this root" unless link.hit?
        return "#{shown} of #{link.total} entries — raise limit (max #{DEFINE_MAX_LIMIT})" if shown < link.total

        "#{shown} #{shown == 1 ? 'entry' : 'entries'}"
      end

      # -- define internals ---------------------------------------------------------

      # The dictionary languages this catalog actually holds, live-derived at
      # serve time (P35-6 L4; the P11 hardcoded-list lesson): a newly synced
      # shelf language is advertised and accepted with zero code change. []
      # when the catalog (or its shelf table) is unavailable — the degrade
      # path: no enum is advertised and no lang is rejected, rather than
      # validating against a stale frozen list.
      # Split note: also read by #input_schema (tools.rb, tools/list); kept with its primary user.
      def define_langs
        catalog = resolve(@catalog)
        return [] unless catalog&.table_exists?(:dictionaries)

        # P106-3: the dictionary_stats census when derived (the desk-
        # commands law), the live distinct scan as the underived fallback.
        if catalog.table_exists?(:dictionary_stats) && !catalog[:dictionary_stats].empty?
          return catalog[:dictionary_stats].distinct.order(:language).select_map(:language)
        end

        catalog[:dictionaries].distinct.order(:language).select_map(:language)
      end

      def define_miss_note(lemma)
        # The slot resolves per call like every other reader here — the raw
        # @catalog may be a lazy opener Proc, and a miss once crashed on it.
        catalog = resolve(@catalog)
        langs = catalog[:dictionaries].distinct.order(:language).select_map(:language)
        "no dictionary entry for #{lemma.inspect} — the shelf holds " \
          "#{catalog[:dictionaries].count} dictionaries (#{langs.join(', ')}); " \
          "diacritics are optional; the lemma must be a dictionary form " \
          "(nabu_search with lemma: finds attestations)"
      end

      # +catalog+ (P24-1): when given, each served entry carries its owner
      # notes — the note lane on the dictionary surface, served by default.
      def render_define(results, lemma:, limit:, catalog: nil)
        if results.empty?
          return json(entries: [],
                      note: define_miss_note(lemma))
        end

        shown = results.first(limit)
        json(
          entries: shown.map do |result|
            payload = define_payload(result)
            catalog ? attach_notes(catalog, result, payload) : payload
          end,
          note: if results.size > limit
                  "more than #{limit} entries, showing #{limit} — raise limit (max #{DEFINE_MAX_LIMIT})"
                else
                  "#{shown.size} #{shown.size == 1 ? 'entry' : 'entries'}"
                end
        )
      end

      # Split note: also read by nabu_show and nabu_etym's fallback; kept with its primary user.
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
        base = base.merge(crossrefs: define_crossrefs(result)) unless result.crossrefs.empty?
        base = base.merge(reflex_fields(result.reflexes, cap: DEFINE_MAX_REFLEXES)) unless result.reflexes.empty?
        return base unless truncated

        base.merge(note: "entry body truncated at #{DEFINE_BODY_CAP} chars — " \
                         "`nabu define #{result.headword}` (CLI) renders it whole")
      end

      # P123-1: cross-references, resolved first (actionable), capped.
      def define_crossrefs(result)
        ordered = result.crossrefs.partition(&:resolved_urn).flatten(1)
        ordered.first(DEFINE_MAX_CROSSREFS).map do |crossref|
          { kind: crossref.kind, label: crossref.label, resolved_urn: crossref.resolved_urn }
        end
      end

      # Resolved citations first (they are the actionable ones), capped. A
      # print citation a configured reference work claims carries its scan
      # anchor (present-only key): status, the show-able urn (nil unless
      # the scan is held), leaf, and the CLI card's pointer wording.
      def define_citations(result)
        ordered = result.citations.partition(&:resolved_urn).flatten(1)
        ordered.first(DEFINE_MAX_CITATIONS).map do |citation|
          base = { label: citation.label, resolved_urn: citation.resolved_urn }
          citation.scan ? base.merge(scan: scan_payload(citation.scan)) : base
        end
      end

      def scan_payload(anchor)
        { status: anchor.status.to_s, work: anchor.work, volume: anchor.volume, page: anchor.page,
          column: anchor.column, line: anchor.line, leaf: anchor.leaf, item: anchor.item, urn: anchor.urn,
          pointer: anchor.pointer }
      end
    end
  end
end
