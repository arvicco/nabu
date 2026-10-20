# frozen_string_literal: true

# Nabu::CLI — library census commands: status, list. Carved out of
# lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    desc "status [SOURCE...]", "Show per-source sync status and passage counts (`nabu list` shows what is held)"
    long_desc <<~HELP, wrap: false
      The SYNC-STATE view. Bare `nabu status` is the COMPACT table (P40-s):
      one dense row per registered source, grouped by kind — a fused
      kind/enablement/cadence column, a SILENT liveness cell that speaks only
      to flag an exception (OLD/DOWN/?REPROBE/UNPROBED), one humanized
      holdings column, and the last run's stamp + zero-suppressed delta. Its
      sibling is `nabu list`, the WHAT-IS-HELD view (content census, per-shelf
      cards): status answers "should I sync?", list answers "what does the
      library hold?".

      `nabu status SOURCE` is one source's full labeled detail block: kind,
      enabled, cadence, the liveness verdict (healthy states included), exact
      thousands-separated counts, license class, the full timestamp/delta, and
      the last run's status. Several names render their blocks in argument
      order (P90-3); an unknown member reports after the known ones print,
      non-zero exit. `nabu status --long` is that extended detail as a
      labeled table for EVERY row.

      --remote probes every upstream first (the same code path as
      `health --remote`, persisting each verdict) and renders the fresh
      drift column — the one-command informed-update flow.
    HELP
    option :remote, type: :boolean, default: false,
                    desc: "Probe every upstream first (same as health --remote), persist, then show fresh drift"
    option :long, type: :boolean, default: false,
                  desc: "The full labeled detail (verbose liveness, exact counts, license, full delta) for every row"
    option :axis, type: :string, banner: "[NAME[,NAME…]]", lazy_default: "",
                  desc: "Group the status table under the research axes (config/axes.yml): bare = all in " \
                        "ratified order, NAME[,NAME…] = those axes only. A source appears under each axis it serves"
    option :all, type: :boolean, default: false,
                 desc: "Ignore the focus profile: show every row (modules + unfocused sources included)"
    option :disabled, type: :boolean, default: false,
                      desc: "The complement view: ONLY the rows nabu enable would add " \
                            "(shelves are always enabled and never appear)"
    def status(*slugs)
      refuse_all_with_disabled!("status")
      slugs = slugs.map { |name| name.to_s.strip }.reject(&:empty?)
      slug = slugs.size <= 1 ? slugs.first.to_s : nil
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # --remote (P14-12): the one-command informed-update flow — run the live
      # upstream probe inline (the SAME code path as `health --remote`, which
      # persists each verdict into the ledger cache), then render the up= column
      # from that fresh cache. Bare `status` is read-only and shows the cached
      # verdicts as-is (with their age).
      ledger = options[:remote] ? probe_upstreams(config, registry) : open_ledger(config)
      db = open_catalog(config)
      # `status SOURCE` is the detail block — UNSCOPED (explicit naming is
      # explicit intent; any source, focused or not). The bare/--long/--axis
      # tables scope to the focus profile (P40-f).
      view = focus_view(config, registry, catalog: db)
      # P90-3 (lane 2): several names render their detail blocks in
      # ARGUMENT order; an unknown member is reported after the known ones
      # print, and the batch exits non-zero naming the unknowns.
      unless slugs.size <= 1
        unknown = []
        slugs.each do |name|
          say status_report(registry, db, ledger, name)
          print_source_enable_hint(view, registry, name)
        rescue Thor::Error => e
          unknown << name
          warn e.message
        end
        return if unknown.empty?

        raise Thor::Error, "status: #{unknown.size} of #{slugs.size} unknown (#{unknown.join(', ')})"
      end
      if slug.empty?
        warn_focus_drift(view)
        # An EMPTY --disabled complement renders no table (the "No sources
        # registered." banner belongs to a truly empty registry, not to an
        # exhausted menu — the stderr footer carries the all-enabled state).
        say status_report(view.registry, db, ledger, slug) unless view.disabled && view.registry.slugs.empty?
        # `status --axis` is SCOPED (P44-r1 addendum): the grouped table, then an
        # enable hint for the axes' not-yet-enabled members — never the
        # whole-library `enabled:` footer. Bare status keeps that footer.
        if options[:axis]
          print_axis_enable_hint(view, registry, selected_axes(registry.axes, registry))
        else
          print_focus_note(view, view.registry_hidden_slugs)
        end
      else
        say status_report(registry, db, ledger, slug)
        print_source_enable_hint(view, registry, slug)
      end
    ensure
      db&.disconnect
      ledger&.disconnect
    end

    # `nabu list wired|unwired|enabled|disabled|locked|unlocked` (P97
    # rider, owner ask 2026-09-11): the three state axes as filters —
    # wired (registry: first sync verified) · enabled (this box's
    # profile) · locked (availability: blocked — grant-gated rows).
    # Registry + profile only, no catalog: a fresh box answers.
    LIST_STATE_WORDS = %w[wired unwired enabled disabled locked unlocked].freeze

    desc "list [SOURCE]", "What the library holds: the shelf census, or one source's card " \
                          "(`nabu status` shows sync state)"
    long_desc <<~HELP, wrap: false
      The WHAT-IS-HELD view — the contents sibling of `nabu status` (which
      answers "should I sync?"; list answers "what does the library hold?").

      Bare `nabu list` is the content census: one line per catalog source —
      live document/passage counts, dictionary entry counts, the languages
      held (codes when few, a count when many), the effective license-class
      mix (document overrides included), and withdrawn/retired counts when
      nonzero (zero fields are suppressed, the house rule).

      `nabu list SOURCE` is one shelf's card: identity (name, adapter,
      registry sync policy + enabled), the shelf's dossier description
      when the local-source shelf carries one (canonical/local-source,
      architecture §16 — seed the shelf once with
      --export-source-dossiers), license class(es) with the source's
      credit line when it carries one, counts, a per-language passage
      breakdown, its dictionaries (dictionary shelves), timeline coverage
      (dated docs + year range) when present, genre-facet and collection
      summaries when present. A card, not a dump — the enumerations below
      go deeper. `nabu list --long` adds each source's description line to
      the census.

      `nabu list --sources` is the one-page onboarding map: every source on
      one line (slug — the first sentence of its dossier description, ~100
      chars, honest ellipsis), grouped under family headers (Greek & Latin ·
      Biblical & Near Eastern · Slavic · Celtic · Indic & Iranian · Egyptian
      & Coptic · Germanic & Old English · Reference & dictionaries · Your
      shelves · Other). Groups are DERIVED from the census languages'
      family lanes (the language-dossier shelf); an optional owner-curated
      `group:` front-matter key in a source dossier overrides the
      derivation. Disabled sources stay visible with an (off) tag; a source
      without a dossier description shows the honest stub hint. Composes
      with nothing — it IS the whole-library view.

      `nabu list wired|unwired|enabled|disabled|locked|unlocked` filters
      the registry by one state axis and shows each row's full posture —
      wired (first sync verified) · enabled (this box's profile) · locked
      (grant-gated availability). Registry + profile only, no catalog
      needed: a fresh box answers.

      `nabu list --axis` groups the census under the research axes (the
      owner's desks, config/axes.yml): each axis leads with its persona
      line, then the same census rows, indented. Axes are TAGS, not folders
      — a source appears under every axis it serves (stated once). Bare
      --axis shows every axis in the ratified order; `--axis slavic` one
      axis; `--axis a,b` those axes only. The FUNCTIONAL SETS resolve here
      too (P77 rider — an axis is a tag, and the registry's non-desk sets
      are the same kind of tag): `--axis core` (the auto-enabled minimum of
      registry instruments), `--axis signs`, `--axis quickstart` (core +
      the starter shelf). An unknown name names the known axes and sets.
      The bare (ungrouped) census is unchanged.

      A bare `nabu list SOURCE --lang CODE` (no enumeration flag) IMPLIES the
      natural mode by the shelf's content kind — a dictionary shelf lists its
      entries in that language, a text shelf its documents — and a header
      announces the implication. Name --documents/--entries explicitly to
      override. (--lang still needs a SOURCE, and does not compose with the
      --collections/--loans census grains.)

      Enumerations (one per invocation, each honoring --limit, default 50,
      0 = all, with an honest "… N more" tail):
        --documents    every document: urn — title [lang] license, urn order,
                       withdrawn/retired flagged inline. Filters: --lang,
                       --license, --withdrawn (ONLY withdrawn/retired — the
                       stewardship lens), --from/--to/--century (the
                       timeline, as in search).
        --entries      a dictionary shelf's entries: headword [dict] — gloss.
                       Filters: --lang (dictionary language), --prefix STR
                       (folded headword prefix — bh finds *bʰer-, the define
                       contract). A passage shelf misses honestly, exit 0.
        --collections  collection → document count for shelves whose urns
                       carry a manifest collection segment (local-library);
                       an honest miss elsewhere, exit 0.
        --loans [CODE] the language-contact lens (P34-2, the stored P17-1
                       per-passage loan-token counts — no reparse). Bare:
                       the census, one row per loan-origin code (tokens/
                       passages/docs, token order). With CODE: the documents
                       carrying such loan tokens, most-saturated first,
                       honoring --limit. An honest miss on shelves without
                       the layer, exit 0.

      Examples:
        nabu list                                # the census, every shelf
        nabu list --sources                      # the one-page grouped map
        nabu list --axis                         # the census, grouped by desk
        nabu list --axis slavic                  # one desk's shelves
        nabu list ccmh                           # one shelf's card
        nabu list local-library --documents      # what did I ingest?
        nabu list local-library --collections    # …and how is it filed?
        nabu list lexica --entries --prefix log  # λόγος and its neighbors
        nabu list iecor --lang xcl               # entries implied (a dictionary shelf)
        nabu list papyri-ddbdp --documents --century 6 --limit 5
        nabu list shelf --documents --withdrawn  # the stewardship lens
        nabu list coptic-scriptorium --loans     # the loan-origin census
        nabu list coptic-scriptorium --loans grc --limit 10
                                                 # the most Greek-saturated books

      Use cases: enumerate a shelf without sqlite3 one-liners; a license
      audit before an export; eyeballing what an ingest actually filed.
    HELP
    option :documents, type: :boolean, default: false,
                       desc: "Enumerate the source's documents (urn order, withdrawn/retired flagged)"
    option :entries, type: :boolean, default: false,
                     desc: "Enumerate a dictionary source's entries (headword + gloss)"
    option :collections, type: :boolean, default: false,
                         desc: "Collection → document count for manifest-collection shelves"
    option :loans, type: :string, banner: "[CODE]", lazy_default: "",
                   desc: "The loan-origin census (bare), or the documents carrying CODE loan tokens, " \
                         "most-saturated first (P17-1 annotations — Coptic Scriptorium)"
    option :sources, type: :boolean, default: false,
                     desc: "The one-page grouped map: every source's description under family headers"
    option :limit, type: :numeric, default: Nabu::Query::List::DEFAULT_LIMIT,
                   desc: "Maximum rows per enumeration (default #{Nabu::Query::List::DEFAULT_LIMIT}; 0 = all)"
    option :prefix, type: :string, banner: "STR",
                    desc: "With --entries: folded headword prefix (bh finds *bʰer-)"
    option :lang, type: :string,
                  desc: "Restrict to one language; bare `list SOURCE --lang CODE` implies the natural " \
                        "mode (dictionary → entries, text → documents)"
    option :license, type: :string,
                     desc: "With --documents: restrict to an exact effective license class"
    option :withdrawn, type: :boolean, default: false,
                       desc: "With --documents: ONLY withdrawn/retired documents (the stewardship lens)"
    option :from, type: :numeric, banner: "YEAR",
                  desc: "With --documents: earliest date on the timeline (negative = BCE)"
    option :to, type: :numeric, banner: "YEAR", desc: "With --documents: latest date on the timeline"
    option :century, type: :numeric, banner: "N",
                     desc: "With --documents: one century's --from/--to shorthand (6, -2)"
    option :long, type: :boolean, default: false,
                  desc: "Census only: add each source's dossier description line (the local-source shelf)"
    option :axis, type: :string, banner: "[NAME[,NAME…]]", lazy_default: "",
                  desc: "Group the census under the research axes (config/axes.yml): bare = all in " \
                        "ratified order, NAME[,NAME…] = those axes only. A source appears under each " \
                        "axis it serves"
    option :"by-date", type: :boolean, default: false,
                       desc: "The chronological census: dated documents by century (earliest-bound " \
                             "buckets, per-century source breakdown) — the whole-library timeline view"
    option :"export-source-dossiers", type: :boolean, default: false,
                                      desc: "Owner one-shot: scaffold a canonical/local-source dossier for " \
                                            "EVERY registered source, descriptions seeded from existing " \
                                            "prose (idempotent; existing dossiers untouched)"
    option :"dry-run", type: :boolean, default: false,
                       desc: "With --export-source-dossiers: report without writing"
    option :all, type: :boolean, default: false,
                 desc: "Ignore the focus profile: census every source (--sources map is always whole-library)"
    option :disabled, type: :boolean, default: false,
                      desc: "The complement view: ONLY the rows nabu enable would add " \
                            "(shelves are always enabled and never appear)"
    option :"by-adopted", type: :boolean, default: false,
                          desc: "Census only: order by adoption date, newest first (the recentness " \
                                "view the pre-sort file order used to give; each row shows its date)"
    def list(slug = nil)
      refuse_all_with_disabled!("list")
      slug = slug.to_s.strip
      return list_by_state(slug) if LIST_STATE_WORDS.include?(slug)

      validate_list_flags!(slug)
      validate_license!(options[:license])
      from, to = date_window
      config = Nabu::Config.load
      return export_source_dossiers(config) if options[:"export-source-dossiers"]

      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      require_timeline!(catalog) if from || to
      # P105-5a: the lemma shelf's holdings live in fulltext — read-only,
      # optional (its cell degrades to zero without one).
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path, readonly: true) if File.exist?(config.fulltext_path)
      query = Nabu::Query::List.new(catalog: catalog, fulltext: fulltext)
      # Bare `list SOURCE --lang X` (P44-r1): with no explicit enumeration
      # flag, --lang IMPLIES the natural mode by the shelf's content kind —
      # a dictionary shelf lists entries, a text shelf documents — and the
      # header announces the implication so it stays legible.
      implied = implied_list_mode(query, slug)
      if options[:"by-date"]
        require_timeline!(catalog)
        print_census_by_date(query.by_date_census)
      elsif options[:axis]
        registry = Nabu::SourceRegistry.load(config.sources_path)
        view = focus_view(config, registry, catalog: catalog)
        warn_focus_drift(view)
        census = query.census
        rows = scoped_census(census, view)
        axes = selected_axes(registry.axes, registry)
        print_census_by_axis(rows, axes, registry)
        # A SCOPED request (P44-r1 addendum): no whole-library `enabled:`
        # footer — just an enable hint for THIS axis's not-yet-enabled members,
        # plus (P77-r5) a sync hint for the enabled ones the catalog has no
        # rows for yet: enabled-but-unsynced is a state, never an absence.
        print_axis_enable_hint(view, registry, axes, catalog_slugs: census.map(&:slug))
      elsif options[:sources]
        print_source_map(query.source_groups, Nabu::SourceRegistry.load(config.sources_path))
      elsif slug.empty?
        registry = Nabu::SourceRegistry.load(config.sources_path)
        view = focus_view(config, registry, catalog: catalog)
        warn_focus_drift(view)
        rows = scoped_census(query.census, view)
        if options[:"by-adopted"]
          # Adoption recency (the field the alphabetic reorder made
          # explicit) — newest first, the date leading each row.
          print_adopted_census(rows, registry)
        elsif view.disabled
          print_disabled_census(view, rows)
        else
          print_census(rows, options[:long] ? query.descriptions : nil)
        end
        # The hidden side here is CENSUS rows the view dropped (catalog-backed,
        # so orphan slugs the registry no longer carries still count).
        print_focus_note(view, query.census.map(&:slug) - rows.map(&:slug))
      elsif options[:documents] || implied == :documents
        say implied_mode_header(:documents, slug, options[:lang]) if implied
        print_list_documents(query.documents(slug, lang: options[:lang], license: options[:license],
                                                   withdrawn_only: options[:withdrawn], from: from, to: to,
                                                   limit: options[:limit].to_i, prefix: options[:prefix]))
      elsif options[:entries] || implied == :entries
        say implied_mode_header(:entries, slug, options[:lang]) if implied
        print_list_entries(slug, query.entries(slug, prefix: options[:prefix], lang: options[:lang],
                                                     limit: options[:limit].to_i))
      elsif options[:collections] then print_list_collections(slug, query.collections(slug))
      elsif options[:loans]
        code = options[:loans].strip
        if code.empty? then print_list_loans_census(slug, query.loans_census(slug))
        else
          print_list_loan_documents(code, query.loan_documents(slug, code: code, limit: options[:limit].to_i))
        end
      else
        registry = Nabu::SourceRegistry.load(config.sources_path)
        view = focus_view(config, registry, catalog: catalog)
        print_list_card(query.card(slug), registry[slug], enabled: card_enablement(view, registry[slug], slug))
        # A named SOURCE is a scoped request too: hint the enable on-ramp only
        # when that source is not yet enabled (silence otherwise).
        print_source_enable_hint(view, registry, slug)
      end
    rescue Nabu::Query::List::Error => e
      # Unknown source slug: a clean stderr line naming the valid slugs —
      # unless the registry KNOWS the slug (P77-r5): registered-but-unsynced
      # is not "unknown", it teaches its own on-ramp instead.
      raise Thor::Error, registered_not_held_message(config, catalog, slug) || e.message
    ensure
      fulltext&.disconnect
      catalog&.disconnect
    end

    # Sources named per century row by `nabu list --by-date` before the
    # "+N more" tail (P81-1; the same house render-cap rule).
    BY_DATE_SOURCES = 4

    no_commands do
      # -- list (P22-1) renderers -------------------------------------------

      # The flag grammar: one enumeration mode per invocation, each filter
      # only where it means something — a wrong combination is a named
      # error, never a silently ignored flag.
      def validate_list_flags!(slug)
        modes = %i[documents entries collections].select { |flag| options[flag] }
        modes << :loans if options[:loans]
        if options[:sources] && (!slug.empty? || modes.any? || options.values_at(
          "long", "export-source-dossiers", "dry-run", "prefix", "lang", "license",
          "withdrawn", "from", "to", "century"
        ).any?)
          raise Thor::Error, "list: --sources is the one-page grouped map — it composes with nothing"
        end
        # --axis groups the bare census under the research desks; it is a
        # census view, not an enumeration — like --sources, it composes with
        # nothing (a SOURCE, an enumeration, --long, --sources are all a
        # different question).
        if options[:axis] && (!slug.empty? || modes.any? || options[:sources] ||
                              options.values_at("long", "export-source-dossiers", "dry-run").any?)
          raise Thor::Error, "list: --axis groups the census under the research axes — " \
                             "drop the SOURCE/enumeration flags"
        end
        # --by-date is a census view like --sources/--axis: it composes
        # with nothing (a SOURCE's own timeline lives on its card; date
        # FILTERS belong to --documents' --from/--to/--century).
        if options[:"by-date"] && (!slug.empty? || modes.any? || options[:sources] || options[:axis] ||
                                   options.values_at("long", "export-source-dossiers", "dry-run",
                                                     "from", "to", "century").any?)
          raise Thor::Error, "list: --by-date is the whole-library chronological census — " \
                             "it composes with nothing (per-source dating sits on `list SOURCE`)"
        end
        if modes.size > 1
          raise Thor::Error, "list: give one of --documents, --entries, --collections, --loans per invocation"
        end
        raise Thor::Error, "list: give a SOURCE with --#{modes.first}" if slug.empty? && modes.any?
        if options[:"export-source-dossiers"] && (!slug.empty? || modes.any?)
          raise Thor::Error, "list: --export-source-dossiers scaffolds ALL registered sources — " \
                             "no SOURCE, no enumeration"
        end
        if options[:"dry-run"] && !options[:"export-source-dossiers"]
          raise Thor::Error, "list: --dry-run composes with --export-source-dossiers"
        end
        if options[:long] && (!slug.empty? || modes.any?)
          raise Thor::Error, "list: --long expands the bare census — drop the SOURCE/enumeration flags"
        end
        if options[:prefix] && !options[:entries] && !options[:documents]
          raise Thor::Error, "list: --prefix filters headwords/dossier codes — use it with --entries " \
                             "or --documents"
        end

        doc_only = %i[license withdrawn from to century].select { |flag| options[flag] }
        unless doc_only.empty? || options[:documents]
          raise Thor::Error, "list: --#{doc_only.first} composes with --documents"
        end
        return if options[:lang].nil? || options[:documents] || options[:entries]

        # Bare `list SOURCE --lang X` no longer refuses — it IMPLIES the
        # natural enumeration (dictionary → entries, text → documents;
        # dispatched below). --lang stays refused only where it cannot imply
        # a mode: with no SOURCE (the census spans the whole library), or on
        # a census grain that does not filter by language (--collections /
        # --loans have their own axes). Each refusal names what DOES work.
        if slug.empty?
          raise Thor::Error, "list: --lang needs a SOURCE (nabu list SOURCE --lang CODE) — " \
                             "the bare census spans the whole library"
        end
        return unless options[:collections] || options[:loans]

        grain = options[:collections] ? "collections" : "loans"
        raise Thor::Error, "list: --lang filters a shelf's documents or dictionary entries " \
                           "(bare `nabu list SOURCE --lang CODE`, or --documents/--entries) — not --#{grain}"
      end

      # Bare `list SOURCE --lang X` (P44-r1): with no explicit enumeration
      # flag and a --lang present, the natural mode is IMPLIED by the shelf's
      # content kind. Returns :documents / :entries, or nil when no
      # implication applies (no SOURCE, no --lang, or an explicit mode/census
      # grain already chosen — validate_list_flags! has already refused the
      # meaningless combinations). Reads the catalog fact via the query
      # object, so an unknown slug surfaces as the usual naming error.
      def implied_list_mode(query, slug)
        return nil if slug.empty? || options[:lang].nil?
        return nil if options[:documents] || options[:entries] ||
                      options[:collections] || options[:loans]

        query.natural_mode(slug)
      end

      # The legible header for an implied enumeration: names the mode, the
      # filter that implied it, and the content-kind reason.
      def implied_mode_header(mode, slug, lang)
        reason = mode == :entries ? "a dictionary shelf" : "a text shelf"
        "#{mode} (implied by --lang #{lang}) — #{slug} is #{reason}"
      end

      # +descriptions+ (P24-0, --long): { slug => dossier description } — one
      # line under each source that has one (zero fields suppressed, the
      # house rule; the dossier shelf is the census's own metadata).
      # The --disabled census (P46-r3 follow-up, owner report: `list
      # --disabled` printed the empty-catalog banner while `status
      # --disabled` showed the row): the menu is REGISTRY-driven — a
      # never-synced complement row is the norm there, not an absence.
      # Census fragments where the catalog holds the slug; an honest
      # per-row "nothing held yet" where it does not. An empty complement
      # prints no table (the stderr footer carries the all-enabled state).
      # The by-adopted census — newest adoptions first, dated rows.
      def print_adopted_census(rows, registry)
        dated = rows.map { |row| [registry[row.slug]&.adopted || "0000-00-00", row] }
                    .sort_by { |date, row| [date, row.slug] }.reverse
        width = rows.map { |r| r.slug.length }.max || 0
        dated.each do |date, row|
          say "#{date}  #{row.slug.ljust(width)}  #{census_fragments(row).join('  ')}"
        end
      end

      def print_disabled_census(view, census_rows)
        slugs = view.registry.slugs
        return if slugs.empty?

        by_slug = census_rows.to_h { |row| [row.slug, row] }
        width = slugs.map(&:length).max
        slugs.each do |slug|
          row = by_slug[slug]
          say "#{slug.ljust(width)}  #{row ? census_fragments(row).join('  ') : 'nothing held yet'}"
        end
      end

      def print_census(rows, descriptions = nil)
        return say("nothing held yet — run nabu sync") if rows.empty?

        width = rows.map { |row| row.slug.length }.max
        rows.each do |row|
          say "#{row.slug.ljust(width)}  #{census_fragments(row).join('  ')}"
          description = descriptions && descriptions[row.slug]
          say "#{' ' * (width + 2)}#{truncate_line(description)}" if description
        end
        say census_summary(rows)
      end

      # Resolve the --axis value to the ordered Axis list to render (P35-1).
      # Bare (empty) --axis = every axis in the ratified file order; a
      # comma-list = those axes, in the order asked (deduped, first wins). An
      # unknown name is a clean error naming the known set — the resolution
      # guarantee (an axis name can never collide with a slug, so this is
      # unambiguous). No axes defined at all is its own honest miss.
      # Route `nabu status` (P40-s): a SOURCE argument renders that one row's
      # full labeled detail block; --axis groups the compact rows under the
      # research desks; --long is the extended detail table; bare is the compact
      # v2 table. An unknown SOURCE names the valid slugs, like `list SOURCE`.
      def status_report(registry, db, ledger, slug)
        unless slug.empty?
          detail = Nabu::StatusReport.render_source(registry: registry, db: db, ledger: ledger, slug: slug,
                                                    canonical_dir: status_canonical_dir)
          return detail if detail

          raise Thor::Error, "unknown source #{slug.inspect} — known sources: #{registry.slugs.join(', ')}"
        end
        if options[:axis]
          return Nabu::StatusReport.render_grouped(registry: registry, db: db, ledger: ledger,
                                                   axes: selected_axes(registry.axes, registry),
                                                   tag_note: AXIS_TAG_NOTE)
        end

        Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger, long: options[:long],
                                  canonical_dir: status_canonical_dir)
      end

      # Where module rows' seam censuses are read from (status detail/long).
      def status_canonical_dir
        Nabu::Config.load.canonical_dir
      end

      def list_by_state(state)
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        profile = Nabu::Profile.exist?(config.profile_path) ? Nabu::Profile.load(config.profile_path) : nil
        enabled = enabled_slugs(profile, registry)
        rows = registry.each_source.select do |entry|
          case state
          when "wired" then entry.wired
          when "unwired" then !entry.wired
          when "enabled" then enabled.include?(entry.slug)
          when "disabled" then !enabled.include?(entry.slug)
          when "locked" then entry.blocked?
          when "unlocked" then !entry.blocked?
          end
        end
        say "#{state} sources (#{rows.size} of #{registry.slugs.size} registered):"
        rows.sort_by(&:slug).each { |entry| say "  #{entry.slug}  #{state_chips(entry, enabled)}" }
        say "  (none)" if rows.empty?
        say "  enable with `nabu enable <axis|source>`" if state == "disabled" && rows.any?
      end

      # The OTHER two axes as compact chips, so any state view shows the
      # full posture of each row.
      def state_chips(entry, enabled)
        chips = []
        chips << (entry.wired ? "wired" : "unwired")
        chips << (enabled.include?(entry.slug) ? "enabled" : "disabled")
        chips << "locked (grant-gated)" if entry.blocked?
        chips << entry.kind if entry.kind != "source"
        chips.join(" · ")
      end

      # --all is everything, --disabled the not-yet-enabled complement —
      # together they name contradictory row sets (P46-r3).
      def refuse_all_with_disabled!(command)
        return unless options[:all] && options[:disabled]

        raise Thor::Error, "#{command}: --all and --disabled are exclusive — " \
                           "--all shows every row, --disabled only the rows nabu enable would add"
      end

      # Drop the census rows the view hides (a shelf/enabled source stays, a
      # non-enabled source goes). Under --all the view is the pass-through and
      # every row stays.
      def scoped_census(rows, view)
        view.active? ? rows.select { |row| view.visible?(row.slug) } : rows
      end

      # The SCOPED enablement hint (P44-r1 addendum). A --axis or named-source
      # request never prints the whole-library `enabled:` list (that is the
      # unscoped view's job) — showing every enabled source under a request for
      # ONE desk is noise. Instead, IFF the requested scope has members not yet
      # enabled, one compact line names just those + the enable on-ramp; when
      # everything requested is already enabled, silence (the zero-signal house
      # rule). Blocked (grant-gated private) members are named INDIVIDUALLY with
      # their grant marker — never folded into `enable <axis>`, which skips them
      # (the r3b rule). Meta line → STDERR, like every enablement note.
      def print_axis_enable_hint(view, registry, axes, catalog_slugs: nil)
        requested = axes.flat_map do |axis|
          next registry.functional_set_members(axis.name) if registry.functional_set?(axis.name)

          registry.axis_members(axis.name)
        end.uniq
        print_scoped_enable_hint(view, registry, requested, enable_axes: axes.map(&:name),
                                                            catalog_slugs: catalog_slugs)
      end

      def print_source_enable_hint(view, registry, slug)
        print_scoped_enable_hint(view, registry, [slug], enable_axes: [])
      end

      def print_scoped_enable_hint(view, registry, requested_slugs, enable_axes:, catalog_slugs: nil)
        return unless view.active? # --all is the full reveal — silent

        enabled = view.resolution.slugs
        gap = requested_slugs.uniq.reject do |slug|
          entry = registry[slug]
          # A shelf always shows and a module only under --all — neither is an
          # `enable` target, so neither counts as an un-enabled gap.
          entry.nil? || entry.shelf? || entry.feature_module? || enabled.include?(slug)
        end
        print_unsynced_hint(registry, requested_slugs, enabled, catalog_slugs)
        return if gap.empty?

        blocked_gap, public_gap = gap.partition { |slug| registry.blocked?(slug) }
        clauses = []
        unless public_gap.empty?
          axes = enable_axes.select { |name| registry.public_axis_members(name).intersect?(public_gap) }
          clauses << if axes.empty?
                       "nabu enable #{public_gap.join(' ')}"
                     else
                       "nabu enable #{axes.join(' ')} (#{public_gap.join(', ')})"
                     end
        end
        blocked_gap.each { |slug| clauses << "#{slug} · grant required (nabu enable #{slug})" }

        count = gap.size
        warn "#{count} member#{'s' unless count == 1} not enabled — #{clauses.join('; ')}"
      end

      # P77-r5 (the osta eyeball): an ENABLED member with no catalog rows yet
      # (post-enable, pre-first-sync) is neither a census row nor an enable
      # gap — without this line it silently vanishes from the scoped view.
      # Shelves are excluded (`nabu ingest`, not sync, fills them); modules
      # stay (they are honest sync targets). Only list passes catalog_slugs —
      # status renders never-synced rows itself, so it opts out with nil.
      def print_unsynced_hint(registry, requested_slugs, enabled, catalog_slugs)
        return if catalog_slugs.nil?

        unsynced = requested_slugs.uniq.select do |slug|
          entry = registry[slug]
          entry && !entry.shelf? && enabled.include?(slug) && !catalog_slugs.include?(slug)
        end
        return if unsynced.empty?

        count = unsynced.size
        warn "#{count} member#{'s' unless count == 1} enabled, not yet synced — " \
             "#{unsynced.map { |slug| "nabu sync #{slug}" }.join('; ')}"
      end

      # P77-r5, the other half of the same eyeball: `list <slug>` on a source
      # the REGISTRY knows but the catalog does not must not claim "unknown
      # source" — the slug is registered and simply has no rows yet. Returns
      # the teaching message, or nil when the catalog-holds error is the
      # honest one (a truly unknown slug, or a different failure).
      def registered_not_held_message(config, catalog, slug)
        return nil if slug.nil? || slug.empty? || catalog.nil?
        return nil if catalog[:sources].where(slug: slug).any?

        registry = Nabu::SourceRegistry.load(config.sources_path)
        entry = registry[slug]
        return nil unless entry
        return "#{slug} is a registered shelf with nothing on it yet — nabu ingest fills it" if entry.shelf?

        # Enablement read with all:false — the --all flag reveals rows, it
        # does not enable anything, so it must not flip this wording.
        view = Nabu::Focus.view(profile: effective_profile(config, registry, catalog: catalog),
                                registry: registry, all: false, disabled: false)
        if view.resolution.slugs.include?(slug)
          "#{slug} is registered and enabled but not yet synced — run nabu sync #{slug}"
        else
          "#{slug} is registered but not enabled — run nabu enable #{slug}, then nabu sync #{slug}"
        end
      end

      def selected_axes(axis_registry, registry)
        if axis_registry.empty?
          raise Thor::Error, "list: no research axes are defined (config/axes.yml) — --axis needs the registry"
        end

        spec = options[:axis].to_s.strip
        return axis_registry.each_axis.to_a if spec.empty?

        spec.split(",").map(&:strip).reject(&:empty?).uniq.map do |name|
          axis_registry[name] || functional_set_axis(registry, name) ||
            raise(Thor::Error, "list: unknown axis #{name.inspect} — known axes: " \
                               "#{axis_registry.names.join(', ')} · functional sets: " \
                               "#{Nabu::SourceRegistry::FUNCTIONAL_SETS.join(', ')}")
        end
      end

      # A functional set rendered as a pseudo-axis (P77 rider): same Axis
      # duck the grouped census walks, persona = what the set IS. Desk
      # order stays ratified; sets sort after (order 900+).
      def functional_set_persona(name)
        { "core" => "The auto-enabled minimum — the registry instruments every install carries",
          "signs" => "The sign/char capability restore set",
          "quickstart" => "The starter shelf — core plus the smallest real sources" }.fetch(name)
      end

      def functional_set_axis(registry, name)
        return nil unless registry.functional_set?(name)

        persona = functional_set_persona(name)
        Nabu::AxisRegistry::Axis.new(
          name: name, persona: persona, desc: persona,
          order: 900 + Nabu::SourceRegistry::FUNCTIONAL_SETS.index(name)
        )
      end

      # `list --axis` (P35-1): the census grouped under the research axes
      # (the owner's desks, config/axes.yml). The tag-semantics note is
      # stated once up front; each axis leads with its VERBATIM persona line
      # (P35-0 first-class render data) and then the SAME census rows the
      # flat view prints, indented — a source under every axis it serves
      # (dual-tagging, D35). An axis with nothing held yet says so honestly.
      # Slug width is global so alignment is stable across groups.
      def print_census_by_axis(rows, axes, registry)
        return say("nothing held yet — run nabu sync") if rows.empty?

        width = rows.map { |row| row.slug.length }.max
        say AXIS_TAG_NOTE
        shown = {}
        axes.each do |axis|
          say ""
          say "#{axis.name} — #{axis.persona}"
          members = rows.select { |row| registry.axis_or_set_member?(axis.name, row.slug) }
          if members.empty?
            say "  (nothing held on this axis yet)"
          else
            members.each do |row|
              say "  #{row.slug.ljust(width)}  #{census_fragments(row).join('  ')}"
              shown[row.slug] = row
            end
          end
        end
        say ""
        # The summary is the DEDUPED UNION of the sources actually shown
        # under the selected axes/sets (P77-r2, owner report 2026-08-13) —
        # never the whole-library aggregate a scoped view didn't display.
        # A source on two selected desks counts once (tags, not folders).
        say census_summary(shown.values)
      end

      # The chronological census (`list --by-date`, P81-1/C-6): one line
      # per century, count + the top sources; the bucketing doctrine
      # (earliest bound, spans announced) stated in the header, never
      # hidden. Source tails cap at BY_DATE_SOURCES with an honest count.
      def print_census_by_date(census)
        return say("no dated documents yet — run nabu sync or nabu rebuild") if census.buckets.empty?

        say "chronological census — dated documents by century (bucketed by earliest bound; " \
            "#{commas(census.multi_century)} span multiple centuries)"
        width = census.buckets.map { |bucket| bucket.label.length }.max
        census.buckets.each do |bucket|
          say "  #{bucket.label.ljust(width)}  #{commas(bucket.documents).rjust(9)}  " \
              "#{by_date_sources(bucket.sources)}"
        end
        share = census.total_documents.positive? ? (census.dated_documents * 100) / census.total_documents : 0
        say "dated #{commas(census.dated_documents)} of #{commas(census.total_documents)} " \
            "live documents (#{share}%)"
      end

      def by_date_sources(sources)
        shown = sources.first(BY_DATE_SOURCES).map { |slug, count| "#{slug} #{commas(count)}" }
        tail = sources.size - BY_DATE_SOURCES
        (shown + (tail.positive? ? ["+#{tail} more"] : [])).join(" · ")
      end

      # Compact census fragments, zero fields suppressed (conventions §10).
      def census_fragments(row)
        parts = []
        parts << "docs=#{row.docs}#{" pass=#{row.passages}" if row.passages.positive?}" if row.docs.positive?
        parts << dictionary_fragment(row.dictionaries, row.entries) if row.entries.positive?
        parts << "dossiers=#{row.dossiers}" if row.dossiers.positive?
        # P105-5a: the notes and lemma shelves census their own grains.
        parts << "notes=#{row.notes}" if row.notes.positive?
        parts << "lemma-rows=#{row.lemma_rows}" if row.lemma_rows.positive?
        # A kind: module holds no catalog rows BY INVARIANT — "empty" would
        # be the document-grain lie; it renders its seam census or its pin.
        parts << (list_module_summary(row.slug, row.pin) || "empty") if parts.empty?
        parts << "langs=#{census_langs(row.languages)}" unless row.languages.empty?
        parts << "license=#{row.license_classes.join(',')}"
        parts << "withdrawn=#{row.withdrawn}" if row.withdrawn.positive?
        parts << "retired=#{row.retired}" if row.retired.positive?
        parts
      end

      # The dicts/entries pair (docs/pass's twin): the dictionary count rides
      # beside the entries when the catalog knows it.
      def dictionary_fragment(dictionaries, entries)
        dictionaries.positive? ? "dicts=#{dictionaries} entries=#{entries}" : "entries=#{entries}"
      end

      # A kind: module row's one-cell descriptor for the list surfaces: its
      # seam census read from canonical/<slug> (Nabu::ModuleCensus), else the
      # pin the catalog holds it at. nil for every non-module slug, so their
      # rows never change. The registry/config load once per command.
      def list_module_summary(slug, pin)
        entry = list_module_registry&.[](slug)
        return nil unless entry&.feature_module?

        Nabu::ModuleCensus.descriptor(entry.adapter_class, slug: slug,
                                                           canonical_dir: Nabu::Config.load.canonical_dir, pin: pin)
      rescue Nabu::Error
        nil
      end

      def list_module_registry
        return @list_module_registry if defined?(@list_module_registry)

        @list_module_registry = begin
          Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
        rescue Nabu::Error
          nil
        end
      end

      # The codes when few, the count when the list would swamp the row.
      def census_langs(codes)
        codes.size <= 3 ? codes.join(",") : codes.size.to_s
      end

      def census_summary(rows)
        parts = [pluralize(rows.size, "source"), "#{rows.sum(&:docs)} docs", "#{rows.sum(&:passages)} passages"]
        entries = rows.sum(&:entries)
        parts << "#{entries} entries" if entries.positive?
        parts.join(" · ")
      end

      # P28-4: the one-page grouped map (`list --sources`) — family headers,
      # `slug — first sentence` lines (the dossier description, ~100 chars,
      # honest ellipsis), (off) tags from the REGISTRY (P23-3b: registry
      # authoritative for enablement; catalog value only for orphans), one
      # footer pointing deeper. Descriptions are the payload — no counts.
      def print_source_map(groups, registry)
        return say("nothing held yet — run nabu sync") if groups.empty?

        groups.each_with_index do |(group, lines), index|
          say "" if index.positive?
          say group
          lines.each { |line| say "  #{source_map_line(line, registry)}" }
        end
        say ""
        say "nabu list SLUG for the full card · docs/library.md for the survey"
      end

      def source_map_line(line, registry)
        entry = registry[line.slug]
        wired = entry ? entry.wired : line.enabled
        off = wired ? "" : " (unwired)"
        return "#{line.slug}#{off} — no description; nabu ingest --shelf source #{line.slug}" unless line.description

        "#{line.slug}#{off} — #{truncate_line(first_sentence(line.description))}"
      end

      # The first sentence of a dossier description: up to the first
      # terminal punctuation followed by whitespace; the whole prose when
      # it is a single sentence.
      def first_sentence(text)
        prose = text.tr("\n", " ").squeeze(" ").strip
        prose[/\A.*?[.!?](?=\s)/] || prose
      end

      def print_list_card(card, entry, enabled: nil)
        say "#{card.slug} — #{card.name}"
        wrap_text(card.description).each { |line| say "  #{line}" } if card.description
        say "  adapter #{card.adapter_class}#{registry_fragment(entry)}#{enablement_fragment(enabled, card.slug)}"
        credit = card.license_text.to_s.strip
        say "  license #{card.license_classes.join(',')}#{" · #{truncate_line(credit)}" unless credit.empty?}"
        say "  #{card_counts(card)}"
        say "  langs #{card.languages.map { |code, n| "#{code}=#{n}" }.join(' ')}" unless card.languages.empty?
        say "  records #{card.record_kinds.map { |kind, n| "#{kind}=#{n}" }.join(' ')}" \
          unless card.record_kinds.empty?
        card.dictionaries.each do |dict|
          say "  dict #{dict.slug} — #{dict.title} [#{dict.language}] entries=#{dict.entries}"
        end
        print_card_axes(card)
      end

      # P78-r7 (owner: "why doesn't it indicate if the source is enabled?"):
      # the card STATES the box-enablement fact instead of implying it by the
      # hint's silence — enablement gates whether `sync` will even run, so a
      # dossier card without it is incomplete. nil = not an enable target
      # (shelf/module/unregistered).
      def card_enablement(view, entry, slug)
        return nil if entry.nil? || entry.shelf? || entry.feature_module?

        view.resolution.slugs.include?(slug)
      end

      def enablement_fragment(enabled, slug)
        case enabled
        when true then " · enabled"
        when false then " · NOT ENABLED on this box (nabu enable #{slug})"
        else ""
        end
      end

      # Registry facts on the header line; a catalog source missing from the
      # registry is abnormal and reads loudly. Kind-aware (P39-0): a shelf reads
      # local memory, a module reads machinery — neither has a cadence or an
      # enablement to show.
      def registry_fragment(entry)
        return " · NOT IN REGISTRY" if entry.nil?
        return " · shelf · local memory" if entry.shelf?
        return " · module · machinery (no catalog rows)" if entry.feature_module?

        " · source · sync #{entry.sync_policy} · #{entry.wired ? 'wired' : 'unwired'}"
      end

      def card_counts(card)
        parts = []
        parts << "docs=#{card.docs}" if card.docs.positive?
        parts << "pass=#{card.passages}" if card.passages.positive?
        parts << dictionary_fragment(card.dictionaries.size, card.entries) if card.entries.positive?
        parts << "dossiers=#{card.dossiers}" if card.dossiers.positive?
        parts << "withdrawn=#{card.withdrawn}" if card.withdrawn.positive?
        parts << "retired=#{card.retired}" if card.retired.positive?
        return parts.join(" ") unless parts.empty?

        list_module_summary(card.slug, card.pin) || "empty"
      end

      # The optional card layers: timeline coverage, facet summary, and the
      # collections census (inlined when small, deferred to --collections
      # when it would swamp the card).
      def print_card_axes(card)
        if card.dated
          say "  dated #{pluralize(card.dated.docs, 'doc')} #{card.dated.min || 'open'}..#{card.dated.max || 'open'}"
        end
        unless card.facets.empty?
          say "  facets #{card.facets.map { |f| "#{f.facet}=#{f.values} values/#{f.docs} docs" }.join(' · ')}"
        end
        return if card.collections.nil?

        if card.collections.size <= 8
          say "  collections #{format_collections(card.collections).join(' ')}"
        else
          say "  collections #{card.collections.size} (see --collections)"
        end
      end

      def format_collections(counts)
        counts.sort_by { |name, count| [-count, name] }.map { |name, count| "#{name}=#{count}" }
      end

      def print_list_documents(page)
        return say("no documents match") if page.rows.empty?

        page.rows.each do |row|
          if row.is_a?(Nabu::Query::List::DossierRow)
            say "#{row.code}#{" — #{row.name}" if row.name}#{" [#{row.family}]" if row.family}"
          else
            flags = "#{' (withdrawn)' if row.withdrawn}#{' (retired upstream)' if row.retired}"
            say "#{row.urn} — #{row.title}#{" [#{row.language}]" if row.language} #{row.license_class}#{flags}"
          end
        end
        print_list_tail(page)
      end

      def print_list_entries(slug, page)
        return say("#{slug} holds no dictionary entries (a passage shelf) — try --documents") if page.nil?
        return say("no entries match") if page.rows.empty?

        page.rows.each do |row|
          gloss = row.gloss.to_s.gsub(/\s+/, " ").strip
          say "#{row.headword} [#{row.dictionary_slug}]#{" — #{truncate_line(gloss)}" unless gloss.empty?}"
        end
        print_list_tail(page)
      end

      # The loans census (P34-2): one row per loan-origin code, token-count
      # order — read straight off the stored P17-1 annotations, no reparse.
      def print_list_loans_census(slug, rows)
        if rows.empty?
          return say("no loan annotations in #{slug} passages (the language-of-origin layer — " \
                     "Coptic Scriptorium parses carry it)")
        end

        width = rows.map { |row| row.code.length }.max
        rows.each do |row|
          say "#{row.code.ljust(width)}  tokens=#{row.tokens}  passages=#{row.passages}  docs=#{row.docs}"
        end
      end

      # `list SOURCE --loans CODE`: the saturation enumeration, most
      # loan-token-heavy documents first.
      def print_list_loan_documents(code, page)
        return say("no documents carry #{code} loan tokens") if page.rows.empty?

        page.rows.each do |row|
          say "#{row.urn} — #{row.title}#{" [#{row.language}]" if row.language} " \
              "tokens=#{row.tokens} passages=#{row.passages}"
        end
        print_list_tail(page)
      end

      def print_list_collections(slug, counts)
        if counts.nil?
          return say("no collection segments in #{slug} document urns " \
                     "(manifest-collection shelves — local-library — carry them)")
        end

        width = counts.keys.map(&:length).max
        format_collections(counts).each do |pair|
          name, count = pair.split("=", 2)
          say "#{name.ljust(width)}  docs=#{count}"
        end
      end

      # The honest truncation tail every list enumeration shares.
      def print_list_tail(page)
        more = page.total - page.rows.size
        say "… #{more} more — raise --limit (0 = all)" if more.positive?
      end

      # House-width prose wrap for the card's description lane (P24-0) —
      # whole words, no truncation: the card serves the dossier's 1–3
      # sentences in full.
      def wrap_text(text, width: 76)
        text.split(/\s+/).each_with_object([]) do |word, lines|
          if lines.empty? || lines.last.length + word.length + 1 > width
            lines << word.dup
          else
            lines.last << " " << word
          end
        end
      end

      # THE SEED (P24-0, owner-fired): a canonical/local-source dossier for
      # every registered source, descriptions from the best existing prose
      # (docs/library.md sections/bullets, sources.yml standalone comments)
      # — honest stubs where none exists, never invented. Idempotent at the
      # file grain: existing dossiers are untouched, so it is safe to
      # re-run after registering new sources. After it: bin/nabu sync
      # local-source derives the catalog records the card/census read.
      def export_source_dossiers(config)
        registry = Nabu::SourceRegistry.load(config.sources_path)
        dir = Nabu::SourceShelf.dir(config)
        report = Nabu::SourceDossierExport.new(
          registry: registry, dir: dir,
          library_md: File.expand_path("../../docs/library.md", __dir__),
          sources_yml: config.sources_path
        ).run!(dry_run: options[:"dry-run"])
        verb = options[:"dry-run"] ? "would scaffold" : "scaffolded"
        say "dossiers: #{verb} #{report.written}, #{report.unchanged} existing untouched → #{dir}"
        if report.stubs.positive?
          say "  #{report.stubs} honest stub(s) — no existing prose found, write the description: " \
              "#{report.stub_slugs.join(', ')}"
        end
        say "next: bin/nabu sync local-source (derives the catalog records)" unless options[:"dry-run"]
      end

      # `status --remote` (P14-12): run the live upstream probe through the SAME
      # RemoteProbe as `health --remote`, whose run persists each verdict into
      # the ledger's source_probes cache, then hand the (write-opened, migrated)
      # ledger back so status renders the just-refreshed up= column. Returns the
      # ledger handle; the caller owns disconnecting it. The probe's exit-code
      # gate is health's concern, not status's — status just reports.
      def probe_upstreams(config, registry)
        ledger = open_or_create_ledger(config)
        Nabu::Health::RemoteProbe.new(
          registry: registry, ledger: ledger, canonical_dir: config.canonical_dir
        ).run
        ledger
      end
    end
  end
end
