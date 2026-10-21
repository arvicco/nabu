# frozen_string_literal: true

# Nabu::CLI — reference desks: language, kind, person, place, axis. Carved out
# of lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    CURVE_BAR_WIDTH = 30

    desc "language [CODE]", "The language-code desk reference: name, family, context, holdings"
    long_desc <<~HELP, wrap: false
      Explains any language code the library surfaces — the corpus tags
      (chu, orv, san-Latn) and the Wiktionary etymology codes the etym
      cognate lists are full of (gkm, zle-ort, zlw-opl…). The card merges
      three layers:

      - NAME, derived from the held kaikki extracts: every descendants node
        carries the human name next to its code, censused into the catalog
        with the dictionary shelves (a catalog predating that census shows
        names only for curated codes until the next rebuild or parse-only
        shelf resync).
      - CONTEXT, curated in the canonical/local-language dossier shelf
        (P19-1: one Markdown file per code — edit it in any editor, then
        `nabu sync local-language` re-derives): period, family, what the
        library holds — every held language, plus family-level entries for
        the etymology tail (zle-* East Slavic stages, gkm Medieval Greek…).
        A code without its own dossier falls back to its family; without
        either it says so honestly. (Libraries that predate the dossier
        migration keep reading the ledger's language notes unchanged.)
      - RELEVANCE, live from the db: documents/passages, gold-lemma rows,
        dictionary shelves, reconstruction-crosswalk edges, and the related
        research axes (the desks whose member sources hold the code, in
        ratified order — nabu axis NAME for any desk card). Zero fields
        are suppressed.

      --long adds where-it-appears detail: per-source document counts and
      the upstream-code split of the etymology edges (chu's edges arrive
      as Wiktionary's "cu"). --list shows the held languages only — the
      ~800-code etymology tail is what `language CODE` is for.
      --curve draws the code's documents + passages per century (each
      document at its date-envelope midpoint; undated last). --mixing (no
      CODE) is the multilingualism census: documents by how many passage
      languages they hold, the commonest mixed inventories, and per source
      how the mixing runs — "block" (each language one contiguous run) or
      "interleaved" (switching back and forth). Both read the precompiled
      rollups only.
      --export-dossiers is THE one-shot canonical-memory migration
      (owner-fired): it writes the ledger's language notes out as dossier
      files, absence-filling only, idempotent; --dry-run previews it.

      Examples:
        nabu language zle-ort      # the code from an etym cognate list
        nabu language chu --long   # a held language, full holdings
        nabu language --list       # every held language
        nabu lang lat --curve      # Latin documents/passages by century
        nabu lang --mixing         # the multilingualism census
        nabu language --export-dossiers --dry-run   # preview the migration
    HELP
    option :list, type: :boolean, default: false,
                  desc: "List the held languages (corpus documents, gold lemmas, or a shelf)"
    option :"export-dossiers", type: :boolean, default: false,
                               desc: "One-shot migration: write ledger language notes out as " \
                                     "canonical/local-language dossiers (idempotent, absence-filling)"
    option :"dry-run", type: :boolean, default: false,
                       desc: "With --export-dossiers: report what would be written, touch nothing"
    option :long, type: :boolean, default: false,
                  desc: "Add per-source document counts and the upstream-code edge split"
    option :curve, type: :boolean, default: false,
                   desc: "Documents + passages per century for CODE (precompiled curve)"
    option :mixing, type: :boolean, default: false,
                    desc: "The multilingualism census: inventory sizes, mixed inventories, switch grain"
    def language(code = nil)
      config = Nabu::Config.load
      return export_language_dossiers(config) if options[:"export-dossiers"]
      return language_census(config, code) if options[:curve] || options[:mixing]

      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      languages = Nabu::Languages.new(catalog: catalog)
      info = catalog && Nabu::Query::LanguageInfo.new(catalog: catalog, fulltext: fulltext)
      if options[:list]
        print_language_list(languages, info, Nabu::Lects.load_default(config: config, overlay: {}))
      else
        term = code.to_s.strip
        raise Thor::Error, "language: give a code (chu, gkm, zle-ort…) or --list" if term.empty?

        registry = Nabu::SourceRegistry.load(config.sources_path)
        lects = Nabu::Lects.load_default(config: config)
        dossiers = Nabu::LanguageDossiers.load_default(config: config)
        notes = catalog ? Nabu::Query::Notes.new(catalog: catalog).for_urn(Nabu::LanguageNote.urn(term)) : []
        print_language_card(term, languages, info, registry: registry, lects: lects,
                                                   dossiers: dossiers, notes: notes)
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "kind census", "The document-kind axis: cross-corpus class counts"
    option :unmapped, type: :boolean, default: false,
                      desc: "List the unmapped raw values by count per source — the curation worklist"
    option :uncovered, type: :boolean, default: false,
                       desc: "List the open-vocabulary values no rule covers (they mint nothing)"
    option :limit, type: :numeric, default: 50, desc: "Rows shown by --uncovered (the full count is announced)"
    long_desc <<~HELP, wrap: false
      The fourth document axis: what KIND of document is this? Upstream
      genre vocabularies fold onto the ruled cross-corpus classes
      (config/kind_classes.yml; the per-source folds live in
      config/kind_map.yml). `census` shows every class family with its
      document and source spread, the honesty buckets (unknown = upstream's
      own "cannot determine"; unmapped = values awaiting a fold rule), the
      open-vocabulary misses (uncovered = subject headings and the like
      that no rule covers — a source declared `vocabulary: open` folds
      them to nothing, counted here instead), and the unclassified
      remainder. Filter the corpus with `nabu search --kind CLASS[/SUB]`.

        nabu kind census              # the class board
        nabu kind census --unmapped   # raw values awaiting a rule
        nabu kind census --uncovered  # open-vocabulary values no rule covers (top 50; --limit N)
    HELP
    def kind(subcommand = "census")
      raise Thor::Error, "usage: nabu kind census [--unmapped|--uncovered]" unless subcommand == "census"

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "kind census: no catalog — run nabu sync or nabu rebuild" if catalog.nil?

      census = Nabu::Query::KindCensus.new(catalog: catalog)
      if options[:unmapped]
        print_kind_unmapped(census, Nabu::Kinds.load_default(config: config))
      elsif options[:uncovered]
        print_kind_uncovered(census, limit: options[:limit].to_i)
      else
        report = census.run
        if report.nil?
          raise Thor::Error,
                "kind census: the kind_stats table is not built yet — run nabu sync or nabu rebuild"
        end

        print_kind_census(report)
      end
    ensure
      catalog&.disconnect
    end

    desc "person NAME|REF", "The person desk card: the derived prosopography index (CBDB, EDH, …)"
    long_desc <<~HELP, wrap: false
      Look a person up in the derived person index: the CBDB thin slice
      (~658k persons of Chinese history), EDH's attested persons (~93.6k
      Latin inscription persons, one card per attestation — the ref names
      the inscription), the Elephantine ancient persons, the Aozora Bunko
      author/translator index (1,335 persons) and the kokubunken waka-poet
      personographies (266). Input is an authority ref (cbdb:1762,
      edh:HD000001/3, aozora:001257, kokubunken:紀貫之) or a name — hanzi,
      pinyin, courtesy/studio names, kana readings, romaji, a Roman name
      as inscribed or in the nominative all key through the shared fold;
      matching is exact under the fold, never fuzzy; homonyms print
      several cards (cbdb first, then edh, elephantine, aozora, kokubunken).

      `nabu person mine SOURCE [AUTHORITY]` runs the CENSUS-ONLY name scan:
      SOURCE's passages against AUTHORITY's name keys (default cbdb; edh,
      elephantine, … — the scope is always explicit). The lane follows the
      authority's keys: Han keys match as substrings, alphabetic ones
      (EDH's Roman names, Elephantine's forms) as whole-word sequences. It
      writes nothing — the apply gate stays closed until an owner ruling
      on the census.

      `nabu person candidates SOURCE [--dry-run]` mines person-name
      CANDIDATES from SOURCE's own case-preserving text — a word occurring
      ≥3 times, ≥90% of them capitalized — into person-name-candidate
      edges in the links journal (read back with `nabu links <passage
      urn>`). Candidates are name forms, never person records: no
      authority, no person card. The scope is recorded, so the rebuild's
      links stage re-mints it (a cheap lane, config/mined_layers.yml).
      --dry-run prints the census and writes nothing.

      Examples:
        nabu person 王安石          # by name
        nabu person "Wang Anshi"   # pinyin, same person
        nabu person 介甫           # the courtesy name resolves too
        nabu person cbdb:1762      # by authority ref
        nabu person "Iulius Optatus"   # an EDH person, nominative form
        nabu person edh:HD000001/3     # by EDH ref (inscription HD000001, person 3)
        nabu person sillok:M_0006771   # a NIKH index-markup person, per source
        nabu person nikh:p094190       # the passage-annotation ref: every NIKH slice holding it
        nabu person mine kanripo   # census the person-name attestations
        nabu person mine edr edh   # EDH's attested persons against EDR's text
        nabu person candidates edh --dry-run   # the candidate recipe's census
        nabu person candidates edh             # mine candidate edges (recorded scope)
    HELP
    def person(*query_parts)
      return run_person_mine(query_parts[1..]) if query_parts.first == "mine"
      return run_person_candidates(query_parts[1..]) if query_parts.first == "candidates"

      query = query_parts.join(" ").strip
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      result = Nabu::Query::Person.new(catalog: catalog).run(query)
      result.cards.each { |card| print_person_card(card) }
    rescue Nabu::Query::Person::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    desc "place NAME|ID", "The place desk card: Pleiades gazetteer facts + the library's holdings there"
    long_desc <<~HELP, wrap: false
      The third dimension of the library (after language and time): one
      ancient place, resolved through the local Pleiades gazetteer dump,
      plus every source's holdings AT that place — counted over the
      Pleiades ids the epigraphic parsers capture from their upstream
      headers (isicily, edh, iip, itant). Only upstream-asserted ids ever
      count: no fuzzy geo-matching anywhere in the pipeline.

      Input is a Pleiades NUMERIC id (or a pleiades.stoa.org/places URL),
      a NAMESPACED ref (P66-2: tm:2810 · cigs:GIR · pleiades:462281 —
      tm/cigs resolve through their own derived index slices), or an EXACT
      place title, matched case-insensitively against the dump — "Segesta"
      works, "Seges" does not (exact only, by design). Homonym titles
      print one card each.

      The card: title, Pleiades id, place types, the attested time-period
      span, and the representative point (lat, lon — display only; no maps,
      no coordinate math). Then the holdings line, per source, descending —
      and (P66-2) the AXIS holdings line: documents whose place_ref axis
      cites the place (adapter-asserted refs + the nabu-places registry's
      applied decisions, both spellings, one count per document) — labeled
      apart because the provenance differs.

      An honest labelled tail follows when id-less documents mention the
      name in their captured findspot TEXT (exact substring, case-
      insensitive): "unlinked findspot mentions" — never merged into the
      id-matched counts.

      The gazetteer dump is the pleiades module's canonical asset
      (`nabu sync pleiades`, ~42k places). Since P45-6 the sync also
      derives a place index into the catalog, so lookups here read it
      instantly; the ~3 s in-memory dump load is paid only while that
      index is not yet derived (re-sync or rebuild derives it). Without
      the dump on disk, a numeric id still counts holdings (the catalog
      side needs no dump); a name lookup is refused with the sync hint.

      Examples:
        nabu place Segesta          # exact title → card + holdings
        nabu place 462281           # Lilybaeum by Pleiades id
        nabu place https://pleiades.stoa.org/places/462281   # same
        nabu place tm:2788          # Pompeii through the TM gazetteer slice
        nabu place cigs:GIR         # Girsu through the CIGS slice
        nabu place mine kanripo --dry-run   # Q9: census Han place-name hits (writes nothing)
        nabu place mine kanripo             # mine place-candidate edges into the links journal
        nabu place mine report kanripo      # review the mined candidates, ranked by document spread
        nabu place mine report kanripo --board   # the per-NAME verdict board (discriminators + snippets)
    HELP
    option :verbose, type: :boolean, default: false,
                     desc: "place apply: #{Nabu::Ops::StageGuide::OPTION_DESC}"
    def place(*query_parts)
      return run_place_apply if query_parts == ["apply"]
      return run_place_mine(query_parts[1..]) if query_parts.first == "mine"
      return run_place_link(query_parts[1..]) if query_parts.first == "link"

      query = query_parts.join(" ").strip
      raise Thor::Error, "place: give a Pleiades numeric id or an exact place title" if query.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      resolver = Nabu::Pleiades.load_default(config: config, catalog: catalog)
      result = Nabu::Query::Place.new(catalog: catalog, pleiades: resolver,
                                      place_shelf_dir: config.source_workdir(Nabu::PlaceDossiers::DIRNAME))
                                 .run(query)
      print_place(result)
    rescue Nabu::Query::Place::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    desc "axis [NAME]", "The research-axis desk card: persona, members, holdings, gold coverage (config/axes.yml)"
    long_desc <<~HELP, wrap: false
      The research axes are the owner's desks — TAGS over the source list
      (config/axes.yml), a source appearing under every desk it serves
      (dual-tagging is the point, D35). This is their reference card, the
      `nabu language` mold pointed at a whole desk instead of a code.

      Bare `nabu axis` lists every desk in ratified (file) order — name and
      persona, one line each. `nabu axis NAME` prints the full card:

      - PERSONA, the hat's one-liner, verbatim from config/axes.yml, and the
        membership rationale (desc) beneath it.
      - MEMBERS, every source the desk tags, each with its enablement (on/off,
        from the registry — the authoritative flip) and its live holdings
        (documents/passages, dictionary entries, dossiers, languages, license
        mix — the same census fragments `nabu list` prints). Zero fields are
        suppressed; a member holding nothing yet says so.
      - LANGUAGES, the codes the member sources hold, one merged doc-or-entry
        count each, holdings descending — the counts keep a multilingual
        pack's spillover honest (kat 3 beside hbo 40,000 explains itself).
        Compact shows ten codes with an honest "… and N more"; --long lifts.
      - GOLD COVERAGE, the aggregate gold-lemma rows across the desk's held
        languages (nabu search --lemma) — honest zero when none are gold.
      - the shipped affordances: `nabu list --axis NAME`, `nabu sync NAME`.

      An unknown axis is refused naming the known set (the slug/axis collision
      guarantee makes a bare name unambiguous). No corpus yet is not an error:
      the persona and membership still print, holdings say "no database".

      Examples:
        nabu axis                  # every desk, one persona line each
        nabu axis celtic           # the Celticist's desk, full card
        nabu axis biblical --long  # the scripture hat, every language code
    HELP
    option :long, type: :boolean, default: false,
                  desc: "Lift the languages-line cap (compact shows ten codes)"
    def axis(name = nil)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      axes = registry.axes
      raise Thor::Error, "axis: no research axes are defined (config/axes.yml)" if axes.empty?

      catalog = open_catalog(config)
      fulltext = catalog ? open_fulltext(config) : nil
      name = name.to_s.strip
      if name.empty?
        print_axis_list(axes)
      else
        definition = axes[name] ||
                     raise(Thor::Error, "axis: unknown axis #{name.inspect} — known axes: #{axes.names.join(', ')}")
        census = catalog ? Nabu::Query::List.new(catalog: catalog).census : nil
        info = catalog ? Nabu::Query::LanguageInfo.new(catalog: catalog, fulltext: fulltext) : nil
        print_axis_card(definition, registry: registry, census: census, info: info)
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    # Language codes shown by the `nabu axis` desk card's languages line
    # before the "… and N more" tail (P48-r3; --long lists all — the same
    # house render-cap rule).
    AXIS_LANGUAGES_ITEMS = 10

    # Crosswalk equivalences shown on the place card's "=" line before the
    # "… and N more" tail (P75 C-3, the same house render-cap rule).
    # const: a render cap, not a corpus census
    PLACE_EQUIVALENCES_SHOWN = 8

    no_commands do
      # P121-2: the two rollup-backed language desks (--curve / --mixing).
      def language_census(config, code)
        catalog = open_catalog(config)
        raise Thor::Error, "language: no catalog — run nabu sync or nabu rebuild" if catalog.nil?

        census = Nabu::Query::LanguageCensus.new(catalog: catalog)
        if options[:mixing]
          print_language_mixing(census.mixing)
        else
          term = code.to_s.strip
          raise Thor::Error, "language --curve: give a code (lat, grc…)" if term.empty?

          print_language_curve(census.curve(term))
        end
      ensure
        catalog&.disconnect
      end

      def print_language_curve(result)
        rollup_status_error("language --curve", result.status)
        if result.points.empty?
          return say("language --curve #{result.code}: no documents hold this code " \
                     "(#{format_duration(result.seconds)})")
        end

        say "#{result.code} — documents and passages per century (each document at its date-envelope midpoint)"
        width = (result.points.map { |point| point.label.length } + [7]).max
        peak = result.points.map(&:passages).max
        result.points.each do |point|
          bar = "█" * [(CURVE_BAR_WIDTH * point.passages.to_f / peak).round, 1].max
          bases = point.bases.any? ? "  (#{point.bases.join(', ')})" : ""
          say "  #{point.label.ljust(width)}  #{commafy(point.documents).rjust(9)} docs · " \
              "#{commafy(point.passages).rjust(11)} passages  #{bar}#{bases}"
        end
        say "curve: #{commafy(result.documents)} docs · #{commafy(result.passages)} passages over " \
            "#{dated_centuries(result.points.count(&:century))} " \
            "(#{format_duration(result.seconds)})"
      end

      def print_language_mixing(result)
        rollup_status_error("language --mixing", result.status)
        say "language mixing — #{commafy(result.documents)} documents by passage-language inventory size"
        result.by_size.each do |size, count|
          share = (100.0 * count / result.documents).round(1)
          say "  #{pluralize(size, 'language').ljust(12)}  #{commafy(count).rjust(11)} docs (#{share}%)"
        end
        print_mixing_inventories(result.inventories)
        print_mixing_sources(result.sources)
        mixed = result.by_size.sum { |size, count| size > 1 ? count : 0 }
        share = result.documents.zero? ? 0 : (100.0 * mixed / result.documents).round(1)
        say "mixing: #{commafy(mixed)} mixed of #{commafy(result.documents)} documents (#{share}%) " \
            "(#{format_duration(result.seconds)})"
      end

      def print_mixing_inventories(inventories)
        return if inventories.empty?

        say "top mixed inventories:"
        width = inventories.map { |languages, _| languages.length }.max
        inventories.each { |languages, count| say "  #{languages.ljust(width)}  #{commafy(count).rjust(9)} docs" }
      end

      def print_mixing_sources(sources)
        return if sources.empty?

        say "switch grain by source (mixed docs · block / interleaved · total switches):"
        width = sources.map { |grain| grain.slug.length }.max
        sources.each do |grain|
          say "  #{grain.slug.ljust(width)}  #{commafy(grain.mixed).rjust(9)} mixed · " \
              "#{commafy(grain.block)} block / #{commafy(grain.interleaved)} interleaved · " \
              "#{commafy(grain.switches)} switches"
        end
      end

      # The person card renderer (P97-2): one line of identity, one of
      # dates/dynasty — thin by design, like the slice.
      def print_person_card(card)
        years = [card.birth_year, card.death_year].compact.join("–")
        dynasty = [card.dynasty_han, card.dynasty].compact.join(" ")
        headline = [card.name_han, card.name].compact.join(" · ")
        say "#{headline}  #{card.authority}:#{card.person_id}"
        details = []
        details << years unless years.empty?
        details << dynasty unless dynasty.empty?
        details << "female" if card.female
        say "  #{details.join(' · ')}" unless details.empty?
      end

      # `nabu person mine SOURCE [AUTHORITY]` (P97-2; widened beyond Han):
      # the census-only scan of SOURCE's text against AUTHORITY's keys; the
      # apply gate stays closed until an owner ruling, so there is no
      # --dry-run — dry is the only mode.
      def run_person_mine(args)
        source, authority = Array(args)
        raise Thor::Error, "usage: nabu person mine SOURCE [AUTHORITY]" if source.to_s.empty?

        authority ||= Nabu::Store::PersonIndex::DEFAULT_AUTHORITY
        config = Nabu::Config.load
        catalog = Nabu::Store.connect(config.catalog_path)
        unless Nabu::Store::PersonIndex.populated?(catalog, authority: authority)
          raise Thor::Error, "person mine: the #{authority.inspect} person-index slice is not derived — " \
                             "sync its source first (nabu sync #{authority})"
        end

        census = Nabu::PersonMine.new(catalog: catalog, authority: authority, progress: progress_reporter)
                                 .census(source: source)
        say "person mine: #{census.source} × #{census.authority} (#{census.lane} lane) — " \
            "#{census.passages} passages scanned against #{census.names_loaded} name keys " \
            "(#{census.names_off_lane} off-lane filtered, #{census.names_ambiguous} ambiguous capped; " \
            "#{format_duration(census.seconds)})"
        census.name_hits.first(15).each do |name, count|
          say format("  %<name>-12s %<count>d passages", name: name, count: count)
        end
        say "  … #{census.name_hits.size - 15} more attested names" if census.name_hits.size > 15
        census.names_stopped.each do |name, count|
          say "  STOPPED #{name} — #{count} passages (above the derived ceiling)"
        end
        say "  census only — the person apply gate stays closed until an owner ruling on these numbers"
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
      end

      # `nabu person candidates SOURCE [--dry-run]`: the person-name
      # candidate recipe over SOURCE's own text. --dry-run prints the
      # census (candidates + every exclusion class) and writes nothing;
      # otherwise the person-name-candidate edges land in the links journal
      # and the scope is recorded for the rebuild's links stage (the
      # batch-CLI derivability contract, the place-mine precedent).
      def run_person_candidates(args)
        args = Array(args)
        dry = args.delete("--dry-run") ? true : false
        source = args.first
        raise Thor::Error, "usage: nabu person candidates SOURCE [--dry-run]" if source.to_s.empty?

        config = Nabu::Config.load
        Nabu::Store.assert_writable!(config.catalog_path) unless dry
        catalog = Nabu::Store.connect(config.catalog_path)
        journal = unless dry
                    Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite://#{config.links_path}"))
                  end
        miner = Nabu::PersonCandidates.new(catalog: catalog, journal: journal, progress: progress_reporter)
        if dry
          print_person_candidates(miner.census(source: source))
          say "  dry run — nothing written"
        else
          result = miner.apply!(source: source)
          Nabu::LinkScopes.record!(config.link_scopes_path, producer: Nabu::PersonCandidates::PRODUCER,
                                                            scope: source, params: {})
          print_person_candidates(result.census)
          say "person candidates: #{result.edges_written} candidate edges written " \
              "(#{result.superseded_edges} superseded) in #{format_duration(result.seconds)} " \
              "— name forms, not person records; read back with `nabu links <passage urn>`"
        end
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      ensure
        journal&.disconnect
        catalog&.disconnect
      end

      def print_person_candidates(census)
        say "person candidates: #{census.source} — #{census.passages} passages, #{census.words} words, " \
            "#{census.candidates.size} name candidates (≥#{Nabu::PersonCandidates::MIN_OCCURRENCES} " \
            "occurrences, ≥#{(Nabu::PersonCandidates::MIN_CAPITALIZED_SHARE * 100).round}% capitalized; " \
            "#{census.candidate_edges} candidate edges; #{format_duration(census.seconds)})"
        census.candidates.first(15).each do |candidate|
          say format("  %<form>-16s %<count>d occurrences, %<share>d%% capitalized",
                     form: candidate.surface, count: candidate.occurrences,
                     share: (candidate.capitalized_share * 100).round)
        end
        say "  … #{census.candidates.size - 15} more candidates" if census.candidates.size > 15
        excluded = census.excluded.sort.map { |reason, count| "#{count} #{reason}" }
        say "  excluded forms: #{excluded.join(', ')}" unless excluded.empty?
      end

      # `nabu place mine SOURCE [GAZETTEER] [--dry-run]` (P96-3 — Q9 v0):
      # mine the gazetteer's Han name keys against SOURCE's passage text
      # into place-candidate edges (review fuel for the np: doctrine,
      # never place_ref). --dry-run prints the census — per-name hit
      # counts, the derived stop set, every filtered class — and writes
      # nothing. Default gazetteer: chgis.
      def run_place_mine(args)
        args = Array(args)
        return run_place_mine_report(args[1..]) if args.first == "report"

        dry = args.delete("--dry-run") ? true : false
        source, gazetteer = args
        raise Thor::Error, "usage: nabu place mine SOURCE [GAZETTEER] [--dry-run]" if source.to_s.empty?

        gazetteer ||= "chgis"
        config = Nabu::Config.load
        Nabu::Store.assert_writable!(config.catalog_path) unless dry
        catalog = Nabu::Store.connect(config.catalog_path)
        unless Nabu::Store::PlaceIndex.populated?(catalog, gazetteer: gazetteer)
          raise Thor::Error,
                "place mine: the #{gazetteer.inspect} place-index slice is not derived — " \
                "sync the gazetteer module first (nabu sync #{gazetteer})"
        end

        journal = if dry
                    nil
                  else
                    Nabu::Store::LinksJournal.migrate!(
                      Nabu::Store::LinksJournal.connect("sqlite://#{config.links_path}")
                    )
                  end
        places = Nabu::Places.load_default(canonical_dir: config.canonical_dir)
        miner = Nabu::PlaceMine.new(catalog: catalog, journal: journal, gazetteer: gazetteer,
                                    progress: progress_reporter,
                                    ruled_out: Nabu::PlaceMine.ruled_out_names(places, source))
        if dry
          print_mine_census(miner.census(source: source), applied: false)
        else
          result = miner.apply!(source: source)
          # Since the 2026-09-27 rebuild dropped the mine run, the scope
          # joins the P70 derivability record so the rebuild links stage
          # re-mints it — the batch-CLI contract, closed for this producer.
          Nabu::LinkScopes.record!(config.link_scopes_path, producer: "place-mine",
                                                            scope: source, params: { "gazetteer" => gazetteer })
          print_mine_census(result.census, applied: true)
          say "place mine: #{result.edges_written} candidate edges written " \
              "(#{result.superseded_edges} superseded) in #{format_duration(result.seconds)} " \
              "— review fuel for np: decisions; read back with `nabu links <passage urn>`"
        end
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      ensure
        journal&.disconnect
        catalog&.disconnect
      end

      # `nabu place mine report [SOURCE] [GAZETTEER] [--limit N]` (P97-1):
      # the aggregate review surface — mined candidates grouped by
      # place, ranked by document spread, each row carrying its evidence
      # and the two exits (stop-list line, place card).
      def run_place_mine_report(args)
        args = Array(args)
        board = args.delete("--board") ? true : false
        limit = Nabu::PlaceMineReport::DEFAULT_LIMIT
        if (i = args.index("--limit"))
          limit = begin
            Integer(args[i + 1])
          rescue TypeError, ArgumentError
            raise Thor::Error, "place mine report: --limit needs a number"
          end
          args.slice!(i, 2)
        end
        source, gazetteer = args
        raise Thor::Error, "place mine report --board needs a SOURCE (verdicts are per source)" if board && source.nil?

        config = Nabu::Config.load
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        if journal.nil?
          raise Thor::Error, "place mine report: no links journal yet — run `nabu place mine SOURCE` first"
        end

        catalog = Nabu::Store.connect(config.catalog_path)
        reporter = Nabu::PlaceMineReport.new(catalog: catalog, journal: journal)
        if board
          result = reporter.board(source: source, gazetteer: gazetteer || "chgis", limit: limit,
                                  registry: Nabu::Places.load_default(canonical_dir: config.canonical_dir),
                                  stop_names: Nabu::PlaceMine.hand_stop_names)
          print_mine_board(result)
        else
          print_mine_report(reporter.run(source: source, gazetteer: gazetteer, limit: limit))
        end
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      ensure
        journal&.disconnect
        catalog&.disconnect
      end

      # The P105-1 verdict surface: one block per NAME — candidates with
      # their discriminators, attestations in context, both exits.
      def print_mine_board(result)
        say "place-mine board: #{result.source} × #{result.gazetteer} — #{result.edges} candidate " \
            "edges · #{result.total_names} undecided names (#{format_duration(result.seconds)})"
        unless result.decided.empty?
          say "  decided already in nabu-places (off the board): " \
              "#{result.decided.map { |name, status| "#{name}=#{status}" }.join(' · ')}"
        end
        say "  stopped since mined (place_stop_names.yml): #{result.stopped.join(' · ')}" unless result.stopped.empty?
        if result.rows.empty?
          say "  nothing undecided in this scope — the board is clean"
          return
        end

        say "  ranked by document spread; exact spread computed over the top #{result.prerank_window} by passages"
        result.rows.each_with_index do |row, i|
          say format("  %<rank>2d. %<name>s — %<docs>d docs · %<passages>d passages · %<n>d candidate%<s>s",
                     rank: i + 1, name: row.name, docs: row.documents, passages: row.passages,
                     n: row.candidates.size, s: row.candidates.size == 1 ? "" : "s")
          row.candidates.each do |c|
            bits = [c.title, c.place_types.first, c.time_periods.join(" "),
                    c.parent && "parent #{c.parent}",
                    c.lat && format("%<lat>.2f,%<lon>.2f", lat: c.lat, lon: c.lon)].compact.reject(&:empty?)
            say "      · #{c.ref}  #{bits.join(' · ')}"
          end
          row.snippets.each { |urn, text| say "      ▸ #{urn}  #{text}" }
          say "      exits: link → names.yml (#{result.source}) · stop → place_stop_names.yml: - \"#{row.name}\""
        end
      end

      def print_mine_report(report)
        scope = [report.source || "all sources", report.gazetteer || "all gazetteers"].join(" × ")
        say "place-mine report: #{scope} — #{report.edges} candidate edges over " \
            "#{report.total_places} places (#{format_duration(report.seconds)})"
        if report.rows.empty?
          say "  nothing mined in this scope — `nabu place mine SOURCE [GAZETTEER]` writes candidates"
          return
        end

        say "  ranked by document spread; exact spread computed over the top #{report.prerank_window} by passages"
        report.rows.each_with_index do |row, i|
          names = row.names.map { |n, c| "「#{n}」×#{c}" }.join(" ")
          say format("  %<rank>2d. %<title>s  %<ref>s — %<docs>d docs · %<passages>d passages · %<names>s",
                     rank: i + 1, title: row.title || "(no title in slice)", ref: row.ref,
                     docs: row.documents, passages: row.passages, names: names)
          say "      sample: #{row.samples.join(' · ')}"
          say "      exits: card `nabu place #{row.ref}` · stop-list (config/place_stop_names.yml): " \
              "#{row.stop_lines.join(' ')}"
        end
        clipped = report.total_places - report.rows.size
        say "  … #{clipped} more places below the cut (--limit raises the cap)" if clipped.positive?
      end

      def print_mine_census(census, applied:)
        say "place mine: #{census.source} × #{census.gazetteer} — #{census.passages} passages " \
            "scanned against #{census.names_loaded} Han name keys " \
            "(#{census.names_non_han} non-Han filtered, #{census.names_ambiguous} ambiguous capped)"
        census.name_hits.first(15).each do |name, count|
          say format("  %<name>-12s %<count>d passages", name: name, count: count)
        end
        say "  … #{census.name_hits.size - 15} more attested names" if census.name_hits.size > 15
        census.names_stopped.each do |name, count|
          say "  STOPPED #{name} — #{count} passages (above the derived ceiling; " \
              "a genuinely geographic name lost here is an allow_names: ruling " \
              "in config/place_stop_names.yml)"
        end
        census.names_allowed.each do |name, count|
          say "  ALLOWED #{name} — #{count} passages (over the ceiling, mined anyway " \
              "by allow_names: ruling)"
        end
        census.names_ruled_out.each do |name, count|
          say "  RULED OUT #{name} — #{count} passages (nabu-places rules it region/rejected: no candidates)"
        end
        say "  candidate edges#{' (dry run — nothing written)' unless applied}: " \
            "#{census.candidate_edges} across #{census.name_hits.size} attested names " \
            "(census pass: #{format_duration(census.seconds)})"
      end

      # `nabu place link SOURCE [GAZETTEER]` (P105-4 — the place-mine apply lane):
      # promote the registry's MATCHED mined names to ruled attestation
      # edges (kind "place") in the links journal. Passage-grain by
      # design — never document_axes.place_ref.
      def run_place_link(args)
        source, gazetteer = Array(args)
        raise Thor::Error, "usage: nabu place link SOURCE [GAZETTEER]" if source.to_s.empty?

        gazetteer ||= "chgis"
        config = Nabu::Config.load
        registry = Nabu::Places.load_default(canonical_dir: config.canonical_dir)
        if registry.nil?
          raise Thor::Error, "place link: no nabu-places registry under canonical/ — " \
                             "run `nabu sync nabu-places` first"
        end

        catalog = Nabu::Store.connect(config.catalog_path)
        journal = Nabu::Store::LinksJournal.migrate!(
          Nabu::Store::LinksJournal.connect("sqlite://#{config.links_path}")
        )
        result = Nabu::PlaceLink.new(catalog: catalog, journal: journal, registry: registry,
                                     gazetteer: gazetteer, progress: progress_reporter)
                                .apply!(source: source)
        # Recorded like every batch scope — the replay runs it AFTER
        # place-mine (LinkScopeReplay.order), promotion needs candidates.
        Nabu::LinkScopes.record!(config.link_scopes_path, producer: "place-link",
                                                          scope: source, params: { "gazetteer" => gazetteer })
        say "place link: #{result.source} × #{result.gazetteer} — #{result.names} ruled " \
            "names → #{result.edges_written} attestation edges written " \
            "(#{result.edges_refreshed} refreshed; superseded #{result.superseded_runs} " \
            "prior runs / #{result.superseded_edges} edges; #{format_duration(result.seconds)}) " \
            "— read back with `nabu links <passage urn>`"
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      ensure
        journal&.disconnect
        catalog&.disconnect
      end

      # `nabu place apply` (P63-7): project the nabu-places registry into
      # document_axes.place_ref — NULL rows only (adapter-asserted refs
      # always win), idempotent, censused per source. Write-guarded by the
      # P62 probe; a missing registry is a polite posture, not a stack.
      def run_place_apply
        config = Nabu::Config.load
        Nabu::Store.assert_writable!(config.catalog_path)
        catalog = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.migrate!(catalog)
        explain_command(:place_apply)
        apply_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        census = Nabu::PlaceApply.run(catalog: catalog, canonical_dir: config.canonical_dir)
        if census.nil?
          say "place apply: no nabu-places registry under canonical/ — " \
              "run `nabu sync nabu-places` first (owner queue, P63)"
          return
        end
        census.except(:total).each do |slug, c|
          say "  #{slug}: #{c[:rows_updated]} rows gained refs across #{c[:names_applied]} names"
          # P81 U-3: a below-certain registry decision no longer dies at
          # apply — each applied low-certainty name reports its rows with
          # the Certainty gloss, upstream word verbatim.
          (c[:uncertain] || {}).each do |name, info|
            say "    #{name} — #{info[:rows]} #{info[:rows] == 1 ? 'row' : 'rows'} " \
                "(#{Nabu::Certainty.gloss(:places_certainty, info[:certainty])})"
          end
        end
        say "place apply: #{census[:total]} axis rows updated " \
            "(#{format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - apply_started)})"
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
      end

      # Bare `nabu axis` (P37-8): one line per desk — name and persona — in
      # ratified (file) order, the `nabu language --list` mold. The full card
      # is one `nabu axis NAME` away.
      def print_axis_list(axes)
        say "research axes — the library's desks (#{axes.size}):"
        width = axes.names.map(&:length).max || 0
        axes.each_axis { |axis| say "  #{axis.name.ljust(width)}  #{axis.persona}" }
        say "nabu axis NAME for the full desk card (members, holdings, gold coverage)"
      end

      # `nabu axis NAME` (P37-8): the research-axis desk card, the `nabu
      # language` mold pointed at a whole desk. The persona rides verbatim
      # (first-class render data), then the membership rationale (desc); then
      # every member the desk tags with its enablement (on/off, from the
      # authoritative registry) and its live holdings (the same census
      # fragments `nabu list` prints); then the aggregate gold-lemma coverage
      # across the desk's held languages; then the shipped affordances. Zero
      # fields suppressed — a member holding nothing says so, a desk with no
      # gold says so, no corpus at all still prints persona + membership.
      def print_axis_card(axis, registry:, census:, info:)
        say "#{axis.name} — #{axis.persona}"
        say_wrapped(axis.desc, indent: 2)
        members = registry.axis_members(axis.name)
        by_slug = (census || []).to_h { |row| [row.slug, row] }
        say "  members (#{members.size}):"
        width = members.map(&:length).max || 0
        members.each do |slug|
          entry = registry[slug]
          # P46-r1: a kind: module row is PERMANENTLY wired: false (nothing
          # mints, nothing to flip) — its cell names the nature; "unwired"
          # is reserved for adapters genuinely awaiting first-sync proof.
          state = if entry&.feature_module?
                    "module "
                  else
                    entry&.wired ? "wired  " : "unwired"
                  end
          say "    #{slug.ljust(width)}  #{state}  #{axis_member_holdings(by_slug[slug], census: census)}"
        end
        print_axis_languages(members, info)
        print_axis_gold(members, by_slug, info, registry: registry)
        say "  commands: nabu list --axis #{axis.name} · nabu sync #{axis.name}"
      end

      # The desk's held language codes (P48-r3): one merged doc-or-entry
      # count per code over the member sources, holdings descending. The
      # counts ARE the honesty mechanism — a multilingual pack's 3-doc
      # spillover reads as 3 beside a 40K holding, never hidden. No catalog,
      # no line (the member cells already say "no database"); a desk holding
      # nothing says so.
      # P49-r4, the deliberate asymmetry: this line KEEPS multilingual pack
      # members (the counts self-explain), while the count-less attribution
      # surfaces (print_language_axes, print_axis_gold) exclude them.
      def print_axis_languages(members, info)
        return unless info

        holdings = info.language_holdings_for(members)
        return say("  languages: none held yet") if holdings.empty?

        shown = options[:long] ? holdings : holdings.first(AXIS_LANGUAGES_ITEMS)
        line = shown.map { |code, count| "#{code} #{commas(count)}" }.join(" · ")
        hidden = holdings.size - shown.size
        line += " … and #{hidden} more (--long lists all)" if hidden.positive?
        say "  languages: #{line}"
      end

      # One member's holdings cell: the census fragments when the source holds
      # something, an honest "nothing held yet" when it is in the registry but
      # empty, and "no database" when the corpus was never built.
      def axis_member_holdings(row, census:)
        return "no database (run nabu sync)" if census.nil?
        return "nothing held yet" if row.nil?

        census_fragments(row).join("  ")
      end

      # The desk's aggregate gold-lemma coverage: gold lemma rows summed over
      # the languages its members actually hold (nabu search --lemma). Honest
      # zero when the held languages carry no gold, honest "no held languages"
      # when the desk holds nothing dated in a language yet.
      # P49-r4: languages reachable ONLY via multilingual pack members stay
      # off the gold claim — the same exclusion rule (and the same rejected-
      # threshold reasoning) as the language card's axes: line, so the hebrew
      # desk stops claiming a treebank pack's kat/phn/xcl gold rows. The
      # languages: line above deliberately KEEPS pack holdings: its per-code
      # counts self-explain a three-doc spillover; this count-less language
      # list cannot.
      def print_axis_gold(members, by_slug, info, registry:)
        attributable = members.reject { |slug| registry.multilingual?(slug) }
        langs = attributable.flat_map { |slug| by_slug[slug]&.languages || [] }.uniq.sort
        return say("  gold lemmas: no held languages yet") if langs.empty?

        total = info ? info.gold_rows_for(langs) : 0
        if total.positive?
          say "  gold lemmas: #{commas(total)} rows across #{langs.join(', ')} (nabu search --lemma)"
        else
          say "  gold lemmas: none in the held languages (#{langs.join(', ')})"
        end
      end

      # Render `place` (P44-2): one card per matched place — headline,
      # holdings per source — then the labelled unlinked tail once. The
      # spec shape: "Lilybaeum, Pleiades 462281 — settlement · archaic…roman
      # · 37.80, 12.43" over "holdings: 214 isicily · 12 edh · 2 iip".
      def print_place(result)
        result.cards.each_with_index do |card, index|
          say "" if index.positive?
          print_place_card(card, dump_loaded: result.dump_loaded)
        end
        return if result.unlinked.empty?

        say "  unlinked findspot mentions of #{result.unlinked_term.inspect} " \
            "(text match, no Pleiades id — not counted above): #{format_source_counts(result.unlinked)}"
      end

      # P81 U-3 (survey A3): a gazetteer's own "?"-suffixed title — the
      # Barrington less-certain lineage — glosses right after the title via
      # the shared cataloguer's-"?" helper; unmarked titles stay ink-free.
      def print_place_card(card, dump_loaded:)
        place = card.place
        if card.pleiades_id.nil?
          # P66-2: a namespaced ref card (tm:2810, cigs:GIR) — the title
          # resolves through that gazetteer's own index slice where derived.
          if place
            say "#{place.title}#{place_query_gloss(place.title)}, #{card.ref}#{place_card_tail(place)}"
          else
            say "#{card.ref} — not in the derived place index"
          end
        elsif place
          say "#{place.title}#{place_query_gloss(place.title)}, Pleiades #{place.id}#{place_card_tail(place)}"
        elsif dump_loaded
          say "Pleiades #{card.pleiades_id} — not in the local gazetteer dump"
        else
          say "Pleiades #{card.pleiades_id} — gazetteer dump not synced " \
              "(`nabu sync pleiades` adds the card)"
        end
        # P75 C-3: the crosswalk line — the derived equivalences this
        # identity is asserted equal to, capped with the cut announced.
        unless card.equivalences.empty?
          shown = card.equivalences.first(PLACE_EQUIVALENCES_SHOWN)
          extra = card.equivalences.size - shown.size
          line = shown.map { |namespace, id| "#{namespace}:#{id}" }.join(" = ")
          line += " … and #{extra} more" if extra.positive?
          say "  = #{line}"
        end
        unless card.pleiades_id.nil? && card.holdings.empty?
          say "  holdings: #{card.holdings.empty? ? 'none' : format_source_counts(card.holdings)}"
        end
        unless card.axis_holdings.empty?
          say "  axis holdings (place_ref — adapter-asserted + registry decisions): " \
              "#{format_source_counts(card.axis_holdings)}"
        end
        card.dossiers.each do |dossier|
          say "  ── dossier: #{dossier.title} ──"
          dossier.body.each_line { |line| say "  #{line.chomp}" }
        end
      end

      # " — types · first…last period · lat, lon", each section only when
      # the dump carries it. Periods render as the attested span endpoints
      # (dump attestation order, not re-sorted — honest to upstream).
      # P76 U-4: the CIGS coordinate-accuracy grade rides the tail verbatim
      # (0–3, higher = more accurate; 0 = unlocated) — a precision fact,
      # never a certainty tier (conventions §12).
      def place_card_tail(place)
        sections = [
          place.place_types.join(" · "),
          period_span(place.time_periods),
          place.lat && place.lon ? format("%<lat>.2f, %<lon>.2f", lat: place.lat, lon: place.lon) : nil,
          place.accuracy ? "coordinate accuracy #{place.accuracy}/3 (CIGS grade)" : nil
        ].compact.reject(&:empty?)
        sections.empty? ? "" : " — #{sections.join(' · ')}"
      end

      def period_span(periods)
        return nil if periods.nil? || periods.empty?
        return periods.first if periods.size == 1

        "#{periods.first}…#{periods.last}"
      end

      def format_source_counts(counts)
        counts.map { |slug, count| "#{count} #{slug}" }.join(" · ")
      end

      # The cataloguer's trailing "?" on a place name (P76 U-2): the
      # Barrington-lineage doubt mark glosses as probable, upstream mark
      # kept verbatim in the name itself.
      def place_query_gloss(name)
        return "" unless name.to_s.strip.end_with?("?")

        " (#{Nabu::Certainty.gloss(:cataloguer_query, '?')})"
      end

      # The kind census board (P99-3): class families ranked by document
      # spread, the honesty buckets rendered apart from the classes, the
      # unclassified remainder announced, one summary line with elapsed.
      def print_kind_census(report)
        width = (report.classes.map { |row| row.head.length } + [10]).max
        report.classes.each do |row|
          say "  #{row.head.ljust(width)}  #{commafy(row.documents).rjust(9)} docs · " \
              "#{pluralize(row.sources, 'source')}"
        end
        say "  #{'unknown'.ljust(width)}  #{commafy(report.unknown_documents).rjust(9)} docs " \
            "(upstream's own \"cannot determine\")"
        say "  #{'unmapped'.ljust(width)}  #{commafy(report.unmapped_documents).rjust(9)} docs " \
            "(values awaiting a fold rule — `nabu kind census --unmapped`)"
        if report.uncovered_values.positive?
          say "uncovered: #{pluralize(report.uncovered_values, 'value')} · " \
              "#{commafy(report.uncovered_documents)} docs in #{pluralize(report.uncovered_sources, 'source')} " \
              "(open vocabularies — no rule covers them, so they mint nothing; " \
              "`nabu kind census --uncovered`)"
        end
        say "no classification: #{pluralize(report.unclassified_sources, 'source')} · " \
            "#{commafy(report.unclassified_documents)} docs (their postures speak)"
        total = report.classified_documents + report.unclassified_documents
        share = total.zero? ? 0 : (100.0 * report.classified_documents / total).round(1)
        say "kind census: #{report.classes.size} class families · " \
            "#{commafy(report.classified_documents)} classified docs (#{share}%) " \
            "(#{format_duration(report.seconds)})"
      end

      # The curation worklist (reworked P101 after the owner read the
      # bare dump and could not tell what it was saying): LEAD with what
      # the list is and what to do with a line, list the TODO tail, then
      # the reviewed not-genre declarations as their own section.
      def print_kind_unmapped(census, kinds)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rows = census.unmapped_worklist
        print_kind_worklist(rows, census)
        print_kind_deliberate(kinds)
        say "kind census: #{pluralize(rows.size, 'unmapped value')} " \
            "(#{format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)})"
      end

      def print_kind_worklist(rows, census)
        return say("kind census: nothing unmapped — every held value has a fold rule") if rows.empty?

        docs = census.run&.unmapped_documents
        say "kind census: #{pluralize(rows.size, 'upstream value')} with no fold rule" \
            "#{" (#{commafy(docs)} documents)" if docs} — each line is a candidate " \
            "config/kind_map.yml entry: fold it to a class, to `unknown` (upstream's " \
            "own cannot-determine), or declare it not-genre under `deliberate:`."
        rows.each do |row|
          say "  #{row.slug.ljust(14)}  #{row.raw.inspect}  ×#{commafy(row.documents)}"
        end
      end

      # The open-vocabulary worklist: values a `vocabulary: open` source
      # carries that no rule covers — they minted no kind row, so this is
      # where they stay visible. Capped at +limit+, the full count
      # announced (cap at render, never a silent truncation).
      def print_kind_uncovered(census, limit:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        worklist = census.uncovered_worklist(limit: [limit, 1].max)
        if worklist.total.zero?
          say "kind census: nothing uncovered — no open-vocabulary source carries a value its rules miss"
        else
          say "kind census: open-vocabulary values no rule covers (they mint no kind row) — " \
              "a genre-shaped line is a candidate config/kind_map.yml rule; a topical one needs nothing."
          worklist.rows.each do |row|
            say "  #{row.slug.ljust(14)}  #{row.raw.inspect}  ×#{commafy(row.documents)}"
          end
        end
        shown = worklist.rows.size
        scope = shown < worklist.total ? "showing #{commafy(shown)} of " : ""
        say "kind census: #{scope}#{pluralize(worklist.total, 'uncovered value')} " \
            "(#{format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)})"
      end

      # The reviewed non-claims: values config declares NOT genre at all
      # (physical layout, cult context, copy markers) — folded to
      # nothing, listed here so the review stays visible, never noise.
      def print_kind_deliberate(kinds)
        declarations = kinds&.deliberate_declarations || []
        return if declarations.empty?

        say "declared not-genre (config/kind_map.yml `deliberate:` — reviewed, fold to nothing):"
        declarations.each do |slug, value, reason|
          say "  #{slug.ljust(14)}  #{value.inspect} — #{reason}"
        end
      end

      # -- language (P18-4, rehomed P19-1): the code desk reference ---------------

      # THE canonical-memory migration (P19-1, owner-fired): ledger
      # language_notes (+ the retired seed yml, when a checkout still has
      # one) → canonical/local-language/<code>.md dossiers. Absence-filling
      # and idempotent — safe to re-run; a dossier lane that already exists
      # (a redirected accretion landed first, or the owner edited) is never
      # overwritten. After it: bin/nabu sync local-language derives the
      # catalog records the card reads.
      def export_language_dossiers(config)
        ledger = open_ledger(config)
        dir = Nabu::LanguageShelf.dir(config)
        seed = File.join(config.config_dir, "languages.yml")
        report = Nabu::LanguageDossierExport.new(ledger: ledger, dir: dir,
                                                 seed_path: File.file?(seed) ? seed : nil)
                                            .run!(dry_run: options[:"dry-run"])
        verb = options[:"dry-run"] ? "would write" : "wrote"
        line = "dossiers: #{verb} #{report.written}, #{report.unchanged} unchanged"
        line += ", #{report.lanes_kept} lane(s) kept (already in a dossier)" if report.lanes_kept.positive?
        say "#{line} → #{dir}"
        say "next: bin/nabu sync local-language (derives the catalog records)" unless options[:"dry-run"]
      ensure
        ledger&.disconnect
      end

      # The card: headline (code — name), family line, curated context (or
      # the family's, labeled; or an honest absence), accreted extra-kind
      # notes (P18-5 — "iecor: IE-CoR variety: …", one line per kind), then
      # live relevance with zero fields suppressed, then the P57-4 stage
      # ladder (when Lects is present and the anchor has registered stages —
      # card-worthy on its own even when nothing else about the bare code is
      # curated: a real ladder is content, not a miss). An unknown code
      # misses honestly, with a family hint when the prefix is a known family.
      def print_language_card(code, languages, info, registry: nil, lects: nil, dossiers: nil, notes: [])
        # P85-A4: the published curated overlay (nabu-data mul/language-
        # dossiers) fills any curated lane the instance's own local dossiers
        # leave absent — identical content on the originating box (local wins),
        # the same context on a fresh install that has only the overlay.
        overlay = dossiers&.dossier(code)
        name = languages.name(code) || overlay&.name
        context = languages.context(code) || overlay&.context
        extras = languages.extra_notes(code)
        extras = overlay.extras.merge(extras) if overlay
        fallback = languages.family_fallback(code)
        relevance = info&.relevance(code)
        held = relevance && !relevance.empty?
        stages = lects&.stages_of(code) || []
        # P67-2: a registered lect anchor is never an unknown code —
        # the registry names it and its descent line renders even with zero
        # holdings (the Aramaic-fan anchors are exactly this case).
        registry_record = lects&.lect(code)
        override_readings = lects&.override_sources(code) || {}
        unless name || context || held || extras.any? || stages.any? || registry_record || overlay ||
               notes.any? || override_readings.any?
          return print_language_miss(code, fallback)
        end

        say "#{code} — #{name || registry_record&.name || '(no name in the held kaikki extracts)'}"
        print_language_override_readings(code, override_readings, lects)
        print_language_family(code, languages, fallback, overlay_family: overlay&.family)
        print_language_descent(code, lects)
        print_language_context(context, fallback)
        # The accreted dossier "stages" section (Nabu::LectDossiers) never
        # renders here — the card owns the LIVE ladder below (same registry
        # facts plus per-stage holdings); printing both would double the
        # surface. Every other accreted kind renders as before.
        extras.except(Nabu::LectDossiers::KIND).each { |kind, body| say_wrapped("#{kind}: #{body}", indent: 2) }
        print_language_witnesses(code, languages)
        print_language_notes(notes)
        print_language_relevance(code, relevance) if relevance
        print_language_dictionary_group(code, info, lects) if info
        print_language_axes(code, info, registry)
        print_language_stage_ladder(code, stages, lects, info)
      end

      # The claim gloss for per-source override codes (owner ruling
      # 2026-10-12): where a collection's legacy code is overridden onto a
      # registered lect, the card states that reading in words — the bare
      # code's ISO assignment may name a different language entirely, and
      # a count surface listing the raw code must never leave that
      # unglossed.
      def print_language_override_readings(code, readings, lects)
        readings.each do |source, lect_id|
          record = lects.lect(lect_id)
          named = record ? "#{record.name} (#{lect_id})" : lect_id
          say_wrapped("collection override: #{source} reads #{code} as #{named} — " \
                      "the collection's own usage, not the code's ISO assignment",
                      indent: 2)
        end
      end

      # P67-2: the descent line — the registry's parent arc, code →
      # root (jpa ← arc ← …), each ancestor named through the same
      # stage-aware walk `parent_of` defines (chu ← sla:pro ← ine-bsl ←
      # ine). Absent registry or a rootless code: no line. A cycle guard
      # rides belt-and-braces (the registry validator already refuses
      # cycles upstream).
      def print_language_descent(code, lects)
        return unless lects

        chain = []
        seen = { code.to_s => true }
        cursor = code.to_s
        while (parent = lects.parent_of(cursor))
          break if seen[parent]

          seen[parent] = true
          chain << parent
          cursor = parent
        end
        return if chain.empty?

        rendered = chain.map do |id|
          record = lects.lect(id)
          record ? "#{id} (#{record.name})" : id
        end
        say "  descent (nabu-lects): #{code} ← #{rendered.join(' ← ')}"
      end

      # P57-4: the stage ladder — every registered stage of +code+ (ord-
      # sorted, already Nabu::Lects#stages_of's contract), each with its
      # band and LIVE holdings: every (language, source) pair the catalog
      # actually carries, resolved through Nabu::Lects#resolve and grouped
      # by resolved lect. A bare-anchor resolution (no stage of its own —
      # still filed under the anchor itself, or reached one whose stage this
      # card does not list) groups under one honest "unstaged" line. A
      # resolution to a DIFFERENT anchor entirely (derom's la-vul -> roa:pro)
      # never enters this ladder — it is a different code's holdings.
      # Reconstructed stages (registry mode: reconstructed) carry the same
      # leading asterisk the etym/define shelves use.
      def print_language_stage_ladder(code, stages, lects, info)
        varieties = lects&.varieties_of(code) || []
        return if (stages.empty? && varieties.empty?) || !info

        totals, variety_totals =
          if info.lect_materialized?
            ladder_totals_from_facets(code, info)
          else
            ladder_totals_from_pairs(code, lects, info)
          end
        return if totals.values.sum.zero? && variety_totals.values.sum.zero?

        if stages.any?
          say "  stages:"
          stages.each do |stage|
            star = stage.mode == :reconstructed ? "*" : ""
            # P76 U-7: an approximate/conventional band_note renders as
            # "ca." on the span — the doctrine's probable tier, the note's
            # own word staying in the registry (conventions §12).
            circa = Nabu::Certainty.tier(:band_note, stage.band_note) == "probable" ? "ca. " : ""
            band = stage.band ? " (#{circa}#{Nabu::Timeline.format_span(stage.band[0], stage.band[1])})" : ""
            say "    #{star}#{stage.stage}  #{stage.name}#{band} — #{plural(totals[stage.id], 'document')}"
          end
        end
        # P58 rider (the owner's zho probe): registered REGISTERS are ladder
        # content — zho/lit is wenyan, not "unstaged". P59-2 (the compose
        # rules): the register line counts EVERY document carrying the
        # variety — stage-less resolutions AND staged-and-varietied ones
        # (akk:na/lit); the latter still fold under their stage above, so
        # the stage column sums to the corpus while the register column
        # reads as an overlay.
        if varieties.any?
          say "  registers:"
          varieties.each do |variety|
            title = variety.name.split(" — ", 2).last
            say "    /#{variety.variety}  #{title} — #{plural(variety_totals[variety.variety], 'document')}"
          end
        end
        unstaged = totals[:unstaged]
        say "    unstaged  — #{plural(unstaged, 'document')}" if unstaged.positive?
      end

      # P58-6: once a materialization exists, the ladder reads the lect
      # facet — the only source that sees per-DOCUMENT journal rulings.
      # Values under other anchors (derom's la-vul -> roa:pro) drop here
      # exactly as they did on the pairs path.
      # Returns [totals, variety_totals]: totals keys stage/register ladder
      # lines (staged-and-varietied folds under its stage); variety_totals
      # counts every carrier of a variety, staged or not — the register
      # line's overlay count (P59-2).
      def ladder_totals_from_facets(code, info)
        totals = Hash.new(0)
        variety_totals = Hash.new(0)
        facet_counts, identity = info.lect_facet_totals(code)
        facet_counts.each do |value, count|
          match = Nabu::Lects.parse_id(value)
          next unless match && match[:anchor] == code.to_s

          totals[ladder_key(code, match)] += count
          variety_totals[match[:variety]] += count if match[:variety]
        end
        totals[:unstaged] += identity if identity.positive?
        [totals, variety_totals]
      end

      # Stage wins (lat:late/ecc groups under lat:late); a stage-less
      # variety is a register line (zho/lit); everything else is honest
      # unstaged.
      def ladder_key(code, match)
        return "#{code}:#{match[:stage]}" if match[:stage]
        return "#{code}/#{match[:variety]}" if match[:variety]

        :unstaged
      end

      # The P57-4 path — a never-materialized catalog resolves (language,
      # source) pairs live, byte-identically to before.
      def ladder_totals_from_pairs(code, lects, info)
        totals = Hash.new(0)
        variety_totals = Hash.new(0)
        info.language_source_pairs.each do |(language, source_slug), count|
          resolved = lects.resolve(language, source: source_slug)
          match = Nabu::Lects.parse_id(resolved)
          next unless match && match[:anchor] == code.to_s

          totals[ladder_key(code, match)] += count
          variety_totals[match[:variety]] += count if match[:variety]
        end
        [totals, variety_totals]
      end

      # P48-r3: the related research desks — every axis whose member
      # sources hold this code (≥1 live document or a dictionary shelf),
      # in ratified (file) order. A code held by no axis-tagged source
      # prints nothing (the house zero-field rule).
      # P49-r4: multilingual packs (the registry marker) never attribute —
      # a pack's whole-grain axes union describes no single held language,
      # so its three hbo docs must not drag twelve desks onto the hbo card.
      # The desks keep the code via any DEDICATED source that holds it.
      # The simple exclusion was chosen over a dominance/share threshold
      # deliberately (era-bound-constants doctrine): any tuned cutoff is a
      # census claim that rots as packs grow, while "packs never attribute,
      # dedicated holders always do" stays true at every census. A pack-only
      # code honestly gets no axes line; its desks still surface the code
      # WITH COUNTS on the axis card's languages: line — the deliberate
      # asymmetry (counts are the honesty mechanism there, print_axis_languages).
      def print_language_axes(code, info, registry)
        return unless info && registry && !registry.axes.empty?

        slugs = info.holding_slugs(code).reject { |slug| registry.multilingual?(slug) }
        return if slugs.empty?

        names = registry.axes.each_axis.map(&:name)
                        .select { |name| registry.axis_members(name).intersect?(slugs) }
        say "  axes: #{names.join(', ')}" unless names.empty?
      end

      # P18-6: the per-source witness notes (kind "witness:<slug>" — what
      # each held source says about this language stage; LIV/EDL accrete
      # them at sync with per-record provenance). One wrapped line per
      # source, quiet when none.
      def print_language_witnesses(code, languages)
        languages.witnesses(code).each do |source, body|
          say_wrapped("witness (#{source}): #{body}", indent: 2)
        end
      end

      def print_language_miss(code, fallback)
        say "#{code} — unknown here: no held text, no shelf, no etymology edge, " \
            "and no name in the held kaikki extracts"
        if fallback
          hint = [fallback.name, fallback.context].compact.join(": ")
          say_wrapped("family hint: #{fallback.code}-* — #{hint}", indent: 2)
        end
        say "  held languages: nabu language --list"
      end

      def print_language_family(code, languages, fallback, overlay_family: nil)
        family = languages.family(code) || overlay_family
        if family
          say_wrapped("family: #{family}", indent: 2)
        elsif fallback&.name
          say_wrapped("family: #{fallback.code}-* — #{fallback.name}", indent: 2)
        end
      end

      # P85-A (owner-ruled 2026-08-28): the private language-note layer — the owner's own
      # per-language notes (`nabu note <code> "…"`), kept local/ and never
      # published, composed beneath the universal overlay. Absent = nothing
      # printed (binding honesty).
      def print_language_notes(notes)
        return if notes.empty?

        say "  notes (private):"
        notes.each { |note| say_wrapped("#{note.note}#{note_tags_fragment(note)}", indent: 4) }
      end

      def print_language_context(context, fallback)
        if context
          say_wrapped(context, indent: 2)
        elsif fallback&.context
          say_wrapped("(no curated note for this code — its #{fallback.code}-* family:) " \
                      "#{fallback.context}", indent: 2)
        else
          say "  (no curated note)"
        end
      end

      def print_language_relevance(code, rel)
        corpus = []
        corpus << plural(rel.documents, "document") if rel.documents.positive?
        corpus << "#{commas(rel.passages)} passages" if rel.passages.positive?
        say "  corpus: #{corpus.join(' · ')}" unless corpus.empty?
        say "  gold lemmas: #{commas(rel.lemma_rows)} rows (nabu search --lemma)" if rel.lemma_rows.positive?
        unless rel.shelves.empty?
          shelf_list = rel.shelves.map { |shelf| "#{shelf.title} (#{commas(shelf.entries)} entries)" }
          say "  dictionary: #{shelf_list.join(' · ')}"
        end
        say "  etymology: #{commas(rel.reflex_edges)} reflex #{rel.reflex_edges == 1 ? 'edge' : 'edges'}" \
          if rel.reflex_edges.positive?
        print_language_long(code, rel) if options[:long]
      end

      # P106-3 (owner ruling, generalization 2): the dictionary GROUP — every shelf whose lect
      # resolution lands at or under this code's node, off the
      # dictionary_stats census. Renders only when the group is WIDER than
      # the code's own shelves (the relevance block above already lists
      # those); a group of one code adds nothing. Feature-off (no census
      # derived yet, or no group): silent — the card is unchanged.
      def print_language_dictionary_group(code, info, lects)
        # const: render cap — the group line is a summary, not a listing
        cap = 8
        group = info.dictionary_group(code, lects: lects)
        return unless group&.node
        return if group.rows.empty? || group.rows.all? { |row| row[:language] == code.to_s }

        count = group.rows.size
        say "  dictionary group (#{group.node}): #{count} #{count == 1 ? 'dictionary' : 'dictionaries'} · " \
            "#{commas(group.total)} entries"
        shown = group.rows.first(cap)
        shown.each do |row|
          code_note = row[:language] == code.to_s ? "" : " · #{row[:language]}"
          say "    #{row[:slug]} — #{commas(row[:entries])} entries#{code_note}"
        end
        hidden = group.rows.size - shown.size
        say "    … #{hidden} more" if hidden.positive?
      end

      # --long: per-source document counts and the upstream-code split of
      # the etymology edges (chu's edges arrive as Wiktionary's "cu").
      def print_language_long(code, rel)
        unless rel.sources.empty?
          say "  by source: #{rel.sources.map { |slug, docs| "#{slug} #{commas(docs)}" }.join(' · ')}"
        end
        return unless rel.edge_codes.any? && rel.edge_codes.keys != [code]

        say "  edge codes: #{rel.edge_codes.map { |edge_code, n| "#{edge_code} #{commas(n)}" }.join(' · ')}"
      end

      # --list: the held languages only (a full dump of the ~800-code
      # etymology tail would be unusable and unpageable; the tail is what
      # `language CODE` is for — stated in the footer, never implied away).
      def print_language_list(languages, info, lects = nil)
        raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless info

        held = info.held
        say "held languages (#{held.size} with corpus documents, gold lemmas, or a shelf):"
        width = held.map { |entry| entry.code.length }.max || 0
        held.each do |entry|
          say "  #{entry.code.ljust(width)}  #{languages.name(entry.code) || '(unnamed)'} — " \
              "#{held_line(entry)}"
        end
        print_registry_extension(lects)
        say "etymology tail: ~800 more codes appear in reflex edges — nabu language CODE explains any"
      end

      # P90-5 (lane 1): the nabu-lects layer the listing was missing —
      # every anchor with minted stages/varieties, i.e. the lect ids the
      # cards, `search --lect` and the postures accept beyond bare codes.
      def print_registry_extension(lects)
        unless lects
          say "registry extension: nabu-lects not synced (nabu sync nabu-lects)"
          return
        end
        ladders = lects.ladders
        say "registry extension (nabu-lects): #{ladders.size} anchors carry minted stages/varieties " \
            "— ids like grc:koi work on cards, --lect and postures:"
        width = ladders.map { |ladder| ladder.anchor.length }.max || 0
        ladders.each do |ladder|
          bits = []
          bits << "stages: #{ladder.stages.join(' ')}" unless ladder.stages.empty?
          bits << "varieties: #{ladder.varieties.join(' ')}" unless ladder.varieties.empty?
          say "  #{ladder.anchor.ljust(width)}  #{ladder.name} — #{bits.join(' · ')}"
        end
      end

      def held_line(entry)
        bits = []
        bits << "#{commas(entry.documents)} docs" if entry.documents.positive?
        bits << "#{commas(entry.lemma_rows)} lemma rows" if entry.lemma_rows.positive?
        (bits + entry.shelves).join(" · ")
      end
    end
  end
end
