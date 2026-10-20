# frozen_string_literal: true

require "io/console"
require "thor"
require_relative "version"
require_relative "display"
require_relative "duration_format"
require_relative "cli/data"
require_relative "cli/lect"
require_relative "cli/layer"
require_relative "cli/index"
require_relative "cli/creds"
require_relative "cli/export"

# CLI flag conventions (P90-3 standing rules, applied whenever a command is
# next touched — never as a sweep):
#   ① `--lang` is the ONE language-filter spelling, accepting a comma list
#      where plural makes sense; legacy spellings (`--langs`, `--languages`)
#      stay as quiet aliases of it.
#   ② `--json` is the machine-readable opt-in convention (`--format` is
#      reserved for commands with more than two real formats).
module Nabu
  # Command-line entry point. Only `version` is functional in Phase 0; the
  # ingest/query subcommands are stubs that report "not implemented" and exit 1
  # so scripts and CI can rely on the failure signal before the real work lands.
  class CLI < Thor
    include DurationFormat

    # The DataCLI namespace note applies at the root too: without it Thor
    # 1.5's `tree` labels its root with the class auto-namespace ("nabu:c_l_i").
    namespace "nabu"

    # The tag-semantics note the axis-grouped surfaces (`list --axis`,
    # `status --axis`, P35-1) state ONCE: axes are TAGS over the source list,
    # so a source appears under every axis it serves — never a folder owning it.
    AXIS_TAG_NOTE = "Axes are tags, not folders — a source appears under every desk it serves."

    # Raise Thor::Error (rather than aborting the process abruptly) so failures
    # surface a clean stderr message and a non-zero exit status.
    def self.exit_on_failure?
      true
    end

    # `nabu search --help` (owner report 2026-07-18): this Thor build does
    # not intercept a help flag AFTER a command name, so "--help" reached
    # FTS5 as the literal query. Route `nabu CMD --help|-h` to `nabu help
    # CMD` for every known command; a literal "--help" stays searchable via
    # quoting inside a longer query (the fts literal fallback).
    def self.start(given_args = ARGV, config = {})
      if Thor::HELP_MAPPINGS.include?(given_args[1]) &&
         all_commands.key?(normalize_command_name(given_args.first.to_s))
        given_args = ["help", given_args.first]
      end
      # P44-i1b: a ^C is an OPERATOR DECISION, not a crash — one honest line
      # and the conventional 130, never a thread-backtrace storm. (Open3's
      # internal reader threads also die noisily at interrupt; bin/nabu turns
      # their report_on_exception chatter off.) State safety is the atomic
      # fetchers' job — an interrupted acquisition leaves staging debris the
      # next run sweeps, announced.
      super
    rescue Interrupt
      warn "\ninterrupted — partial work is staged safely; the next run cleans up and starts fresh."
      exit 130
    end

    # The --display flag, shared by every command that renders passage text to
    # the terminal (P27-0: show, align, search, concord, parallels, cognates).
    # Modes come from the Nabu::Display registry so sibling packets can add
    # modes (reading, …) without touching this declaration.
    def self.display_option
      option :display, type: :string, default: Nabu::Display::DEFAULT_MODE, banner: "MODE",
                       desc: "Display mode: default (config/display.yml policies), " \
                             "full (every stored byte, no transforms), plain (strip all " \
                             "defined mark classes), reading (edition apparatus simplified, " \
                             "qere read), diplomatic (edition marks as stored), " \
                             "translit (romanized rendering), " \
                             "mono (default without token colors) — see docs/display.md"
    end

    desc "version", "Print the Nabu version"
    def version
      say Nabu::VERSION
    end

    desc "data SUBCOMMAND ...ARGS", "The nabu-data production rail: document and build publishable derived datasets"
    subcommand "data", DataCLI

    desc "lect SUBCOMMAND ...ARGS", "Per-document lect rulings: the journaled overlay tier of lect resolution"
    subcommand "lect", LectCLI

    desc "creds SUBCOMMAND ...ARGS", "Stored upstream credentials (gated member areas): set, list"
    subcommand "creds", CredsCLI

    # P61-2: `nabu layer` is the core-layers front door — today one
    # command, `suggest`, the generalized census (lect + dating + places +
    # script sections). `nabu lect suggest` stays as the historical alias;
    # both run the same report.
    desc "layer SUBCOMMAND ...ARGS", "Core-layer postures: the generalized suggest front door"
    subcommand "layer", LayerCLI

    # P112-3: the fulltext-index operations surface — gauges,
    # freshness stamps, and the standalone merge consolidation.
    desc "index SUBCOMMAND ...ARGS", "Fulltext-index operations: doctor (gauges + freshness)"
    subcommand "index", IndexCLI

    desc "migrate-local", "Move the instance files (rulings, grants, profile…) from config/ to local/config/ (P71)"
    def migrate_local
      config = Nabu::Config.load
      result = Nabu::LocalMigration.run(config: config)
      result.moved.each do |name|
        from, to = if name == Nabu::Config::HISTORY_DB_FILENAME
                     ["db/", "local/"]
                   elsif Nabu::LocalMigration::SHELF_SLUGS.include?(name)
                     ["canonical/", "local/shelves/"]
                   else
                     ["config/", "local/config/"]
                   end
        say "moved   #{from}#{name} -> #{to}#{name}"
      end
      result.conflicts.each do |name|
        say "CONFLICT: #{name} exists at BOTH its legacy home and local/ — the local copy governs; " \
            "reconcile and delete the straggler by hand", :yellow
      end
      say "nothing to move — the local/ layout is current" if result.moved.empty? && result.conflicts.empty?
    end

    desc "rebuild", "Rebuild the derived db/ from canonical/ (parse-only; no fetch)"
    option :dry_run, type: :boolean, default: false,
                     desc: "Print what would happen and change nothing"
    option :profile, type: :boolean, default: false,
                     desc: "Print the per-source/per-stage timing table after the rebuild (P36-0)"
    option :incremental, type: :boolean, default: false,
                         desc: "Keep the catalog; re-derive only fingerprint-dirty sources " \
                               "(full rebuild remains the reference)"
    option :trust_stages, type: :boolean, default: false,
                          desc: "--incremental only (P87-3): mint the fulltext stage stamps at " \
                                "current versions without re-deriving — ONLY when this index " \
                                "was built by the current code"
    option :trust_derivations, type: :boolean, default: false,
                               desc: "--incremental only (P89-1): re-stamp parser-drift-only sources " \
                                     "without replay when git vouches their own parser files predate " \
                                     "the stamp — the bridge for a catalog built by current code"
    option :full_links, type: :boolean, default: false,
                        desc: "Carry no links scope this run: re-mine every recorded scope and " \
                              "compare the would-be-carried ones against their stamps (the " \
                              "self-check, forced now; it also runs every " \
                              "#{Nabu::LinkStamps::SELF_CHECK_EVERY}th links stage)"
    option :parse_workers, type: :numeric,
                           desc: "Forked parse workers for parallel-replay sources (1 = serial; " \
                                 "default: rebuild.parse_workers setting, else cores - 1, capped)"
    option :verbose, type: :boolean, default: false, desc: Nabu::Ops::StageGuide::OPTION_DESC
    def rebuild
      config = Nabu::Config.load
      parse_workers = rebuild_parse_workers(config)
      # P62 rider: rebuild DROPS the catalog — doing that under a live
      # writer corrupts nothing (derived data) but wastes both runs; the
      # pre-flight fails in a quarter second instead. Dry runs read only.
      Nabu::Store.assert_writable!(config.catalog_path) unless options[:dry_run]
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # db/ is derived data by design (architecture §1); dropping it is the whole
      # point, so a real run needs no confirmation. An empty registry has nothing
      # to replay.
      return say("Nothing to rebuild: no sources registered.") if registry.empty?
      return rebuild_incremental(config, registry, parse_workers) if options[:incremental]

      rebuilder = Nabu::Rebuild.new(config: config, registry: registry, full_links: options[:full_links],
                                    parse_workers: parse_workers)
      if options[:dry_run]
        # --profile implies nothing extra on a dry run: there is no run to time.
        print_plan(rebuilder.plan)
      else
        explain_command(:rebuild)
        result = rebuilder.run(progress: progress_reporter)
        finish_progress
        print_result(result)
        print_profile(result.profile) if options[:profile]
      end
    rescue Nabu::CatalogBusyError => e
      raise Thor::Error, e.message
    rescue Sequel::DatabaseError => e
      raise unless Nabu::Store.busy_error?(e)

      raise Thor::Error, "#{Nabu::CatalogBusyError.new(config.catalog_path).message} " \
                         "(a writer arrived mid-rebuild; rebuilds are simply re-run)"
    end

    desc "verify", "Re-hash canonical files against the catalog (bitrot/tamper check; cronnable)"
    def verify
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      result = Nabu::Verify.new(config: config, registry: registry, db: catalog).run
      print_verify(result)
      # A clean run returns normally (exit 0); any mismatch/missing/unparseable
      # exits 1 via the shared Thor::Error path, the report already on stdout.
      raise Thor::Error, verify_failure_summary(result) unless result.clean?
    ensure
      catalog&.disconnect
    end

    desc "health", "Source health checks (run-history trends + live golden replay; --remote for the upstream probe)"
    option :remote, type: :boolean, default: false,
                    desc: "Probe every registered upstream (git ls-remote + license drift); no cloning, no corpus fetch"
    option :backfill_pins, type: :boolean, default: false,
                           desc: "Record ledger pins for pre-ledger sources from local clones / state files; no network"
    option :all, type: :boolean, default: false,
                 desc: "The full board: check every source (modules + unfocused included) AND show every " \
                       "row (the default view prints findings only; ok/by-design rows fold into a rollup)"
    option :accept_creep, type: :string, banner: "SLUG",
                          desc: "Record owner acceptance of SLUG's current quarantine baseline " \
                                "(quiets the creep alarm; it re-arms past the accepted level)"
    option :accept_shed, type: :string, banner: "SLUG",
                         desc: "Record owner acceptance of SLUG's current withdrawal shed " \
                               "(quiets the creep alarm; it re-arms past the accepted level)"
    option :note, type: :string,
                  desc: "Optional rationale recorded with --accept-creep / --accept-shed"
    def health
      # Bare `health` is the local, no-network P5-5 check (run-history trends +
      # live golden replay). --remote is the P5-3 upstream probe.
      # --backfill-pins (P15-7) is the one-shot pin recovery. --accept-creep
      # (P43-0) books a reviewed creep anomaly durably in the ledger. Each
      # keeps its own helper, db lifetime, and exit-code raise.
      return run_backfill_pins if options[:backfill_pins]
      return run_accept_creep(options[:accept_creep]) if options[:accept_creep]
      return run_accept_shed(options[:accept_shed]) if options[:accept_shed]

      options[:remote] ? run_remote_health : run_local_health
    end

    desc "search QUERY", "Full-text search the corpus (FTS5 over folded text)"
    long_desc <<~HELP, wrap: false
      Full-text search over every live passage, bm25-ranked. Matching is
      diacritic- and case-insensitive on BOTH sides: μηνιν finds μῆνιν,
      ΜΗΝΙΝ finds both — type without accents, breathings, or iota
      subscripts and still hit the polytonic editions. The fold also matches
      modern Japanese reading habits: 学 finds 學, 弁 finds 辨/瓣/辯.

      EXACT (--exact): glyph-literal match — the query must appear in the
      passage's stored text exactly as typed (NFC-normalized, but nothing
      else: no diacritic strip, no case fold, no reform fold). Use it to tell a
      literal 弁 apart from the default's 弁/辨/瓣/辯. It runs the normal folded
      search for candidates, then keeps only glyph-literal hits — so it does
      not combine with --fuzzy/--near/--lemma/--morph or the character filters.

      WHOLE-WORD (--word): keep only hits where the query lands on a WORD
      BOUNDARY in the stored text — a fold-aware whole-word match. ἦ finds the
      standalone particle ἦ but NOT ἦμαρ (the query sits mid-word there); 学
      still folds to 學 but only as a whole word. A boundary is the start/end
      of the text or a non-letter (whitespace, punctuation — combining marks
      are word-internal, so accents never break a word). --word composes with
      --exact (word-AND-glyph exact: ἦ finds ἦ, not ἦμαρ nor a folded ἠ) and,
      alone, with the plain fold; it does NOT combine with
      --fuzzy/--near/--lemma/--morph or the character filters. Spaceless scripts
      have no word boundaries: --word on a query containing Han or kana is
      REFUSED (use --exact for glyph-literal matching there). Hangul is
      space-delimited, so --word treats it like any alphabetic script.

      BROWSE (term-less): run search with NO query to LIST the corpus, but only
      when at least one CONTENT-NARROWING filter is present — a date window
      (--from/--to/--century), --date-basis, --place, a genre facet (--type/--province/
      --material), or --loans. The page is served in corpus order (no ranking),
      the standard hit rendering with a stored-text window per passage, --limit
      honored. --lang/--license/--source/--axis select whole shelves and are NOT
      sufficient on their own — a term-less listing of a whole language is a
      dump, not a browse — so combine them WITH a content filter to scope one
      (`--century 2 --axis epigraphy` lists the 2nd-c. inscriptions). The
      character-structure filters (--radical/--strokes/--char-component) are a
      separate term-less path of their own.

      Query syntax (SQLite FTS5 over the folded text):
        μηνιν αειδε          all words must appear in the passage (implicit AND)
        '"μηνιν αειδε"'      exact adjacent phrase — FTS quotes, so shell-quote them
        μηνι*                prefix match (μῆνιν, μηνίω, μήνιμα, …)
      Boolean OR/NOT are not supported: operators are folded to lowercase
      and become ordinary search terms.

      Each hit prints the passage urn, its language, and a folded snippet
      with the match in [brackets] (on an interactive terminal, RTL scripts
      highlight the match in reverse video instead — bracket glyphs do not
      survive bidi reordering; piped output keeps the brackets). The snippet is the SEARCH form, not the
      edition text — `nabu show <urn>` gives the pristine passage. DDbDP
      papyri render lost text as the […] gap marker.

      Filters (combinable):
        --lang     ISO-639-3 passage language: grc, lat, got, chu, orv, san, …
        --license  effective license class (document override beats source):
                   open, attribution, nc, research_private, restricted
        --source   one source slug (nabu list names them); composes with
                   every other filter, --lemma/--near/--fuzzy included
        --limit    maximum hits, default 20

      LEMMA SEARCH (--lemma FORM): exact dictionary-form lookup over the
      gold treebank annotations (UD, PROIEL, TOROT — the sources that carry
      per-token lemmas). One lemma finds every inflected attestation, even
      suppletive stems no text query can reach: --lemma λέγω hits λέγουσι,
      λέγοιεν, AND εἶπας/εἰπεῖν. Hits show the dictionary form, the surface
      form(s) that matched, and the pristine passage line. Diacritics are
      optional on the query, exactly as in text search (λεγω works; so does
      final-sigma-insensitive λόγος/λογοσ). --lemma REPLACES the text query
      (combining both is not supported); it composes with --lang, --limit,
      and --license. Passages outside the treebanks carry no lemma
      annotations and are honestly absent here.

      MORPH FACETS (--morph case=dat,number=pl): with --lemma, narrow to
      attestations whose morphology matches the given facets (comma-joined
      key=value, all required). The vocabulary is Universal Dependencies
      feature names — case, number, gender, person, tense, mood, voice,
      degree (values dat, pl/sg, masc, aor, opt, sub…); UD treebanks match on
      their `feats`, PROIEL/TOROT and GLAUx (AGDT postag) are decoded from
      their positional tags into the same names. Each hit shows the matching surface form(s) and the
      decoded morph evidence. --morph REQUIRES --lemma (bare morphology search
      is out of scope); ORACC carries no inflectional morphology, so
      inflectional facets never match it (honest absence). See conventions §6.1.

      PROXIMITY (A --near B [--window N]): keep only hits where B occurs
      within N words of A in the SAME passage — λόγος near θεός is John 1:1.
      Built on FTS5 NEAR over the folded search forms: --window N is the max
      words BETWEEN the two terms (default 10; 0 = immediately adjacent), and
      NEAR is order-independent (A…B and B…A both count). The window counts
      folded tokens, so for cuneiform (akk/sux), where sign-joins and
      determinatives fold to spaces, one transliterated word spans several
      tokens and the window reads tighter. --near composes with --lemma (the
      anchor then expands to the lemma's attested surface forms before the
      NEAR: --lemma λέγω --near κύριος finds εἶπε near κύριος too), and with
      --lang/--license/--limit. Cross-passage adjacency is OUT — the passage
      is the unit. --morph does not compose with --near (out of scope). Both
      matched terms are bracketed in the snippet, shown in the stored text
      (the pristine spelling, not the folded search form).

      FUZZY (--fuzzy): substring/fragment search for damaged texts — matches
      the fragment ANYWHERE in a passage, mid-word included, where normal
      search sees only whole words and prefixes. Type the fragment straight
      off the edition: editorial square brackets are stripped from the query
      before matching, so `']μηνιν αει['` works as typed. Built on a
      character-trigram index over the folded search form (same
      diacritic/case folding as plain search), so fragments need at least 3
      characters. Scope is DOCUMENTARY sources only (papyri-ddbdp, oracc,
      edh, open-etruscan, edr, elephantine — registry `fuzzy_index: true`):
      papyrus lines, tablets and damaged inscriptions are where fragment
      search earns its index bytes; every result footer names the
      live scope. For half-remembered LITERARY quotations use plain search
      or `nabu parallels` — the literary corpus is deliberately not
      trigram-indexed (it would grow the index 15×). Composes with --lang,
      --limit, --license, and --from/--to/--century/--place; --long prints
      the full folded passage instead of the windowed snippet. --fuzzy
      replaces the FTS query syntax: the fragment is matched literally
      (no AND/phrase/prefix operators) and does not combine with
      --lemma/--near/--morph.

      DATE BASIS (--date-basis CLASS[,CLASS...]): keep only documents whose
      PRIMARY date — the one `nabu show` renders — is of the named class:
      artifact (the source's own typed date of the object or witness),
      composition (attributed author-era dating), edition (a print year) or
      silver (a model/tool ESTIMATE from the local-dates shelf, projected by
      `nabu silver-dates --project`; any upstream date outranks it). With
      --from/--to/--century the window then reads that same primary date,
      so `--date-basis artifact --century 2` holds out author-era datings
      instead of mixing them in. Without --date-basis the date window reads
      upstream dates only — silver estimates answer only when named. An
      unknown class is refused naming the known set. Text search, --fuzzy,
      --scan and a term-less browse.

      FACETS (--type / --province / --material): document-grained categorical
      filters over the facet table (P17-2 — EDH inscriptions seed it: 22
      EAGLE inscription types, 103 Roman provinces, materials). Patterns are
      case-insensitive and match the normalized term OR the upstream raw code
      (--type epitaph and --type titsep both work; % wildcards as in
      --place). They compose with the text query, --fuzzy, and every
      date/place filter — the epigraphist's slice is
      `--type epitaph --province "Pannonia inferior" --century 2`. A document
      with no facet row falls out under an active filter (honest absence:
      only faceted sources — inscriptions — can match). Like the date
      filters they do not combine with --lemma/--near. Facet rows land at
      `nabu rebuild` (like the timeline).

      --facet NAME=PATTERN is the generic form: any facet name, repeatable
      (each one must hold). A name is one axis across both grains — the
      document facets (okhc collection, cdli material, author …) AND the
      passage facets projected from per-article annotations (sillok
      subject, itkc genre), which narrow to the very passage that carries
      the claim: `--facet subject=왕실-%` lists Sillok articles under the
      royal-house subject tree. The pattern matches the value or the
      authority ref. --type/--province/--material are shorthands for
      --facet genre=/province=/material=.

      LOANS (--loans CODE): the language-contact facet (P34-2, reading the
      P17-1 annotations) — keep only passages carrying at least one token
      the corpus tags as borrowed from CODE. Passage-grained and read
      straight off each passage's stored token annotations: no reparse, no
      rebuild step. Codes are the mapped origins grc / hbo / arc / lat /
      egy plus any verbatim upstream name (Akkadian, Arabic, Phoenician,
      Persian…), matched case-insensitively; an unattested code finds
      nothing, honestly. Today the Coptic Scriptorium shelf carries the
      layer (~56k of its passages bear Greek loan tokens). Unlike the
      document facets, --loans composes with EVERYTHING: the text query,
      --fuzzy, --lemma/--morph, --near, and all of --lang/--license/
      --source/date/place/facet filters — the loans corpus is
      gold-lemmatized, so `--lemma ⲛⲟⲩⲧⲉ --loans grc` is the designed
      move (attestations of a Coptic lemma in Greek-loan-bearing verses).
      `nabu list coptic-scriptorium --loans` is the census view.

      Sources ingesting parallel translations (registry `translations: true`,
      P7-4) make those English passages ordinary search hits; --lang eng
      scopes to them, --lang grc keeps them out. `show <hit> --parallel`
      jumps from either side to the aligned line in the other.

      Examples:
        nabu search μηνιν                          # finds μῆνιν, accents optional
        nabu search '"ανδρα μοι εννεπε"'           # Odyssey 1.1 — including the
                                                   #   papyri that quote it
        nabu search sapientia --lang lat           # Latin corpus only
        nabu search μηνι* --lang grc               # every derivative of the stem
        nabu search αγαπη --license attribution    # only freely re-usable hits
        nabu search "rich-haired" --lang eng       # the ingested translations
        nabu search --lemma λέγω --lang grc        # every attestation in the Greek
                                                   #   treebank: λέγουσι, εἶπας, εἰπεῖν…
        nabu search --lemma tu --lang lat          # te, tibi, tu across PROIEL Cicero
        nabu search --lemma λόγος --morph case=dat,number=pl
                                                   # only the dative-plural λόγοις
        nabu search λόγος --near θεός --window 5    # λόγος within 5 words of θεός
                                                   #   (John 1:1 and its kin)
        nabu search --lemma λέγω --near κύριος      # every inflection of λέγω
                                                   #   near κύριος: τάδε λέγει κύριος
        nabu search --fuzzy ']μηνιν αει['           # a damaged scrap, brackets and
                                                   #   all — infix match, papyri+oracc
        nabu search --fuzzy στρατηγ --century 6     # mid-word fragment, 6th c. papyri
        nabu search --century 2 --axis epigraphy    # term-less browse: the 2nd-c.
                                                   #   inscriptions, corpus order
        nabu search "dis manibus" --type epitaph --province "Germania superior"
                                                   # the D M formula on epitaphs of
                                                   #   one province (EDH facets)
        nabu search 大王大妃 --facet subject=왕실-의식%   # Sillok articles on royal rites
        nabu search --fuzzy "votum solvit" --type "votive%" --material Sandstein
                                                   # V S L M on sandstone votives
        nabu search ⲡⲛⲟⲩⲧⲉ --loans grc --lang cop   # "God" in verses that carry
                                                   #   Greek loan tokens
        nabu search arma --meter H                  # hits restricted to scanned
                                                    #   hexameters (P44 meter layer:
                                                    #   pedecerto/hypotactic)
        nabu search --meter P --lang lat            # term-less browse: every scanned
                                                    #   pentameter line
        nabu search --lemma ⲕⲁϩ --loans grc         # a Coptic lemma's attestations
                                                   #   inside the Greek-contact zone

      Use cases: find a half-remembered line; concordance-style scans of a
      word across six corpora at once; checking which sources attest a term
      (and under what license) before an export.
    HELP
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    option :source, type: :string, banner: "SLUG",
                    desc: "Restrict to one source (`nabu list` names the slugs)"
    option :axis, type: :string, banner: "NAME[,NAME...]",
                  desc: "Restrict to the members of one or more research axes (config/axes.yml) — the " \
                        "multi-source generalization of --source; composes with every path and filter"
    option :limit, type: :numeric, default: 20, desc: "Maximum number of hits"
    option :lemma, type: :string, banner: "FORM",
                   desc: "Exact-lemma search over the gold treebanks (replaces the text query)"
    option :morph, type: :string, banner: "FACETS",
                   desc: "Morphology facets (with --lemma), e.g. case=dat,number=pl"
    option :near, type: :string, banner: "TERM",
                  desc: "Proximity: keep only hits where TERM is within --window words of the query/lemma"
    option :window, type: :numeric, default: Nabu::Query::Proximity::DEFAULT_WINDOW,
                    desc: "Max words between the two --near terms (default " \
                          "#{Nabu::Query::Proximity::DEFAULT_WINDOW}; 0 = adjacent)"
    option :from, type: :numeric, banner: "YEAR",
                  desc: "Earliest date: signed historical year, negative = BCE (-300 = 300 BCE, no year 0)"
    option :to, type: :numeric, banner: "YEAR",
                desc: "Latest date: signed historical year (14 = 14 CE); composes with --from"
    option :century, type: :numeric, banner: "N",
                     desc: "Shorthand for one century's --from/--to (6 = 6th c. CE, -2 = 2nd c. BCE)"
    option :date_basis, type: :string, banner: "CLASS[,CLASS...]",
                        desc: "Date-basis filter: keep documents whose primary date is of this class " \
                              "(artifact, composition, edition, silver); with --from/--to the window " \
                              "reads that same date"
    option :place, type: :string, banner: "NAME|ns:id",
                   desc: "Provenance filter: a namespaced ref (tm:2810, cigs:GIR), a name resolved " \
                         "to its identities + name match, or a LIKE pattern (oxyrhynch%)"
    option :script, type: :string, banner: "TAG",
                    desc: "Script filter, ISO 15924-style registry tag (latn, xsux): the held text's " \
                          "~script lect axis OR the artifact-script axis (\"Latin-script Gaulish\")"
    option :sign, type: :string, banner: "GLYPH|NAME",
                  desc: "Search by cuneiform sign (the inverse of nabu signs): 𒀝 or AK expands to " \
                        "an OR over the sign's OSL reading values; IS the query — give no term"
    option :within, type: :string, banner: "LAT,LON,KM",
                    desc: "Geo-radius filter over the coordinates lane (source-asserted " \
                          "find-locations, e.g. rundata): 59.86,17.64,50 keeps documents found " \
                          "within 50 km; coordinate-less documents fall out"
    option :scan, type: :boolean, default: false,
                  desc: "Filter-first mode: walk the term's matches in corpus order intersected " \
                        "with the active filters — deterministic, never sampled (the mode for " \
                        "a common term + a selective filter); needs a term AND a filter"
    option :type, type: :string, banner: "PATTERN",
                  desc: "Inscription-type facet filter (epitaph, votive%, or the raw titsep code)"
    option :kind, type: :string, banner: "CLASS[/SUB[/SUB]]",
                  desc: "Document-kind filter over the ruled cross-corpus classes: any path " \
                        "prefix matches its whole family (funerary ⊇ funerary/epitaph, " \
                        "literary/narrative ⊇ literary/narrative/epic), a full path narrows; " \
                        "unmapped and unknown are first-class (`nabu kind census` lists all)"
    option :province, type: :string, banner: "PATTERN",
                      desc: "Roman-province facet filter (Germania inferior, pannonia%)"
    option :material, type: :string, banner: "PATTERN",
                      desc: "Material facet filter (Marmor, sandstein%)"
    option :facet, type: :string, repeatable: true, banner: "NAME=PATTERN",
                   desc: "Any facet by name, at either grain — document facets (collection, author …) " \
                         "and passage facets (sillok subject, itkc genre): --facet subject=왕실-% " \
                         "matches value or ref, LIKE patterns pass through; repeatable (AND)"
    option :loans, type: :string, banner: "CODE",
                   desc: "Loan-origin facet: only passages with ≥1 token borrowed from CODE " \
                         "(grc, hbo, arc, lat, egy — Coptic Scriptorium)"
    option :meter, type: :string, banner: "CODE",
                   desc: "Meter facet: only passages carrying a meter enrichment with this code " \
                         "(pedecerto codes H, P, …) or name (hypotactic 'dactylic hexameter'); " \
                         "case-insensitive; composes with a text query or stands alone as a browse"
    option :meter_pattern, type: :string, banner: "PATTERN",
                           desc: "Meter facet: exact foot/scansion pattern (pedecerto DSDS, " \
                                 "hypotactic '-u u -uu …'); composes with --meter or stands alone"
    option :radical, type: :numeric, banner: "N",
                     desc: "Character filter: KangXi radical number 1-214 (Unihan kRSUnicode); " \
                           "composes with --strokes/--char-component and a text query"
    option :strokes, type: :string, banner: "A-B",
                     desc: "Character filter: total-stroke range A-B (or a single N; Unihan kTotalStrokes)"
    option :char_component, type: :string, banner: "C",
                            desc: "Character filter: characters CONTAINING C anywhere in their " \
                                  "structure (KRADFILE ∪ BabelStone IDS transitive containment)"
    option :charset, type: :string, banner: "CHARS",
                     desc: "Graded-reading filter (P72-1): only passages whose distinct Han " \
                           "characters fall INSIDE this set (fold-aware; spaces ignored); " \
                           "composes with a text query and --lang/--license/--source"
    option :signset, type: :string, banner: "SIGNS",
                     desc: "Sign-coverage filter for the ATF corpora (P77-r16, sign-learning P-3): " \
                           "only passages whose resolved OSL sign inventory falls inside this " \
                           "comma-separated set of sign names/values; composes with --max-foreign"
    option :max_foreign, type: :numeric, default: 0, banner: "N",
                         desc: "With --charset/--signset: allow up to N characters/signs outside " \
                               "the set per passage (0-3); each hit names its strangers"
    option :min_chars, type: :numeric, default: 0, banner: "N",
                       desc: "With --charset: only passages with at least N distinct Han " \
                             "characters — floors the cleanest-first order above one-char fragments"
    option :fuzzy, type: :boolean, default: false,
                   desc: "Substring/fragment search over the documentary trigram index (]μηνιν αει[)"
    option :withdrawn, type: :boolean, default: false,
                       desc: "Attic inspection: search WITHDRAWN passages only (upstream-gone " \
                             "documents, revision-pruned passages) — substring match over the " \
                             "folded text, each hit labeled with its reason; composes with " \
                             "--limit only"
    option :similar, type: :string, banner: "URN",
                     desc: "Semantic neighbors of one embedded passage (P93-5): " \
                           "same-language cross-edition retrieval over the nabu-embed vectors, " \
                           "rendered in bands (close/near/loose), model named in the header — " \
                           "IS the query (give no term); composes with --limit only"
    option :long, type: :boolean, default: false,
                  desc: "With --fuzzy: print the full folded passage instead of the windowed snippet"
    option :gold_only, type: :boolean, default: false,
                       desc: "With --lemma: gold (verified) annotations only — exclude silver " \
                             "(automatic) lemmatization and equivalence (scholar-curated " \
                             "Classical-Latin equivalents on non-Latin passages)"
    option :exact, type: :boolean, default: false,
                   desc: "Glyph-literal match; the default fold matches modern reading habits " \
                         "(学 finds 學, 弁 finds 辨/瓣/辯) — --exact does not"
    option :word, type: :boolean, default: false,
                  desc: "Whole-word match: the query must land on a word boundary in the stored " \
                        "text (ἦ finds ἦ, not ἦμαρ); refuses spaceless CJK/kana"
    option :words, type: :boolean, default: false,
                   desc: "Tibetan word-grain match (P54-4): keep only hits whose matched span " \
                         "aligns with word boundaries (nabu-data xct/segmentation) — Tibetan is " \
                         "indexed at syllable grain, so a plain query also lands on accidental " \
                         "runs across word boundaries; non-Tibetan queries or an unsynced module " \
                         "degrade to plain search with a note"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Lect filter (P57-4, nabu-lects module): keep only hits whose (language, " \
                        "source) resolves to this lect id or a more specific one under it " \
                        "(--lect lat matches lat:med; --lect lat:med matches lat:med and " \
                        "lat:med/xyz, not lat:cla). Text search or a term-less browse only, not " \
                        "--lemma/--near; errors if the nabu-lects module is not synced"
    display_option
    def search(query = nil)
      query = query.to_s.strip
      display_mode
      date_basis_filter
      if (options[:from] || options[:to] || options[:century] || options[:place] || facet_filters ||
          options[:date_basis]) &&
         (options[:near] || options[:lemma])
        raise Thor::Error, "search: --from/--to/--century/--date-basis/--place/--type/--province/--material/--facet " \
                           "compose with text search only, not --lemma/--near (the dated/faceted corpus — " \
                           "papyri, inscriptions — is not lemmatized)"
      end
      if options[:fuzzy] && (options[:near] || options[:lemma] || options[:morph])
        raise Thor::Error, "search: --fuzzy is literal substring matching — it does not combine " \
                           "with --lemma/--near/--morph"
      end
      if (options[:meter] || options[:meter_pattern]) &&
         (options[:near] || options[:lemma] || options[:fuzzy] || char_filter_options?)
        raise Thor::Error, "search: --meter/--meter-pattern filter the meter enrichment layer and " \
                           "compose with plain text search or a term-less browse only — not " \
                           "--lemma/--near/--fuzzy or the character-structure filters"
      end
      if options[:gold_only] && (!options[:lemma] || options[:near])
        raise Thor::Error, "search: --gold-only filters the lemma tier — it requires --lemma " \
                           "(and does not compose with --near)"
      end
      if options[:exact] && (options[:fuzzy] || options[:near] || options[:lemma] || options[:morph])
        raise Thor::Error, "search: --exact is glyph-literal substring matching over the plain " \
                           "text query — it does not combine with --fuzzy/--near/--lemma/--morph"
      end
      if options[:exact] && char_filter_options?
        raise Thor::Error, "search: --exact is a word-level glyph-literal filter — it does not " \
                           "combine with the character-structure filters (--radical/--strokes/--char-component)"
      end
      if options[:word] && (options[:fuzzy] || options[:near] || options[:lemma] || options[:morph] ||
                            char_filter_options?)
        raise Thor::Error, "search: --word is a whole-word filter over the plain text query — it " \
                           "composes only with --exact, not --fuzzy/--near/--lemma/--morph or the " \
                           "character-structure filters"
      end
      if options[:word] && (msg = Nabu::Query::Search.word_refusal_for(query))
        raise Thor::Error, "search: #{msg}"
      end
      if options[:words] && (query.empty? || options[:fuzzy] || options[:near] || options[:lemma] ||
                             options[:morph] || options[:exact] || options[:word] || char_filter_options?)
        raise Thor::Error, "search: --words is the Tibetan word-grain filter over the plain text " \
                           "query — it needs a text query and does not combine with --exact/--word/" \
                           "--fuzzy/--near/--lemma/--morph or the character-structure filters"
      end
      if options[:lect] && (options[:near] || options[:lemma] || options[:fuzzy] || char_filter_options?)
        raise Thor::Error, "search: --lect filters the lect-resolution layer and composes with " \
                           "plain text search or a term-less browse only — not --lemma/--near/" \
                           "--fuzzy or the character-structure filters"
      end

      if options[:charset]
        if options[:fuzzy] || options[:near] || options[:lemma] || options[:morph] ||
           options[:exact] || options[:word] || options[:words] || char_filter_options? ||
           options[:signset]
          raise Thor::Error, "search: --charset is the coverage filter over whole passages — it " \
                             "composes with a plain text query and --lang/--license/--source only"
        end
        return graded_search(query)
      end
      if options[:signset]
        if query || options[:fuzzy] || options[:near] || options[:lemma] || options[:morph] ||
           options[:exact] || options[:word] || options[:words] || char_filter_options?
          raise Thor::Error, "search: --signset is the sign-coverage filter over whole ATF passages " \
                             "— it composes with --max-foreign and --lang/--license/--source only"
        end
        return sign_graded_search
      end
      if options[:max_foreign].to_i.positive?
        raise Thor::Error, "search: --max-foreign only accompanies --charset or --signset"
      end

      if char_filter_options?
        if options[:fuzzy] || options[:near] || options[:lemma] || options[:morph]
          raise Thor::Error, "search: the character filters (--radical/--strokes/--char-component) are " \
                             "character-level structure search — they do not combine with the word-level " \
                             "--lemma/--near/--fuzzy/--morph (they compose with a plain text query)"
        end
        return char_structured_search(query)
      end
      if options[:similar]
        unless query.empty? && !options[:fuzzy] && !options[:near] && !options[:lemma] &&
               !options[:morph] && !options[:exact] && !options[:word] && !options[:scan] &&
               !options[:withdrawn] && !char_filter_options? && !options[:sign]
          raise Thor::Error, "search: --similar URN is the semantic-neighbors page — the urn IS " \
                             "the query (give no term); it composes with --limit only"
        end
        return similar_search(options[:similar])
      end
      if options[:withdrawn]
        if query.empty? || options[:fuzzy] || options[:near] || options[:lemma] || options[:morph] ||
           options[:exact] || options[:word] || options[:words] || options[:scan] ||
           char_filter_options? || options[:sign]
          raise Thor::Error, "search: --withdrawn is the attic inspection — a plain text query " \
                             "plus --limit only (the withdrawn set is small; filters would " \
                             "overpromise)"
        end
        return withdrawn_search(query)
      end
      return sign_search(query) if options[:sign]
      return scan_search(query) if options[:scan]
      return fuzzy_search(query) if options[:fuzzy]
      return proximity_search(query) if options[:near]
      return lemma_search(query) if options[:lemma]
      raise Thor::Error, "search: --morph requires --lemma (bare morphology search is out of scope)" if options[:morph]
      return browse_search if query.empty?

      validate_license!(options[:license])
      from, to = date_window
      place = options[:place]
      facets = facet_filters
      loans = loans_filter
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      # Either half of the derived store missing means the corpus was never
      # built/indexed; a search cannot run.
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

      require_timeline!(catalog) if from || to || place || options[:date_basis]
      require_facets!(catalog) if facets
      validate_source!(catalog, options[:source])
      axis_names, axis_slugs = axis_membership(command: "search", config: config)
      lects = require_lects!(config, options[:lect])

      searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext, lects: lects || :auto,
                                         places: Nabu::Places.load_default(canonical_dir: config.canonical_dir))
      results = searcher.run(query, lang: options[:lang], license: options[:license],
                                    limit: options[:limit].to_i, from: from, to: to, place: place,
                                    date_basis: date_basis_filter,
                                    facets: facets, source: options[:source], sources: axis_slugs,
                                    loans: loans, meter: options[:meter],
                                    meter_pattern: options[:meter_pattern],
                                    exact: options[:exact], word: options[:word], words: options[:words],
                                    lect: options[:lect], script: options[:script],
                                    within: within_filter)
      print_search_results(results, facets: facets, query: query, loans: loans, axis: axis_names,
                                    incomplete: searcher.incomplete_hint, exact: options[:exact],
                                    word: options[:word], rank_note: searcher.rank_note,
                                    meter_note: searcher.meter_note, words_note: searcher.words_note,
                                    place_note: searcher.place_note)
      print_display_footer
    rescue Nabu::Error => e
      # A malformed filter arg (--script shape) or a query-layer refusal —
      # a clean stderr message and exit 1, never a backtrace.
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "concord QUERY", "Concordance (KWIC): keyword-in-context lines, one per hit"
    long_desc <<~HELP, wrap: false
      Keyword-in-context concordance: every hit as one line — left context, the
      matched keyword, right context — with the keyword aligned in a fixed
      column so you can scan a word's usage down the page. The keyword is
      located in the PRISTINE edition text (accents and all), not the folded
      search form: a concordance is for reading real usage.

      Matching is exactly `nabu search`: diacritic- and case-insensitive on both
      sides (μηνιν finds μῆνιν), implicit-AND multiple words, "quoted phrase",
      prefix* — and --lemma FORM for exact dictionary-form lookup over the gold
      treebanks (finds every inflected attestation). Rows come in CORPUS order
      (urn/citation), not relevance order — the point is scanning, not ranking.
      One row per passage: a passage with the keyword twice shows its first
      occurrence.

      Layout: left context is trimmed to --width cells per side (default 40)
      and right-justified so the keyword column lines up; the right context is
      trimmed to the same width; clipped context is marked with …. Each row
      ends with the passage urn and [language]. Alignment counts East-Asian
      display width (Nabu::Display.width), so a lzh/ojp Han line lines up its
      keyword column exactly where a grc line does — each ideograph two cells.

      Filters (as in search): --lang, --license, --limit (default 20).

      Examples:
        nabu concord μῆνιν                       # every attestation of μῆνιν, KWIC
        nabu concord μηνιν --width 30            # tighter context, accents optional
        nabu concord ἄειδε --lang grc --limit 50
        nabu concord --lemma λέγω --lang grc     # every inflection in context:
                                                 #   λέγουσι, εἶπας, εἰπεῖν…
        nabu concord sapientia --lang lat        # a Latin word across the corpus

      Use cases: see how a word is actually used across six corpora at once;
      spot collocations and formulae; build a hand concordance for a term before
      writing about it.
    HELP
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    option :limit, type: :numeric, default: 20, desc: "Maximum number of KWIC lines"
    option :width, type: :numeric, default: Nabu::Query::Concord::DEFAULT_WIDTH,
                   desc: "Context characters per side (default #{Nabu::Query::Concord::DEFAULT_WIDTH})"
    option :lemma, type: :string, banner: "FORM",
                   desc: "Exact-lemma concordance over the gold treebanks (replaces the text query)"
    display_option
    def concord(query = nil)
      query = query.to_s.strip
      display_mode
      lemma = options[:lemma]
      if lemma
        raise Thor::Error, "concord: --lemma replaces the text query — give one or the other" unless query.empty?

        lemma = lemma.strip
        raise Thor::Error, "concord: --lemma needs a lemma" if lemma.empty?
      elsif query.empty?
        raise Thor::Error, "concord: give a query"
      end

      validate_license!(options[:license])
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
      if lemma && !fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
        raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                           "run nabu sync or nabu rebuild"
      end

      rows = Nabu::Query::Concord.new(catalog: catalog, fulltext: fulltext).run(
        query.empty? ? nil : query, lemma: lemma, lang: options[:lang],
                                    license: options[:license], limit: options[:limit].to_i, width: options[:width].to_i
      )
      print_concord_rows(rows)
      print_display_footer
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "parallels URN", "Find passages that quote or echo this one (intertext over the FTS index)"
    long_desc <<~HELP, wrap: false
      Passage-anchored intertext: point at ONE passage and find where the corpus
      quotes or echoes it — the classicist's "who cites this line? where does it
      resurface?" (docs/intertext-design.md §1). Query-time over the same FTS
      index as `search`, no precomputation: the anchor is folded to its search
      form, cut into overlapping 4-word grams, and each gram is probed as an
      exact phrase; passages that share grams are candidates, ranked by shared-
      gram count WEIGHTED BY RARITY (a rare shared phrase — a real quotation —
      outweighs a pile of common function-word grams).

      Not to be confused with `align` (the translation-column hub, verse X across
      its witnesses): parallels DISCOVERS reception across the whole corpus, from
      surface text alone.

      Each hit is one DOCUMENT (duplicate witnesses and multi-edition works
      otherwise flood the ranks): its best-matching passage urn, the score, the
      number of shared grams, and — when the document matches in several places —
      a "loci" count. Under each hit the shared PHRASE spans are shown (the grams
      merged back into contiguous text). Evidence is the folded search form, so
      accents/breathings are stripped — it marks WHAT matched; `nabu show <urn>`
      gives the pristine line.

      Elision is folded at gram-build: the apostrophe that some editions write as
      a letter (SBLGNT ἐπʼ) and others as punctuation (Swete/First1K ἐπ’) is
      stripped so a gram matches across editions — the fix that lets Matthew 4:4
      find LXX Deuteronomy 8:3.

      Only the anchor's OWN document is excluded. Translations and other-language
      witnesses self-exclude (they share no folded tokens with the anchor's
      language); a second same-language edition of the anchor's own work is kept
      — it is exactly the corroborating parallel you want.

      LEMMA ECHOES: when the anchor carries gold treebank lemmas (UD/PROIEL/
      TOROT), a second section lists passages sharing ≥2 of its RARE lemmas —
      re-inflected or reordered allusion that verbatim grams miss. Absent (and
      free) for non-lemmatized anchors.

      Filters: --lang / --license (exact class) scope candidates; --limit caps
      each list (default 15). --long expands every truncated list — all shared
      phrase spans and all shared lemmas, untrimmed (compact shows the first few
      with a "… and N more" tail).

      BATCH MODE (P16-1, the links journal): `parallels --batch SCOPE` mines a
      whole corpus slice — SCOPE is a source slug or a document-urn prefix,
      exactly the `formulas` scope grammar — looping this same engine over
      every anchor passage and PERSISTING the hits as kind=parallel edges in
      the links journal (db/links.sqlite3; `nabu links <urn>` reads them, and
      `show` grows a "linked:" footer). Each unordered pair is stored once, in
      the direction the probe found it; a rerun of the same scope supersedes
      the previous run's edges (idempotent). Pruning is explicit, never
      silent: only the top --per-anchor hits (default
      #{Nabu::BatchParallels::DEFAULT_PER_ANCHOR}) clearing --min-score
      (default #{Nabu::BatchParallels::DEFAULT_MIN_SCORE}) persist, and the
      summary line names both. --db writes the journal somewhere else (a
      scratch run). Interactive output is NEVER persisted — recomputing costs
      milliseconds; a stored copy would only go stale.

      PROFILES AND CHUNKS (P122-2): --profile NAME loads a declared tuning
      profile from config/reuse_profiles.yml (latin: trigrams, a 0.1 floor,
      a function-word drop; chinese: character 4-grams on the CJK lane, a 0.1
      floor, 10 hits per anchor) — explicit flags (--lang, --min-score,
      --per-anchor, --gram-size) still override it, and the run records the
      profile plus every effective parameter. --chunk-size N mines N anchors
      per committed chunk and prints one progress line per chunk (chunk N/M ·
      anchors · candidates · edges minted · elapsed) on stderr; a killed run
      resumes at its cursor when the same command is rerun (finished chunks
      are never re-mined, no edge is duplicated); --restart discards an
      unfinished run instead.

      Examples:
        nabu parallels urn:nabu:sblgnt:john:1.1          # John 1:1 across the Fathers
        nabu parallels urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1
                                                         # the Odyssey proem — who quotes it
        nabu parallels urn:nabu:sblgnt:matt:4.4 --long   # Matt 4:4 → Luke, Origen, LXX Deut 8:3
        nabu parallels <urn> --lang grc --limit 30       # Greek parallels only, wider page
        nabu parallels --batch urn:nabu:sblgnt:matt --lang grc
                                                         # mine Matthew's parallels into the journal
        nabu parallels --batch sblgnt --min-score 0.1    # a whole source, stricter floor
        nabu parallels --batch corpus-corporum --profile latin --chunk-size 5000 2> pl.log
                                                         # Patrologia, resumable, logged

      Use cases: trace a verse's reception; find the source a Father is quoting;
      seed the citation graph one batch scope at a time.
    HELP
    option :lang, type: :string, desc: "Restrict candidates to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict candidates to an exact license class (open, attribution, nc, …)"
    option :limit, type: :numeric, default: 15, desc: "Maximum hits per signal (default 15)"
    option :long, type: :boolean, default: false,
                  desc: "Expand every truncated list: all shared phrase spans and shared lemmas, untrimmed"
    option :batch, type: :boolean, default: false,
                   desc: "Mine a SCOPE (source slug or urn prefix) and persist edges to the links journal"
    option :min_score, type: :numeric, banner: "S",
                       desc: "With --batch: rarity-score floor an edge must clear " \
                             "(default #{Nabu::BatchParallels::DEFAULT_MIN_SCORE})"
    option :per_anchor, type: :numeric, banner: "N",
                        desc: "With --batch: top document-grain hits kept per anchor " \
                              "(default #{Nabu::BatchParallels::DEFAULT_PER_ANCHOR})"
    option :db, type: :string, banner: "PATH",
                desc: "With --batch: write the links journal at PATH instead of db/links.sqlite3"
    option :profile, type: :string, banner: "NAME",
                     desc: "With --batch: load a tuning profile from config/reuse_profiles.yml " \
                           "(latin, chinese); explicit flags override it"
    option :gram_size, type: :numeric, banner: "N",
                       desc: "With --batch: shingle width in gram tokens " \
                             "(default #{Nabu::Query::Parallels::GRAM_SIZE}, or the profile's)"
    option :chunk_size, type: :numeric, banner: "N",
                        desc: "With --batch: mine N anchors per committed chunk — a killed run " \
                              "resumes at its cursor when rerun with the same flags"
    option :restart, type: :boolean, default: false,
                     desc: "With --batch: supersede an unfinished chunked run instead of resuming it"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Restrict candidates to a lect (P59-3, nabu-lects module): keep only hits " \
                        "whose resolution is this lect id or a more specific one under it — the " \
                        "same prefix semantics as search --lect; errors if the module is not synced"
    display_option
    def parallels(urn = nil)
      urn = urn.to_s.strip
      display_mode
      validate_license!(options[:license])
      if options[:batch] && options[:lect]
        raise Thor::Error, "parallels: --lect does not apply with --batch (the miner is corpus-wide)"
      end
      return batch_parallels(urn) if options[:batch]

      %i[min_score per_anchor db profile gram_size chunk_size restart].each do |flag|
        next unless options[flag]

        raise Thor::Error, "parallels: --#{flag.to_s.tr('_', '-')} only applies with --batch " \
                           "(interactive results are never persisted)"
      end
      raise Thor::Error, "parallels: give a passage urn" if urn.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

      result = Nabu::Query::Parallels.new(catalog: catalog, fulltext: fulltext)
                                     .run(urn, limit: options[:limit].to_i,
                                               lang: options[:lang], license: options[:license],
                                               lect: options[:lect])
      print_parallels(result, urn: urn, long: options[:long])
      print_display_footer
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "formulas SCOPE", "Mine the repeated n-gram formulas within a corpus slice (oral-formulaic)"
    long_desc <<~HELP, wrap: false
      Intra-corpus formula mining: point at a corpus SLICE and find its recurring
      formulas — the oral-formulaic scholar's "what are the fixed phrases of this
      tradition, and where does each occur?" (docs/intertext-design.md §5). The
      same gram machinery as `parallels` pointed INWARD: instead of probing one
      passage against the whole corpus, every passage of the slice is folded, cut
      into overlapping n-word grams, and the grams counted in memory — the ones
      that recur are the formulas. Zero precomputation (~0.2 s per ~200k-token
      slice); reads the folded text straight from the catalog.

      SCOPE is a source slug (`aspr`) when one exists, else a urn prefix — a whole
      work (urn:cts:greekLit:tlg0012.tlg001.perseus-grc2) or a super-prefix over
      several (urn:cts:greekLit:tlg0012 = Iliad + Odyssey, the Homeric corpus).

      LANGUAGE: a translation-bearing source rides the same urn prefix as its base
      text (perseus-greek holds Greek AND aligned English), so an unfiltered run
      mixes traditions — pass --lang to mine one (a single-language source like
      ASPR needs none).

      RANKING: by count × gram length. No stoplist — the ranking is self-filtering
      (a genuine formula out-recurs any pure function-word sequence; measured, not
      one all-function-word gram reaches Homer's top). --min-count raises the
      recurrence floor against a noisy tail.

      Each formula prints its count and the folded gram (accents stripped, like
      `search` highlights — `nabu show <urn>` gives the pristine line), with a few
      example loci beneath. --long lists every locus of every reported formula.

      BATCH MODE (P16-2, the links journal): `formulas --batch SCOPE` runs the
      whole-tradition sweep once and PERSISTS kind=formula edges. A formula is
      a refrain across many loci, so it maps onto the pair-shaped journal as a
      STAR: each formula's first locus (urn order — deterministic) is the hub,
      with one edge to every other locus carrying the gram (detail) and the
      count (score); `nabu links <locus>` shows which refrain ties the line to
      the tradition, and `links <hub>` fans out every locus. Pruning is named,
      never silent: the top --max-formulas by rank persist (default
      #{Nabu::BatchFormulas::DEFAULT_MAX_FORMULAS}), at --min-count and
      --gram-size, all recorded in the run's params. A rerun of the same scope
      supersedes (idempotent); --db writes the journal elsewhere. Interactive
      output is never persisted.

      Examples:
        nabu formulas urn:cts:greekLit:tlg0012 --lang grc   # the Homeric formulas
        nabu formulas aspr                                  # Old English verse formulas
        nabu formulas aspr --gram-size 3 --min-count 5      # the riddle refrain "hwæt ic hatte"
        nabu formulas urn:cts:greekLit:tlg0012 --lang grc --long   # every locus
        nabu formulas --batch aspr                          # persist the ASPR formula stars
        nabu formulas --batch urn:cts:greekLit:tlg0012 --lang grc --max-formulas 500

      Use cases: characterize a tradition's formulaic diction; find every
      occurrence of a formula; seed an oral-formulaic study; wire the refrains
      into the mined citation graph (`nabu links`).
    HELP
    option :lang, type: :string,
                  desc: "Restrict the slice to a language (grc, ang) — wanted when a source mixes translations"
    option :min_count, type: :numeric, default: Nabu::Query::Formulas::DEFAULT_MIN_COUNT,
                       desc: "Minimum recurrence to count as a formula (default 3)"
    option :gram_size, type: :numeric, default: Nabu::Query::Formulas::DEFAULT_GRAM_SIZE,
                       desc: "Words per gram (2–8; default 4)"
    option :limit, type: :numeric, default: Nabu::Query::Formulas::DEFAULT_LIMIT,
                   desc: "Maximum formulas shown (default 25)"
    option :long, type: :boolean, default: false,
                  desc: "List every locus of every reported formula (compact shows a few examples)"
    option :batch, type: :boolean, default: false,
                   desc: "Sweep the SCOPE once and persist kind=formula edges to the links journal"
    option :max_formulas, type: :numeric, banner: "N",
                          desc: "With --batch: top formulas by rank persisted " \
                                "(default #{Nabu::BatchFormulas::DEFAULT_MAX_FORMULAS})"
    option :db, type: :string, banner: "PATH",
                desc: "With --batch: write the links journal at PATH instead of db/links.sqlite3"
    def formulas(scope = nil)
      scope = scope.to_s.strip
      return batch_formulas(scope) if options[:batch]

      %i[max_formulas db].each do |flag|
        next unless options[flag]

        raise Thor::Error, "formulas: --#{flag.to_s.tr('_', '-')} only applies with --batch " \
                           "(interactive results are never persisted)"
      end
      raise Thor::Error, "formulas: give a source slug or urn prefix" if scope.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog

      result = Nabu::Query::Formulas.new(catalog: catalog).run(
        scope, gram_size: options[:gram_size].to_i, min_count: options[:min_count].to_i,
               lang: options[:lang], limit: options[:limit].to_i, long: options[:long]
      )
      print_formulas(result, long: options[:long])
    rescue ArgumentError => e
      raise Thor::Error, "formulas: #{e.message}"
    ensure
      catalog&.disconnect
    end

    desc "links URN", "Mined cross-reference edges touching this urn (the links journal)"
    long_desc <<~HELP, wrap: false
      Read the links journal (docs/intertext-design.md §7, architecture §15):
      every batch-mined edge touching URN, BOTH directions, grouped by kind
      (parallel, formula, cognate, reference, etymology). Each edge shows
      its counterpart urn resolved to the document title and language plus
      its kind's evidence — a parallel's rarity score, a formula's gram and
      count (← the hub locus of the refrain's star; `links <hub>` fans out
      every locus), a cognate's meet (ref · root [shelf] — a gem-pro shelf
      under a Slavic witness reads as a borrowing), a reference's asserting
      manifest (P19-4: a local-library article beside the passages it
      discusses), an etymology's ancestor lemma (P28-3: a Coptic dictionary
      entry's hieroglyphic/demotic predecessors from the ORAEC crosswalk);
      → means a batch anchor at URN discovered the counterpart,
      ← means the edge was found from the other end. The footer cites the
      producer run(s) that minted the edges — scope, parameters, and date —
      so every edge is honest about its provenance.

      Edges are urn-keyed and live OUTSIDE the rebuildable dbs, so they
      survive `nabu rebuild` untouched; counterparts re-resolve against the
      current catalog (passage grain first, document grain second,
      dictionary-entry grain third — an ingested shelf's urn:nabu:dict:
      urns read "headword — dictionary"), and one that no longer resolves
      is flagged "(not in catalog)" rather than hidden. Edges are minted
      ONLY by batch producers (`parallels --batch SCOPE`, `formulas --batch
      SCOPE`, `cognates --batch WORK`, and the sync-time reference/etymology
      refreshes of the declaring sources); interactive output never
      persists.

      Compact shows the first few edges per kind; --long lists all. --db
      reads a journal written elsewhere (a scratch batch run).

      Examples:
        nabu links urn:nabu:sblgnt:matt:4.4     # who is wired to Matt 4:4
        nabu links urn:nabu:sblgnt:matt:4.4 --long
        nabu links <urn> --db /tmp/links.sqlite3

      Use cases: walk the mined citation graph passage by passage; audit what
      a batch run asserted; jump between quotation and source via `nabu show`.
    HELP
    option :long, type: :boolean, default: false,
                  desc: "List every edge of every kind (compact shows the first few per kind)"
    option :db, type: :string, banner: "PATH",
                desc: "Read the links journal at PATH instead of db/links.sqlite3"
    def links(urn = nil)
      urn = urn.to_s.strip
      raise Thor::Error, "links: give a passage or document urn" if urn.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      path = options[:db] || config.links_path
      journal = Nabu::Store::LinksJournal.open_readonly(path)
      return say("no links journal yet — mine one with `nabu parallels --batch SCOPE`") if journal.nil?

      result = Nabu::Query::Links.new(catalog: catalog, journal: journal).run(urn)
      raise Thor::Error, "links: unknown urn #{urn} (no catalog entry, no edges)" if result.nil?

      print_links(result, long: options[:long])
      print_links_notes_lane(catalog, urn)
    ensure
      catalog&.disconnect
      journal&.disconnect
    end

    desc "show URN", "Show a passage or document by urn (withdrawn items shown, flagged)"
    long_desc <<~HELP, wrap: false
      Inspect one passage or one whole document by urn. Unlike search and
      export, show hides nothing: withdrawn and retired-upstream items
      appear too, honestly labeled — this is the "what does my collection
      actually hold" lens.

      A PASSAGE urn prints the pristine text, its document, effective
      license, revision, and the full provenance trail (loaded / revised /
      withdrawn / restored / retired events with timestamps) — the
      passage's complete life story.

      A DOCUMENT urn prints the header (title, language, source, license,
      revision, any withdrawn/retired flag) and every passage in citation
      order, listed as :suffixes relative to the document urn printed once
      above; --full-urn restores absolute urns for copy-paste. Long
      documents: pipe to less.

      urn shapes across the corpus:
        CTS editions   urn:cts:greekLit:tlg0012.tlg002.perseus-grc2       (document)
                       urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1   (book 1, line 1)
        papyri (DDbDP) urn:nabu:ddbdp:aegyptus:89:240:b2:5
                       (:b2 = implicit restart block — an unlabeled column/
                        fragment where the edition's line numbers restart)
        treebanks      urn:nabu:proiel:afnik:194690                     (sentence)
                       urn:nabu:ud:gothic-proiel:got_proiel-ud-dev:37589

      RANGES (URN:<start>-<end>): a document urn plus two citation suffixes
      joined by a hyphen prints an INCLUSIVE, sequence-ordered slice of that
      one document between the endpoints — both endpoints must resolve to
      existing passages of the same document (a clear error names whichever
      fails; a start after its end is refused, suggesting a swap). The slice
      is by STORED sequence, whatever citation shapes lie between: a papyri
      restart block (:b2, an implicit column/fragment) is sliced straight
      through. Precedence: a literal passage urn is resolved FIRST, so a urn
      that itself contains a hyphen is never misparsed as a range; the range
      split is on the LAST hyphen (citation suffixes never contain one, the
      version segment perseus-grc2 does). Ranges compose with --full-urn and
      with --parallel (the range slices the queried edition; pairing then
      applies to the sliced rows only).

      PARALLEL TRANSLATIONS (--parallel [LANG], default eng): for a CTS
      document or passage urn — or an ORACC tablet, whose translation is the
      -en sibling document (P13-4) — find the sibling edition of the SAME
      work in LANG (sources ingest translations only when their registry
      entry sets `translations: true`) and render the two SPAN-GROUPED by
      citation suffix. A verse-for-verse translation pairs line by line —
      :1.1 Greek next to :1.1 English. A card-cited prose translation (both
      English Homers) anchors one block of text at a card's first line: the
      original lines are listed, then the translation ONCE, labeled with its
      coverage in the original's numbering (`eng [:1.1 — covers :1.1–:1.43]`)
      plus a clip note when a range shows only part of a card. ORACC's
      paragraph-grained SAA units render as exactly such blocks over the
      tablet's o.1/r.5 lines. A suffix present in only one edition renders
      honestly one-sided, never fuzzed. Works with --full-urn. Where a
      kind=translation link edge joins documents across sources (the
      Kangyur↔84000 crosswalk), --parallel pairs them at Degé folio/page
      grain — no extra flag.

      Examples:
        nabu show urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1
        nabu show urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1-1.10
                                                  # Iliad 1.1–1.10, one slice
        nabu show urn:nabu:ddbdp:aegyptus:89:240:1-b2:2
                                                  # a papyrus slice across a restart block
        nabu show urn:nabu:ddbdp:aegyptus:89:240            # whole papyrus
        nabu show urn:nabu:ddbdp:aegyptus:89:240 --full-urn # absolute urns
        nabu show urn:cts:greekLit:tlg0013.tlg013.perseus-grc2 --parallel
                                                  # Greek + eng, line by line
        nabu show urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.5-1.10 --parallel
                                                  # a mid-card slice: the eng block labeled
                                                  #   "covers :1.1–:1.43; range shows :1.5–:1.10"
        nabu show urn:cts:greekLit:tlg0013.tlg013.perseus-eng2:1 --parallel grc
                                                  # one translated line + its original
        nabu show urn:nabu:oshb:gen:1:1 --tokens  # + the stored token annotations,
                                                  #   verbatim (form, lemma, osm, …)

      TOKENS (--tokens): appends the passage's stored token annotations as
      one line per token — `form` first, then every key the store holds for
      that token, exactly as stored (the honest raw view; nothing decoded,
      nothing invented). A passage without token annotations, and a
      document/range urn, say so.

      SEGMENTED (--segmented): renders Tibetan-language rows (xct/bod/otb)
      with word boundaries — the stored text with a space inserted at each
      boundary (tokens verbatim, trailing tsheg kept), segmented through
      the published nabu-data xct/segmentation dataset. An off-language
      row, or a box that has not run `nabu sync nabu-data`, prints the
      plain text plus one honest note.

      Use cases: read the real edition text behind a search snippet; audit
      a document's revision/provenance history after a sync; eyeball what
      "withdrawn" or "retired upstream" actually holds; read a Greek work
      you can't sight-read next to its English translation; inspect the
      exact lemma/morphology evidence a treebank stored for one passage.
    HELP
    option :full_urn, type: :boolean, default: false,
                      desc: "List document passages with absolute urns instead of :suffixes"
    option :parallel, type: :string, lazy_default: "eng", banner: "[LANG]",
                      desc: "Align with the same work's LANG edition by citation suffix (default eng)"
    option :random, type: :boolean, default: false,
                    desc: "Show random passages instead of a urn (the eyeball ritual at a source flip)"
    option :source, type: :string, banner: "SLUG",
                    desc: "With --random: draw only from this source (default: the whole corpus)"
    option :lang, type: :string, banner: "CODE",
                  desc: "With --random: draw only passages in this language (grc, lat, … — the multi-lang eyeball)"
    option :count, type: :numeric, default: 1,
                   desc: "With --random: how many passages (default 1, cap #{Nabu::Query::Random::MAX_COUNT})"
    option :tokens, type: :boolean, default: false,
                    desc: "Append the passage's stored token annotations verbatim (form + every key present)"
    option :segmented, type: :boolean, default: false,
                       desc: "Render Tibetan (xct/bod/otb) passages with word boundaries " \
                             "(needs the synced nabu-data module)"
    display_option
    def show(urn = nil)
      urn = urn.to_s.strip
      display_mode
      if options[:tokens] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --tokens does not compose with --random/--parallel"
      end
      if options[:segmented] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --segmented does not compose with --random/--parallel"
      end

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      if options[:random]
        show_random(catalog, urn, config)
        return print_display_footer
      end
      raise Thor::Error, "show: --source requires --random" if options[:source]
      raise Thor::Error, "show: --lang restricts --random draws — give a urn, or add --random" if options[:lang]
      raise Thor::Error, "show: give a urn" if urn.empty?

      if options[:parallel]
        show_parallel(catalog, urn, options[:parallel], config)
        return print_display_footer
      end

      # pleiades: :auto — the findspot line (P44-2) feature-detects the
      # gazetteer dump lazily; nothing loads unless the shown document
      # carries a captured Pleiades id.
      show_query = Nabu::Query::Show.new(catalog: catalog, pleiades: :auto)
      result = show_query.run(urn)
      raise Thor::Error, "urn not found: #{urn}" if result.nil?

      # --segmented (P54-2): the word-broken Tibetan rendering. The
      # segmentation is Query::Show's (the one serializer MCP shares); here
      # we only swap texts on a copy of the result — or keep the plain
      # output plus the query layer's one honest note line.
      seg_note = nil
      if options[:segmented]
        seg_note = show_query.segmentation_note(result.respond_to?(:language) ? result.language : nil)
        result = segmented_show_result(show_query, result) if seg_note.nil?
      end

      print_show(result)
      say seg_note if seg_note
      print_show_tokens(result) if options[:tokens]
      print_linked_footer(config, result.urn)
      print_notes_footer(catalog, result)
      print_display_footer
    rescue Nabu::Query::Range::Error, Nabu::Query::Random::Error,
           Nabu::Query::Parallel::TranslationMismatch => e
      # A range urn that names two endpoints but can't be honoured (endpoint
      # missing, or reversed), an unknown --random --source, or a --parallel
      # LANG the translation link cannot serve: a clean stderr message + exit 1.
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    desc "note URN|CODE [TEXT]", "Annotate any urn the corpus knows, or a language code (→ local-notes/)"
    long_desc <<~HELP, wrap: false
      The owner's annotation lane (architecture §16) — scholia of one's own,
      keyed by ANY urn the corpus knows: a document, a passage, a range, a
      dictionary entry. A bare LANGUAGE CODE (chu, zle-ort — no colon) is a
      target too (P85): `nabu note chu "…"` files a PRIVATE per-language note
      that the `nabu language chu` card composes beneath the published overlay
      (it stays local/, never published — the urn:nabu:lang:<code> layer).
      Notes are canonical memory: they live as YAML files
      under canonical/local-notes/<topic>.yml (append-only through the
      Nabu::NoteShelf gateway; hand-edits welcome — the file is the record),
      and the catalog only indexes them (urn_notes, rebuilt at every
      sync/rebuild). Once noted, the urn's renders carry the note: `show`
      prints an "owner note (topic, date): …" footer (a document also counts
      its passage-note children), `define` prints entry notes after the
      body, `links` shows an owner-notes lane, and the MCP surface serves
      notes by default (withheld wherever the target document is withheld).

      Modes:
        nabu note URN "TEXT"    scripted append (TEXT may be several words)
        nabu note URN           existing notes? show them; none? prompt for
                                one (TTY only — a pipe without TEXT refuses
                                honestly BEFORE any write)
        nabu note --list        enumerate notes (bounded --limit; --topic
                                narrows)

      The urn must RESOLVE in the catalog — a note on a typo'd urn would sit
      unreachable forever, so a miss is an error naming it. --force records
      a note on a not-yet-held urn deliberately (notes on planned material);
      such notes read "(dangling)" at render until the urn arrives.

      --topic groups notes however you like (default "#{Nabu::NoteShelf::DEFAULT_TOPIC}";
      one file per topic); --tags rides a comma-separated tag list.

      Examples:
        nabu note urn:nabu:ccmh:mar:mt "Collate against Jagić 1883 before citing."
        nabu note urn:nabu:dict:lsj:logos "Anchor for the John 1.1 witness comparison." --topic lexicon
        nabu note urn:nabu:planned:vaillant --force "Order the reprint." --tags acquisitions
        nabu note urn:nabu:ccmh:mar:mt         # read what you said
        nabu note --list --topic lexicon
    HELP
    option :topic, type: :string, banner: "NAME",
                   desc: "Topic file under canonical/local-notes/ (default #{Nabu::NoteShelf::DEFAULT_TOPIC}; " \
                         "with --list: narrow to this topic)"
    option :tags, type: :string, banner: "collation,ocs", desc: "Tags, comma-separated"
    option :force, type: :boolean, default: false,
                   desc: "Record a note on a not-yet-held urn (flagged dangling at render)"
    option :list, type: :boolean, default: false,
                  desc: "Enumerate notes (bounded; --topic narrows, --limit lifts)"
    option :rm, type: :string, banner: "ID",
                desc: "Remove one note by its id (nabu note --list shows ids)"
    option :limit, type: :numeric, default: Nabu::Query::Notes::DEFAULT_LIMIT,
                   desc: "With --list: how many notes (default #{Nabu::Query::Notes::DEFAULT_LIMIT})"
    def note(urn = nil, *text_parts)
      config = Nabu::Config.load
      return note_list(config, urn) if options[:list]
      return note_remove(config, urn) if options[:rm]

      target = urn.to_s.strip
      raise Thor::Error, "note: give a urn or a language code (or --list)" if target.empty?

      # P85-A: a bare language code (chu, zle-ort — no colon) targets the
      # private language-note layer via its canonical pseudo-URN; anything
      # colon-bearing stays an ordinary corpus-URN note.
      code = Nabu::LanguageNote.code_for(target)
      urn = code ? Nabu::LanguageNote.urn(code) : target

      text = text_parts.join(" ").strip
      text = show_notes_or_prompt(config, urn) if text.empty?
      return if text.nil? # existing notes were shown — a read, not a write

      append_note(config, urn, text)
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    end

    desc "lemma-enrich LANGUAGE", "Run the silver-lemma enricher over the uncovered slice (P84-1)"
    long_desc <<~HELP, wrap: false
      The silver-lemma lane (P84-1): a local CPU lemmatizer (venv-managed
      Stanza; la:ittb for the Latin wave) runs over every live passage of
      LANGUAGE that has NO lemma coverage, and the raw model output lands
      on the local-lemmas shelf (local/shelves/local-lemmas/<language>/,
      through the Nabu::LemmaShelf gateway — model output costs hours of
      compute, so the derivability law homes it in a shelf, never db/).
      The shelf projects into passage_lemmas as tier-silver rows ONLY on
      the owner's word (owner-ruled 2026-08-29): --index after a campaign, or
      --index-only any time. A full rebuild never projects it (it announces
      the shelf and names this command); routine source syncs maintain
      already-projected slices but never arm a clean index. Gold rows are
      never touched: a passage with ANY existing lemma coverage is skipped.

      RESUMABLE: the campaign checkpoints at every shard flush — re-fire
      the same command after any interruption and it continues where the
      shelf left off. LANGUAGE accepts the catalog code or common aliases
      (lat/la). Wave-1 is Latin only; grc is measured but deliberately
      parked for its own wave.

      One-time setup: the venv (python + stanza + the la model) is an
      owner-run bootstrap — docs/manual/silver-lemma-venv.md. The default
      home is ~/.nabu/venvs/stanza (override: --venv or $NABU_STANZA_VENV).

      Modes:
        nabu lemma-enrich lat --dry-run        census + honest ETA, nothing runs
        nabu lemma-enrich lat                  the campaign (hours; resumable)
        nabu lemma-enrich lat --limit 100      bounded smoke run
        nabu lemma-enrich lat --index          campaign, then project the shelf
        nabu lemma-enrich lat --index-only     project the shelf, run nothing
        nabu lemma-enrich lat --spot-check 250 the P79-4 gold protocol: sample
                                               gold-annotated passages, score
                                               folded-lemma accuracy per source
    HELP
    option :dry_run, type: :boolean, default: false,
                     desc: "Census the uncovered slice and print the ETA; run nothing"
    option :limit, type: :numeric, banner: "N", desc: "Stop after N passages (smoke runs)"
    option :venv, type: :string, banner: "DIR",
                  desc: "The stanza venv (default ~/.nabu/venvs/stanza or $NABU_STANZA_VENV)"
    option :batch_size, type: :numeric, default: Nabu::LemmaEnrich::DEFAULT_BATCH,
                        desc: "Passages per model request (default #{Nabu::LemmaEnrich::DEFAULT_BATCH})"
    option :shard_size, type: :numeric, default: Nabu::LemmaEnrich::DEFAULT_SHARD,
                        desc: "Records per shelf shard / checkpoint stride " \
                              "(default #{Nabu::LemmaEnrich::DEFAULT_SHARD})"
    option :index, type: :boolean, default: false,
                   desc: "After the run, project the shelf into passage_lemmas (tier silver) now " \
                         "instead of waiting for the next rebuild/sync"
    option :index_only, type: :boolean, default: false,
                        desc: "Only project the existing shelf into passage_lemmas; run no model"
    option :spot_check, type: :numeric, banner: "N",
                        desc: "Score the model against N gold-annotated passages; writes nothing"
    def lemma_enrich(language_name)
      config = Nabu::Config.load
      language = Nabu::LemmaEnrich.resolve_language(language_name)
      shelf = Nabu::LemmaShelf.new(dir: Nabu::LemmaShelf.dir(config))
      return lemma_index_only(config, shelf) if options[:index_only]

      catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path, readonly: true)
      begin
        enricher = Nabu::LemmaEnrich.new(
          catalog: catalog, fulltext: fulltext, shelf: shelf, language: language,
          worker_argv: options[:dry_run] ? nil : lemma_worker_argv(language),
          batch_size: options[:batch_size].to_i, shard_size: options[:shard_size].to_i,
          limit: options[:limit]&.to_i, progress: progress_reporter
        )
        return lemma_spot_check(enricher) if options[:spot_check]

        census = enricher.census
        say "silver lemmas (#{language}): #{commas(census.total)} live passages — " \
            "#{commas(census.covered)} covered, #{commas(census.shelved)} shelved, " \
            "#{commas(census.uncovered)} uncovered"
        say "  estimated #{Nabu::Eta.format_seconds(census.eta_seconds)} single-process " \
            "at the measured #{Nabu::LemmaEnrich::TRIAL_RATE.to_i} passages/s (P79-4)"
        return if options[:dry_run]

        result = enricher.run!
        finish_progress
        say "lemmatized #{commas(result.processed)} passages in " \
            "#{Nabu::Eta.format_seconds(result.elapsed_seconds)} " \
            "(#{format('%.1f', result.rate)}/s) — #{result.shards_written} shard(s) shelved; " \
            "skipped: #{commas(result.skipped_covered)} covered, " \
            "#{commas(result.skipped_shelved)} shelved, #{commas(result.skipped_empty)} empty"
        say "  model: #{result.model} #{result.model_version} (#{result.package})"
        say "  shelf: #{shelf.language_dir(language)}"
      ensure
        catalog.disconnect
        fulltext.disconnect
      end
      lemma_index_only(config, shelf) if options[:index]
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    end

    desc "silver-dates", "The local-dates shelf: import date estimates, project them as silver dates (P122-1)"
    long_desc <<~HELP, wrap: false
      The silver-date lane (P122-1, the silver-lemma mold at document
      grain): model- or tool-emitted date ESTIMATES are non-derivable
      output, so they live on the local-dates shelf
      (local/shelves/local-dates/, JSONL shards written only through the
      Nabu::DateShelf gateway) — never in db/.

      --import FILE shelves one batch: a JSONL file, one estimate per line —
        {"urn": "urn:…", "not_before": -300, "not_after": -200,
         "basis": "model", "estimator": "chronos", "estimator_version": "0.3",
         "confidence": 0.8, "note": "…"}
      Signed historical years (BCE negative, no year 0; either bound may be
      null = open). Every urn must name a live document the catalog holds
      (--force shelves estimates for material not yet held). A later
      estimate for the same urn supersedes the earlier one.

      --project is the OWNER's gate: it arms the shelf and projects the
      latest estimate per live document into the timeline as SILVER rows
      (date_class "silver", precision "estimate", the estimator named in
      the date string). Once armed, every rebuild flavor, builders:refresh
      and sync re-projects behind the timeline — the lane survives `nabu
      rebuild`. --retract disarms the shelf and drops the projected rows
      (the shelf itself is untouched). Both re-derive the lemma/curve
      rollups, which bucket by date.

      Honesty: a silver date never answers a filter that promises
      upstream dates (`search --from/--to`, `vocab --by-century`, source
      date coverage, lect date inference, published nabu-data dates). It
      is the primary date only where no upstream date exists, and then
      renders labeled ("[silver — model estimate …]" on the card,
      date_class silver in exports); `search --date-basis silver` finds
      exactly those documents.

      Examples:
        nabu silver-dates                          census: shelf, arm state, projected rows
        nabu silver-dates --import estimates.jsonl
        nabu silver-dates --project
        nabu silver-dates --retract
    HELP
    option :import, type: :string, banner: "FILE", desc: "Shelve a JSONL batch of date estimates"
    option :force, type: :boolean, default: false,
                   desc: "With --import: shelve estimates for urns the catalog does not hold"
    option :project, type: :boolean, default: false,
                     desc: "Arm the shelf and project it into the timeline as silver dates (owner's gate)"
    option :retract, type: :boolean, default: false,
                     desc: "Disarm the shelf and drop the projected silver dates"
    def silver_dates
      modes = %i[import project retract].select { |mode| options[mode] }
      raise Thor::Error, "silver-dates: one of --import/--project/--retract at a time" if modes.size > 1
      raise Thor::Error, "silver-dates: --force only accompanies --import" if options[:force] && !options[:import]

      config = Nabu::Config.load
      shelf = Nabu::DateShelf.new(dir: Nabu::DateShelf.dir(config))
      case modes.first
      when :import then silver_dates_import(config, shelf)
      when :project then silver_dates_project(config, shelf)
      when :retract then silver_dates_retract(config, shelf)
      else silver_dates_census(config, shelf)
      end
    rescue Nabu::Error => e
      raise Thor::Error, "silver-dates: #{e.message}"
    end

    desc "embed", "Build/refresh the semantic vectors over the embed-flagged sources (P93-4)"
    long_desc <<~HELP, wrap: false
      The semantic-vector build lane (owner-ruled after the P79-5 trial): encodes every
      live passage of the embed-flagged sources (registry
      `embed_index: true` — the literary core; the trial priced the full
      library as a measured NO) with the trial's model
      (multilingual-e5-base, venv worker) into db/vectors.sqlite3 — the
      store `search --similar` reads.

      INCREMENTAL BY CONSTRUCTION (the ruling's design constraint): rows
      key on (model, urn) plus the sha of the exact text embedded, never
      passage ids — so a rebuild invalidates nothing, and every run is a
      delta: the first is the priced ~22 h build (batches commit as they
      land; interrupt and re-fire freely), later runs re-embed only new
      or revised text, usually seconds. Only a deliberate MODEL change
      re-embeds everything, beside the old rows, never over them.

      Pointed Hebrew/Aramaic embeds a marks-stripped variant (the trial's
      finding: the pointed text carries zero signal for this model
      class); the stored passage text is untouched.

      One-time setup: the venv (python + sentence-transformers + the
      model) is an owner-run network bootstrap — docs/manual/embed-venv.md.
      Default home ~/.nabu/venvs/embed (override: --venv or
      $NABU_EMBED_VENV).

      Modes:
        nabu embed --status       census (fresh/stale/missing) + honest ETA, nothing runs
        nabu embed                the campaign (delta; first run ~22 h, resumable)
        nabu embed --limit 500    bounded smoke run
    HELP
    option :status, type: :boolean, default: false,
                    desc: "Census the scope (fresh/stale/missing) and print the ETA; run nothing"
    option :limit, type: :numeric, banner: "N", desc: "Stop after N passages (smoke runs)"
    option :venv, type: :string, banner: "DIR",
                  desc: "The embed venv (default ~/.nabu/venvs/embed or $NABU_EMBED_VENV)"
    option :batch_size, type: :numeric, default: Nabu::Embed::DEFAULT_BATCH,
                        desc: "Passages per model request (default #{Nabu::Embed::DEFAULT_BATCH})"
    def embed
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      slugs = registry.embed_slugs
      raise Thor::Error, "no sources flagged embed_index: true in config/sources.yml" if slugs.empty?

      catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
      vectors = Nabu::Store.connect(config.vectors_path)
      begin
        embedder = Nabu::Embed.new(
          catalog: catalog, vectors: vectors, slugs: slugs,
          worker_argv: options[:status] ? nil : Nabu::Embed.worker_argv(venv: options[:venv]),
          batch_size: options[:batch_size].to_i, limit: options[:limit]&.to_i,
          progress: progress_reporter
        )
        census = embedder.census
        say "embed scope: #{slugs.size} sources, #{commas(census.total)} live passages — " \
            "#{commas(census.fresh)} fresh, #{commas(census.stale)} stale, " \
            "#{commas(census.missing)} missing"
        say "  owed: #{commas(census.stale + census.missing)} passages, estimated " \
            "#{Nabu::Eta.format_seconds(census.eta_seconds)} at the measured " \
            "#{Nabu::Embed::TRIAL_RATE.round(1)} passages/s (P79-5)"
        return if options[:status]

        result = embedder.run!
        say "embedded #{commas(result.embedded)} passages in " \
            "#{Nabu::Eta.format_seconds(result.elapsed_seconds)} " \
            "(#{result.rate.round(1)}/s); skipped: #{commas(result.skipped_fresh)} fresh, " \
            "#{commas(result.skipped_empty)} empty"
        say "  model: #{result.model} dim #{result.dim} (worker #{result.worker_version})"
        say "  store: #{config.vectors_path}"
      ensure
        catalog.disconnect
        vectors.disconnect
      end
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    end

    desc "align REF", "Render one citation across every witness of a registered work (the alignment hub)"
    long_desc <<~HELP, wrap: false
      Cross-source alignment (architecture §10): one citation of a registered
      WORK rendered in every witness the alignment registry
      (config/alignments.yml) names — the same verse in Greek, Latin, Gothic,
      Classical Armenian, and Old Church Slavonic, in one screen. Witnesses
      render in registry order, each with its language and its EFFECTIVE
      license class (the five NT witnesses are all nc — mind the labels when
      quoting).

      REF is a citation in the work's scheme — for the `nt` work,
      BOOK chapter.verse ("MARK 2.3"; quote it or let Thor join the words).
      Matching is forgiving: case, extra spaces, and chapter:verse colons all
      normalize ("mark 2:3" finds MARK 2.3). REF may also be a PASSAGE URN
      (pivot from a show/search hit): the sentence's verse is looked up and
      aligned across the other witnesses.

      Alignment is at citation grain over the treebanks' verse annotations,
      and sentence≠verse: a witness's sentence that spans a verse boundary is
      shown once, labeled with everything it covers. Honesty rules: a witness
      that simply lacks the verse (the Armenian sample holds only scattered
      chapters; Gothic is fragmentary) reads "not attested"; a registered
      witness whose source was never synced reads "not synced". Adding a
      witness (say, the ISWOC Old English Mark) is a registry entry, not code.

      --work names the work explicitly. Without it, a ref resolves through
      the index: when exactly one registered work attests it, that work is
      picked automatically (nt for "MARK 2.3", ot for "GEN 1.1"); a ref
      several works attest asks you to pick among the attesters.

      Examples:
        nabu align MARK 2.3                 # the paralytic, five ways
        nabu align "mark 2:3"               # same — refs normalize
        nabu align urn:nabu:proiel:marianus:36421
                                            # pivot: this OCS sentence, aligned
        nabu align MATT 5.25 --work nt      # explicit work id

      Use cases: read the Vorlage beside the translation (THE working method
      of comparative philology); check how each witness renders a
      construction; learn OCS/Gothic against the Greek you can already read.
    HELP
    option :work, type: :string, banner: "ID",
                  desc: "Alignment work id from config/alignments.yml (optional when only one is registered)"
    option :collate, type: :boolean, default: false,
                     desc: "Diff the witnesses instead of listing them: a raw-token apparatus per " \
                           "(language, script) group — base reading, then per-witness divergences only " \
                           "(cross-script witnesses rendered undiffed, honestly)"
    option :base, type: :string, banner: "LABEL",
                  desc: "With --collate: the base witness (label or document urn) each group diffs " \
                        "against (default: the first witness in registry order)"
    option :long, type: :boolean, default: false,
                  desc: "Lift the #{Nabu::Query::Align::MAX_REFS}-ref range ceiling and render every ref " \
                        "(compact clips a huge range by default); with --collate, also print each " \
                        "witness's full tokens instead of only its divergences"
    display_option
    def align(*ref_parts)
      ref = ref_parts.join(" ").strip
      raise Thor::Error, "align: give a citation ref (e.g. MARK 2.3) or a passage urn" if ref.empty?

      display_mode
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog && fulltext

      registry = Nabu::AlignmentRegistry.load(config.alignments_path)
      if options[:collate]
        result = Nabu::Query::Collation.new(catalog: catalog, fulltext: fulltext, registry: registry)
                                       .run(ref, work: options[:work], base: options[:base], long: options[:long])
        print_collation(result, long: options[:long])
      else
        raise Thor::Error, "align: --base only applies with --collate" if options[:base]

        result = Nabu::Query::Align.new(catalog: catalog, fulltext: fulltext, registry: registry)
                                   .run(ref, work: options[:work], long: options[:long])
        print_align(result)
      end
      print_display_footer
    rescue Nabu::Query::Align::Error, Nabu::ValidationError => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "define LEMMA", "Look up a lemma in the dictionary shelf (LSJ, L&S, Bosworth-Toller, MW, Wiktionary-OCS)"
    long_desc <<~HELP, wrap: false
      The dictionary shelf (architecture §11): look a dictionary form up in
      the lexica the corpus holds locally — LSJ (A Greek-English Lexicon,
      grc) and Lewis & Short (A Latin Dictionary, lat), both CC BY-SA from
      the Perseus Digital Library, Bosworth-Toller (An Anglo-Saxon
      Dictionary, ang; CC BY 4.0, LINDAT dump), Monier-Williams (A
      Sanskrit-English Dictionary, san; CC BY-NC-SA 3.0, Cologne CDSL —
      SLP1 transcoded to IAST, so aṃśa and amsa both reach the entry, and
      RV./BhP. citations resolve into the GRETIL shelf), and Wiktionary Old
      Church Slavonic (chu; kaikki.org extract, CC-BY-SA + GFDL —
      etymologies with their Proto-Slavic/PIE chains kept in the body).
      Entries print whole:
      headword, short gloss, then the full entry body as structured plain
      text with sense labels on their own lines (the MCP nabu_define surface
      is the bounded sibling).

      Matching folds like lemma search (conventions §9): diacritics optional
      (μηνις finds μῆνις), final sigma both ways (λόγος/λογοσ), Latin v/u j/i
      merged, Old English æ/þ/ð typeable in ASCII (aethele finds æðele,
      thing finds þing). Homographs are separate entries and all print (volo
      the verb, volo the flyer). LEMMA must be a dictionary form —
      `nabu search --lemma` finds the attestations, and its hits carry these
      glosses.

      Citations inside an entry stay as text; those that point at a work THIS
      corpus holds are additionally resolved to passage urns and listed at
      the end of the entry — `nabu show <urn>` opens the cited line. LSJ
      cites editions we may not hold (perseus-grc1 vs our grc2); resolution
      re-anchors to the in-catalog edition of the same work, preferring the
      original language over translations. Unresolvable citations (works not
      ingested, inscriptions, fragment collections) are honest misses, not
      links.

      The reconstruction shelves (P14-1, architecture §12) join in with the
      comparativist's asterisk: `define '*bogъ'` (quote the star — zsh globs
      a bare `*`) scopes to the Wiktionary Proto-Slavic/PIE/Proto-Germanic
      extracts (sla-pro/ine-pro/gem-pro), and a reconstruction entry also
      lists its descendant reflexes — with corpus attestation counts where
      the reflex is a gold lemma here. Proto headwords fold to ASCII (§9:
      ʰ→h, ʷ→w), so `define '*gʷʰew-'` and `define '*gwhew-'` reach the same
      root. `nabu etym` walks the same crosswalk from the attested side.

      --lang grc|lat|ang|san|chu|sla-pro|ine-pro|gem-pro restricts to one
      shelf; --limit caps the entries.

      --facet NAME=PATTERN (repeatable, each must hold) keeps only entries
      the dictionary-entry facet surface tags: JMdict's domain / usage /
      dialect / loan_source labels, WOLD's semantic_field / word_class /
      borrowed_status, TLS's concept. The pattern matches the value or its
      ref, case-insensitively; LIKE patterns pass through.

      Examples:
        nabu define μῆνις              # LSJ: wrath — with Il. 1.1 resolved
        nabu define λόγος              # the long one, whole
        nabu define virtus --lang lat  # Lewis & Short only
        nabu define aethele --lang ang # Bosworth-Toller: æðele, noble
        nabu define amsa --lang san    # Monier-Williams: aṃśa/aṃsa, RV. resolved into GRETIL
        nabu define богъ --lang chu    # Wiktionary-OCS: god, ex Proto-Slavic *bogъ
        nabu define '*bogъ'            # the reconstruction, with its reflexes (quote *)
        nabu define 経 --facet domain=Buddhism  # JMdict's Buddhist-domain senses only
    HELP
    option :lang, type: :string,
                  desc: "Restrict to one dictionary language (any language on the live " \
                        "shelf — the miss message lists what is held)"
    option :limit, type: :numeric, default: Nabu::Query::Define::DEFAULT_LIMIT,
                   desc: "Maximum entries printed (homographs are separate entries)"
    option :long, type: :boolean, default: false,
                  desc: "Expand every truncated reflex list in full, grouped by language " \
                        "(compact is the default; MCP nabu_define stays bounded)"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Restrict to shelves whose (language, source) RESOLUTION is this lect id " \
                        "or under it (P59-3; per-source overrides included — derom's la-vul " \
                        "scopes under roa, never lat); errors if the nabu-lects module is not synced"
    option :facet, type: :string, repeatable: true, banner: "NAME=PATTERN",
                   desc: "Entry facet filter — domain=medicine, usage=archaic, semantic_field=Kinship, " \
                         "concept=WORLD: matches value or ref, LIKE patterns pass through; repeatable (AND)"
    def define(*lemma_parts)
      lemma = lemma_parts.join(" ").strip
      raise Thor::Error, "define: give a lemma (e.g. λόγος, virtus)" if lemma.empty?

      facets = facet_specs(command: "define", example: "domain=Buddhism")
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
      unless catalog.table_exists?(:dictionary_entries)
        raise Thor::Error, "no dictionary shelf in this catalog yet — run nabu sync lexica " \
                           "(or nabu rebuild after one)"
      end
      # P106-3: the header answers from the dictionary_stats census when
      # one is derived (the desk-commands law); the live distinct scan
      # stays the pre-036/underived fallback, byte-identical.
      shelf_langs, shelf_count =
        if catalog.table_exists?(:dictionary_stats) && !catalog[:dictionary_stats].empty?
          [catalog[:dictionary_stats].distinct.order(:language).select_map(:language),
           catalog[:dictionary_stats].count]
        else
          [catalog[:dictionaries].distinct.order(:language).select_map(:language),
           catalog[:dictionaries].count]
        end
      @shelf_summary = "the shelf holds #{shelf_count} dictionaries " \
                       "(#{shelf_langs.join(', ')})"
      unless facets.empty?
        @shelf_summary += "; entry facets #{facets.map { |name, pattern| "#{name}=#{pattern}" }.join(', ')}"
      end
      if options[:lang] && !Nabu::Languages.code_variants(options[:lang]).intersect?(shelf_langs)
        raise Thor::Error, "define: --lang must be a language on the live shelf " \
                           "(#{shelf_langs.join(', ')})"
      end

      fulltext = open_fulltext(config)
      @languages = Nabu::Languages.new(catalog: catalog)
      # Fetch every matching shelf, cap at render (P34-r2): with the CJK
      # shelves live a Han headword matches 6+ dictionaries, and the old
      # fetch-time cap hid the tail silently (the gate found `define 棄`
      # missing tls-words). --long lifts the cap; compact announces it.
      results = Nabu::Query::Define.new(catalog: catalog, fulltext: fulltext)
                                   .run(lemma, lang: options[:lang], limit: nil, lect: options[:lect],
                                               facets: facets)
      shown = options[:long] ? results : results.first(options[:limit].to_i)
      print_define_results(lemma, shown, catalog: catalog)
      if (hidden = results.size - shown.size).positive?
        say format("… %<n>d more %<verb>s (--long shows all; --limit raises the cap)",
                   n: hidden, verb: hidden == 1 ? "entry matches" : "entries match")
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "etym LEMMA", "Walk an attested lemma to its reconstructions and cognates (architecture §12)"
    long_desc <<~HELP, wrap: false
      The comparativist's walk: from an ATTESTED lemma (богъ, guþ, deus) to
      every reconstruction whose descendants name it — the Wiktionary proto
      shelves (Proto-Slavic, Proto-Indo-European, Proto-Germanic, and
      (P17-3) Proto-Balto-Slavic, Proto-West Germanic, Proto-Italic,
      Proto-Indo-Iranian; kaikki.org extracts, CC-BY-SA + GFDL) and every
      other shelf carrying reflex edges (StarLing bases, MW comparanda —
      the miss message lists what is live) — then UP the ancestor chain, one indent
      per shelf hop (each shelf enters a walk once, so the chain is bounded
      and cycle-safe): прьстъ reaches *pьrstъ ← *pírštan ← *per- end to
      end. A loan-flagged edge labels its arrow "←(loan)", and a
      loan-flagged cognate reads "(loan)" (the P17-3 borrowed flag; rows
      not yet reparsed carry no label — honest unknown, not a claim).

      Every cognate reflex that is a gold lemma in this catalog carries its
      attestation count (searchable via `nabu search --lemma`); the rest
      are listed honestly as "not attested here". Romanization bridges
      scripts — guþ reaches *gudą through Gothic 𐌲𐌿𐌸 — and the folding is
      the conventions §9 contract (diacritics optional).

      An unstarred lemma that names no descendant FALLS BACK to a
      reconstruction-headword lookup, so the proto form itself resolves —
      typed with its phonetic superscripts (`etym bʰewgʰ`) or in pure ASCII
      (`etym bhewgh`, the §9 fold ʰ→h/ʷ→w), root hyphen optional. A quoted
      leading asterisk looks a reconstruction up directly (`etym '*bogъ'`,
      like `define '*bogъ'`) — quote the star, zsh globs a bare `*`; the
      bare-form fallback makes it mostly unnecessary. --lang scopes the
      attested match; --limit caps the entries. The MCP sibling is nabu_etym
      (bounded); this CLI prints everything.

      A lemma with NO crosswalk path at all falls back once more (P24-2) —
      to the same lookup `nabu define` runs: a prose etymological article
      (Vasmer's Russian dictionary carries no reflex edges) still answers,
      rendered in the define format under an honest "no reconstruction
      path in the crosswalk" header. A genuine total miss enumerates the
      crosswalk's live shelves, derived from the catalog.

      Examples:
        nabu etym богъ --lang chu     # Zographensis god → *bogъ → *bʰeh₂g-
        nabu etym guþ --lang got      # Gothic → *gudą → *ǵʰutós
        nabu etym bhewgh              # bare ASCII proto form → *bʰewgʰ-
        nabu etym '*kaisaraz'         # direct lookup (quoted — zsh globs *)
    HELP
    option :lang, type: :string, banner: "chu|orv|got|grc|lat|…",
                  desc: "Scope the attested-lemma match to one language"
    option :limit, type: :numeric, default: Nabu::Query::Etym::DEFAULT_LIMIT,
                   desc: "Maximum reconstruction entries printed"
    option :long, type: :boolean, default: false,
                  desc: "Expand every truncated cognate list in full, grouped by language " \
                        "(compact is the default; MCP nabu_etym stays bounded)"
    def etym(*lemma_parts)
      lemma = lemma_parts.join(" ").strip
      raise Thor::Error, "etym: give a lemma (e.g. богъ, guþ) or *reconstruction" if lemma.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
      unless catalog.table_exists?(:dictionary_reflexes)
        raise Thor::Error, "no reconstruction shelf in this catalog yet — run " \
                           "nabu sync wiktionary-recon (or nabu rebuild after one)"
      end

      fulltext = open_fulltext(config)
      @languages = Nabu::Languages.new(catalog: catalog)
      @lects = Nabu::Lects.load_default(config: config)
      query = Nabu::Query::Etym.new(catalog: catalog, fulltext: fulltext)
      results = query.run(lemma, lang: options[:lang], limit: options[:limit].to_i)
      if results.empty?
        # P24-2 coordination (owner incident 2026-07-16: define found the
        # Vasmer сигать article, etym missed flat): on a crosswalk miss,
        # fall back to the SAME Query::Define lookup the define command
        # runs — one execution path, rendered in the define house format.
        # Fallback fires ONLY on a miss: etym's primary contract stays the
        # walk, hits are never mixed.
        entries = Nabu::Query::Define.new(catalog: catalog, fulltext: fulltext)
                                     .run(lemma, lang: options[:lang], limit: options[:limit].to_i)
        print_etym_fallback(lemma, entries, shelves: query.crosswalk_shelves)
      else
        print_etym_results(results)
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "char CHAR", "The character/sign desk card: Han, Cuneiform, or Egyptian Hieroglyphs"
    long_desc <<~HELP, wrap: false
      The character card (P37-4; sign legs P65): one glyph in, the full held
      identity out — dispatched by script. A Han character gets the P37-4
      dictionary-shelf card below; a CUNEIFORM glyph (𒊬, compounds like
      𒋀𒀊 included) gets the OSL sign card (name · @aka · MZL/LAK/ABZL/
      HZL/ŠL list concordances · values by language · CDLI meaning glosses ·
      variant forms · fulltext attestation); an EGYPTIAN HIEROGLYPH (𓅃)
      gets the Unikemet card (Gardiner-plus catalog code · description ·
      function · phonetic value · JSesh/Hieroglyphica/IFAO concordances ·
      aes corpus attestation). Multi-character input is the sign-NAME lane,
      never a text lane: an OSL sign name or value spelling (SAR, szesz,
      |ŠEŠ.AB| — C-ATF ASCII folds apply, and a trailing x reads as the ₓ
      subscript: idx → idₓ), then a sign-list concordance number — MZL535
      qualified, or bare 535/852 matched across every held list (MZL, LAK,
      ABZL, HZL, ŠL, …), each hit naming the token that matched — then a
      Gardiner-style code (G5, N35). The sign cards need their modules
      synced: nabu sync osl / nabu sync unikemet. A Han READING also
      resolves: pinyin (wen · wén — toneless input folds tones) via Unihan
      kMandarin, and Japanese via KANJIDIC2 on/kun — as kana (ひと · タイ,
      hiragana/katakana fold together, okurigana dots are notation) or as
      ROMAJI on the dictionary-caps convention, no kana keyboard needed:
      ALL-CAPS is an on'yomi (TAI · KOKU), lowercase a kun'yomi (hito ·
      kuni; lowercase also answers as pinyin, each hit labeled). Every
      lane lists every character that carries the reading.

      --json emits the frozen machine contract the Edubba downstream
      consumes — the cuneiform/hieroglyph sign cards (P65) and the Han
      card (P72-2) alike; an ambiguous value input lists ALL candidate
      signs, never one silently.

      The Han card composes every shelf the library holds — the join no
      single dictionary site offers. It matches Jisho's synchronic
      completeness field-for-field where a shelf backs it, and exceeds it
      diachronically with a column no online dictionary carries. The binding
      rule everywhere: a field whose shelf can't back THIS character is
      ABSENT, never rendered "—".

      Sections, in render order (each names its backing shelf; absent
      sections are silently omitted):

        header        glyph · total strokes · KangXi radical number+name
                      (Unihan kRSUnicode/kTotalStrokes)
        decomposition the IDS structure + its components, each with the
                      follow-up commands to walk into it (BabelStone IDS)
        components    the flat component index Jisho searches (KRADFILE)
        variants      trad/simp/semantic/z-variant forms (Unihan)
        readings ja   on/kun/nanori + meanings (KANJIDIC2)
        readings      Mandarin/Korean/Vietnamese + the Unihan kJapanese layer
        pedagogy      Jōyō grade · JLPT · newspaper frequency (KANJIDIC2)
        desk-ref      the reference codes, zero suppressed — Unicode always,
                      four-corner/SKIP/JIS/dic numbers where KANJIDIC2 holds
                      them
        — the diachronic column (where nabu exceeds Jisho) —
        Old Chinese   Baxter-Sagart reconstruction + gloss
        Middle Chinese Qieyun reading, 反切, 音韻地位 (tshet-uinh)
        early Japan   positions in the Heian hanzi dictionaries (HDIC)
        TLS           sense-level concepts + classical attestation counts
        corpus        attestation frequency across the held corpora
        search        the printed `search CHAR*`-family follow-ups

      The card's grain is ONE glyph (or one sign name/code). The
      component-search siblings are `nabu search --radical N`,
      `--strokes A-B` and `--char-component C`.

      Examples:
        nabu char 棄       # reject/abandon — radical 75 木, the whole card
        nabu char 木       # the component itself; its containment neighbours
        nabu char 𒊬       # the cuneiform sign card (SAR)
        nabu char idₓ      # an ambiguous value — every candidate listed
        nabu char 𓅃       # the falcon — Unikemet card
        nabu char G5       # the same sign by Gardiner-style code
        nabu char wen      # every Han character read wén/wěn/wèn…
        nabu char ひと     # every kanji with the kun reading ひと
        nabu char TAI      # CAPS romaji = on'yomi タイ
        nabu char kuni     # lowercase romaji = kun'yomi くに
    HELP
    option :json, type: :boolean, default: false,
                  desc: "Sign cards only: emit the frozen machine-readable contract"
    option :as, type: :string,
                desc: "Narrow an ambiguous input to ONE lens: identity · reading · sign · han " \
                      "(P86-5 — `char a` is a Latin letter AND a reading AND a sign value)"
    def char(glyph = nil)
      input = Nabu::Normalize.nfc(glyph.to_s.strip)
      if input.empty?
        raise Thor::Error, "char: give a character (e.g. nabu char 棄) or a sign name/code " \
                           "(nabu char SAR · nabu char G5)"
      end

      config = Nabu::Config.load
      return char_as_lens(config, input) if options[:as]

      case Nabu::CharDispatch.lane(input)
      when :cuneiform then cuneiform_char_card(config, input)
      when :hieroglyphic then hieroglyphic_char_card(config, input)
      when :marks then editorial_marks_char_card(config, input)
      when :name then name_char_card(config, input)
      else han_char_card(config, input)
      end
    end

    desc "signs URN|TEXT", "Sign-by-sign reading of ATF transliteration through the Oracc Sign List"
    long_desc <<~HELP, wrap: false
      The cuneiform sign desk (P53-2): ATF transliteration resolved token by
      token through the Oracc Sign List (the osl module, `nabu sync osl`)
      into sign identities — value → sign name → Unicode codepoint(s)/glyph.
      The sign list adds IDENTITY, not curriculum: what each spelled value
      is, never what to make of it.

      Input is EITHER a passage/document urn out of the ATF corpora
      (cdli/oracc/ebl/etcsl shelves — the catalog is opened read-only,
      language taken from the row) OR raw ATF transliteration text
      (language via --lang; no catalog needed). C-ATF ASCII folds apply
      (sz→š, s,→ṣ, t,→ṭ, '→ʾ, u2→u₂); the ETCSL romanization (c→š, j→ŋ)
      folds automatically for etcsl urns and under --dialect etcsl for raw
      text.

      Every token carries one honest status: deterministic · qualified
      (valueₓ(SIGN) — the explicit sign resolved) · ambiguous (ALL candidate
      signs listed, never one silently) · no-codepoint (sign resolved,
      honestly unencoded upstream) · broken (x, [...]) · unknown (not in the
      OSL — said plainly). Determinatives ({d}, {gesz}) are unbraced and
      marked det. Absent data is ABSENT, never "—".

      --json emits the frozen machine contract (one object: mode/urn/
      language/dialect/source envelope, per-line token records with
      input_value · status · sign_name · codepoints[] · candidates[] ·
      language_qualifier) — the same shape the MCP nabu_signs tool serves;
      downstream consumers (Edubba reading panels) script against it.

      Examples:
        nabu signs 'lugal-e {d}en-lil2-ra'      # raw C-ATF, folded and resolved
        nabu signs --dialect etcsl 'cag4-ta'    # ETCSL romanization
        nabu signs urn:nabu:cdli:p469841        # every line of the tablet
        nabu signs --json 'szesz' | jq .        # the frozen contract
    HELP
    option :lang, type: :string, banner: "CODE",
                  desc: "Language filter for %lang-qualified sign readings (urn mode " \
                        "defaults to the passage's language)"
    option :dialect, type: :string, banner: "NAME",
                     desc: "Transliteration dialect: etcsl (c→š, j→ŋ; auto for etcsl urns)"
    option :json, type: :boolean, default: false,
                  desc: "Emit the frozen machine-readable contract instead of columns"
    def signs(*input)
      raw = input.join(" ").strip
      if raw.empty?
        raise Thor::Error, "signs: give a passage urn or raw ATF transliteration " \
                           "(e.g. nabu signs 'lugal-e {d}en-lil2-ra')"
      end

      config = Nabu::Config.load
      list = Nabu::SignList.load_default(config: config)
      if list.nil?
        raise Thor::Error, "signs: no sign list on this box yet — run `nabu sync osl` " \
                           "(the Oracc Sign List module), then retry"
      end

      dialect = signs_dialect(options[:dialect])
      catalog = nil
      if raw.start_with?("urn:")
        catalog = open_catalog(config)
        raise Thor::Error, "signs: no corpus — run nabu sync or nabu rebuild" unless catalog

        result = signs_urn_result(raw, list: list, catalog: catalog, dialect: dialect)
      else
        result = Nabu::Query::Signs.new(sign_list: list)
                                   .run_text(raw, language: options[:lang], dialect: dialect || :catf)
      end

      if options[:json]
        say JSON.generate(Nabu::Query::Signs.json_payload(result))
      else
        print_signs(result)
      end
    ensure
      catalog&.disconnect
    end

    desc "info QUERY", "One front door: the character, language/lect, or script dossier card for QUERY"
    long_desc <<~HELP, wrap: false
      The dossier front door (P90-5): one command that answers "what is
      this?" across the three desk namespaces, dispatching to the existing
      cards byte-identically — an alias, never a reimplementation:

        1. a single character (any non-ASCII grapheme) or a Gardiner-style
           sign code (G5, Aa27)                → the `nabu char` card
        2. a known language code or lect id (chu, grc:koi, sla-pro)
                                               → the `nabu language` card
        3. a script tag or script name (glag / Glagolitic — the curated
           dossiers of config/script_dossiers.yml) → the script card

      Earlier rungs win; when a language code shadows a script tag the
      language card renders and a footer names the shadowed reading.
      Anything else misses honestly, naming all three namespaces.
    HELP
    def info(query = nil)
      term = Nabu::Normalize.nfc(query.to_s.strip)
      raise Thor::Error, "info: give a character, a language/lect code, or a script tag/name" if term.empty?
      return char(term) if term.grapheme_clusters.size == 1 && !term.match?(/\A[[:ascii:]]\z/)
      return char(term) if term.match?(/\A[A-Z][a-z]?\d+[a-z]?\z/) # Gardiner-style sign codes

      config = Nabu::Config.load
      lects = Nabu::Lects.load_default(config: config, overlay: {})
      if info_language?(config, term, lects)
        language(term)
        if (tag = info_script_tag(term))
          say "(#{term.inspect} is also script tag #{tag.inspect} — languages resolve first; " \
              "`nabu info #{Nabu::ScriptDossiers.lookup(tag).name}` shows the script card)"
        end
        return
      end
      return print_script_card(tag, lects) if (tag = info_script_tag(term))

      raise Thor::Error,
            "info: #{term.inspect} is not a known character, language/lect code, or script — " \
            "try nabu char CHAR, nabu language --list, or a script tag from config/script_dossiers.yml"
    end

    desc "lemma FORM", "A lemma's attestation profile: first/last century, the gold/silver curve, sources"
    long_desc <<~HELP, wrap: false
      Reads the precompiled lemma rollup (built at rebuild and by
      `rake builders:refresh`, refreshed per source after every sync) — never
      the passages themselves, so the card is instant at any corpus size.

      - FIRST / LAST attested century, each with its date basis: "artifact"
        (the object/witness date the source asserts) or "composition"
        (author-era dating). A document's century is the MIDPOINT of its
        date envelope (300–30 BCE buckets as 2nd c. BCE).
      - The per-century curve, gold (verified annotation) and silver
        (automatic lemmatization) kept apart: attestations / documents per
        century, then one sparkline row per grade on a shared scale.
        Undated attestations close the table.
      - The top sources, and the dictionary shelves carrying the form.

      An attestation is one passage attesting the lemma (the lemma-index
      grain). FORM folds like `search --lemma`; --lang scopes to one
      language (every stored spelling of the code).

        nabu lemma hostis --lang lat
        nabu lemma λόγος --lang grc
    HELP
    option :lang, type: :string, aliases: ["--language"], banner: "CODE",
                  desc: "Scope to one language (lat, grc…; --language is an alias)"
    def lemma(form)
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "lemma: no catalog — run nabu sync or nabu rebuild" if catalog.nil?

      result = Nabu::Query::LemmaProfile.new(catalog: catalog).run(form, language: options[:lang])
      print_lemma_profile(result)
    ensure
      catalog&.disconnect
    end

    SPARK_LEVELS = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █].freeze
    ROLLUP_REFRESH_HINT = "run `bundle exec rake builders:refresh` (or the next nabu rebuild)"
    ROLLUP_MIGRATION_HINT = "this catalog predates the lemma rollups (migration 038) — " \
                            "the next nabu rebuild builds them"
    CURVE_BAR_WIDTH = 30

    no_commands do
      # The honest hints of the absent/unbuilt rollup (the desk law: a hint,
      # never a scan).
      def rollup_status_error(command, status)
        case status
        when :absent then raise Thor::Error, "#{command}: #{ROLLUP_MIGRATION_HINT}"
        when :unbuilt then raise Thor::Error, "#{command}: the rollup is not built yet — #{ROLLUP_REFRESH_HINT}"
        end
      end

      def print_lemma_profile(result)
        rollup_status_error("lemma", result.status)
        scope = result.language ? " [#{result.language}]" : ""
        if result.status == :unattested
          say "lemma #{result.form}#{scope}: not attested in the lemma rollup (gold or silver)"
          print_lemma_dictionary(result.dictionary)
          return say("lemma: 0 attestations (#{format_duration(result.seconds)})")
        end

        say "lemma #{result.form}#{scope_label(result)} — #{lemma_span(result)}"
        print_lemma_curve(result.curve)
        print_lemma_sources(result.sources)
        print_lemma_dictionary(result.dictionary)
        total = result.curve.sum { |point| point.gold[:occurrences] + point.silver[:occurrences] }
        say "lemma: #{commafy(total)} attestations · " \
            "#{dated_centuries(result.curve.count(&:century))} " \
            "(#{format_duration(result.seconds)})"
      end

      def dated_centuries(count) = "#{count} dated #{count == 1 ? 'century' : 'centuries'}"

      def scope_label(result)
        result.language ? " [#{result.language}]" : " [#{result.languages.join(', ')}]"
      end

      def lemma_span(result)
        return "no dated attestation (every attestation is undated)" unless result.first

        edge = ->(point) { "#{point.label}#{" (#{point.bases.join(', ')})" if point.bases.any?}" }
        return "attested in #{edge.call(result.first)} only" if result.first.century == result.last.century

        "first attested #{edge.call(result.first)} · last #{edge.call(result.last)}"
      end

      def print_lemma_curve(curve)
        width = (curve.map { |point| point.label.length } + [7]).max
        say "  #{'century'.ljust(width)}  #{'gold att/docs'.rjust(16)}  #{'silver att/docs'.rjust(16)}"
        curve.each do |point|
          say "  #{point.label.ljust(width)}  #{grade_cell(point.gold).rjust(16)}  " \
              "#{grade_cell(point.silver).rjust(16)}"
        end
        dated = curve.reject { |point| point.century.nil? }
        return if dated.empty?

        peak = dated.flat_map { |point| [point.gold[:occurrences], point.silver[:occurrences]] }.max
        %i[gold silver].each do |grade|
          next if dated.all? { |point| point.public_send(grade)[:occurrences].zero? }

          say "  #{grade.to_s.ljust(6)} #{sparkline(dated, grade, peak)}  " \
              "(#{dated.first.label} → #{dated.last.label}, one cell per century)"
        end
      end

      def grade_cell(tally)
        tally[:occurrences].zero? ? "—" : "#{commafy(tally[:occurrences])} / #{commafy(tally[:documents])}"
      end

      # One cell per century across the contiguous dated span (no century
      # 0 — the signed index skips it), on a scale shared by both grades so
      # the rows compare; "·" = no attestation that century.
      def sparkline(dated, grade, peak)
        by_century = dated.to_h { |point| [point.century, point.public_send(grade)[:occurrences]] }
        (dated.first.century..dated.last.century).reject(&:zero?).map do |century|
          count = by_century.fetch(century, 0)
          next "·" if count.zero?

          SPARK_LEVELS[((count.to_f / peak) * (SPARK_LEVELS.size - 1)).round]
        end.join
      end

      def print_lemma_sources(sources)
        return if sources.empty?

        cells = sources.map do |share|
          grades = []
          grades << "#{commafy(share.gold)} gold" if share.gold.positive?
          grades << "#{commafy(share.silver)} silver" if share.silver.positive?
          "#{share.slug} #{grades.join(' + ')}"
        end
        say "  top sources: #{cells.join(' · ')}"
      end

      def print_lemma_dictionary(links)
        return if links.empty?

        say "  dictionaries (nabu define for the full entry):"
        links.each do |link|
          gloss = link.gloss ? " — #{truncate_line(link.gloss, 70)}" : ""
          say "    #{link.slug}: #{link.headword}#{gloss}  #{link.urn}"
        end
      end
    end

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

      `nabu person mine SOURCE` runs the CENSUS-ONLY name scan over a held
      source's passages (the PlaceMine Han-lane shape). It writes nothing —
      The apply gate stays closed until an owner ruling on the census.

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
    HELP
    def person(*query_parts)
      return run_person_mine(query_parts[1..]) if query_parts.first == "mine"

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

    no_commands do
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

      # `nabu person mine SOURCE` (P97-2): the census-only scan; the
      # apply gate stays closed until an owner ruling, so there is no --dry-run — dry is
      # the only mode.
      def run_person_mine(args)
        source = Array(args).first
        raise Thor::Error, "usage: nabu person mine SOURCE" if source.to_s.empty?

        config = Nabu::Config.load
        catalog = Nabu::Store.connect(config.catalog_path)
        unless Nabu::Store::PersonIndex.populated?(catalog)
          raise Thor::Error, "person mine: the person index is not derived — run `nabu sync cbdb` first"
        end

        census = Nabu::PersonMine.new(catalog: catalog, progress: progress_reporter)
                                 .census(source: source)
        say "person mine: #{census.source} × #{census.authority} — #{census.passages} passages " \
            "scanned against #{census.names_loaded} Han name keys " \
            "(#{census.names_non_han} non-Han filtered, #{census.names_ambiguous} ambiguous capped; " \
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
        miner = Nabu::PlaceMine.new(catalog: catalog, journal: journal, gazetteer: gazetteer,
                                    progress: progress_reporter)
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

    # The one pointer line every deprecated `focus` alias prints (P44-r3b).
    FOCUS_POINTER = "focus is now enable/disable; this alias will be removed in a future release"

    desc "enable AXIS|SOURCE...|all", "Enable sources or axes on this box — `all` is every ungated source in one move"
    long_desc <<~HELP, wrap: false
      Add axes and/or sources to config/profile.yml — this box's ENABLEMENT
      CONFIG (P44-r3b). The entries govern BOTH what `nabu sync` / `sync --all`
      acquires AND the default row set of `nabu list` / `status` / `health` and
      the MCP nabu_status sources array. `nabu search` / `show` / `export` stay
      library-wide (enablement scopes acquisition + visibility, never reading).

      A GROUP name (core · signs) expands to the group's SOURCE members —
      its modules are machinery, pre-enabled by nature, and never enter the
      profile. `nabu enable signs && nabu sync signs` restores the whole
      sign/char capability on a fresh box.

      enable is ADDITIVE: it APPENDS (never trims). An AXIS is recorded by name
      (it expands to the axis's PUBLIC members); a SOURCE by slug. Enabling an
      axis never implicitly enables its grant-gated (blocked) members — each is
      skipped with the on-ramp line, so a private research source is only ever
      enabled by naming it. Enabling a blocked source BY SLUG runs its grant
      terms and demands a typed `granted` (or --grant-acknowledged) once,
      recorded in the ledger; a later enable skips the prompt.

      Examples:
        nabu enable germanic          # the germanic desk's public sources
        nabu enable sblgnt proiel     # two sources by slug
        nabu enable titus-avestan     # a grant-gated source: shows terms, asks
    HELP
    option :grant_acknowledged, type: :boolean, default: false,
                                desc: "Acknowledge a grant-gated source's terms non-interactively " \
                                      "(scripted use); records the acknowledgment, then enables."
    def enable(*names)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      names = names.map(&:strip).reject(&:empty?)
      raise Thor::Error, "enable: name at least one axis, source, or group to enable" if names.empty?

      # `enable all` (owner feature, 2026-10-13): the fast path to a whole
      # library — every source the box can sync unattended, in one move.
      # Access-gated rows (blocked availability, grant-gated, credential-
      # bound) are deliberately skipped with their reasons: each of those
      # must be enabled BY NAME so its own grant/credential flow runs.
      if names.include?("all")
        raise Thor::Error, "enable all: stands alone (it already covers every ungated source)" if names.size > 1

        rows = registry.slugs.map { |slug| registry[slug] }.reject(&:feature_module?)
        gated, open_rows = rows.partition { |e| e.blocked? || e.grant_required? || e.credentials }
        unless gated.empty?
          say "skipped as access-gated (enable each by name to run its grant or credential flow):"
          gated.each do |e|
            reasons = [e.blocked? ? "blocked" : nil, e.grant_required? ? "grant-gated" : nil,
                       e.credentials ? "credentials: #{e.credentials}" : nil].compact
            say "  #{e.slug} (#{reasons.join(', ')})"
          end
        end
        names = open_rows.map(&:slug)
        say "enable all → #{names.size} ungated sources"
      end

      # P68-4: a GROUP name expands to its source members (modules are
      # machinery — pre-enabled by nature, never profile entries), so
      # `nabu enable signs && nabu sync signs` is the whole restore dance.
      names = names.flat_map do |name|
        next name unless Nabu::SourceRegistry::GROUPS.include?(name)

        members = registry.group_members(name)
        sources = members.reject { |slug| registry[slug].feature_module? }
        modules = members - sources
        say "#{name} group → enabling #{sources.join(', ')}"
        say "  (#{modules.join(', ')}: modules — pre-enabled by nature)" unless modules.empty?
        sources
      end

      Nabu::Focus.validate_names!(names, registry)
      ledger = open_or_create_ledger(config)
      catalog = open_catalog(config) # read-only: only the migration detector needs it
      run_enable(config, registry, names, ledger: ledger, catalog: catalog)
    rescue Nabu::Focus::UnknownName => e
      raise Thor::Error, "enable: #{e.message}"
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      ledger&.disconnect
    end

    desc "disable AXIS|SOURCE...", "Disable sources or axes on this box (synced data stays)"
    long_desc <<~HELP, wrap: false
      Remove axes and/or sources from config/profile.yml (the enablement
      config). The synced data STAYS on disk — disabling only drops the entries
      from the enabled set, so `sync`/`list`/`status` stop touching/showing them
      by default (--all still reveals them). Withdrawal of data is a different,
      existing concept. Removing a name the registry no longer knows (drift
      after a hand-edit) is fine — disable never validates, so it also cleans up.

      Examples:
        nabu disable germanic
        nabu disable proiel
    HELP
    def disable(*names)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      names = names.map(&:strip).reject(&:empty?)
      raise Thor::Error, "disable: name at least one axis or source to disable" if names.empty?

      catalog = open_catalog(config)
      run_disable(config, registry, names, catalog: catalog)
    ensure
      catalog&.disconnect
    end

    desc "focus [only|add|drop|clear] [NAMES…]",
         "DEPRECATED — alias for enable/disable (will be removed in a future release)"
    long_desc <<~HELP, wrap: false
      DEPRECATED (P44-r3b): the focus profile was promoted to the local
      enablement config, and the verbs moved to `nabu enable` / `nabu disable`.
      Each focus subcommand still works for one release as an alias, printing a
      pointer to its replacement:

        nabu focus only <names…>  →  clear, then nabu enable <names…>
        nabu focus add  <names…>  →  nabu enable  <names…>
        nabu focus drop <names…>  →  nabu disable <names…>
        nabu focus clear          →  enable nothing (empty enabled set)
        nabu focus                →  show the current enabled set
    HELP
    def focus(action = nil, *names)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      names = names.map(&:strip).reject(&:empty?)
      say FOCUS_POINTER
      ledger = open_or_create_ledger(config)
      catalog = open_catalog(config) # read-only: only the migration detector needs it
      case action.to_s.strip
      when "" then show_enablement(effective_profile(config, registry, catalog: catalog), registry)
      when "only"
        Nabu::Focus.validate_names!(names, registry)
        Nabu::Profile.new([]).save(config.profile_path) # clear first (only = clear + enable)
        run_enable(config, registry, names, ledger: ledger, catalog: catalog)
      when "add"
        Nabu::Focus.validate_names!(names, registry)
        run_enable(config, registry, names, ledger: ledger, catalog: catalog)
      when "drop" then run_disable(config, registry, names, catalog: catalog)
      when "clear"
        Nabu::Profile.new([]).save(config.profile_path)
        say "cleared — no sources enabled (nabu enable <axis|source> to add)"
      else
        raise Thor::Error, "focus: unknown action #{action.inspect} — use only, add, drop, clear " \
                           "(or the new nabu enable/disable)"
      end
    rescue Nabu::Focus::UnknownName => e
      raise Thor::Error, "focus: #{e.message}"
    ensure
      catalog&.disconnect
      ledger&.disconnect
    end

    desc "cognates TARGET", "Verses where aligned witnesses use reflexes of the same root (architecture §12)"
    long_desc <<~HELP, wrap: false
      The comparativist's join (P15-3): verses of a registered alignment work
      where witnesses in TWO OR MORE languages use reflexes of the SAME
      reconstruction root — the alignment hub (nabu align) crossed with the
      Wiktionary reconstruction crosswalk (nabu etym). Gothic salt ~ OCS соль
      meet at PIE *sḗh₂l in the salt saying (LUKE 14.34); hlaifs ~ хлѣбъ at
      *hlaibaz in "he who eats my bread" (JOHN 13.18).

      TARGET is a registered work id (nt, ot, psalms — batches the whole
      work), a verse ref (LUKE 14.34), a chapter (LUKE 14), or a book (LUKE).
      Each hit names the root with its SHELF — and the shelf is part of the
      answer: a Slavic witness meeting a Germanic witness at a gem-pro entry
      (*hlaibaz, *kaisaraz) is very possibly a BORROWING, not common descent;
      ine-pro meets are the inheritance signal. Since P17-3 a witness whose
      descent from the root the crosswalk FLAGS as a loan reads "(loan)"
      (chu хлѣбъ (loan) ~ got hlaifs at *hlaibaz — the flag ORs along the
      closure path, so a loan on a proto-to-proto edge still fires); the
      shelf heuristic remains the caption for unflagged edges — upstream
      flags are high-precision, low-recall — and rows predating the flag
      reparse carry no label (honest unknown).

      Corpus-common words are suppressed by default (a lemma in ≥ 10% of its
      language's gold passages, absolute floor 50 — ὁ, jah, и would otherwise
      flood every verse); --all shows them, and the header counts what fell.
      Frequency is a coarse proxy: богъ (4.9% of OCS) and нъ "but" (4.7%) are
      inseparable by df, so some common words survive — read the hits.

      Recall is bounded by Wiktionary descendants coverage (roughly a third
      of Gothic and a fifth of OCS gold lemma types reach any proto entry)
      and by gold lemmatization (~10% of the corpus): absence of a hit is
      absence of evidence, not evidence of unrelatedness.

      --langs got,chu restricts the comparison to the named languages (at
      least two); --work picks the alignment work when the ref is ambiguous;
      --long lifts the #{Nabu::Query::Cognates::MAX_GROUPS}-hit compact cap
      and expands gloss/dictionary/document detail per hit.

      BATCH MODE (P16-2, the links journal): `cognates --batch WORK` maps the
      whole work once and PERSISTS kind=cognate edges between the aligned
      witness passages that meet at a reconstruction root — one edge per
      cross-language passage pair, its detail carrying the meet (ref · root
      [SHELF] — the shelf rides every edge because a gem-pro meet for a
      Slavic witness reads as a borrowing), its score the distinct-root
      count. WORK must be a registered work id (per-ref runs stay
      interactive). Common-word suppression stays on (--all lifts it, and
      the run records that); a rerun of the same work supersedes
      (idempotent); --db writes the journal elsewhere. Interactive output is
      never persisted.

      Examples:
        nabu cognates "LUKE 14.34"            # the salt saying, all languages
        nabu cognates nt --langs got,chu      # the whole NT, Gothic × OCS
        nabu cognates "JOHN 13" --langs got,chu,grc
        nabu cognates nt --langs got,chu --all  # keep the common-word matches
        nabu cognates --batch nt --langs got,chu  # persist the Gothic × OCS cognate map
    HELP
    option :work, type: :string,
                  desc: "Alignment work id (optional when the target decides it)"
    option :langs, type: :string, banner: "got,chu", aliases: ["--lang"],
                   desc: "Restrict the comparison to these languages (comma-joined, at least two); " \
                         "--lang is the standing alias (the one language-filter spelling)"
    option :all, type: :boolean, default: false,
                 desc: "Show the common-word matches the default suppresses"
    option :long, type: :boolean, default: false,
                  desc: "Render every hit (compact caps at #{Nabu::Query::Cognates::MAX_GROUPS}) " \
                        "and expand gloss/dictionary/document detail"
    option :batch, type: :boolean, default: false,
                   desc: "Map the whole WORK once and persist kind=cognate edges to the links journal"
    option :db, type: :string, banner: "PATH",
                desc: "With --batch: write the links journal at PATH instead of db/links.sqlite3"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Scope witnesses OF THIS LECT'S ANCHOR LANGUAGE to the lect (P59-3: " \
                        "--lect grc:koi keeps cognate sets whose Greek witness is Koine; " \
                        "other-language witnesses pass untouched); errors if the nabu-lects " \
                        "module is not synced"
    display_option
    def cognates(*target_parts)
      target = target_parts.join(" ").strip
      display_mode
      return batch_cognates(target) if options[:batch]

      if options[:db]
        raise Thor::Error, "cognates: --db only applies with --batch " \
                           "(interactive results are never persisted)"
      end
      raise Thor::Error, "cognates: give a work id (nt) or a citation ref (e.g. LUKE 14.34)" if target.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog && fulltext

      registry = Nabu::AlignmentRegistry.load(config.alignments_path)
      result = Nabu::Query::Cognates.new(catalog: catalog, fulltext: fulltext, registry: registry)
                                    .run(target, work: options[:work], langs: parse_langs(options[:langs]),
                                                 all: options[:all], long: options[:long],
                                                 lect: options[:lect])
      print_cognates(result)
      print_display_footer
    rescue Nabu::Query::Cognates::Error, Nabu::ValidationError => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "vocab URN", "Lemma-frequency profile of a document/range vs the corpus (gold shelves only)"
    long_desc <<~HELP, wrap: false
      Profile the gold-lemma vocabulary of one document, a citation range, or a
      single passage (P14-3, improvements §1.7): total tokens carrying a gold
      lemma, how many distinct lemmas, the most DISTINCTIVE vocabulary, and the
      in-document hapax legomena (lemmas attested exactly once).

      "Distinctive" means over-represented HERE versus the whole corpus, ranked
      by a log-odds-ratio with an informative Dirichlet prior (Monroe et al.
      2008) — the z-score damps rare-lemma noise a plain frequency ratio would
      let blow up, so the list is the text's real subject vocabulary, not its
      accidental singletons (those get their own hapax line). Each row shows the
      lemma's document token count and its corpus passage-frequency.

      Gold lemmas exist only for the treebank shelves (PROIEL, TOROT, ISWOC, the
      UD treebanks) and the ORACC cuneiform layer — about 8% of the corpus. A
      document without gold lemmas (Perseus, First1K, the papyri, ASPR poetry)
      is not an error: it says so plainly and lists the gold-bearing languages
      so you can profile something that works. --limit caps both the distinctive
      list and the hapax spellings printed (default #{Nabu::Query::Vocab::DEFAULT_LIMIT}).

      DIACHRONY (--by-century): instead of one document's lemmas, plot the DATED
      corpus across centuries (P15-2, the timeline). Bare, it is the shape
      of your dated holdings — one row per century (BCE/CE), the document count.
      With a text QUERY it becomes "plot this word across centuries": how many
      dated documents attest the term in each century. Composes with --lang,
      --license, --from/--to/--century, and --place; counts are per DOCUMENT and
      bucketed by EARLIEST year (a ranged papyrus lands in its first century), so
      the footer names how many span more than one century. Most of the corpus is
      undated (papyri via HGV, Slovene goo300k/IMP carry dates); undated
      documents are simply absent here, never an error.

      Examples:
        nabu vocab urn:nabu:proiel:caes-gal          # Caesar's Gallic War
        nabu vocab urn:nabu:proiel:cic-off --limit 30
        nabu vocab urn:nabu:proiel:hdt:1.1-1.100     # a citation range
        nabu vocab --by-century                      # the dated corpus over time
        nabu vocab --by-century στρατηγ --lang grc   # a word plotted across centuries
        nabu vocab --by-century --place oxyrhynch%   # Oxyrhynchus, century by century
    HELP
    option :limit, type: :numeric, default: Nabu::Query::Vocab::DEFAULT_LIMIT,
                   desc: "Cap the distinctive list and hapax spellings printed"
    option :long, type: :boolean, default: false,
                  desc: "List every hapax legomenon (and every gold-bearing language) in full, " \
                        "escaping the --limit display cap (the distinctive ranking stays top-N)"
    option :by_century, type: :boolean, default: false,
                        desc: "Diachronic mode: bucket the DATED corpus (or a text query) by century"
    option :lang, type: :string, desc: "With --by-century: restrict to a language (grc, lat, …)"
    option :license, type: :string, desc: "With --by-century: restrict to an exact license class"
    option :from, type: :numeric, banner: "YEAR", desc: "With --by-century: earliest year (negative = BCE)"
    option :to, type: :numeric, banner: "YEAR", desc: "With --by-century: latest year"
    option :century, type: :numeric, banner: "N", desc: "With --by-century: one century's window (6, -2)"
    option :place, type: :string, banner: "PATTERN", desc: "With --by-century: provenance place LIKE filter"
    option :chars, type: :boolean, default: false,
                   desc: "Character-grain profile (P72-4): per-document Han character frequencies " \
                         "— the sinograph instrument for unlemmatized documents (kanripo/cbeta/aozora)"
    option :coverage, type: :string, banner: "CHARS",
                      desc: "With --chars: coverage of the document against this character set " \
                            "(fold-aware) — occurrence %, distinct split, and the top strangers"
    option :json, type: :boolean, default: false,
                  desc: "With --chars: emit the frozen machine contract instead of the card"
    def vocab(urn = nil)
      urn = urn.to_s.strip
      return vocab_by_century(urn) if options[:by_century]
      raise Thor::Error, "vocab: give a document, range, or passage urn" if urn.empty?
      return char_vocab(urn) if options[:chars]
      raise Thor::Error, "vocab: --coverage/--json ride the --chars profile" if options[:coverage] || options[:json]

      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
      unless fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
        raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                           "run nabu sync or nabu rebuild"
      end

      profile = Nabu::Query::Vocab.new(catalog: catalog, fulltext: fulltext)
                                  .run(urn, limit: options[:limit].to_i)
      print_vocab(profile)
    rescue Nabu::Query::Vocab::NotFound, Nabu::Query::Range::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "mcp", "Serve the corpus to an AI client over MCP (stdio, read-only) — see docs/mcp.md"
    long_desc <<~HELP, wrap: false
      Run the Model Context Protocol server on stdin/stdout: a READ-ONLY
      conversational surface over the local nabu corpus, exposing thirteen
      tools — nabu_search (full-text, lemma, morph, similar), nabu_show,
      nabu_concord (KWIC), nabu_align, nabu_parallels, nabu_links,
      nabu_define (the dictionary shelves), nabu_etym, nabu_cognates,
      nabu_char, nabu_signs, nabu_place, and nabu_status (coverage) — to
      any MCP client (Claude Code, Claude Desktop). The catalog and index are opened
      SQLITE_OPEN_READONLY: this process is POSITIVELY unable to write to db/.

      This is a plumbing command, not an interactive one. STDOUT IS THE PROTOCOL
      CHANNEL — it carries newline-delimited JSON-RPC and nothing else.
      Diagnostics go to stderr, or appended to a file with --log FILE. The
      openers are lazy and read-only, so a corpus that appears or is rebuilt
      mid-session is picked up without a restart. The server runs until stdin
      closes (EOF) or it is signalled (SIGINT/SIGTERM), then exits 0.

      You normally never type this yourself — a client spawns it. This repo ships
      .mcp.json, so opening Claude Code in the repo registers nabu automatically.
      User-scope, Claude Desktop, the tool reference, the license/attribution
      stance, and an example transcript are in docs/mcp.md.

      Examples:
        nabu mcp                       # a client spawns this; speaks JSON-RPC on stdio
        nabu mcp --log /tmp/nabu-mcp.log   # tee diagnostics to a file (stdout stays clean)
    HELP
    option :log, type: :string, banner: "FILE",
                 desc: "Append diagnostics to FILE instead of stderr (stdout is the protocol channel)"
    def mcp
      config = Nabu::Config.load
      log = mcp_log(options[:log])
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # Lazy, memoizing, read-only openers (Nabu::ReadonlyOpener — a
      # later sweep extracted the P8-2 plumbing): resolved on every tool call, so a
      # corpus that appears or is rebuilt mid-session is picked up without
      # a restart; nil when the file is absent (Tools renders the graceful
      # "no corpus" / "rebuilding" states). The watchdog below vacates
      # stale handles on IDLE sessions too — the P93 incident: a deleted
      # pre-rebuild catalog's 118 GB stayed pinned for days because the
      # per-call re-stat never ran without a call.
      openers = {
        catalog: Nabu::ReadonlyOpener.new(config.catalog_path) do
          Nabu::Store.connect(config.catalog_path, readonly: true)
        end,
        fulltext: Nabu::ReadonlyOpener.new(config.fulltext_path) do
          Nabu::Store.connect_fulltext(config.fulltext_path, readonly: true)
        end,
        # The history ledger, read-only (P14-12): nabu_status surfaces the
        # cached upstream-drift verdicts from source_probes. MCP reads the raw
        # dataset (no model binding) and NEVER probes upstreams live.
        ledger: Nabu::ReadonlyOpener.new(config.history_path) do
          Nabu::Store.connect(config.history_path, readonly: true)
        end,
        # The links journal, read-only (P16-1): nabu_links reads batch-mined
        # edges. Absent file = no batch has run (a graceful state).
        links: Nabu::ReadonlyOpener.new(config.links_path) do
          Nabu::Store.connect(config.links_path, readonly: true)
        end,
        # The vector store, read-only (P93-5): nabu_search's similar_to.
        # Absent file = never embedded (the honest-note state).
        vectors: Nabu::ReadonlyOpener.new(config.vectors_path) do
          Nabu::Store.connect(config.vectors_path, readonly: true)
        end
      }
      Nabu::ReadonlyOpener.watch(openers.values)
      tools = Nabu::MCP::Tools.new(
        catalog: openers[:catalog].to_proc,
        fulltext: openers[:fulltext].to_proc,
        ledger: openers[:ledger].to_proc,
        links: openers[:links].to_proc,
        vectors: openers[:vectors].to_proc,
        # Static config, loaded once — a malformed registry fails HERE, loudly,
        # not mid-conversation.
        alignments: Nabu::AlignmentRegistry.load(config.alignments_path),
        # The source registry (P23-3b): authoritative for enablement, so
        # nabu_status renders a sources.yml flip immediately (the db row only
        # mirrors it at the source's next sync).
        registry: registry,
        # The enabled-slug set (P44-r3b): nabu_status's sources array defaults
        # to this box's enabled sources, matching the CLI list/status default.
        enabled_slugs: mcp_enabled_slugs(config, registry),
        # The Pleiades gazetteer (P44-3): :auto = feature-detect lazily per
        # call (nabu_place, nabu_show findspot) — the derived catalog place
        # index when a sync/rebuild has built it (P45-6, instant), else the
        # canonical dump; an unsynced box degrades exactly like the CLI,
        # never crashes.
        pleiades: :auto,
        # The Oracc Sign List (P53-2): :auto = feature-detect canonical/osl
        # lazily per call (nabu_signs); an unsynced box notes the sync hint,
        # every other tool byte-identical (the lane-off rule).
        sign_list: :auto,
        # The sign-card seams (P68-3, nabu_char): same lazy feature-detect
        # posture — CDLI readings ride canonical/osl/00etc, the Egyptian
        # spine canonical/unikemet.
        readings: :auto, hieroglyphs: :auto,
        # Tibetan word segmentation (P54-2): :auto = feature-detect
        # canonical/nabu-data lazily inside Query::Show (nothing loads
        # unless nabu_show is asked for a segmented render); an unsynced
        # box answers the flag with the sync-hint note.
        tibetan_words: :auto,
        # The nabu-lects module (P57-4): :auto = feature-detect
        # canonical/nabu-lects lazily per call (nabu_search's `lect`
        # filter); an unsynced box answers `lect` with an InvalidArguments
        # naming the module, every other tool byte-identical.
        lects: :auto,
        # The lect-provenance gloss seams (P81 U-5): static config, loaded
        # once — the rules' tier: words and the override rows' tier: map,
        # joined against each shown document's facet basis.
        lect_rules: Nabu::LectRules.load(config.lect_facet_rules_paths),
        lect_override_tiers: Nabu::Lects.override_tiers(config.lect_overrides_paths)
      )
      $stdout.sync = true
      install_mcp_signal_traps
      # stdout carries protocol only; every diagnostic goes to the log IO.
      Nabu::MCP::Server.new(tools: tools, log: log).run($stdin, $stdout)
    ensure
      log.close if log && !log.equal?($stderr)
    end

    # P121-1: `nabu export` is a command family — the research tables
    # (documents, links: a file + license manifest under exports/) and the
    # passage stream, which stays the DEFAULT command so `nabu export
    # --format jsonl ...` is byte-unchanged (ExportCLI).
    desc "export SUBCOMMAND ...ARGS",
         "Research exports — documents/links tables with a license manifest — and the passage stream"
    subcommand "export", ExportCLI

    desc "backup", "Snapshot the permanent set (canonical/, config/, local/, .docs/) — never the derived dbs"
    long_desc <<~HELP, wrap: false
      File-level rsync backup (architecture §8, P7-2; the P71 three-folder
      contract) — the concept's promise: restorable from a plain rsync copy
      with zero services running. The REQUIRED set is everything permanent:

        canonical/   the asset, INCLUDING every .attic/ (upstream-scrapped
                     files that exist nowhere else — a per-slug git mirror
                     would miss them; file-level or nothing)
        config/      the project definition (registries, rules, postures)
        local/       THE INSTANCE: owner rulings, grants, profile, the
                     history ledger, acquisitions — never in the repo

      Everything under db/ is derived (`nabu rebuild` regenerates it from
      the three folders) and is NEVER backed up (owner ruling 2026-08-16):
      restore = clone the repo, rsync the folders back, `nabu rebuild`.
      A pre-P71 box whose ledger still sits at db/history.sqlite3 is
      refused up front — run `nabu migrate-local` first, then back up.

      Target: local/config/settings.yml `backup: target:` (a path under a
      mounted external volume), overridable with --to PATH.

      THE MOUNT-POINT GUARD: the target must live on a REAL mounted volume. If
      the volume is not mounted, the path is a bare directory on the boot disk,
      and rsync would silently back up onto it — then shadow the real volume once
      it mounts. backup REFUSES this unless --allow-unmounted (for deliberately
      local targets: the drill, a scratch copy).

      --dry-run prints the rsync plan and changes nothing.

      Examples:
        nabu backup                                   # to the configured volume
        nabu backup --to /Volumes/NabuBackup/nabu     # explicit target
        nabu backup --dry-run                          # show the plan
    HELP
    option :to, type: :string,
                desc: "Target path override (default: backup.target in the local/config/settings.yml overlay)"
    option :dry_run, type: :boolean, default: false, desc: "Print the rsync plan and change nothing"
    option :allow_unmounted, type: :boolean, default: false,
                             desc: "Skip the mount-point guard (for a deliberately-local target)"
    def backup
      config = Nabu::Config.load
      result = Nabu::Backup.new(
        config: config, target: options[:to],
        dry_run: options[:dry_run], allow_unmounted: options[:allow_unmounted]
      ).run
      print_backup(result)
      raise Thor::Error, backup_failure_summary(result) unless result.ok?
    rescue Nabu::Backup::Error => e
      # No target, or the mount-point guard tripped: a clean stderr message + exit 1.
      raise Thor::Error, e.message
    end

    # How many evidence spans / shared lemmas a compact `parallels` hit shows
    # before it elides with a "… and N more" tail; --long lifts the cap.
    PARALLELS_COMPACT_ITEMS = 3
    # Compact evidence-span width; --long prints the span untrimmed.
    PARALLELS_SPAN_CHARS = 72
    # Edges shown per kind by `nabu links` before the "… and N more" tail
    # (--long lists all — the conventions §10 house rule).
    LINKS_COMPACT_ITEMS = 10
    # Language codes shown by the `nabu axis` desk card's languages line
    # before the "… and N more" tail (P48-r3; --long lists all — the same
    # house render-cap rule).
    AXIS_LANGUAGES_ITEMS = 10
    # Crosswalk equivalences shown on the place card's "=" line before the
    # "… and N more" tail (P75 C-3, the same house render-cap rule).
    # const: a render cap, not a corpus census
    PLACE_EQUIVALENCES_SHOWN = 8
    # Reading values shown on the `search --sign` header line before the
    # "… and N more" tail (P75 C-4, the same house render-cap rule).
    # const: a render cap, not a corpus census
    SIGN_SEARCH_VALUES_SHOWN = 12
    # RTL snippet highlight = SGR reverse video (P42-r4, strike 4 — the
    # matrix ruling on the owner's iTerm2). Every CHARACTER-based highlight
    # is at the mercy of the renderer's bidi treatment, and four attempts
    # measured four failure modes; a cell ATTRIBUTE rides the glyph wherever
    # reordering moves it and cannot be broken by any bidi algorithm.
    RTL_HIGHLIGHT_ON = "\e[7m"
    RTL_HIGHLIGHT_OFF = "\e[27m"
    # Batch-mining progress tick cadence (anchors per stderr line); a scope
    # smaller than one tick prints no progress at all — just the summary.
    BATCH_PROGRESS_EVERY = 200

    # The no-silent-script-miss table (P27-2). A zero-hit query carrying
    # codepoints of a script NO fold neutralization covers gets ONE honest
    # hint naming what to try — the owner incident was exactly a silent
    # cross-script miss. Censused entries only: Glagolitic rides the OCS
    # dictionary shelf as variant forms (never passage text), and the
    # Gothic corpora are romanized (conventions §9). Devanagari and
    # Cyrillic do NOT hint — their neutralizations already fold them.
    SCRIPT_MISS_HINTS = {
      "Glagolitic" => [0x2C00..0x2C5F,
                       "no cross-script fold is registered for Glagolitic — the Slavic shelves " \
                       "index Cyrillic and Latin-diplomatic spellings (try въста or vъsta)"],
      "Gothic-script" => [0x10330..0x1034F,
                          "no cross-script fold is registered for Gothic script — the Gothic " \
                          "corpora are romanized (try guþ, jah)"]
    }.freeze

    # H9 (P35-6): the skip-with-note rule for a corrupt annotations_json —
    # Show marks the parse failure (ANNOTATIONS_UNREADABLE) and every
    # render that would have used the lane says so.
    ANNOTATIONS_UNREADABLE_NOTE = "stored annotations are unreadable (invalid JSON) — skipped"

    no_commands do
      # -- display policy (P27-0) ------------------------------------------
      # Passage text reaches the terminal ONLY through display_text, which
      # applies the per-language display.yml policy under the --display mode
      # and records what changed; print_display_footer then hints ONCE per
      # invocation — never silent alteration, never a hint when nothing
      # happened. MCP and export never touch this path: pristine text.

      # Resolve --display MODE against the registry; validate before any
      # output so an unknown mode is a clean named error.
      def display_mode
        @display_mode ||= Nabu::Display.mode(options[:display] || Nabu::Display::DEFAULT_MODE)
      rescue Nabu::Display::UnknownModeError => e
        raise Thor::Error, e.message
      end

      def display_policies
        @display_policies ||= Nabu::Display.load_policies(Nabu::Config.load.display_path)
      rescue Nabu::Display::ConfigError => e
        raise Thor::Error, e.message
      end

      def display_source_policies
        @display_source_policies ||= Nabu::Display.load_source_policies(Nabu::Config.load.display_path)
      rescue Nabu::Display::ConfigError => e
        raise Thor::Error, e.message
      end

      # Render one run of text for the terminal and remember which transforms
      # actually applied (for the footer hint). +source+/+annotations+
      # (P27-1) are the optional edition context — call sites that know the
      # passage's source (the show family) pass them so `--display reading`
      # can apply the per-source convention rules and the ketiv/qere choice;
      # everywhere else the language-level policies alone apply.
      def display_text(text, language, source: nil, annotations: nil)
        @display_gaiji_ladder = true if source && display_source_policies[source]&.gaiji == "ladder"
        rendered = Nabu::Display.render(text.to_s, language: language,
                                                   mode: display_mode, policies: display_policies,
                                                   source: source, annotations: annotations,
                                                   source_policies: display_source_policies,
                                                   gaiji_map: gaiji_map_for(source),
                                                   gaiji_ids: gaiji_ids_for(source),
                                                   gaiji_substitutes: gaiji_substitutes_for(source))
        display_applied.merge(rendered.applied)
        record_gaiji(rendered.gaiji)
        rendered.text
      end

      def display_applied
        @display_applied ||= Set.new
      end

      # Render a SNIPPET — StoredSnippet output with the match in [brackets] —
      # for the terminal (P42-r4, four strikes deep). Square brackets inside
      # RTL text are unrenderable-portably: they are a bidi-mirrored pair,
      # and each character-based fix failed a different way on the owner's
      # iTerm2 (mirrorless reversal showed ]word[; brackets cut OUT of the
      # isolate were swept into the reversed segment anyway; the symmetric ‖
      # detached at passage-edge matches; RLM gluing was ignored — invisible
      # bidi controls do not extend that renderer's runs, though a VISIBLE
      # strong-R paseq does, matrix line 8). The ruling fix highlights with
      # a cell ATTRIBUTE instead of characters: SGR reverse video rides the
      # glyph wherever reordering moves it and no bidi algorithm can touch
      # it (matrix line 9 on the owner's screen). Gated by color_output?
      # (mode + NO_COLOR/NABU_COLOR/tty): piped or colorless output keeps
      # the logical [brackets] — no renderer, no bidi, and the documented
      # grep/MCP contract stays byte-identical. ANSI escapes are ASCII —
      # untouched by mark strips and NFC round-trips (the painted-tokens
      # precedent). Only PAIRED brackets convert (a stored lone Leiden
      # bracket stays literal); a stored [...] lacuna pair colors like a
      # match — the same ambiguity the bracket convention always had.
      def display_snippet(text, language)
        unless Nabu::Display.isolates?(language: language.to_s, mode: display_mode,
                                       policies: display_policies) && color_output?
          return display_text(text, language)
        end

        marked = text.to_s.gsub(/\[([^\[\]]*)\]/) { "#{RTL_HIGHLIGHT_ON}#{Regexp.last_match(1)}#{RTL_HIGHLIGHT_OFF}" }
        display_text(marked, language)
      end

      # The source's three gaiji ladder lanes (P37-3/P38-2), each memoized per
      # source: config/gaiji/<source>.tsv (faithful), <source>-ids.tsv (IDS)
      # and <source>-substitutes.tsv (substitutes) — only kanripo ships them
      # today. A missing file is an empty map (that rung degrades to the next),
      # and the non-show call sites (no source) never load a map at all.
      def gaiji_map_for(source) = gaiji_lane(source, "")

      def gaiji_ids_for(source) = gaiji_lane(source, "-ids")

      def gaiji_substitutes_for(source) = gaiji_lane(source, "-substitutes")

      def gaiji_lane(source, suffix)
        return {} unless source

        (@gaiji_lanes ||= {})[[source, suffix]] ||=
          Nabu::Display.load_gaiji_map(File.join(Nabu::Config.load.gaiji_dir, "#{source}#{suffix}.tsv"))
      end

      # Running per-rung gaiji tallies for the once-per-invocation footer
      # ([faithful, ids, substitute, placeholder], summed across every passage a
      # show-family command renders).
      def display_gaiji
        @display_gaiji ||= [0, 0, 0, 0]
      end

      def record_gaiji(tally)
        return unless tally

        display_gaiji[0] += tally.faithful
        display_gaiji[1] += tally.ids
        display_gaiji[2] += tally.substitute
        display_gaiji[3] += tally.placeholder
      end

      # Per-token language coloring (P27-2): the single-passage show view —
      # the one render where the stored P7-5 tokens annotation is at hand —
      # colorizes tokens tagged with a language OTHER than the passage's own
      # (corph's Latin glosses in Old Irish, OSHB's Aramaic verses). Gated
      # three ways: the mode's #colors? (mono/full say no), NO_COLOR /
      # NABU_COLOR / tty (Display.color?), and the honest-tagging rule
      # (untagged and base-language tokens stay uncolored). Painting wraps
      # PRISTINE token forms before the display transform — ANSI escapes are
      # ASCII, untouched by mark-class strips and NFC round-trips.
      def painted_passage_text(passage)
        return passage.text unless color_output?

        tokens = passage.annotations["tokens"]
        return passage.text unless tokens.is_a?(Array)

        painted, legend = Nabu::Display::TokenColors.paint(passage.text, tokens: tokens,
                                                                         language: passage.language)
        return passage.text if legend.empty?

        display_applied << "token colors: #{legend.map { |lang, color| "#{lang}=#{color}" }.join(' ')}"
        painted
      end

      def color_output?
        mode = display_mode
        (!mode.respond_to?(:colors?) || mode.colors?) && Nabu::Display.color?(tty: $stdout.tty?)
      end

      # The once-per-invocation honesty footer: named only when a transform
      # actually changed something (compact rule — zero-signal silence).
      #   display: cantillation stripped (--display full shows all marks)
      #   display: cantillation stripped · rtl isolates (--display full shows all marks)
      # One footer per invocation, composing every applied transform's
      # vocabulary (P27-0 strips · P27-1 edition · P27-2 translit/colors/
      # spacing); the escape hatch names diplomatic when edition transforms
      # applied, else full.
      def print_display_footer
        gaiji_text = gaiji_clause(*display_gaiji)
        return if display_applied.empty? && gaiji_text.nil?

        labels = display_applied.to_a
        edition = Nabu::Display::EDITION_LABELS & labels
        parts = []
        parts << "transliterated" if labels.delete("translit")
        colors = labels.select { |label| label.start_with?("token colors") }
        strips = labels - colors - edition - ["spacing", Nabu::Display::ISOLATES]
        parts << "#{strips.join(', ')} stripped" unless strips.empty?
        parts << "apparatus simplified: #{edition.join(', ')}" unless edition.empty?
        parts << gaiji_text if gaiji_text
        parts << "spacing" if labels.include?("spacing")
        parts.concat(colors)
        parts << Nabu::Display::ISOLATES if labels.include?(Nabu::Display::ISOLATES)
        say "display: #{parts.join(' · ')} (#{display_footer_hint(edition, !gaiji_text.nil?)})"
      end

      # The escape-hatch hint: diplomatic when any edition-level transform ran
      # (apparatus OR gaiji — both are "shown as stored" under diplomatic),
      # naming "refs" when gaiji is the only edition transform; else full.
      def display_footer_hint(edition, gaiji)
        return "--display diplomatic shows the edition marks" unless edition.empty?
        return "--display diplomatic shows the gaiji refs" if gaiji

        "--display full shows all marks"
      end

      # The gaiji footer clause, per rung. Returns nil when there is nothing to
      # announce. Two shapes, honest to the policy:
      #   ladder (P38-2)     — FAITHFUL is silent (it IS the character); the
      #                        lossy rungs (substitutes, IDS compositions) and
      #                        the ⬚ placeholders DO get announced ("never
      #                        silent"). An all-faithful render says nothing.
      #   placeholder (P37-3) — the preserved rungs-1+4 vocabulary: unresolved
      #                        (⬚) refs and how many resolved to a real glyph.
      def gaiji_clause(faithful, ids, substitute, placeholder)
        return ladder_gaiji_clause(ids, substitute, placeholder) if @display_gaiji_ladder

        placeholder_gaiji_clause(faithful, placeholder)
      end

      def ladder_gaiji_clause(ids, substitute, placeholder)
        bits = []
        bits << "#{substitute} substituted" if substitute.positive?
        bits << "#{ids} composed" if ids.positive?
        bits << "#{placeholder} unresolved gaiji" if placeholder.positive?
        bits.empty? ? nil : bits.join(", ")
      end

      def placeholder_gaiji_clause(resolved, unresolved)
        if unresolved.positive? && resolved.positive?
          "#{unresolved} unresolved gaiji (#{resolved} resolved)"
        elsif unresolved.positive?
          "#{unresolved} unresolved gaiji"
        elsif resolved.positive?
          "#{resolved} gaiji resolved"
        end
      end

      # Reject an unknown --license up front (before opening any db) with the
      # closed enum of valid classes, so the user sees the choices. Shared by
      # search and export.
      def validate_license!(license)
        return if license.nil?
        return if Nabu::SourceManifest::LICENSE_CLASSES.include?(license)

        raise Thor::Error,
              "unknown license #{license.inspect} " \
              "(choose from #{Nabu::SourceManifest::LICENSE_CLASSES.join(', ')})"
      end

      # Resolve --century (a whole century's bounds) OR --from/--to into a
      # [from, to] signed-historical-year window (P15-2). The reviewed guards:
      # no year 0 (1 BCE = -1, 1 CE = +1), a clear F>T message (not a silent
      # empty result), and --century is mutually exclusive with --from/--to.
      def date_window
        if options[:century]
          if options[:from] || options[:to]
            raise Thor::Error, "date filter: --century is shorthand for --from/--to — use one or the other"
          end

          idx = options[:century].to_i
          raise Thor::Error, "date filter: there is no century 0 (1st c. CE is 1, 1st c. BCE is -1)" if idx.zero?

          return Nabu::Timeline.century_bounds(idx)
        end

        from = coerce_year(options[:from], "--from")
        to = coerce_year(options[:to], "--to")
        if from && to && from > to
          raise Thor::Error, "date filter: --from #{from} is after --to #{to} " \
                             "(BCE years are negative — 300 BCE is -300, so -300 comes before -30)"
        end
        [from, to]
      end

      # The parsed --date-basis class list (P122-1, Nabu::Query::DateBasis), or
      # nil. Validated up front — before any db opens — so an unknown class
      # exits 1 naming the known set, the validate_license! stance.
      def date_basis_filter
        Nabu::Query::DateBasis.parse(options[:date_basis])
      rescue Nabu::Error => e
        raise Thor::Error, "search: #{e.message}"
      end

      def coerce_year(value, flag)
        return nil if value.nil?

        year = value.to_i
        raise Thor::Error, "date filter: there is no year 0 (#{flag}); 1 BCE is -1, 1 CE is 1" if year.zero?

        year
      end

      # A date/place filter needs document_axes; a catalog that predates
      # migration 008 (never rebuilt) hasn't got it. Fail with a clear pointer
      # rather than a Sequel "no such table".
      def require_timeline!(catalog)
        return if catalog.table_exists?(:document_axes)

        raise Thor::Error, "no timeline (this catalog predates it) — run nabu rebuild"
      end

      # A facet filter needs document_facets (migration 009) — same honest
      # pointer as the timeline guard.
      def require_facets!(catalog)
        return if catalog.table_exists?(:document_facets)

        raise Thor::Error, "no facet table (this catalog predates it) — run nabu rebuild"
      end

      # The active facet filters as {facet name => pattern}, or nil when none
      # (P17-2): --type → genre, --province → province, --material → material;
      # each --facet NAME=PATTERN adds its name (a repeat of a name wins last).
      def facet_filters
        filters = {}
        filters["genre"] = options[:type] if options[:type]
        filters["kind"] = options[:kind] if options[:kind]
        filters["province"] = options[:province] if options[:province]
        filters["material"] = options[:material] if options[:material]
        filters.merge!(facet_specs(command: "search", example: "subject=왕실-%"))
        filters.empty? ? nil : filters
      end

      # The repeatable --facet NAME=PATTERN specs as {name => pattern} (a
      # repeat of a name wins last) — search's and define's shared parse.
      def facet_specs(command:, example:)
        Array(options[:facet]).to_h do |spec|
          name, pattern = spec.to_s.split("=", 2).map(&:strip)
          if name.to_s.empty? || pattern.to_s.empty?
            raise Thor::Error, "#{command}: --facet takes NAME=PATTERN (#{example}) — got #{spec.inspect}"
          end

          [name, pattern]
        end
      end

      # The active loans code (P34-2), or nil. No validation beyond the strip:
      # the code rides as a bound value (never SQL or a JSON path), so any
      # string is safe and an unattested one is an honest no-match. Needs no
      # rebuild guard either — annotations_json is initial schema.
      def loans_filter
        code = options[:loans].to_s.strip
        code.empty? ? nil : code
      end

      # The content-narrowing filters that make a TERM-LESS browse legal
      # (P42-6): a date window (--from/--to/--century), a provenance --place, a
      # genre facet (--type/--province/--material), or the --loans facet — each
      # narrows WHICH passages, not merely which shelf. --lang/--license/
      # --source/--axis select whole shelves and are deliberately NOT sufficient
      # alone: a term-less listing of a whole language (or license, or source,
      # or axis) is a corpus DUMP, not a browse. The character-structure filters
      # are already a legal term-less path and return earlier (char_structured_search).
      def content_narrowing_filters?
        options[:from] || options[:to] || options[:century] || options[:date_basis] || options[:place] ||
          facet_filters || loans_filter || options[:meter] || options[:meter_pattern] ||
          options[:lect] || options[:script] || options[:within]
      end

      # Parse --within LAT,LON,KM into three floats (P75 C-9); range
      # validation lives in Search#within_spec, the shared enforcement
      # point.
      def within_filter
        spec = options[:within]
        return nil if spec.nil?

        parts = spec.split(",").map(&:strip)
        values = parts.map { |part| Float(part, exception: false) }
        if parts.size != 3 || values.any?(&:nil?)
          raise Thor::Error, "search: --within takes LAT,LON,KM (59.86,17.64,50) — got #{spec.inspect}"
        end

        values
      end

      # The refusal for a term-less `search` that carries no content-narrowing
      # filter — the old "give a query" message, extended (P42-6) to say exactly
      # what WOULD make a term-less browse legal, and why the shelf-selectors do not.
      def browse_refusal_message
        "search: give a query — or a content-narrowing filter to browse the corpus " \
          "term-less: a date window (--from/--to/--century), --date-basis, --place, a facet " \
          "(--type/--province/--material/--facet), --loans, --meter/--meter-pattern, --lect, --script, " \
          "or --within. " \
          "--lang/--license/--source/--axis " \
          "select whole shelves and cannot stand alone (that would dump the shelf, not browse it)."
      end

      # Term-less filtered browse (P42-6): a legal empty-query `search` — one
      # content-narrowing filter present — lists the corpus in corpus order
      # (Search#browse: passages.id ascending, no ranking) under the standard
      # filters and rendering. Reached only from #search on an empty query, and
      # only after the char/fuzzy/near/lemma paths have returned, so the sole
      # residual flags are the plain path's own; --exact/--word have no term to
      # match here and are refused rather than silently ignored.
      def browse_search
        if options[:exact] || options[:word]
          raise Thor::Error, "search: --exact/--word are glyph/word post-filters over a query term — " \
                             "they cannot run a term-less browse (drop them, or add a query)"
        end
        raise Thor::Error, browse_refusal_message unless content_narrowing_filters?

        validate_license!(options[:license])
        from, to = date_window
        place = options[:place]
        facets = facet_filters
        loans = loans_filter
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        require_timeline!(catalog) if from || to || place || options[:date_basis]
        require_facets!(catalog) if facets
        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        lects = require_lects!(config, options[:lect])

        searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext, lects: lects || :auto,
                                           places: Nabu::Places.load_default(canonical_dir: config.canonical_dir))
        results = searcher.browse(lang: options[:lang], license: options[:license],
                                  limit: options[:limit].to_i, from: from, to: to, place: place,
                                  date_basis: date_basis_filter,
                                  facets: facets, source: options[:source], sources: axis_slugs,
                                  loans: loans, meter: options[:meter],
                                  meter_pattern: options[:meter_pattern], lect: options[:lect],
                                  script: options[:script], within: within_filter)
        print_search_results(results, facets: facets, query: "", loans: loans, axis: axis_names,
                                      browse: true, from: from, to: to, place: place,
                                      within: options[:within],
                                      meter_note: searcher.meter_note, place_note: searcher.place_note)
        print_display_footer
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # search --sign (P75 C-4, the inverse of `nabu signs`): resolve one
      # cuneiform sign — glyph, OSL name/alias, or an UNAMBIGUOUS reading
      # value — and serve the standard filtered page over an FTS OR of the
      # sign's reading values (Query::Search#run_sign). --sign IS the
      # query: a term alongside it, or a text-mode modifier, is refused.
      def sign_search(query)
        term = options[:sign]
        unless query.to_s.strip.empty?
          raise Thor::Error, "search: --sign is itself the query — drop the term (#{query.inspect})"
        end

        %i[fuzzy near lemma exact word words meter meter_pattern scan].each do |flag|
          next unless options[flag]

          raise Thor::Error, "search: --sign does not compose with --#{flag.to_s.tr('_', '-')} " \
                             "(the page is an OR over the sign's reading values)"
        end

        validate_license!(options[:license])
        from, to = date_window
        facets = facet_filters
        loans = loans_filter
        config = Nabu::Config.load
        list = Nabu::SignList.load_default(config: config)
        raise Thor::Error, "search: --sign needs the Oracc Sign List — run `nabu sync osl`" if list.nil?

        record = resolve_search_sign(list, term)
        values = record.values.map(&:value).uniq
        raise Thor::Error, "search: sign #{record.name} carries no reading values" if values.empty?

        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        require_timeline!(catalog) if from || to || options[:place] || options[:date_basis]
        require_facets!(catalog) if facets
        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        lects = require_lects!(config, options[:lect])

        searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext, lects: lects || :auto,
                                           places: Nabu::Places.load_default(canonical_dir: config.canonical_dir))
        results = searcher.run_sign(values, lang: options[:lang], license: options[:license],
                                            limit: options[:limit].to_i, from: from, to: to,
                                            date_basis: date_basis_filter,
                                            place: options[:place], facets: facets,
                                            source: options[:source], sources: axis_slugs,
                                            loans: loans, lect: options[:lect], script: options[:script])
        print_sign_search_header(record, values)
        print_search_results(results, facets: facets, query: values.first, loans: loans, axis: axis_names,
                                      incomplete: searcher.incomplete_hint, rank_note: searcher.rank_note,
                                      place_note: searcher.place_note)
        print_display_footer
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # search --scan (P75 C-10, owner-ruled): the filter-first MODE —
      # distinct from plain search by contract, not a fallback it silently
      # becomes. Needs a term (else browse already serves corpus order) AND
      # at least one filter (else plain search already serves the page).
      def scan_search(query)
        %i[fuzzy near lemma exact word words].each do |flag|
          next unless options[flag]

          raise Thor::Error, "search: --scan does not compose with --#{flag} (one mode at a time)"
        end
        if query.to_s.strip.empty?
          raise Thor::Error, "search: --scan needs a query term (a term-less filtered walk is " \
                             "plain browse — drop --scan)"
        end
        unless content_narrowing_filters? || options[:lang] || options[:source] || options[:axis]
          raise Thor::Error, "search: --scan is the filter-first mode — give a filter " \
                             "(--place/--from/--lect/--script/--lang/--source/…); an unfiltered " \
                             "term is plain search's job"
        end

        validate_license!(options[:license])
        from, to = date_window
        facets = facet_filters
        loans = loans_filter
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        require_timeline!(catalog) if from || to || options[:place] || options[:date_basis]
        require_facets!(catalog) if facets
        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        lects = require_lects!(config, options[:lect])

        searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext, lects: lects || :auto,
                                           places: Nabu::Places.load_default(canonical_dir: config.canonical_dir))
        results = searcher.run_scan(query, lang: options[:lang], license: options[:license],
                                           limit: options[:limit].to_i, from: from, to: to,
                                           date_basis: date_basis_filter,
                                           place: options[:place], facets: facets,
                                           source: options[:source], sources: axis_slugs,
                                           loans: loans, meter: options[:meter],
                                           meter_pattern: options[:meter_pattern],
                                           lect: options[:lect], script: options[:script],
                                           within: within_filter)
        print_search_results(results, facets: facets, query: query, loans: loans, axis: axis_names,
                                      incomplete: searcher.incomplete_hint,
                                      rank_note: searcher.rank_note,
                                      meter_note: searcher.meter_note,
                                      place_note: searcher.place_note)
        print_display_footer
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # Glyph first, then OSL name/alias/form, then a reading VALUE when it
      # names exactly one sign (ambiguity lists the candidates, never picks
      # one silently — the sign-card rule).
      def resolve_search_sign(list, term)
        record = list.sign_for_glyph(term) || list.sign(term)
        return record if record

        candidates = list.lookup(term)
        return candidates.first if candidates.size == 1

        if candidates.size > 1
          raise Thor::Error, "search: value #{term.inspect} is ambiguous across " \
                             "#{candidates.map(&:name).join(' · ')} — give the sign name or glyph"
        end
        raise Thor::Error, "search: no OSL sign resolves #{term.inspect} " \
                           "(give a glyph 𒀝, a name AK / |ŠEŠ.AB|, or a reading value)"
      end

      def print_sign_search_header(record, values)
        shown = values.first(SIGN_SEARCH_VALUES_SHOWN)
        extra = values.size - shown.size
        list = shown.join(" ")
        list += " … and #{extra} more" if extra.positive?
        say "sign: #{[record.ucun, record.name].compact.join('  ')} — " \
            "#{values.size} reading #{values.size == 1 ? 'value' : 'values'}: #{list}"
      end

      # --source SLUG (P22-1, search/export): reject an unknown slug up front,
      # naming the valid slugs (the define-miss pattern). Validated against
      # the CATALOG — what is held is what can be filtered.
      def validate_source!(catalog, slug)
        return if slug.nil?
        return if catalog[:sources].where(slug: slug).any?

        known = catalog[:sources].order(:slug).select_map(:slug)
        raise Thor::Error, "unknown source #{slug.inspect} — the catalog holds: #{known.join(', ')}"
      end

      # P57-4: --lect needs the nabu-lects module. nil when +lect+ was not
      # given (no load attempted); the loaded Nabu::Lects when it was and
      # the module is synced; a clean Thor::Error naming the module
      # otherwise (the CLI half of Search's own Nabu::Error guard).
      def require_lects!(config, lect)
        return nil unless lect

        lects = Nabu::Lects.load_default(config: config)
        raise Thor::Error, "search: --lect needs the nabu-lects module — nabu-lects module not synced" unless lects

        lects
      end

      # --axis NAME[,NAME…] (P37-8, search/export): resolve the named research
      # axes to the union of their member slugs — the membership filter, the
      # multi-source generalization of --source. Returns [axis names in the
      # order asked, member slugs] or nil when --axis is absent. An unknown
      # axis is refused naming the known set (the P35-1 resolution guarantee),
      # and an empty registry says so; the slug/axis collision guarantee makes
      # a bare name unambiguous.
      def axis_membership(command:, config:)
        spec = options[:axis].to_s.strip
        return nil if spec.empty?

        registry = Nabu::SourceRegistry.load(config.sources_path)
        axes = registry.axes
        raise Thor::Error, "#{command}: no research axes are defined (config/axes.yml)" if axes.empty?

        names = spec.split(",").map(&:strip).reject(&:empty?).uniq
        names.each do |name|
          next if registry.functional_set?(name)

          axes[name] ||
            raise(Thor::Error, "#{command}: unknown axis #{name.inspect} — known axes: " \
                               "#{axes.names.join(', ')} · functional sets: " \
                               "#{Nabu::SourceRegistry::FUNCTIONAL_SETS.join(', ')}")
        end
        slugs = names.flat_map do |name|
          registry.functional_set?(name) ? registry.functional_set_members(name) : registry.axis_members(name)
        end
        [names, slugs.uniq]
      end

      # -- the local enablement config (P44-r3b, promoted from P40-f focus) --

      # The EFFECTIVE enablement profile for +config+ against +registry+. The
      # promotion's default inversion (P44-r3b): an ABSENT config no longer
      # means "everything". Three cases:
      #   file EXISTS         → its entries are the enabled set, as-is.
      #   absent + a library  → MIGRATION: write every registry source present
      #                         in the catalog out once, announced (no silent
      #                         visibility loss of a built library). Needs the
      #                         catalog to detect it, so surfaces without one
      #                         (remote health) pass catalog: nil and defer.
      #   absent + fresh box  → the quickstart starter set (empty until r3c
      #                         seeds the tags → the honest empty-state).
      def effective_profile(config, registry, catalog: nil)
        path = config.profile_path
        if Nabu::Profile.exist?(path)
          profile = Nabu::Profile.load(path)
          # An EMPTY pre-promotion (P40-f focus-era) file means "no focus
          # trim", never "nothing enabled" — it migrates exactly like an
          # absent file (announced, once). Only an empty file SAVED UNDER
          # THE ENABLEMENT HEADER governs as deliberately-empty (a
          # disable-everything is re-saved with the new header, so it
          # never re-migrates). Files with entries govern as-is either way.
          return profile unless profile.empty? && !Nabu::Profile.enablement_header?(path)
        end

        migrated = migrate_profile(config, registry, catalog)
        return migrated if migrated

        Nabu::Profile.new(Nabu::Profile.default_entries(registry))
      end

      # The one-time migration (P44-r3b): if the box already built a library
      # (the catalog carries source rows) but has no enablement config yet,
      # write one enabling every registry source present in the catalog, so the
      # promotion never drops visibility of what the owner already synced.
      # Returns the saved profile, or nil when there is nothing to migrate.
      def migrate_profile(config, registry, catalog)
        return nil unless catalog&.table_exists?(:sources)

        present = catalog[:sources].select_map(:slug) & registry.slugs
        return nil if present.empty?

        profile = Nabu::Profile.new(present).save(config.profile_path)
        warn "enablement: wrote config/profile.yml enabling your #{pluralize(present.size, 'synced source')} " \
             "(the profile is now this box's enabled set — nabu enable/disable to adjust)."
        profile
      end

      # The working scope for a read surface: the effective enablement resolved
      # against the registry, honoring --all. The filtered registry it carries
      # is what status/list/health render instead of the full one. +catalog+
      # feeds the migration detector (nil where a surface has none open yet).
      def focus_view(config, registry, catalog: nil)
        Nabu::Focus.view(
          profile: effective_profile(config, registry, catalog: catalog),
          registry: registry, all: options[:all], disabled: options[:disabled] || false
        )
      end

      # The box's effective enabled set: the stored profile resolved
      # against the registry (modules pre-enabled by nature); no profile
      # file = the fresh-box default entries.
      def enabled_slugs(profile, registry)
        profile ||= Nabu::Profile.new(Nabu::Profile.default_entries(registry))
        view = Nabu::Focus.view(profile: profile, registry: registry, all: false)
        registry.slugs.select { |slug| view.visible?(slug) }.to_set
      end

      # The enablement META lines go to STDERR, never stdout: piped output stays
      # byte-identical to the table, while the terminal user still sees context.
      # A default view names the enabled set + the exact hidden count, or the
      # honest empty-state when nothing is enabled; --all (the full reveal) is
      # silent.
      def print_focus_note(view, hidden_slugs)
        # The --disabled complement (P46-r3): the rows shown ARE the enable
        # menu, so the footer is the on-ramp (or the all-enabled state) —
        # never the enabled-set summary, never the empty-state.
        return warn(Nabu::Focus.disabled_footer_line(view.registry.slugs)) if view.disabled
        return unless view.active?

        if view.resolution.slugs.empty?
          warn Nabu::Focus.empty_state_line
        else
          warn Nabu::Focus.footer_line(view.entries, hidden_slugs, resolved_count: view.resolution.slugs.size)
        end
      end

      # Warn once about names the file carries that the registry no longer
      # knows (drift after a hand-edit): ignored, never fatal.
      def warn_focus_drift(view)
        warn Nabu::Focus.drift_line(view.unknown) unless view.unknown.empty?
      end

      # `nabu enable <axis|source…>`: additive. Validate the names, migrate an
      # absent-but-built profile first (no visibility loss), then append —
      # recording the AXIS NAME (the existing profile vocabulary; Focus expands
      # it to its PUBLIC members, blocked ones skipped) or the source slug. A
      # blocked (grant-gated private) source named BY SLUG runs the P42-r1 grant
      # flow here, at the natural consent moment; enabling an AXIS never drags a
      # blocked member in — each is skipped with the on-ramp line.
      def run_enable(config, registry, names, ledger:, catalog:)
        profile = effective_profile(config, registry, catalog: catalog)
        entries = profile.entries.dup
        added = []
        names.each do |name|
          if registry.axes[name]
            note_blocked_axis_members(registry, name)
          else
            enable_source!(registry[name], ledger) # raises (adds nothing) on a refused grant
          end
          added << name unless entries.include?(name)
        end
        Nabu::Profile.new(entries + added).save(config.profile_path)
        announce_enablement(config, registry, verb: "enabled", changed: added, catalog: catalog)
      end

      # One source being enabled by slug: a grant-gated (blocked) source with a
      # grant block runs the P42-r1 acknowledgment before it joins the enabled
      # set — a refusal raises (and the caller adds nothing).
      def enable_source!(entry, ledger)
        return unless entry.blocked? && entry.grant_required?

        enable_grant!(entry, ledger)
      end

      # Print the on-ramp line for every blocked (grant-gated) member an axis
      # would otherwise drag in — enabling an axis never implicitly enables its
      # private members (P44-r3b).
      def note_blocked_axis_members(registry, axis_name)
        registry.blocked_axis_members(axis_name).each do |slug|
          say "#{slug} is grant-gated — enable it explicitly: nabu enable #{slug}", :yellow
        end
      end

      # The P42-r1 grant flow AT ENABLE TIME: a recorded acknowledgment skips
      # the prompt with an honest one-liner; --grant-acknowledged records
      # non-interactively; otherwise show the terms and demand the typed word
      # (no TTY / refusal aborts with the request scaffold, adding nothing).
      def enable_grant!(entry, ledger)
        gate = Nabu::GrantGate.new(ledger: ledger, grants_path: Nabu::Config.load.grants_path)
        return say("#{entry.slug}: grant already acknowledged — enabling.", :yellow) if gate.acknowledged?(entry.slug)

        if options[:grant_acknowledged]
          gate.record!(slug: entry.slug, terms: entry.grant.terms, how: "flag")
          return say("#{entry.slug}: grant acknowledged (--grant-acknowledged) — recorded, enabling.", :yellow)
        end
        raise Thor::Error, Nabu::GrantGate.abort_message(entry) unless $stdin.tty?

        say Nabu::GrantGate.notice(entry), :yellow
        say Nabu::GrantGate.prompt_line(entry)
        answer = $stdin.gets
        raise Thor::Error, Nabu::GrantGate.abort_message(entry) unless Nabu::GrantGate.acknowledged_answer?(answer)

        gate.record!(slug: entry.slug, terms: entry.grant.terms, how: "typed")
        say "#{entry.slug}: grant acknowledged — recorded, enabling.", :green
      end

      # `nabu disable <axis|source…>`: remove entries from the config (synced
      # data stays — withdrawal is a different, existing concept). Removes any
      # entry that matches a name given, whether it is an axis name or a slug.
      def run_disable(config, registry, names, catalog:)
        profile = effective_profile(config, registry, catalog: catalog)
        removed = profile.entries & names
        Nabu::Profile.new(profile.entries - names).save(config.profile_path)
        announce_enablement(config, registry, verb: "disabled", changed: removed, catalog: catalog)
        warn_still_required(config, registry, names, catalog: catalog)
      end

      # P77-r4 (the survey's disable finding): a disabled name the closure
      # re-adds must SAY so — "disabled" while it stays enabled is a lie.
      def warn_still_required(config, registry, names, catalog:)
        resolution = Nabu::Focus.resolve(effective_profile(config, registry, catalog: catalog), registry)
        names.select { |name| resolution.slugs.include?(name) }.each do |name|
          dependents = registry.required_by(name) & resolution.slugs
          next if dependents.empty?

          warn "#{name} stays enabled — required by #{dependents.join(', ')} " \
               "(disable the dependent to drop it)"
        end
      end

      # Confirm a write: what changed, then the current enabled set.
      def announce_enablement(config, registry, verb:, changed:, catalog:)
        say(changed.empty? ? "nothing #{verb} (already so)" : "#{verb}: #{changed.sort.join(', ')}")
        show_enablement(effective_profile(config, registry, catalog: catalog), registry)
      end

      # The current enabled set, grouped by PROVENANCE (P77-r2, owner report
      # 2026-08-13): core first (the auto-enabled default — shown even when
      # no profile entry names it), then each profile axis entry with the
      # members it pulls in, then the individually enabled remainder. Every
      # source is listed ONCE, under the first provenance that covers it,
      # and the headline count is the DEDUPED UNION of all of them — never
      # the raw entry count alone (a single axis entry covers many sources).
      def show_enablement(profile, registry)
        resolution = Nabu::Focus.resolve(profile, registry)
        return say(Nabu::Focus.empty_state_line) if resolution.slugs.empty?

        groups = enablement_groups(registry, resolution)
        entries = profile.entries.size
        total = groups.sum { |_label, members| members.size }
        say "enabled (#{entries} #{entries == 1 ? 'entry' : 'entries'} → #{total} distinct sources):"
        groups.each { |label, members| say "  #{label}: #{members.join(', ')}" }
        unless resolution.unknown.empty?
          say "  unknown: #{resolution.unknown.join(', ')} (not a known axis or source — ignored)"
        end
        shown = resolution.slugs.count { |slug| !registry[slug]&.feature_module? }
        say "resolved: #{pluralize(shown, 'source')} enabled (nabu status shows them; --all shows everything)"
      end

      def enablement_groups(registry, resolution)
        groups = []
        shown = []
        core = registry.core_members
        unless core.empty?
          groups << ["core (enabled by default)", core.sort]
          shown += core
        end
        resolution.axes.each do |axis|
          members = (registry.axis_members(axis) - shown).sort
          groups << ["#{axis} (axis)", members] unless members.empty?
          shown += members
        end
        individual = (resolution.sources - shown).sort
        groups << ["sources", individual] unless individual.empty?
        shown += individual
        # The chain-pulled remainder (P77-r3): slugs in the resolution only
        # because something above requires them, each named with its
        # dependents — the package-manager provenance.
        required = (resolution.slugs - shown).reject { |slug| registry[slug]&.shelf? }.sort
        unless required.empty?
          labeled = required.map do |slug|
            "#{slug} (by #{(registry.required_by(slug) & resolution.slugs).join(', ')})"
          end
          groups << ["required", labeled]
        end
        groups
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

      # Render `verify`: one line per source (OK with a count, or FAILED with
      # its itemized issues), then any never-synced skips, then a verdict.
      def print_verify(result)
        result.outcomes.each { |outcome| print_verify_outcome(outcome) }
        result.skips.each { |skip| say "  skip    #{skip.slug} (no canonical data — never synced)" }
        say(result.clean? ? "All canonical documents verified against the catalog." : "Integrity check FAILED.")
      end

      def print_verify_outcome(outcome)
        if outcome.ok?
          say "  OK      #{outcome.slug}  (#{pluralize(outcome.verified, 'document')} verified)"
        else
          say "  FAILED  #{outcome.slug}  (#{outcome.verified} checked, #{pluralize(outcome.issues.size, 'issue')})"
          outcome.issues.each { |issue| say "    #{format_verify_issue(issue)}" }
        end
      end

      def format_verify_issue(issue)
        case issue.kind
        when :mismatch
          "MISMATCH    #{issue.urn}  stored #{issue.detail.fetch(:stored)[0, 12]} != " \
          "recomputed #{issue.detail.fetch(:recomputed)[0, 12]}  (#{issue.canonical_path})"
        when :missing
          "MISSING     #{issue.urn}  (#{issue.canonical_path})"
        when :unparseable
          "UNPARSEABLE #{issue.urn}  #{issue.detail}  (#{issue.canonical_path})"
        end
      end

      def verify_failure_summary(result)
        "verify: #{pluralize(result.issues.size, 'document')} failed the integrity check"
      end

      def pluralize(count, noun) = "#{count} #{noun}#{'s' unless count == 1}"

      # Render `backup`: the target + mode banner, one line per section (name,
      # status, files/size/duration or the failure detail), then a summary.
      def print_backup(result)
        say "#{result.dry_run ? 'Backup plan (dry run — nothing changes)' : 'Backup'} → #{result.target}"
        result.sections.each { |section| say "  #{format_backup_section(section)}" }
        say "  #{backup_summary(result)}"
      end

      def format_backup_section(section)
        label = section.name.ljust(10)
        case section.status
        when :ok
          "#{label} #{section.status.to_s.ljust(8)} #{pluralize(section.files, 'file')}, " \
          "#{human_bytes(section.bytes)}  (#{format('%.2fs', section.duration)}) → #{section.dest}"
        when :skipped
          "#{label} #{'skipped'.ljust(8)} #{section.detail} (#{section.source})"
        else
          "#{label} #{'FAILED'.ljust(8)} #{section.detail}"
        end
      end

      def backup_summary(result)
        verb = result.dry_run ? "would back up" : "backed up"
        base = "#{verb} #{pluralize(result.files, 'file')}, #{human_bytes(result.bytes)} " \
               "in #{format('%.2fs', result.duration)}"
        result.ok? ? "#{base} — OK" : "#{base} — #{pluralize(result.failed.size, 'section')} FAILED"
      end

      def backup_failure_summary(result)
        "backup: #{pluralize(result.failed.size, 'section')} failed — #{result.failed.map(&:name).join(', ')}"
      end

      def human_bytes(bytes)
        units = %w[B KB MB GB TB]
        size = bytes.to_f
        unit = 0
        while size >= 1024 && unit < units.size - 1
          size /= 1024
          unit += 1
        end
        unit.zero? ? "#{bytes} B" : "#{format('%.1f', size)} #{units[unit]}"
      end

      # `show --random` (P11-9): N random visible passages, each in the standard
      # passage layout — the eyeball ritual at a source flip. A urn alongside
      # --random is contradictory (it picks passages for you); an empty result
      # is an honest note, not an error.
      def show_random(catalog, urn, config)
        raise Thor::Error, "show: --random takes no urn (it picks passages for you)" unless urn.empty?
        return show_random_parallel(catalog, config) if options[:parallel]

        results = Nabu::Query::Random.new(catalog: catalog)
                                     .run(source: options[:source], lang: options[:lang], count: options[:count].to_i)
        if results.empty?
          scope = +""
          scope << " in source #{options[:source]}" if options[:source]
          scope << " in #{options[:lang]}" if options[:lang]
          return say("no passages to show#{scope} (nothing visible — the corpus may be empty or all withdrawn)")
        end

        results.each_with_index do |result, index|
          say "" if index.positive?
          print_show_passage(result)
        end
      end

      # P47-r1 (owner: "elephantine is perfect for --parallel showcase!"):
      # --random composes with --parallel — draw ORIGINALS (the sampler
      # already excludes translation siblings) until one carries a parallel
      # in the requested language, render the paired view; a scope that
      # yields none in the attempt budget (12 draws per requested passage —
      # a retry bound, not a corpus claim) says so honestly.
      def show_random_parallel(catalog, config)
        random = Nabu::Query::Random.new(catalog: catalog)
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        parallel = Nabu::Query::Parallel.new(catalog: catalog, journal: journal)
        wanted = options[:count].to_i.clamp(1, Nabu::Query::Random::MAX_COUNT)
        shown = []
        attempts = 0
        while shown.size < wanted && attempts < wanted * 12
          attempts += 1
          draw = random.run(source: options[:source], lang: options[:lang], count: 1).first
          break if draw.nil?
          next if shown.include?(draw.urn)

          # A draw whose translation edge cannot serve the requested lang is
          # simply not a parallel-bearing draw (P48-r2) — keep drawing.
          pair = begin
            parallel.run(draw.urn, lang: options[:parallel])
          rescue Nabu::Query::Parallel::TranslationMismatch
            nil
          end
          next if pair.nil? || pair.right.nil?

          say "" unless shown.empty?
          print_parallel(pair)
          shown << draw.urn
        end
        return unless shown.empty?

        scope = options[:source] ? " in source #{options[:source]}" : ""
        say "no parallel-bearing draw#{scope} after #{attempts} attempts — the scope may hold no " \
            "#{options[:parallel]} siblings (`show <urn> --parallel` pairs a known document; " \
            "`show --random` alone draws unpaired)"
      ensure
        journal&.disconnect
      end

      # Render `show`: a passage in the context of its document, or a document
      # header plus its passages in sequence. Withdrawn items ARE shown, tagged.
      def print_show(result)
        case result
        when Nabu::Query::Show::PassageResult then print_show_passage(result)
        when Nabu::Query::Show::DocumentResult then print_show_document(result)
        when Nabu::Query::Show::RangeResult then print_show_range(result)
        when Nabu::Query::Define::Result then print_define_entry(result)
        end
      end

      # `show --segmented` (P54-2): the result with every passage text
      # word-broken through Query::Show#segmented_text — a copy, so every
      # existing print path renders unchanged (tokens verbatim, spaces at
      # word boundaries). Only reached when the segmentation note is nil
      # (a Tibetan row with the nabu-data dataset synced).
      def segmented_show_result(query, result)
        case result
        when Nabu::Query::Show::PassageResult
          result.with(text: query.segmented_text(result.text))
        when Nabu::Query::Show::DocumentResult, Nabu::Query::Show::RangeResult
          result.with(passages: result.passages.map { |line| line.with(text: query.segmented_text(line.text)) })
        else
          result
        end
      end

      # The source-level credit line (P43-2, the grant's "clearly indicated
      # wherever displayed" duty), shown only when the source carries one — a
      # nil/blank credit (every ordinary source) prints nothing.
      def print_credit(result)
        credit = result.credit.to_s.strip
        say "  credit: #{credit}" unless credit.empty?
      end

      # P44-7: the meter line — shown only when the passage carries a scansion
      # enrichment (pedecerto over held Perseus-Latin verse), byte-identical
      # absence otherwise. "meter: H DSDS (pedecerto)": metrical code, foot
      # pattern (omitted when empty), producer.
      def print_meter(passage)
        meter = passage.meter
        return if meter.nil?

        pattern = meter.pattern.to_s.strip
        code = [meter.meter.to_s.strip, pattern].reject(&:empty?).join(" ")
        say "  meter: #{code} (#{meter.producer})"
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

      # P44-2: the findspot line — shown only when the document's parse-
      # captured Pleiades id resolves through the local gazetteer dump
      # (title + place types; maps and coordinate math are out by design).
      # Absent dump, absent id, unknown id: no line, byte-identical output.
      def print_findspot(result)
        spot = result.findspot
        return if spot.nil?

        if spot.id.nil?
          # P69-1: the coordinates findspot — the source's own WGS84 pair,
          # no gazetteer (rundata's SRDB columns).
          pair = format("%<lat>.5f, %<lon>.5f", lat: spot.lat, lon: spot.lon)
          say "  findspot: #{[spot.title, pair].compact.join(' — ')}"
          return
        end
        types = spot.place_types.empty? ? "" : " (#{spot.place_types.join(' · ')})"
        say "  findspot: #{spot.title} — Pleiades #{spot.id}#{types}"
      end

      # P61-3 (D60-b): the artifact-script line — only where the original
      # artifact's script DIFFERS from the held surface (the lane is minted
      # on difference by construction). Tag + config note, honest and short.
      # P76 U-7: the upstream script_uncertain flag glosses "(script
      # uncertain)" — on the artifact line when one exists, else on its own
      # honest line (the flag can ride documents outside the differs-only
      # lane).
      def print_artifact(result)
        artifact = result.artifact
        return if artifact.nil?

        if artifact.script
          note = artifact.note ? " — #{artifact.note}" : ""
          flag = artifact.uncertain ? " (script uncertain)" : ""
          say "  artifact script: #{artifact.script}#{note}#{flag} (held surface differs; see the lect ~axis)"
        elsif artifact.uncertain
          say "  script: (script uncertain — upstream flag)"
        end
      end

      def print_show_passage(passage)
        say "#{passage.urn}#{" [#{passage.language}]" if passage.language}#{withdrawn_tag(passage.withdrawn)}"
        say "  #{display_text(painted_passage_text(passage), passage.language,
                              source: passage.source_slug, annotations: passage.annotations)}"
        say "  document: #{passage.document_urn}#{" — #{passage.document_title}" if passage.document_title}"
        say "  source: #{passage.source_slug}   license: #{passage.license_class}   " \
            "sequence: #{passage.sequence}   revision: #{passage.revision}"
        print_credit(passage)
        print_lect(passage)
        print_timeline(passage.timeline)
        print_findspot(passage)
        print_meter(passage)
        # H9 (P35-6): a corrupt annotation lane announces itself instead of
        # posing as an unannotated passage.
        say "  note: #{ANNOTATIONS_UNREADABLE_NOTE}" if annotations_unreadable?(passage)
        return if passage.provenance.empty?

        say "  provenance:"
        passage.provenance.each do |event|
          # P112-2: an implicit "loaded" (no per-passage breadcrumb) may
          # carry no timestamp at all — render the event without one.
          stamp = event.at ? "#{event.at}  " : ""
          say "    #{stamp}#{event.event}#{"  #{event.tool}" if event.tool}"
        end
      end

      # `show URN --tokens` (P35-6, the journaled gate find): the honest RAW
      # view of the stored token annotations — one line per token, `form`
      # first, then EVERY other key exactly as stored (lemma/gloss/osm/lang/
      # …, nested values as compact JSON). No display transforms, no
      # invention; a passage without tokens, and a non-passage grain, both
      # say so instead of rendering nothing.
      def print_show_tokens(result)
        unless result.is_a?(Nabu::Query::Show::PassageResult)
          return say "--tokens renders at passage grain — give a passage urn"
        end
        return say ANNOTATIONS_UNREADABLE_NOTE if annotations_unreadable?(result)

        tokens = result.annotations["tokens"]
        tokens = tokens.is_a?(Array) ? tokens.grep(Hash) : []
        return say "no token annotations stored for this passage" if tokens.empty?

        say "tokens (#{tokens.size}):"
        tokens.each { |token| say "  #{token_line(token)}" }
      end

      # One token as `form=… key=…` pairs, form first, stored key order after,
      # non-scalar values as compact JSON — verbatim, never interpreted.
      def token_line(token)
        keys = (["form"] + token.keys).uniq.select { |key| token.key?(key) }
        keys.map do |key|
          value = token[key]
          "#{key}=#{value.is_a?(String) ? value : JSON.generate(value)}"
        end.join("  ")
      end

      def annotations_unreadable?(result)
        result.annotations[Nabu::Query::Show::ANNOTATIONS_UNREADABLE] == true
      end

      def print_unreadable_annotations_count(lines)
        count = lines.count { |line| annotations_unreadable?(line) }
        return unless count.positive?

        say "  note: #{count} #{count == 1 ? 'passage carries' : 'passages carry'} " \
            "unreadable stored annotations (invalid JSON) — skipped"
      end

      def print_show_document(document)
        title = document.title ? " — #{document.title}" : ""
        lang = document.language ? " [#{document.language}]" : ""
        say "#{document.urn}#{title}#{lang}" \
            "#{withdrawn_tag(document.withdrawn, reason: document.withdrawn_reason,
                                                 at: document.withdrawn_at)}#{retired_tag(document)}"
        say "  source: #{document.source_slug}   license: #{document.license_class}   revision: #{document.revision}"
        print_credit(document)
        print_timeline(document.timeline)
        print_findspot(document)
        print_artifact(document)
        print_facets(document.facets, language: document.language)
        say "  passages (#{document.passages.size}):"
        document.passages.each do |line|
          say "    #{passage_label(document, line)}#{withdrawn_tag(line.withdrawn)}  " \
              "#{display_text(line.text, document.language,
                              source: document.source_slug, annotations: line.annotations)}"
        end
        print_unreadable_annotations_count(document.passages)
      end

      # Render a range (P7-6): the document header like a document listing, an
      # honest "[N of M passages]" note plus the two endpoint urns, then the
      # inclusive slice as :suffixes (--full-urn restores absolute urns).
      def print_show_range(range)
        title = range.title ? " — #{range.title}" : ""
        lang = range.language ? " [#{range.language}]" : ""
        say "#{range.urn}#{title}#{lang}#{withdrawn_tag(range.withdrawn)}#{retired_tag(range)}"
        say "  source: #{range.source_slug}   license: #{range.license_class}   revision: #{range.revision}"
        print_credit(range)
        print_timeline(range.timeline)
        say "  range: #{range.start_urn} … #{range.end_urn}  " \
            "[#{range.passages.size} of #{range.total} passages]"
        range.passages.each do |line|
          say "    #{passage_label(range, line)}#{withdrawn_tag(line.withdrawn)}  " \
              "#{display_text(line.text, range.language,
                              source: range.source_slug, annotations: line.annotations)}"
        end
        print_unreadable_annotations_count(range.passages)
      end

      # P81 U-5: the lect line — only when the document carries a
      # materialized lect facet row ("no row means identity", P58-4; a
      # bare-code passage prints nothing). The resolution's provenance
      # basis rides in parentheses; where the ruling behind the basis
      # STATES a tier (the rule's tier:, the override row's tier:) the
      # parenthetical glosses through Certainty's :lect_tier carrier
      # instead — certain stays provenance-only ink, deviation is labeled:
      # "lect: arc:mid (probable — rule sefaria-arc-subshelf, approximation)".
      def print_lect(passage)
        return unless passage.lect

        say "  lect: #{passage.lect}#{lect_facet_note(passage.lect_basis, code: passage.language)}"
      end

      # " (<gloss>)" when the basis's ruling states a tier, " (<basis>)"
      # as bare provenance otherwise, "" for a basis-less row (materialized
      # before the P81 basis lane) — shared by the passage lect line and
      # the document facets line.
      def lect_facet_note(basis, code:)
        return "" unless basis

        gloss = Nabu::LectGloss.gloss(basis, code: code, rules: cli_lect_rules,
                                             override_tiers: cli_lect_override_tiers)
        " (#{gloss || basis})"
      end

      # The config-stated tier carriers, memoized per command run (both are
      # small YAML reads; nil rules = no rules file, an honest untiered
      # render).
      def cli_lect_rules
        return @cli_lect_rules if defined?(@cli_lect_rules)

        @cli_lect_rules = Nabu::LectRules.load(Nabu::Config.load.lect_facet_rules_paths)
      end

      def cli_lect_override_tiers
        return @cli_lect_override_tiers if defined?(@cli_lect_override_tiers)

        @cli_lect_override_tiers = Nabu::Lects.override_tiers(Nabu::Config.load.lect_overrides_paths)
      end

      # The timeline line (P15-2), when the document has one. A date span
      # ("113 BCE", "501–700 CE", "≤ 257 BCE") with the informative precision
      # ("low"/"high", not the derived exact/range/year) and the provenance
      # place; place-only rows print as "place:". Undated documents print
      # nothing (an absence, never an error).
      def print_timeline(timeline)
        return if timeline.nil?

        span = Nabu::Timeline.format_span(timeline.not_before, timeline.not_after)
        place = timeline.place_name ? " · #{timeline.place_name}#{place_query_gloss(timeline.place_name)}" : ""
        if span && timeline.date_class == Nabu::Store::SilverDates::DATE_CLASS
          # P122-1: an estimate is never dressed as an upstream date.
          say "  date: #{span} [silver — #{timeline.date_raw}]#{place}"
        elsif span
          say "  date: #{span}#{precision_note(timeline.precision)}#{place}"
        elsif timeline.place_name
          say "  place: #{timeline.place_name}#{place_query_gloss(timeline.place_name)}"
        end
      end

      # P76 U-2 (conventions §12): a genuinely graded precision word routes
      # through Certainty — house tier plus the upstream word verbatim
      # ('(uncertain — hgv "low")'); "high" is certain and SILENT; width
      # words beyond the always-silent exact/range/year keep their plain
      # informative note ("(period)") — width, not doubt.
      def precision_note(precision)
        return "" if %w[exact range year].include?(precision)

        gloss = Nabu::Certainty.gloss(:hgv_precision, precision)
        return " (#{gloss})" if gloss
        return "" if Nabu::Certainty.tier(:hgv_precision, precision) == "certain"

        " (#{precision})"
      end

      # The cataloguer's trailing "?" on a place name (P76 U-2): the
      # Barrington-lineage doubt mark glosses as probable, upstream mark
      # kept verbatim in the name itself.
      def place_query_gloss(name)
        return "" unless name.to_s.strip.end_with?("?")

        " (#{Nabu::Certainty.gloss(:cataloguer_query, '?')})"
      end

      # The facets line (P17-2), one compact line and only when faceted:
      # "facets: genre=epitaph (titsep) · province=Latium et Campania …". The
      # raw code rides in parentheses when it differs from the value (the `?`
      # certainty stays visible). P81 U-5: the lect facet's raw is its
      # provenance basis — it renders through the tier gloss (or as the bare
      # basis) exactly like the passage card's lect line.
      def print_facets(facets, language: nil)
        return if facets.nil? || facets.empty?

        kind_rows, rest = facets.partition { |facet| facet.facet == "kind" }
        rendered = rest.map do |facet|
          if facet.facet == "lect"
            "lect=#{facet.value}#{lect_facet_note(facet.raw, code: language)}"
          else
            raw = facet.raw && facet.raw != facet.value ? " (#{facet.raw})" : ""
            "#{facet.facet}=#{facet.value}#{raw}"
          end
        end
        say "  facets: #{rendered.join(' · ')}" unless rest.empty?
        print_kind_line(kind_rows)
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

      # The kind axis' card line (P99-3, owner-ruled 2026-09-13): every class the
      # document carries on ONE line, multi-label joined with " + ",
      # the upstream claim(s) visible verbatim. A declaration-born row
      # (raw nil — okhc's source_kind) shows no upstream tail.
      def print_kind_line(kind_rows)
        return if kind_rows.empty?

        classes = kind_rows.map(&:value).uniq.join(" + ")
        raws = kind_rows.map(&:raw).compact.uniq
        upstream = raws.empty? ? "" : " — upstream: #{raws.map(&:inspect).join(', ')}"
        say "  kind: #{classes}#{upstream}"
      end

      # Print practice: the document urn appears once in the header, each
      # passage line carries only its changing :suffix (":b2:5"). --full-urn
      # restores absolute urns (copy-paste into `show`/scripts). A passage
      # whose urn doesn't extend the document urn (never minted by our
      # adapters, but data is data) falls back to the full urn.
      def passage_label(document, line)
        return line.urn if options[:full_urn]

        suffix = line.urn.delete_prefix(document.urn)
        suffix == line.urn || suffix.empty? ? line.urn : suffix
      end

      # -- show --parallel (P7-4) ------------------------------------------

      # Resolve + align + render, with the honest failure modes: unknown urn
      # (exit 1, same message as plain show), no LANG sibling or translation
      # edge in the catalog (exit 1, names the language), and a translation
      # edge that cannot serve LANG (exit 1 via TranslationMismatch, naming
      # the language that would work). The links journal rides along
      # read-only so the P48-r2 kind=translation edges (Kangyur↔84000) pair
      # cross-source with no extra flag.
      def show_parallel(catalog, urn, lang, config)
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        result = Nabu::Query::Parallel.new(catalog: catalog, journal: journal).run(urn, lang: lang)
        raise Thor::Error, "urn not found: #{urn}" if result.nil?
        if result.right.nil?
          raise Thor::Error, "no #{lang} parallel edition of this work in the catalog for #{urn} " \
                             "(--parallel pairs sibling CTS editions within one source, or " \
                             "cross-source over a kind=translation link edge; is " \
                             "`translations: true` set and the source resynced?)#{align_hint(urn, config)}"
        end

        print_parallel(result)
      ensure
        journal&.disconnect
      end

      # Cosmetic rider (P11-8): --parallel's "is translations: true set" hint is
      # misleading for a CROSS-source text (Vulgate/LXX/WEB have no sibling CTS
      # edition to pair). When the urn is a registered alignment witness, point
      # at `nabu align` instead — the hub built for exactly this.
      def align_hint(urn, config)
        registry = Nabu::AlignmentRegistry.load(config.alignments_path)
        witnessed = registry.works.any? do |work|
          work.witnesses.any? do |witness|
            witness.document_urns.any? { |doc| urn == doc || urn.start_with?("#{doc}:") }
          end
        end
        witnessed ? " — this text is an alignment-hub witness; try `nabu align REF` for cross-source alignment" : ""
      rescue Nabu::ValidationError
        ""
      end

      # Render the alignment (P8-1b span-grouped): both document headers, the
      # paired/blocks/one-sided counts, then one span-group at a time. A verse
      # pair keeps the compact pair form (byte-identical to pre-P8-1b); a coarse
      # block prints the original lines first, then the translation once with
      # its full coverage (and a clip note when a slice shows only part of it);
      # one-sided rows dash the missing side. Withdrawn passages are shown,
      # tagged (show-family).
      def print_parallel(result)
        say format_parallel_side(result.left)
        say "  parallel: #{format_parallel_side(result.right)}"
        say "  #{parallel_counts(result)}"
        width = [result.left.language.to_s.length, result.right.language.to_s.length].max + 2
        result.groups.each { |group| print_parallel_group(group, result, width) }
      end

      def print_parallel_group(group, result, width)
        case group.kind
        when :pair        then print_parallel_pair(group, result, width)
        when :block       then print_parallel_block(group, result, width)
        when :original    then print_parallel_one_sided(group, result, width, side: :left)
        when :translation then print_parallel_one_sided(group, result, width, side: :right)
        end
      end

      # Verse pair / one-sided rows: the pre-P8-1b two-line form, the suffix (or
      # absolute urn under --full-urn) over one line per language, "—" for the
      # absent side. Kept byte-identical so verse-for-verse output never shifts.
      def print_parallel_pair(group, result, width)
        line = group.originals.first
        say "  #{options[:full_urn] ? line.urn : group.anchor}"
        say "    #{parallel_line(result.left.language, line, width)}"
        say "    #{parallel_line(result.right.language, group.translation, width)}"
      end

      def print_parallel_one_sided(group, result, width, side:)
        present = side == :left ? group.originals.first : group.translation
        say "  #{options[:full_urn] ? present.urn : present.suffix}"
        left = side == :left ? present : nil
        right = side == :right ? present : nil
        say "    #{parallel_line(result.left.language, left, width)}"
        say "    #{parallel_line(result.right.language, right, width)}"
      end

      # Coarse block: each owned original as a suffix-labeled left line, then
      # the translation once, labeled with its full coverage in the original's
      # numbering plus a clip note when the shown slice is only part of it.
      def print_parallel_block(group, result, width)
        group.originals.each do |line|
          say "  #{options[:full_urn] ? line.urn : line.suffix}"
          say "    #{parallel_line(result.left.language, line, width)}"
        end
        say "  #{result.right.language} #{block_coverage(group)}"
        say "    #{display_text(group.translation.text, result.right.language)}" \
            "#{withdrawn_tag(group.translation.withdrawn)}"
      end

      # `[:1.1 — covers :1.1–:1.43; range shows :1.5–:1.10]` — the anchor, the
      # full ownership span, and (only when clipped) the shown sub-range.
      def block_coverage(group)
        covers = "covers #{group.covers_first}–#{group.covers_last}"
        clip = group.clipped ? "; range shows #{group.shown_first}–#{group.shown_last}" : ""
        "[#{group.anchor} — #{covers}#{clip}]"
      end

      # -- align (P11-3) ----------------------------------------------------

      # Render the cross-source alignment: the ref + work header with an
      # honest attestation count, then one block per witness in registry
      # order — title, language, license label, and the sentences (urn line,
      # text line), a multi-verse sentence labeled with its full span.
      def print_align(result)
        return print_align_range(result) if result.is_a?(Nabu::Query::Align::RangeResult)

        attesting = result.witnesses.count { |witness| witness.status == :ok }
        say "#{result.ref} — #{result.title}"
        say "  #{attesting} of #{result.witnesses.size} witnesses attest this ref"
        result.witnesses.each { |witness| print_align_witness(witness, result.ref) }
      end

      # A range/chapter query (P11-8): the query header, a one-line witness
      # legend (title/lang/license shown ONCE, not repeated per ref), then one
      # compact block per ref in document order — ref line, then one line per
      # witness (its text, or an honest not-attested/not-synced dash).
      def print_align_range(result)
        say "#{result.query} — #{result.title}"
        say "  #{result.total} refs; witnesses: #{align_range_legend(result).join('; ')}"
        say "  #{absent_range_summary(result.absent)}" unless result.absent.empty?
        if result.truncated
          say "  showing first #{result.groups.size} of #{result.total} refs " \
              "(cap #{Nabu::Query::Align::MAX_REFS}) — narrow the range, or pass --long to render all"
        end
        result.groups.each { |group| print_align_range_group(group) }
      end

      # P11-9: witnesses absent from every rendered ref are summarized here once
      # (grouped by reason) rather than dashed on every ref line — the owner's
      # readability fix. Partially-attested witnesses stay in the per-ref blocks.
      def absent_range_summary(absent)
        by_reason = absent.group_by(&:reason)
        parts = []
        if (rows = by_reason[:not_attested])
          parts << "not attested in this range: #{rows.map(&:label).join(', ')}"
        end
        if (rows = by_reason[:not_synced])
          parts << "not synced: #{rows.map(&:label).join(', ')}"
        end
        parts.join("; ")
      end

      # One legend entry per witness (registry order): its language + license
      # from the richest view across the shown refs, or "not synced" when the
      # witness holds no data anywhere in the range.
      def align_range_legend(result)
        result.groups.first.witnesses.map(&:label).map do |label|
          views = result.groups.map { |group| group.witnesses.find { |witness| witness.label == label } }
          synced = views.find { |witness| witness.status != :not_synced }
          if synced
            "#{label} [#{synced.language}] license: #{synced.license_class}#{align_numbering_note(synced)}"
          else
            "#{label} not synced"
          end
        end
      end

      def print_align_range_group(group)
        say ""
        say group.ref
        group.witnesses.each { |witness| print_align_range_witness(witness, group.ref) }
      end

      def print_align_range_witness(witness, ref)
        case witness.status
        when :not_synced then say "    #{witness.label} — not synced"
        when :no_match   then say "    #{witness.label} — not attested"
        else
          witness.sentences.each do |sentence|
            say "    #{witness.label}  #{display_text(sentence.text, witness.language)}" \
                "#{align_native_note(witness, sentence)}#{align_span_note(sentence, ref)}"
          end
        end
      end

      def print_align_witness(witness, ref)
        say ""
        if witness.status == :not_synced
          # A nil urn = a multi-book witness whose map lacks this ref's book;
          # naming an unrelated book's urn would mislead — phrase neutrally.
          detail = if witness.document_urn
                     "#{witness.document_urn} is registered but not in the catalog"
                   else
                     "its registered documents are not in the catalog"
                   end
          say "#{witness.label} — not synced (#{detail})"
          return
        end

        # A multi-document witness misses without a book to name — no title.
        say "#{witness.label}#{" — #{witness.title}" if witness.title} [#{witness.language}]   " \
            "license: #{witness.license_class}#{align_numbering_note(witness)}"
        return say "  not attested (this witness lacks #{ref})" if witness.status == :no_match

        witness.sentences.each do |sentence|
          say "  #{sentence.urn}#{align_native_note(witness, sentence)}#{align_span_note(sentence, ref)}"
          say "    #{display_text(sentence.text, witness.language)}"
        end
      end

      # "  · Hebrew (Masoretic) numbering" — flags a witness whose psalter is
      # numbered in a different system than the work vocabulary (P13-5), so the
      # reader knows its refs were remapped to align.
      def align_numbering_note(witness)
        witness.numbering ? "   · #{witness.numbering} numbering" : ""
      end

      # "  [Hebrew (Masoretic): PSA 23.1]" — the witness's OWN ref for this
      # sentence, shown only when its numbering diverges from the queried ref.
      def align_native_note(witness, sentence)
        return "" unless sentence.native_ref

        "  [#{witness.numbering}: #{sentence.native_ref}]"
      end

      # "  [covers MARK 2.3, MARK 2.4]" — only when the sentence spans beyond
      # the queried ref (sentence≠verse, stated honestly).
      def align_span_note(sentence, ref)
        return "" if sentence.refs == [ref]

        "  [covers #{sentence.refs.join(', ')}]"
      end

      # -- align --collate (P15-4) ------------------------------------------------

      # The collation apparatus (intertext-design §2): the query/work header,
      # then one block per ref — each (language, script) cell as a base reading
      # plus the per-witness divergences, uncollated cross-script/sole witnesses
      # rendered undiffed and honestly, and any missing witnesses named once.
      def print_collation(result, long:)
        say "#{result.query} — #{result.title} · collation"
        if result.truncated
          say "  showing first #{result.refs.size} of #{result.total} refs " \
              "(cap #{Nabu::Query::Align::MAX_REFS}) — narrow the range, or pass --long to render all"
        end
        result.refs.each do |ref_collation|
          say ""
          say ref_collation.ref if result.refs.size > 1
          print_collation_ref(ref_collation, long: long)
        end
      end

      def print_collation_ref(ref_collation, long:)
        say "  no witness attests this ref" if ref_collation.cells.empty? && ref_collation.asides.empty?
        ref_collation.cells.each { |cell| print_collation_cell(cell, long: long) }
        ref_collation.asides.each { |aside| print_collation_aside(aside) }
        print_collation_missing(ref_collation.missing)
      end

      # One collated cell: the base line in full, then each other witness — its
      # full tokens under --long, "(agrees with base)" when identical, else its
      # apparatus of divergences (agreements elided).
      def print_collation_cell(cell, long:)
        base = cell.readings.find(&:is_base)
        say "  [#{cell.language}/#{cell.script}] #{cell.readings.size} witnesses, base #{cell.base_label}"
        say "    = #{base.label}  #{display_text(base.tokens.join(' '), cell.language)}"
        cell.readings.reject(&:is_base).each do |reading|
          say "      #{reading.label}  #{collation_reading_body(reading, long: long, language: cell.language)}"
        end
      end

      def collation_reading_body(reading, long:, language:)
        return display_text(reading.tokens.join(" "), language) if long
        return "(agrees with base)" if reading.edits.empty?

        reading.edits.map { |edit| format_collation_edit(edit, language) }.join("; ")
      end

      # Apparatus marks: a substitution as "base → variant", an omission as
      # "om. base" (the witness lacks it), an insertion as "add. variant".
      def format_collation_edit(edit, language)
        case edit.op
        when :sub
          "#{display_text(edit.base.join(' '), language)} → #{display_text(edit.witness.join(' '), language)}"
        when :del then "om. #{display_text(edit.base.join(' '), language)}"
        when :ins then "add. #{display_text(edit.witness.join(' '), language)}"
        end
      end

      # An uncollated witness: rendered undiffed, its reason stated plainly —
      # cross-script (the fold cannot bridge the transcription systems) or the
      # sole witness of its language here.
      def print_collation_aside(aside)
        reason = if aside.reason == :cross_script
                   "not collated — different transcription system, the fold cannot bridge it"
                 else
                   "not collated — sole witness of its language here"
                 end
        say "  [#{aside.language}/#{aside.script}] #{aside.label}  license: #{aside.license_class}  (#{reason})"
        say "    #{display_text(aside.text, aside.language)}"
      end

      def print_collation_missing(missing)
        no_match = missing.select { |witness| witness.status == :no_match }.map(&:label)
        not_synced = missing.select { |witness| witness.status == :not_synced }.map(&:label)
        withheld = missing.select { |witness| witness.status == :withheld }.map(&:label)
        say "  not attested here: #{no_match.join(', ')}" unless no_match.empty?
        say "  not synced: #{not_synced.join(', ')}" unless not_synced.empty?
        say "  license-withheld: #{withheld.join(', ')}" unless withheld.empty?
      end

      def format_parallel_side(side)
        "#{side.urn}#{" — #{side.title}" if side.title}#{" [#{side.language}]" if side.language}"
      end

      # Honest grouped arithmetic: paired counts 1:1 verse pairs; the blocks
      # clause (and its owned-line total) appears only when there ARE coarse
      # blocks, so verse-for-verse output stays byte-identical to pre-P8-1b.
      def parallel_counts(result)
        paired = result.groups.count { |group| group.kind == :pair }
        blocks = result.groups.select { |group| group.kind == :block }
        left_only = result.groups.count { |group| group.kind == :original }
        right_only = result.groups.count { |group| group.kind == :translation }
        block_lines = blocks.sum { |group| group.originals.size }
        blocks_clause = blocks_clause(blocks.size, block_lines)
        "aligned by citation: #{paired} paired, #{blocks_clause}" \
          "#{left_only} #{result.left.language} only, #{right_only} #{result.right.language} only"
      end

      # The blocks clause appears only when there ARE coarse blocks, so
      # verse-for-verse output stays byte-identical to the pre-P8-1b header.
      def blocks_clause(blocks, lines)
        return "" if blocks.zero?

        "#{plural(blocks, 'block')} covering #{plural(lines, 'line')}, "
      end

      def plural(count, noun)
        "#{count} #{noun}#{'s' unless count == 1}"
      end

      def parallel_line(language, line, width)
        label = language.to_s.ljust(width)
        return "#{label}—" if line.nil?

        "#{label}#{display_text(line.text, language)}#{withdrawn_tag(line.withdrawn)}"
      end

      # +reason:+/+at:+ (P93-2): the document card names WHY and WHEN it
      # left when the loader recorded it; a bare flag stays the honest
      # render for pre-P93 withdrawals and passage lines.
      def withdrawn_tag(withdrawn, reason: nil, at: nil)
        return "" unless withdrawn

        detail = [reason, at.respond_to?(:strftime) ? at.strftime("%Y-%m-%d") : at].compact.join(", ")
        detail.empty? ? "  (withdrawn)" : "  (withdrawn: #{detail})"
      end

      # P5-2: upstream scrapped the file; the attic kept it. Live, labeled.
      def retired_tag(document)
        document.retired_upstream ? "  (retired upstream)" : ""
      end

      # Open the fulltext index for reading; nil when the file is absent OR the
      # FTS table was never built (both mean "no index" → the sync/rebuild hint).
      def open_fulltext(config)
        return nil unless File.exist?(config.fulltext_path)

        db = Nabu::Store.connect_fulltext(config.fulltext_path)
        return db if db.table_exists?(Nabu::Store::Indexer::TABLE)

        db.disconnect
        nil
      end

      # One hint line per unregistered script present in the zero-hit query;
      # silent (zero-signal) otherwise.
      def print_script_miss_hints(query)
        return if query.nil?

        SCRIPT_MISS_HINTS.each_value do |(range, hint)|
          say "note: #{hint}" if query.each_char.any? { |char| range.cover?(char.ord) }
        end
      end

      # Render hits: urn + optional [language] header, then the snippet. Every
      # path's snippet is a window of the STORED text (P39-r3/P40-w,
      # StoredSnippet) — text_normalized, the folded skeleton, is NEVER shown (it
      # rendered 学 as 學 and だ as た). +proximity: true+ marks the two-term NEAR
      # snippet (both terms bracketed, on the stored glyphs since P40-w); +exact+
      # / +word+ annotate the glyph-literal / whole-word filters, so the footer
      # labels each path truthfully. Active facet filters (P17-2) are named in
      # one compact footer line — and only then. +incomplete+ (P35-6): the query
      # layer's honesty hint (the exhausted-inner-window note, or the
      # --exact/--word scan-ceiling note) — printed whenever present, so a short
      # page never masquerades as a complete answer.
      def print_search_results(results, facets: nil, query: nil, loans: nil, axis: nil, incomplete: nil,
                               exact: false, word: false, proximity: false, rank_note: nil,
                               browse: false, from: nil, to: nil, place: nil, within: nil,
                               meter_note: nil, words_note: nil, place_note: nil)
        if results.empty?
          say "no matches"
          # Empty-under-filter honesty (P35): --exact/--word suppressed the folded
          # candidates, so a "no matches" here must name the filter it applied.
          if exact
            say "note: --exact matched glyph-literally (the default fold would also find " \
                "reform variants, e.g. 学↔學, 弁↔辨/瓣/辯)"
          end
          say "note: --word required a whole-word match (a fragment inside a longer word does not count)" if word
          # The P42-2 guard served a corpus-wide sample (P42-r3) — an empty
          # page over a degraded path says so too, never a clean-looking silence.
          say "note: #{rank_note}" if rank_note
          # The meter facet's honesty line (P45-5): an empty page under
          # --meter says what layer it filtered on — or that the layer is
          # empty / the code unknown — never a silent zero.
          say "note: #{meter_note}" if meter_note
          # The word-grain degrade note (P54-4): --words could not filter
          # (non-Tibetan query / unsynced module) — plain search served.
          say "note: #{words_note}" if words_note
          # The --place lane note (P75 C-1): which lane an empty page
          # filtered on — identity refs or the name-LIKE fallback.
          say "note: #{place_note}" if place_note
          say "note: #{incomplete}" if incomplete
          return print_script_miss_hints(query)
        end

        results.each do |result|
          say "#{result.urn}#{" [#{result.language}]" if result.language}"
          say "  #{display_snippet(result.snippet, result.language)}"
        end
        say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} " \
            "(#{search_snippet_label(exact: exact, word: word, proximity: proximity,
                                     rank_note: rank_note, browse: browse)})" \
            "#{browse_window_footer(from: from, to: to, place: place, within: within) if browse}" \
            "#{facet_footer(facets, loans: loans, axis: axis)}"
        say "note: #{meter_note}" if meter_note
        say "note: #{words_note}" if words_note
        say "note: #{place_note}" if place_note
        say "note: #{incomplete}" if incomplete
        print_search_credits(results)
      end

      # The credit duty on the search surface (P43-2): the DISTINCT source
      # credits among the hits just shown, one line each — so a hit's text and
      # the attribution its grant requires appear on the same page. Nothing when
      # no shown source carries a credit (every ordinary search).
      def print_search_credits(results)
        results.filter_map { |r| r.credit&.strip }.reject(&:empty?).uniq.each do |credit|
          say "credit: #{credit}"
        end
      end

      # The date/place clause of a term-less browse footer (P42-6), naming the
      # content filters that made the browse legal (facets/loans/axis are named
      # by facet_footer); empty when neither is active (compact-footer rule).
      def browse_window_footer(from:, to:, place:, within: nil)
        parts = []
        parts << "dates: #{browse_year_window(from, to)}" if from || to
        parts << "place: #{place}" if place
        parts << "within: #{within}" if within
        parts.empty? ? "" : " · #{parts.join(' · ')}"
      end

      # A signed-year window as a compact footer string: "-300..-30", "from
      # 500", or "to 100" (BCE years negative — the --from/--to grammar).
      def browse_year_window(from, to)
        return "#{from}..#{to}" if from && to
        return "from #{from}" if from

        "to #{to}"
      end

      # The footer clause naming what the snippet shows, per path. All three
      # paths now show the STORED text (P40-w carried proximity off the folded
      # index form); --exact / --word / proximity annotate what the match means.
      # +rank_note+ (P42-2, plain path only) appends the skipped-rank honesty
      # clause: "…; term too common to rank — corpus-wide sample".
      def search_snippet_label(exact:, word: false, proximity: false, rank_note: nil, browse: false)
        return "filtered browse — corpus order, no ranking" if browse
        return "both terms bracketed; snippet shows the text as stored" if proximity

        stored = "snippet shows the text as stored"
        # A filtered path (--exact and/or --word) leads with what the match means;
        # plain search leads with the stored-text promise, then "fold-aware".
        return ["#{stored}; matching is fold-aware", rank_note].compact.join("; ") unless exact || word

        mode = if exact && word then "glyph-exact, whole-word"
               elsif exact then "glyph-exact"
               else "whole-word, fold-aware"
               end
        "#{mode}; #{stored}"
      end

      # " · facets: genre=epitaph province=pannonia% · loans: grc · axis: celtic"
      # — empty when no facet/loans/axis filter is active (zero-signal silence,
      # the compact rule). The axis names the desk(s) the membership filter
      # scoped to (P37-8).
      def facet_footer(facets, loans: nil, axis: nil)
        parts = []
        parts << "facets: #{facets.map { |facet, pattern| "#{facet}=#{pattern}" }.join(' ')}" if facets&.any?
        parts << "loans: #{loans}" if loans
        # The meter facet (P45-5) names its active filter in the footer like
        # every other facet; the source-layer note is a separate line.
        parts << "meter: #{[options[:meter], options[:meter_pattern]].compact.join(' ')}" if
          options[:meter] || options[:meter_pattern]
        parts << "axis: #{Array(axis).join(',')}" if axis && !Array(axis).empty?
        parts.empty? ? "" : " · #{parts.join(' · ')}"
      end

      # Render fuzzy hits (P16-4): the search-hit shape (urn + [language],
      # then the folded snippet with the fragment in [brackets]; --long lifts
      # the snippet window, house rule), plus ONE scope line — the fuzzy
      # index is documentary-only, so every render names what it covers (the
      # honest answer when --lang grc "finds nothing" in the literary corpus).
      def print_fuzzy_results(results, scope:, long: false, facets: nil, loans: nil, axis: nil, incomplete: nil)
        if results.empty?
          say "no matches"
        else
          results.each do |result|
            say "#{result.urn}#{" [#{result.language}]" if result.language}"
            say "  #{display_snippet(long ? result.folded_marked : result.snippet, result.language)}"
          end
          say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} " \
              "(fuzzy substring; highlights are diacritic-folded)#{facet_footer(facets, loans: loans, axis: axis)}"
        end
        say "note: #{incomplete}" if incomplete
        covered = scope&.any? ? scope.join(", ") : "no sources (flag fuzzy_index: true in config/sources.yml)"
        say "fuzzy index covers: #{covered}"
      end

      # Render KWIC rows (P8-3): left + keyword + right (each side already
      # trimmed to width by Concord), then the urn + [language] tag. The left
      # context is a fixed width, so keyword columns align down the page.
      # Non-gold lemma-mode rows carry the search --lemma tag (P26-4 silver,
      # P34-3 equivalence); gold and text-mode rows render exactly as before.
      # The footer totals each non-gold share so a mixed page is never
      # silently mixed.
      def print_concord_rows(rows)
        return say("no matches") if rows.empty?

        width = options[:width].to_i
        rows.each do |row|
          tier = row.tier && row.tier != "gold" ? " [#{row.tier}]" : ""
          left, keyword, right = concord_display_pieces(row, width)
          say "#{left}#{keyword}#{right}  #{row.urn}#{" [#{row.language}]" if row.language}#{tier}"
        end
        footer = "#{rows.size} #{rows.size == 1 ? 'line' : 'lines'} (KWIC; keyword in pristine text, corpus order)"
        silver = rows.count { |row| row.tier == "silver" }
        footer += " — #{silver} silver (automatic lemmatization)" if silver.positive?
        equivalence = rows.count { |row| row.tier == "equivalence" }
        footer += " — #{equivalence} equivalence (Classical-Latin equivalents)" if equivalence.positive?
        say footer
      end

      # Concord's columns were padded by Concord over the PRE-display pieces;
      # a display transform (stripped marks, isolate wrapping, token coloring)
      # changes their cell width, so re-pad here over DISPLAY CELLS
      # (Nabu::Display.rjust/ljust — ANSI SGR and isolates count 0, wide
      # clusters count 2) to keep the keyword column at exactly +width+ cells.
      def concord_display_pieces(row, width)
        left = display_text(row.left.sub(/\A +/, ""), row.language)
        right = display_text(row.right.sub(/ +\z/, ""), row.language)
        keyword = display_text(row.keyword, row.language)
        [Nabu::Display.rjust(left, width), keyword, Nabu::Display.ljust(right, width)]
      end

      # Render `parallels` (P15-1): the anchor line, then one hit per document —
      # urn [lang], score, shared-gram count and loci, and the shared PHRASE
      # spans indented beneath. A lemma-echoes section follows when the anchor is
      # gold-lemmatized. `--long` expands every truncated list.
      def print_parallels(result, urn:, long:)
        raise Thor::Error, "parallels: no live passage at #{urn} (check `nabu show #{urn}`)" if result.nil?

        title = result.anchor_title ? " — #{result.anchor_title}" : ""
        say "parallels of #{result.anchor_urn}#{title}"
        if result.gram_count.zero?
          say "  passage too short for #{Nabu::Query::Parallels::GRAM_SIZE}-word grams"
          return
        end

        say "  no surface-gram parallels" if result.hits.empty?
        result.hits.each { |hit| print_parallel_hit(hit, long: long) }
        say "#{result.hits.size} #{result.hits.size == 1 ? 'parallel' : 'parallels'} " \
            "from #{result.gram_count} grams (evidence is diacritic-folded)"
        print_lemma_echoes(result.lemma_echoes, long: long) unless result.lemma_echoes.empty?
      end

      def print_parallel_hit(hit, long:)
        loci = hit.loci > 1 ? " · #{hit.loci} loci" : ""
        grams = "#{hit.shared_gram_count} #{hit.shared_gram_count == 1 ? 'gram' : 'grams'}"
        say "#{hit.urn}#{" [#{hit.language}]" if hit.language}  " \
            "score #{format('%.2f', hit.score)} · #{grams}#{loci}"
        lines = compact_list(hit.evidence, long: long) do |span|
          display_text(long ? span : truncate_line(span, PARALLELS_SPAN_CHARS), hit.language)
        end
        lines.each { |line| say "  #{line}" }
      end

      def print_lemma_echoes(echoes, long:)
        say "lemma echoes (rare shared lemmas — re-inflected/reordered allusion):"
        echoes.each do |echo|
          say "#{echo.urn}#{" [#{echo.language}]" if echo.language}  score #{format('%.2f', echo.score)}"
          say "  #{compact_list(echo.shared_lemmas, long: long).join(', ')}"
        end
      end

      # Render `formulas` (P15-5): the slice header (passages/tokens), then one
      # line per formula — count × the folded gram — with example loci beneath
      # (compact) or every locus (--long). The footer states the ranking and the
      # recurring total so the "top N of M" elision is explicit.
      def print_formulas(result, long:)
        lang = result.lang ? " [#{result.lang}]" : ""
        say "formulas in #{result.scope}#{lang} — " \
            "#{plural(result.passage_count, 'passage')} / #{plural(result.token_count, 'token')}"
        return say("  no passages in scope (unknown source slug or urn prefix?)") if result.passage_count.zero?
        return say("  no #{result.gram_size}-grams recur ≥#{result.min_count}× in this slice") if result.formulas.empty?

        result.formulas.each { |formula| print_formula(formula, long: long) }
        say "showing #{result.formulas.size} of #{plural(result.recurring_count, 'formula')} " \
            "recurring ≥#{result.min_count}× (rank = count × #{result.gram_size}-gram length; " \
            "grams are diacritic-folded)"
      end

      def print_formula(formula, long:)
        say "#{formula.count}×  #{formula.gram}"
        return if formula.loci.empty?

        prefix = !long && formula.count > formula.loci.size ? "e.g. " : ""
        say "     #{prefix}#{formula.loci.join(', ')}"
      end

      # -- links journal (P16-1) ------------------------------------------------

      # `parallels --batch SCOPE`: mine the scope with Nabu::BatchParallels and
      # persist edges to the links journal. Progress ticks go to stderr
      # (stdout keeps the summary); the summary NAMES the pruning thresholds —
      # no silent caps — and suppresses zero fields (house style).
      def batch_parallels(scope)
        raise Thor::Error, "parallels --batch: give a source slug or urn prefix" if scope.empty?

        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        profile = batch_profile
        chunk_size = batch_chunk_size
        journal = Nabu::Store::LinksJournal.open!(options[:db] || config.links_path)
        result = Nabu::BatchParallels.new(catalog: catalog, fulltext: fulltext, journal: journal)
                                     .run(scope, profile: profile, lang: options[:lang], license: options[:license],
                                                 chunk_size: chunk_size, restart: options[:restart],
                                                 progress: chunk_size ? nil : batch_progress,
                                                 on_chunk: chunk_size ? batch_chunk_progress : nil,
                                                 **batch_thresholds)
        # P70-3b: the batch scope is config-durable — rebuild replays it
        # (P122-2: the profile NAME and chunk size ride along; the replay
        # re-resolves the profile from config/, the project definition).
        unless options[:db]
          params = { "lang" => options[:lang], "license" => options[:license],
                     "profile" => options[:profile], "chunk_size" => chunk_size }
                   .merge(batch_thresholds.transform_keys(&:to_s)).compact
          Nabu::LinkScopes.record!(config.link_scopes_path, producer: "parallels",
                                                            scope: scope, params: params)
        end
        print_batch_parallels(result)
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      rescue Interrupt
        raise unless chunk_size

        # A chunked run's committed chunks are durable (their edges and the
        # cursor landed together); only the chunk in flight rolled back.
        warn "\ninterrupted — every committed chunk is kept; rerun the same command to resume at the cursor."
        exit 130
      ensure
        catalog&.disconnect
        fulltext&.disconnect
        journal&.disconnect
      end

      def batch_thresholds
        thresholds = {}
        thresholds[:min_score] = options[:min_score].to_f if options[:min_score]
        thresholds[:per_anchor] = options[:per_anchor].to_i if options[:per_anchor]
        thresholds[:gram_size] = options[:gram_size].to_i if options[:gram_size]
        thresholds
      end

      # The --profile lookup (P122-2): a ReuseProfiles::Profile, nil when
      # the flag is absent; an undeclared name names the declared ones.
      def batch_profile
        return nil unless options[:profile]

        Nabu::ReuseProfiles.default.fetch(options[:profile])
      end

      # One stderr line per committed chunk (P122-2) — log-friendly, so a
      # `2> mine.log` run is readable while it is live.
      def batch_chunk_progress
        ->(report) { warn "  #{Nabu::BatchParallels.chunk_line(report)}" }
      end

      def batch_chunk_size
        return nil unless options[:chunk_size]

        size = options[:chunk_size].to_i
        raise Thor::Error, "parallels --batch: --chunk-size must be a positive integer" unless size.positive?

        size
      end

      # A stderr tick every BATCH_PROGRESS_EVERY anchors (and at the end), so a
      # minutes-long mine is visibly alive without flooding the terminal.
      def batch_progress
        lambda do |done, total, edges|
          return unless (done % BATCH_PROGRESS_EVERY).zero? || done == total

          warn "  #{done}/#{total} anchors · #{edges} edges" if total > BATCH_PROGRESS_EVERY
        end
      end

      def print_batch_parallels(result)
        say "batch parallels over #{result.scope}#{" [#{result.lang}]" if result.lang}: " \
            "#{plural(result.edges_written, 'edge')} written#{batch_refreshed(result)} · run #{result.run_id}" \
            "#{" · profile #{result.profile}" if result.profile}"
        say "  #{plural(result.anchor_count, 'anchor')} · kept top #{result.per_anchor}/anchor " \
            "at score ≥ #{result.min_score} · #{result.gram_size}-grams#{batch_superseded(result)} · " \
            "#{format('%.1f', result.elapsed)} s"
        return unless result.chunks > 1 || result.resumed

        say "  #{result.chunks_mined} of #{plural(result.chunks, 'chunk')} mined this run" \
            "#{' (resumed at the cursor)' if result.resumed}"
      end

      # `formulas --batch SCOPE` (P16-2): sweep the whole tradition once and
      # persist each formula as a STAR of kind=formula edges (hub = its first
      # locus in urn order; detail = the gram, score = the count — the
      # edge-shape verdict is argued in Nabu::BatchFormulas). Same summary
      # discipline as batch parallels: every pruning knob named.
      def batch_formulas(scope)
        raise Thor::Error, "formulas --batch: give a source slug or urn prefix" if scope.empty?

        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog

        journal = Nabu::Store::LinksJournal.open!(options[:db] || config.links_path)
        result = Nabu::BatchFormulas.new(catalog: catalog, journal: journal)
                                    .run(scope, gram_size: options[:gram_size].to_i,
                                                min_count: options[:min_count].to_i,
                                                lang: options[:lang], **max_formulas_option)
        unless options[:db]
          Nabu::LinkScopes.record!(config.link_scopes_path, producer: "formulas", scope: scope,
                                                            params: { "gram_size" => options[:gram_size].to_i,
                                                                      "min_count" => options[:min_count].to_i,
                                                                      "lang" => options[:lang] }
                                           .merge(max_formulas_option.transform_keys(&:to_s)).compact)
        end
        print_batch_formulas(result)
      rescue ArgumentError => e
        raise Thor::Error, "formulas: #{e.message}"
      ensure
        catalog&.disconnect
        journal&.disconnect
      end

      def max_formulas_option
        options[:max_formulas] ? { max_formulas: options[:max_formulas].to_i } : {}
      end

      def print_batch_formulas(result)
        say "batch formulas over #{result.scope}#{" [#{result.lang}]" if result.lang}: " \
            "#{plural(result.edges_written, 'edge')} written#{batch_refreshed(result)} · run #{result.run_id}"
        coalesced = result.coalesced.positive? ? " · #{result.coalesced} overlapping pairs coalesced" : ""
        say "  #{plural(result.formula_count, 'formula')} persisted as stars " \
            "(top #{result.max_formulas} by rank of #{result.recurring_count} recurring " \
            "≥#{result.min_count}× #{result.gram_size}-grams)#{coalesced}" \
            "#{batch_superseded(result)} · #{format('%.1f', result.elapsed)} s"
      end

      # `cognates --batch WORK` (P16-2): map the whole alignment work once and
      # persist kind=cognate edges between cross-language witness passages
      # meeting at a reconstruction root; the meet (ref · root [shelf]) rides
      # each edge's detail (the provenance verdict is argued in
      # Nabu::BatchCognates).
      def batch_cognates(work_id)
        raise Thor::Error, "cognates --batch: give a registered work id (nt)" if work_id.empty?

        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog && fulltext

        registry = Nabu::AlignmentRegistry.load(config.alignments_path)
        journal = Nabu::Store::LinksJournal.open!(options[:db] || config.links_path)
        result = Nabu::BatchCognates.new(catalog: catalog, fulltext: fulltext,
                                         registry: registry, journal: journal)
                                    .run(work_id, langs: parse_langs(options[:langs]), all: options[:all])
        unless options[:db]
          Nabu::LinkScopes.record!(config.link_scopes_path, producer: "cognates", scope: work_id,
                                                            params: { "langs" => parse_langs(options[:langs]),
                                                                      "all" => options[:all] }.compact)
        end
        print_batch_cognates(result)
      ensure
        catalog&.disconnect
        fulltext&.disconnect
        journal&.disconnect
      end

      def print_batch_cognates(result)
        langs = result.langs ? " [#{result.langs.join('×')}]" : ""
        say "batch cognates over #{result.work}#{langs}: " \
            "#{plural(result.edges_written, 'edge')} written#{batch_refreshed(result)} · run #{result.run_id}"
        suppressed = if result.suppressed.positive?
                       " · #{plural(result.suppressed, 'common-word group')} suppressed (--all keeps)"
                     else
                       ""
                     end
        say "  #{plural(result.group_count, 'verse-root group')}#{suppressed}" \
            "#{batch_superseded(result)} · #{format('%.1f', result.elapsed)} s"
      end

      def batch_refreshed(result)
        result.edges_refreshed.positive? ? " (+#{result.edges_refreshed} refreshed in place)" : ""
      end

      def batch_superseded(result)
        return "" unless result.superseded_runs.positive?

        " · superseded #{plural(result.superseded_runs, 'prior run')} " \
          "(#{plural(result.superseded_edges, 'edge')})"
      end

      # Render `nabu links` (P16-1): the urn header, one section per kind with
      # each edge's direction, resolved counterpart, and score, then the
      # provenance footer citing the producer run(s). Compact caps each kind at
      # LINKS_COMPACT_ITEMS; --long lists all (house rule, conventions §10).
      def print_links(result, long:)
        title = result.title ? " — #{result.title}" : ""
        say "links of #{result.urn}#{title}"
        return say("  no links") if result.total.zero?

        result.groups.keys.sort.each { |kind| print_links_group(kind, result.groups.fetch(kind), long: long) }
        result.runs.each do |run|
          say "#{plural(result.total, 'edge')} · run #{run.id}: #{run.producer} over #{run.scope} " \
              "#{format_link_params(run.params)}· #{run.created_at.strftime('%Y-%m-%d')}"
        end
      end

      def print_links_group(kind, edges, long:)
        say "#{kind} (#{edges.size}):"
        shown = long ? edges : edges.first(LINKS_COMPACT_ITEMS)
        shown.each { |edge| say "  #{format_link_edge(edge, kind)}" }
        hidden = edges.size - shown.size
        say "  … and #{hidden} more (--long lists all)" if hidden.positive?
      end

      def format_link_edge(edge, kind)
        arrow = edge.direction == :out ? "→" : "←"
        where = if edge.resolved?
                  "#{" — #{edge.title}" if edge.title}#{" [#{edge.language}]" if edge.language}"
                else
                  " (not in catalog)"
                end
        "#{arrow} #{edge.urn}#{where}#{format_link_evidence(edge, kind)}"
      end

      # The per-kind evidence tail (P16-2): a formula edge shows its gram and
      # slice count (“saga hwaet ic hatte” ×4 — "score 4.00" would misread a
      # count as a rarity score); a cognate edge shows its meet (the detail
      # already carries ref · root [shelf], and its score merely counts the
      # roots listed there — suppressed as zero-signal); a parallel edge keeps
      # the rarity score; an unknown future kind prints whatever it has.
      def format_link_evidence(edge, kind)
        case kind
        when "formula"
          "#{"  “#{edge.detail}”" if edge.detail}#{"  ×#{edge.score.to_i}" if edge.score}"
        when "cognate"
          edge.detail ? "  #{edge.detail}" : ""
        else
          "#{"  score #{format('%.2f', edge.score)}" if edge.score}#{"  #{edge.detail}" if edge.detail}"
        end
      end

      # Array params (cognates' langs) render comma-joined, not as inspected
      # Ruby arrays — compact house style.
      def format_link_params(params)
        pairs = params.except("kind").map do |key, value|
          # A long list (a profile's stop tokens) is provenance, not footer
          # reading — counted here; params_json keeps it whole.
          shown = if value.is_a?(Array)
                    value.size > 5 ? "#{value.size} tokens" : value.join(",")
                  else
                    value
                  end
          "#{key} #{shown}"
        end
        pairs.empty? ? "" : "(#{pairs.join(', ')}) "
      end

      # The `show` footer (P16-1): one "linked:" line, ONLY when the links
      # journal holds edges touching this urn — zero-signal silence otherwise
      # (no journal, no edges, nothing printed). Read-only, absent-file-safe.
      def print_linked_footer(config, urn)
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        return if journal.nil?

        counts = Nabu::Store::LinksJournal.kind_counts(journal, urn)
        return if counts.empty?

        say "  linked: #{counts.sort_by { |kind, _| kind }.map { |kind, count| "#{count} #{kind}" }.join(', ')}"
      ensure
        journal&.disconnect
      end

      # -- nabu note (P24-1) -------------------------------------------------

      # The `show`/`define` notes footer: one "owner note (topic, date): …"
      # line per note on the urn, and — on a document — the passage-note
      # children count. Zero-signal silence when unnoted (the linked-footer
      # stance); a catalog predating migration 015 has no lane at all.
      def print_notes_footer(catalog, result)
        reader = Nabu::Query::Notes.new(catalog: catalog)
        return unless reader.available?

        reader.for_urn(result.urn).each do |row|
          say "  owner note (#{row.topic}, #{row.added}): #{row.note}#{note_tags_fragment(row)}"
        end
        return unless result.is_a?(Nabu::Query::Show::DocumentResult)

        children = reader.child_count(result.urn)
        say "  passage notes: #{children}" if children.positive?
      end

      # The `links` owner-notes lane: the urn's own notes beside its mined
      # edges (curation next to discovery), silent when unnoted.
      def print_links_notes_lane(catalog, urn)
        rows = Nabu::Query::Notes.new(catalog: catalog).for_urn(urn)
        return if rows.empty?

        say "owner notes (#{rows.size}):"
        rows.each { |row| say "  #{note_line(row)}" }
      end

      def note_line(row)
        id = Nabu::NoteFile.record_id(topic: row.topic, urn: row.urn, added: row.added, note: row.note)
        "[#{id}] (#{row.topic}, #{row.added}) #{row.note}#{note_tags_fragment(row)}"
      end

      def note_tags_fragment(row)
        row.tags.empty? ? "" : "  [#{row.tags.join(', ')}]"
      end

      # `nabu note --list`: the bounded enumeration, oldest first, each urn
      # resolution-checked so a --force note on a not-yet-held urn reads
      # honestly dangling.
      # note --rm ID: one removal through the gateway, then the same
      # surgical derived refresh the append uses (file rewritten) or a
      # topic teardown (last note removed the file): rows + pin dropped.
      def note_remove(config, urn_arg)
        raise Thor::Error, "note: --rm takes no urn argument (--topic scopes the id search)" \
          unless urn_arg.to_s.strip.empty?

        shelf = Nabu::NoteShelf.new(dir: Nabu::NoteShelf.dir(config), resolver: nil)
        removal = shelf.remove_note!(id: options[:rm], topic: options[:topic])
        say "  removed  [#{options[:rm].strip.downcase}] #{removal.record.urn} — " \
            "#{removal.record.note[0, 60]}#{'…' if removal.record.note.length > 60}"
        if removal.file_deleted
          drop_note_topic(config, removal.topic, removal.path)
        else
          refresh_note_topic(config, removal.path)
        end
      end

      # The last note of a topic left the shelf: its derived rows and its
      # ledger pin go with the file (millisecond ops, the fast-path rule).
      def drop_note_topic(config, topic, path)
        catalog = open_catalog(config)
        begin
          catalog[:urn_notes].where(topic: topic).delete if catalog&.table_exists?(:urn_notes)
        ensure
          catalog&.disconnect
        end
        ledger = open_ledger(config)
        begin
          if ledger
            Nabu::Store::Pin.where(source_slug: Nabu::NoteShelf::SLUG,
                                   repo_url: "local:#{File.basename(path)}").delete
          end
        ensure
          ledger&.disconnect
        end
      end

      # -- lemma-enrich helpers (P84-1) ------------------------------------

      def lemma_worker_argv(language)
        Nabu::LemmaEnrich.worker_argv(language: language, venv: options[:venv])
      end

      # Project the shelf into passage_lemmas now (tier silver,
      # insert-if-absent, frequencies delta'd) — the same pass every
      # rebuild/sync runs, fired standalone so a finished campaign is
      # searchable without waiting for one.
      def lemma_index_only(config, shelf)
        raise Thor::Error, "no local-lemmas shelf at #{shelf.dir} — run a campaign first" \
          if shelf.languages.empty?

        registry = Nabu::SourceRegistry.load(config.sources_path)
        catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
        fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
        begin
          # P87-2: the apply rides the projection cache — the
          # fold/group work runs once per shelf state; a valid cache makes
          # this pass resolution+insert only. An UNARMED index (no silver
          # anywhere — the post-rebuild case) gets the bare-table window:
          # indexes drop, the bulk lands, each index rebuilds sorted.
          cache = Nabu::Store::SilverLemmaCache.new(
            path: Nabu::Store::SilverLemmaCache.default_path(config)
          )
          progress_reporter.stage("silver lemmas: fingerprinting the shelf")
          fingerprint = shelf.fingerprint
          cache.build!(shelf: shelf, progress: progress_reporter) unless cache.valid_for?(fingerprint)
          armed = Nabu::Store::Indexer.silver_armed?(fulltext)
          apply = lambda do
            Nabu::Store::SilverLemmaIndexer.apply_cached!(
              catalog: catalog, fulltext: fulltext, cache: cache,
              dictionary_filter_slugs: registry.lemma_filter_slugs,
              update_frequencies: true, progress: progress_reporter
            )
          end
          progress_reporter.stage("silver lemmas: projecting the cache into passage_lemmas" \
                                  "#{' (bare-table window — indexes cycle)' unless armed}")
          result = if armed
                     apply.call
                   else
                     Nabu::Store::Indexer.cycle_lemma_indexes(fulltext) { apply.call }
                   end
          finish_progress
          say "indexed #{commas(result.passages_indexed)} passages " \
              "(#{commas(result.rows_inserted)} silver rows) — skipped: " \
              "#{commas(result.skipped_covered)} already covered, " \
              "#{commas(result.skipped_missing)} missing/withdrawn, " \
              "#{commas(result.skipped_mismatch)} language-drifted; " \
              "#{commas(result.filtered_lemmas)} lemmas dictionary-filtered"
        ensure
          catalog.disconnect
          fulltext.disconnect
        end
        refresh_lemma_rollup(config)
      end

      # P121-2: the projection just moved silver passage_lemmas rows, so
      # the lemma attestation rollup re-derives in the same breath — the
      # `lemma` desk never serves a pre-projection silver curve.
      def refresh_lemma_rollup(config)
        catalog = Nabu::Store.connect(config.catalog_path)
        rows = Nabu::Store::LemmaRollup.refresh_lemmas!(catalog: catalog, fulltext_path: config.fulltext_path)
        say "lemma rollup re-derived: #{commas(rows)} rows"
      ensure
        catalog&.disconnect
      end

      # -- silver-dates (P122-1) --------------------------------------------

      def silver_dates_import(config, shelf)
        records = Nabu::DateShelf.read_import(options[:import])
        catalog = open_catalog(config) unless options[:force]
        raise Thor::Error, "silver-dates: no catalog to resolve urns against — run nabu sync, or --force" \
          if catalog.nil? && !options[:force]

        resolver = catalog && ->(urn) { !catalog[:documents].where(urn: urn, withdrawn: false).empty? }
        path = Nabu::DateShelf.new(dir: shelf.dir, resolver: resolver)
                              .append_batch!(records: records, force: options[:force])
        say "shelved #{commas(records.size)} estimate(s) → #{path}"
        say "  not yet on the timeline — `nabu silver-dates --project` projects the shelf" unless shelf.armed?
        say "  the shelf is armed — re-project now with `nabu silver-dates --project`" if shelf.armed?
      ensure
        catalog&.disconnect
      end

      def silver_dates_project(config, shelf)
        raise Thor::Error, "silver-dates: the local-dates shelf at #{shelf.dir} is empty — --import first" \
          if shelf.shard_paths.empty?

        catalog = open_or_create_catalog(config)
        shelf.arm!
        report = Nabu::Store::SilverDates.project!(catalog: catalog, shelf: shelf)
        say "projected #{commas(report.projected)} silver date(s) — " \
            "#{commas(report.unresolved)} estimate(s) name no live document, " \
            "#{commas(report.superseded)} superseded by a later estimate"
        say "  armed: every rebuild, builders:refresh and sync now re-projects the shelf"
        refresh_date_rollups(config, catalog)
      ensure
        catalog&.disconnect
      end

      def silver_dates_retract(config, shelf)
        shelf.disarm!
        catalog = open_catalog(config)
        removed = catalog ? Nabu::Store::SilverDates.retract!(catalog: catalog) : 0
        say "retracted #{commas(removed)} silver date(s); the shelf is disarmed (its estimates stay shelved)"
        refresh_date_rollups(config, catalog) if catalog
      ensure
        catalog&.disconnect
      end

      def silver_dates_census(config, shelf)
        records = 0
        shelf.each_record { records += 1 }
        say "local-dates shelf: #{shelf.dir}"
        say "  #{commas(records)} estimate(s) in #{commas(shelf.shard_paths.size)} shard(s), " \
            "#{commas(shelf.latest_by_urn.size)} document urn(s)"
        say "  #{shelf.armed? ? 'ARMED — projected at every rebuild/refresh/sync' : 'not armed — never projected'}"
        catalog = open_catalog(config)
        return unless catalog&.table_exists?(:document_axes)

        rows = catalog[:document_axes].where(axis_source: Nabu::Store::SilverDates::AXIS_SOURCE).count
        say "  #{commas(rows)} silver date row(s) on the timeline"
      ensure
        catalog&.disconnect
      end

      # The lemma/curve rollups bucket documents by date, so a moved
      # silver lane re-derives them in the same breath (the desks never
      # lag a projection — the lemma-enrich --index-only precedent).
      def refresh_date_rollups(config, catalog)
        return say("  lemma rollups: not in this catalog (migrate, then rake builders:refresh)") \
          unless Nabu::Store::LemmaRollup.available?(catalog)

        summary = Nabu::Store::LemmaRollup.rebuild!(catalog: catalog, fulltext_path: config.fulltext_path)
        say "  lemma rollups re-derived: #{commas(summary.lemma_rows)} lemma, #{commas(summary.curve_rows)} curve rows"
      end

      def lemma_spot_check(enricher)
        report = enricher.spot_check(sample: options[:spot_check].to_i)
        finish_progress
        say "gold spot-check (folded-lemma agreement on LCS-aligned tokens):"
        report.sort_by { |_slug, row| -row[:accuracy] }.each do |slug, row|
          say format("  %<slug>-18s gold_tokens=%<gold>-7d aligned=%<aligned>-7d folded=%<acc>.1f%%",
                     slug: slug, gold: row[:gold_tokens], aligned: row[:aligned], acc: row[:accuracy])
        end
        say "  (P79-4 bands: ~99% in-domain ITTB; 75–89% cross-domain — investigate a fall below them)"
      end

      def note_list(config, urn_arg)
        raise Thor::Error, "note: --list takes no urn (--topic narrows, --limit lifts)" \
          unless urn_arg.to_s.strip.empty?

        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        page = Nabu::Query::Notes.new(catalog: catalog).list(topic: options[:topic], limit: options[:limit].to_i)
        return say(%(no notes yet — nabu note URN "TEXT" writes the first)) if page.total.zero?

        resolved = Nabu::NoteShelf.catalog_resolver(catalog)
        page.rows.each do |row|
          say "#{row.urn}#{' (dangling)' unless resolved.call(row.urn)} — #{note_line(row)}"
        end
        remaining = page.total - page.rows.size
        say "… and #{remaining} more (--limit lifts, --topic narrows)" if remaining.positive?
      ensure
        catalog&.disconnect
      end

      # `nabu note URN` without TEXT: existing notes are SHOWN (a read —
      # works piped or not); a bare urn with none prompts on a TTY and
      # refuses honestly otherwise, BEFORE any write (the ingest precedent).
      # Returns the text to append, or nil when notes were shown.
      def show_notes_or_prompt(config, urn)
        existing = existing_notes(config, urn)
        unless existing.empty?
          say "notes on #{urn} (#{existing.size}):"
          existing.each { |row| say "  #{note_line(row)}" }
          say %(add another: nabu note #{urn} "TEXT" · remove one: nabu note --rm ID)
          return nil
        end
        unless $stdin.tty?
          raise Thor::Error, "note: no TEXT and no TTY to prompt — pass the note as an argument " \
                             "(nabu note URN \"TEXT\"); nothing was written"
        end

        # Plain $stdin.gets, NOT Thor's ask: Thor routes ask through
        # LineEditor::Readline when the readline ext exists (CI's Ruby 3.3
        # bundles it; homebrew 4.0 dropped it), and Readline reads the real
        # fd — invisible to the suite's $stdin double and to piped input.
        # One prompt, one line; the say keeps the ingest prompt furniture.
        say "  note for #{urn} (type it, Enter saves, ^C aborts):"
        answer = $stdin.gets.to_s.strip
        raise Thor::Error, "note: refusing an empty note — nothing was written" if answer.empty?

        answer
      end

      def existing_notes(config, urn)
        catalog = open_catalog(config)
        return [] unless catalog

        Nabu::Query::Notes.new(catalog: catalog).for_urn(urn, topic: options[:topic])
      ensure
        catalog&.disconnect
      end

      # The note-resolution seam (P85-A): a language pseudo-URN resolves when
      # the library actually knows the code (a held corpus language OR a
      # curated/census-named one) — so a note on a typo'd code refuses like a
      # note on a typo'd corpus URN; everything else defers to the standard
      # corpus-URN resolver.
      def note_resolver(catalog)
        return nil unless catalog

        base = Nabu::NoteShelf.catalog_resolver(catalog)
        languages = Nabu::Languages.new(catalog: catalog)
        lambda do |urn|
          code = Nabu::LanguageNote.code_of(urn)
          code ? known_language?(catalog, languages, code) : base.call(urn)
        end
      end

      def known_language?(catalog, languages, code)
        return true if languages.name(code)

        catalog.table_exists?(:documents) && !catalog[:documents].where(language: code).empty?
      end

      # The write path: resolution-checked append through the NoteShelf
      # gateway, then a SURGICAL derived refresh — parse the one topic file,
      # replace its urn_notes rows, upsert its ledger pin. NEVER the shelf's
      # ordinary sync: that path runs LocalFetch discovery plus the corpus
      # indexer, minutes of machinery for a one-line append (owner defect
      # 2026-07-18: "notes supposed to be lightning fast"). The full sync/
      # rebuild replays the same rows from the same file — consistency is by
      # construction, speed is the feature.
      def append_note(config, urn, text)
        resolved = true
        catalog = open_catalog(config)
        begin
          resolver = note_resolver(catalog)
          resolved = resolver ? resolver.call(urn) : false if options[:force]
          shelf = Nabu::NoteShelf.new(dir: Nabu::NoteShelf.dir(config), resolver: resolver)
          path = shelf.append_note!(urn: urn, note: text,
                                    topic: options[:topic] || Nabu::NoteShelf::DEFAULT_TOPIC,
                                    tags: (options[:tags] || "").split(","), force: options[:force])
          say "  noted    #{urn} → #{path}"
        ensure
          catalog&.disconnect
        end
        refresh_note_topic(config, path)
        unless resolved
          say "  note: #{urn} is not in the catalog yet — it reads (dangling) until the urn arrives", :yellow
        end
        say "try: bin/nabu show #{urn}" if resolved
      end

      # The fast-append derived refresh (P26 hotfix): one topic file parsed,
      # its urn_notes rows replaced, its per-file ledger pin upserted — the
      # exact rows a full sync would produce for this file, in milliseconds.
      # Other topics' pins are untouched (the sync-time set-reconcile stays
      # the full pipeline's job). Absent db/ledger degrade honestly: the
      # note is canonical either way and the next sync/rebuild indexes it.
      def refresh_note_topic(config, path)
        note_file = Nabu::NoteFile.load(path)
        catalog = open_catalog(config)
        if catalog
          begin
            Nabu::Store::NoteLoader.replace_for_topic!(catalog, note_file)
          ensure
            catalog.disconnect
          end
        else
          say "  (no catalog yet — the note indexes at the next sync/rebuild)"
        end
        ledger = open_ledger(config)
        return unless ledger

        begin
          key = "local:#{File.basename(path)}"
          sha = Digest::SHA256.file(path).hexdigest
          row = Nabu::Store::Pin.first(source_slug: Nabu::NoteShelf::SLUG, repo_url: key)
          if row
            row.update(last_sync_sha: sha)
          else
            Nabu::Store::Pin.create(
              source_slug: Nabu::NoteShelf::SLUG, repo_url: key, last_sync_sha: sha
            )
          end
        ensure
          ledger.disconnect
        end
      end

      # Cap a list to PARALLELS_COMPACT_ITEMS with a "… and N more" tail unless
      # +long+; each kept item passes through the block (span trimming). The tail
      # itself names --long so the elision is discoverable.
      def compact_list(items, long:)
        kept = long ? items : items.first(PARALLELS_COMPACT_ITEMS)
        rendered = kept.map { |item| block_given? ? yield(item) : item }
        extra = items.size - kept.size
        rendered << "… and #{extra} more (--long)" if extra.positive?
        rendered
      end

      # search --lemma FORM (P7-5): exact-lemma lookup over the treebank lemma
      # index. Replaces the FTS query (simplest honest v1 — combining both is
      # future work); composes with --lang/--license/--limit. A fulltext file
      # predating P7-5 lacks the lemma table, so that gets its own honest hint.
      # search --fuzzy FRAGMENT (P16-4): substring/fragment search over the
      # documentary trigram index (Query::Fuzzy — candidates, then verify).
      # Same open/close discipline as the sibling search paths; the trigram
      # table missing means the fulltext index predates P16-4, an honest
      # reindex hint, exactly the lemma-index precedent.
      def char_filter_options?
        options[:radical] || options[:strokes] || options[:char_component]
      end

      # --strokes N or A-B → an inclusive [low, high] range, or nil.
      def parse_strokes_option
        raw = options[:strokes]&.strip or return nil
        if (m = raw.match(/\A(\d+)\z/))
          [m[1].to_i, m[1].to_i]
        elsif (m = raw.match(/\A(\d+)-(\d+)\z/))
          [m[1].to_i, m[2].to_i].minmax
        else
          raise Thor::Error, "search: --strokes takes N or A-B (e.g. --strokes 8 or --strokes 8-12)"
        end
      end

      # The graded-reading search (P72-1, Edubba FR-1): --charset coverage
      # over the P72 passage_chars index — quasi-instant by construction
      # (indexed rarest-char candidates + exact verify), honest hint when
      # the index predates P72.
      def graded_search(query)
        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        validate_source!(catalog, options[:source])
        outcome = Nabu::Query::Graded.new(catalog: catalog, fulltext: fulltext)
                                     .run(query, charset: options[:charset],
                                                 max_foreign: options[:max_foreign].to_i,
                                                 min_chars: options[:min_chars].to_i,
                                                 lang: options[:lang], license: options[:license],
                                                 source: options[:source], limit: options[:limit].to_i)
        print_graded_results(outcome, query: query)
        print_display_footer
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def print_graded_results(outcome, query:)
        unless outcome.indexed
          return say("coverage not indexed yet — the passage_chars index arrives with the next " \
                     "`nabu rebuild` (or any sync's index refresh); no scan attempted")
        end
        if outcome.results.empty?
          tail = query.empty? ? "" : " that also match #{query.inspect}"
          return say("no passages read inside this #{outcome.charset_size}-character set" \
                     "#{" (±#{options[:max_foreign].to_i})" if options[:max_foreign].to_i.positive?}#{tail}")
        end

        outcome.results.each do |result|
          strangers = result.foreign.empty? ? "" : "  +{#{result.foreign.join(' ')}}"
          say "#{result.urn}  [#{result.language}]  #{result.nchars} chars#{strangers}"
          say "  #{result.text}"
        end
        say ""
        say "coverage: #{outcome.charset_size}-character set" \
            "#{" ± #{options[:max_foreign].to_i} strangers" if options[:max_foreign].to_i.positive?}" \
            "#{"; text query #{query.inspect}" unless query.empty?}" \
            "#{' — candidate window filled; narrow with --source/--lang for the rest' if outcome.capped}"
      end

      # The sign-coverage graded lane (P77-r16, sign-learning P-3): the
      # --charset architecture keyed on OSL sign names over the ATF
      # corpora. Needs the sign list (nabu sync osl) AND the passage_signs
      # index (a rebuild/refresh with the list present).
      def sign_graded_search
        validate_license!(options[:license])
        config = Nabu::Config.load
        list = Nabu::SignList.load_default(config: config)
        raise Thor::Error, "search: --signset needs the OSL sign list — run `nabu sync osl` first" unless list

        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        validate_source!(catalog, options[:source])
        outcome = Nabu::Query::SignGraded.new(catalog: catalog, fulltext: fulltext, sign_list: list)
                                         .run(signset: options[:signset],
                                              max_foreign: options[:max_foreign].to_i,
                                              lang: options[:lang], license: options[:license],
                                              source: options[:source], limit: options[:limit].to_i)
        print_sign_graded_results(outcome)
        print_display_footer
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def print_sign_graded_results(outcome)
        unless outcome.indexed
          return say("sign coverage not indexed yet — the passage_signs index arrives with the " \
                     "next `nabu rebuild` (or a sign-source sync's refresh) once osl is synced; " \
                     "no scan attempted")
        end
        if outcome.results.empty?
          return say("no passages read inside this #{outcome.signset_size}-sign set" \
                     "#{" (±#{options[:max_foreign].to_i})" if options[:max_foreign].to_i.positive?}")
        end

        outcome.results.each do |result|
          strangers = result.foreign.empty? ? "" : "  +{#{result.foreign.join(' ')}}"
          say "#{result.urn}  [#{result.language}]  #{result.nsigns} signs#{strangers}"
          say "  #{result.text}"
        end
        say ""
        say "sign coverage: #{outcome.signset_size}-sign set" \
            "#{" ± #{options[:max_foreign].to_i} strangers" if options[:max_foreign].to_i.positive?}" \
            "#{' — candidate window filled; narrow with --source/--lang for the rest' if outcome.capped}"
      end

      # The explicit character-structure search (P37-4): --radical/--strokes/
      # --char-component resolve to a glyph set (CharFilter), which filters
      # Han-language passages by containment, composing with a plain text
      # query. Kept visibly distinct from FTS — the footer names the filters.
      def char_structured_search(query)
        validate_license!(options[:license])
        if options[:radical] && !options[:radical].to_i.between?(1, 214)
          raise Thor::Error, "search: --radical is a KangXi radical number 1-214 (got #{options[:radical]})"
        end

        strokes = parse_strokes_option
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        unless catalog.table_exists?(:dictionary_entries)
          raise Thor::Error, "no char shelf in this catalog — run nabu sync unihan (for --radical/" \
                             "--strokes) or babelstone-ids/kradfile (for --char-component)"
        end
        validate_source!(catalog, options[:source])

        outcome = Nabu::Query::CharSearch.new(catalog: catalog, fulltext: fulltext)
                                         .run(query, radical: options[:radical]&.to_i, strokes: strokes,
                                                     component: options[:char_component], lang: options[:lang],
                                                     license: options[:license], source: options[:source],
                                                     limit: options[:limit].to_i)
        print_char_search_results(outcome, query: query)
        print_display_footer
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def print_char_search_results(outcome, query:)
        labels = outcome.labels.join(" AND ")
        if outcome.resolved_empty
          return say("no characters match [#{labels}] in the held char shelves — sync unihan " \
                     "(--radical/--strokes) or babelstone-ids/kradfile (--char-component)")
        end
        if outcome.results.empty?
          tail = query.empty? ? "" : " that also match #{query.inspect}"
          return say("no passages carry a character matching [#{labels}]#{tail} " \
                     "(#{outcome.char_count} characters resolved)")
        end

        outcome.results.each do |result|
          say "#{result.urn}  [#{result.language}]  {#{result.matched.join(' ')}}"
          say "  #{result.text}"
        end
        say ""
        text_note = query.empty? ? "" : "; text query #{query.inspect}"
        say "character filter: [#{labels}] — #{outcome.char_count} " \
            "#{outcome.char_count == 1 ? 'character' : 'characters'} resolved#{text_note}"
        say Nabu::Query::CatalogJoin::INCOMPLETE_PAGE_HINT if outcome.incomplete
      end

      # The semantic-neighbors page (P93-5): URN-anchored, no model
      # at query time — one sqlite-vec scan of the same-language subpool.
      # Every absent-machinery case surfaces as the query layer's honest
      # hint (store not built / anchor unembedded / extension missing).
      def similar_search(urn)
        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        vectors = Nabu::Store.connect(config.vectors_path)
        finder = Nabu::Query::Similar.new(catalog: catalog, vectors: vectors)
        page = finder.run(urn, limit: options[:limit].to_i)
        say "similar to #{page.anchor_urn} [#{page.language}] — model #{page.model}, " \
            "same-language only (cross-language is not served: the P79-5 measurement)"
        if page.results.empty?
          say "no neighbors in the store"
        else
          page.results.each do |result|
            say "#{result.urn}  (#{result.band})#{"  — #{result.document_title}" if result.document_title}"
            say "  #{display_snippet(result.snippet, result.language)}"
          end
          say "#{page.results.size} #{page.results.size == 1 ? 'neighbor' : 'neighbors'} " \
              "(banded semantic similarity — never a curated alignment; nabu align serves those)"
        end
        print_display_footer
      ensure
        catalog&.disconnect
        vectors&.disconnect
      end

      # The attic search (P93-2, first half of an owner ruling): scan the withdrawn set,
      # substring over folded text, reasons labeled. No fulltext file
      # needed — the scan is catalog-side by design (Search#run_withdrawn's
      # class note carries the measured argument).
      def withdrawn_search(query)
        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        fulltext = open_fulltext(config)
        searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run_withdrawn(query, limit: options[:limit].to_i)
        if results.empty?
          say "no matches in the withdrawn set"
        else
          results.each do |result|
            say "#{result.urn}#{" [#{result.language}]" if result.language}  WITHDRAWN " \
                "(#{result.reason || 'reason unrecorded'}" \
                "#{", #{result.withdrawn_at.strftime('%Y-%m-%d')}" if result.withdrawn_at})"
            say "  #{display_snippet(result.snippet, result.language)}"
          end
          say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} in the withdrawn set " \
              "(substring over folded text; nothing here is served by default search)"
        end
        print_display_footer
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def fuzzy_search(query)
        raise Thor::Error, "search: --fuzzy needs a fragment" if query.empty?

        validate_license!(options[:license])
        from, to = date_window
        facets = facet_filters
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        unless fulltext.table_exists?(Nabu::Store::Indexer::TRIGRAM_TABLE)
          raise Thor::Error, "no fuzzy index (the fulltext index predates fragment search) — " \
                             "run nabu sync or nabu rebuild"
        end

        require_timeline!(catalog) if from || to || options[:place] || options[:date_basis]
        require_facets!(catalog) if facets
        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        fuzzy = Nabu::Query::Fuzzy.new(catalog: catalog, fulltext: fulltext)
        results = fuzzy.run(query, lang: options[:lang], license: options[:license],
                                   limit: options[:limit].to_i, from: from, to: to, place: options[:place],
                                   date_basis: date_basis_filter,
                                   facets: facets, source: options[:source], sources: axis_slugs,
                                   loans: loans_filter)
        print_fuzzy_results(results, scope: fuzzy.scope, long: options[:long], facets: facets,
                                     loans: loans_filter, axis: axis_names, incomplete: fuzzy.incomplete_hint)
        print_display_footer
      rescue Nabu::Query::Fuzzy::QueryTooShort => e
        raise Thor::Error, "search: --fuzzy needs at least 3 characters after folding " \
                           "(#{query.inspect} folds to #{e.folded.inspect}) — the trigram floor"
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def lemma_search(positional_query)
        unless positional_query.empty?
          raise Thor::Error, "search: --lemma replaces the text query — give one or the other"
        end

        lemma = options[:lemma].strip
        raise Thor::Error, "search: --lemma needs a lemma" if lemma.empty?

        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        unless fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
          raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                             "run nabu sync or nabu rebuild"
        end

        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        searcher = Nabu::Query::LemmaSearch.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run(lemma, lang: options[:lang], license: options[:license],
                                      limit: options[:limit].to_i, morph: options[:morph],
                                      source: options[:source], sources: axis_slugs,
                                      gold_only: options[:gold_only], loans: loans_filter)
        print_lemma_results(results, query: lemma, axis: axis_names, incomplete: searcher.incomplete_hint)
        print_display_footer
      rescue Nabu::Query::MorphFacets::Error => e
        raise Thor::Error, "search: #{e.message}"
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # search A --near B [--window N] (P14-8): proximity search over the FTS
      # index via FTS5 NEAR. The anchor is the positional query OR --lemma
      # (expanded to attested surface forms); --near B is the second term;
      # --window N is the max folded tokens between them (default 10, 0 =
      # adjacent). Hits render exactly like plain search — the snippet brackets
      # BOTH terms. --morph does not compose (out of scope, said honestly).
      def proximity_search(positional_query)
        near = options[:near].strip
        raise Thor::Error, "search: --near needs a term" if near.empty?
        if options[:morph]
          raise Thor::Error, "search: --morph does not compose with --near " \
                             "(morphology-narrowed proximity is out of scope)"
        end
        window = options[:window].to_i
        raise Thor::Error, "search: --window must be 0 or more" if window.negative?

        lemma = options[:lemma]&.strip
        if options[:lemma]
          unless positional_query.empty?
            raise Thor::Error,
                  "search: --lemma replaces the text query — give one or the other"
          end
          raise Thor::Error, "search: --lemma needs a lemma" if lemma.empty?
        elsif positional_query.empty?
          raise Thor::Error, "search: --near needs an anchor term (a query, or --lemma)"
        end

        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        if lemma && !fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
          raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                             "run nabu sync or nabu rebuild"
        end

        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        searcher = Nabu::Query::Proximity.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run(
          query: lemma ? nil : positional_query, lemma: lemma, near: near, window: window,
          lang: options[:lang], license: options[:license], limit: options[:limit].to_i,
          source: options[:source], sources: axis_slugs, loans: loans_filter
        )
        print_search_results(results, loans: loans_filter, axis: axis_names,
                                      incomplete: searcher.incomplete_hint, proximity: true)
        print_display_footer
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # Render lemma hits: urn + language, the dictionary form with the surface
      # form(s) that attest it, then the PRISTINE passage line (truncated) —
      # the surface form already marks the match, so readability wins over a
      # folded snippet here. Non-gold hits are labeled per hit — gold stays
      # unlabeled, the pre-tier render exactly (P26-0 silver; P34-3
      # equivalence: a Latin key on a non-Latin passage, scholar-curated,
      # never attestation); the footer totals each non-gold share and names
      # the way out.
      def print_lemma_results(results, query: nil, axis: nil, incomplete: nil)
        if results.empty?
          say "no matches"
          say "note: #{incomplete}" if incomplete
          return print_script_miss_hints(query)
        end

        results.each do |result|
          forms = result.surface_forms.empty? ? "(no surface form)" : result.surface_forms
          gloss = result.gloss ? "  (#{result.gloss})" : ""
          morph = result.morph ? "  {#{result.morph}}" : ""
          tier = result.tier == "gold" ? "" : " [#{result.tier}]"
          say "#{result.urn}#{" [#{result.language}]" if result.language}#{tier}  " \
              "#{result.lemma} → #{forms}#{gloss}#{morph}"
          say "  #{display_text(truncate_line(result.text), result.language)}"
        end
        silver = results.count { |result| result.tier == "silver" }
        footer = "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} (exact lemma match; text is pristine)"
        footer += " — #{silver} silver (automatic lemmatization; --gold-only excludes)" if silver.positive?
        equivalence = results.count { |result| result.tier == "equivalence" }
        if equivalence.positive?
          footer += " — #{equivalence} equivalence (scholar-curated Classical-Latin equivalents; " \
                    "--gold-only excludes)"
        end
        footer += " · axis: #{Array(axis).join(',')}" if axis && !Array(axis).empty?
        say footer
        say "note: #{incomplete}" if incomplete
      end

      # Render a vocab profile (P14-3): the header (urn, title, language, scope),
      # then either the gold-lemma summary + distinctive table + hapax line, or
      # the honest no-gold-lemmas notice naming the gold-bearing languages.
      def print_vocab(profile)
        header = "#{profile.urn}#{" — #{profile.title}" if profile.title}"
        header += " [#{profile.language}]" if profile.language
        say header
        say "  #{profile.kind}, #{pluralize(profile.passages, 'passage')}"
        return print_vocab_no_gold(profile) if profile.total_tokens.zero?

        # The tier label (P26-4): a silver document profiles, but its counts
        # never render under the gold name — the line SAYS silver, plus an
        # explicit automatic-lemmatization warning. Gold (and pre-tier nil)
        # keeps the exact pre-tier render.
        silver = profile.lemma_tier == "silver"
        say "  #{silver ? 'silver' : 'gold'} lemmas: #{commafy(profile.total_tokens)} tokens · " \
            "#{commafy(profile.distinct_lemmas)} distinct lemmas · " \
            "#{commafy(profile.hapax_count)} hapax legomena " \
            "(#{profile.annotated_passages} of #{profile.passages} passages annotated)"
        if silver
          say "  lemma tier: silver (automatic lemmatization — token counts are not gold " \
              "attestation; corpus reference frequencies stay gold-only)"
        end
        print_vocab_distinctive(profile.distinctive)
        print_vocab_hapax(profile.hapax, profile.hapax_count)
      end

      # The distinctive-vocabulary table: lemma, its token count here, its corpus
      # passage-frequency, and the log-odds z-score, most distinctive first.
      def print_vocab_distinctive(distinctive)
        return if distinctive.empty?

        say ""
        say "  distinctive vocabulary (log-odds vs corpus, top #{distinctive.size}):"
        # Pad the lemma column by display cells (P35-7): a lzh/ojp lemma of Han
        # is two cells per ideograph, so char-count ljust would drift the table.
        width = distinctive.map { |e| Nabu::Display.width(e.lemma) }.max
        distinctive.each do |entry|
          say "    #{Nabu::Display.ljust(entry.lemma, width)}  #{entry.doc_count}× here · " \
              "#{commafy(entry.corpus_freq)}× corpus  (z=#{format('%.1f', entry.score)})"
        end
      end

      # The hapax legomena line: attested exactly once in this document. The full
      # count, then up to --limit spellings (they can number in the hundreds) —
      # or, under --long (house rule P15-8), every spelling with no "(+N more)"
      # tail. The full list already rides in the profile; --limit only caps the
      # print, so --long is a pure render concern here.
      def print_vocab_hapax(hapax, hapax_count)
        return if hapax_count.zero?

        say ""
        shown = options[:long] ? hapax : hapax.first(options[:limit].to_i)
        more = hapax_count - shown.size
        tail = more.positive? ? " (+#{commafy(more)} more)" : ""
        say "  hapax legomena (#{commafy(hapax_count)}, once each): #{shown.join(', ')}#{tail}"
      end

      # `vocab --by-century` (P15-2): the diachronic histogram of the dated
      # corpus, optionally filtered by a text query (plot a word across
      # centuries) and by --lang/--license/date/--place.
      # P72-4: the character-grain profile + coverage instrument.
      def char_vocab(urn)
        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog

        profile = Nabu::Query::CharVocab.new(catalog: catalog)
                                        .run(urn, limit: options[:limit].to_i,
                                                  coverage: options[:coverage])
        if options[:json]
          say JSON.pretty_generate(Nabu::Query::CharVocab.json_payload(urn, profile))
          return
        end
        raise Thor::Error, "vocab: no document #{urn}" unless profile

        print_char_vocab(profile)
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      ensure
        catalog&.disconnect
      end

      def print_char_vocab(profile)
        say "#{profile.urn}  #{profile.title}  [#{profile.language}]"
        if profile.total.zero?
          say "  no Han characters in this document — the char-grain profile is for sinograph texts"
          return
        end
        say "  #{profile.total} Han character occurrences · #{profile.distinct} distinct · " \
            "#{profile.passages} passages · #{profile.hapax_count} hapax"
        say ""
        say "  top characters:"
        profile.top.each { |row| say format("    %<char>s  %<count>6d", char: row.char, count: row.count) }
        say ""
        say "  hapax (once only): #{profile.hapax.join(' ')}#{' …' if profile.hapax_count > profile.hapax.size}"
        return unless profile.coverage

        c = profile.coverage
        say ""
        say "  coverage vs #{c.charset_size}-character set: #{c.occurrence_pct}% of occurrences · " \
            "#{c.distinct_covered}/#{c.distinct_total} distinct characters inside"
        return if c.strangers.empty?

        strangers = c.strangers.map { |row| "#{row.char} #{row.count}" }.join("  ·  ")
        say "  top strangers (teach next): #{strangers}"
      end

      def vocab_by_century(query)
        validate_license!(options[:license])
        from, to = date_window
        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        require_timeline!(catalog)
        fulltext = open_fulltext(config) unless query.empty?
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" if !query.empty? && fulltext.nil?

        result = Nabu::Query::Century.new(catalog: catalog, fulltext: fulltext).run(
          query: query.empty? ? nil : query, lang: options[:lang], license: options[:license],
          from: from, to: to, place: options[:place]
        )
        print_century(result)
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def print_century(result)
        say(if result.query
              "diachrony of #{result.query.inspect} (dated documents by century)"
            else
              "dated corpus by century"
            end)
        return say("  no dated documents match") if result.buckets.empty?

        width = result.buckets.map { |bucket| bucket.label.length }.max
        result.buckets.each do |bucket|
          say "  #{bucket.label.ljust(width)}  #{commafy(bucket.documents)} " \
              "#{bucket.documents == 1 ? 'document' : 'documents'}"
        end
        multi = result.multi_century.positive? ? "; #{commafy(result.multi_century)} span multiple centuries" : ""
        say "  #{commafy(result.total_documents)} dated documents (bucketed by earliest year#{multi})"
      end

      # A document with no gold lemmas: say so plainly and name the gold-bearing
      # languages (from the lemma index) so the user can profile something real.
      def print_vocab_no_gold(profile)
        say "  no gold lemmas — this document is not linguistically annotated " \
            "(0 of #{pluralize(profile.passages, 'passage')} carry one)."
        say "  Gold lemmas come from the treebank shelves (PROIEL, TOROT, ISWOC, " \
            "Universal Dependencies) and the ORACC cuneiform layer."
        # --long (house rule P15-8) lists every gold-bearing language; the compact
        # default shows the first eight with a "…" elision marker.
        shown = options[:long] ? profile.gold_languages : profile.gold_languages.first(8)
        langs = shown.map { |lang, count| "#{lang} (#{commafy(count)})" }
        ellipsis = profile.gold_languages.size > shown.size ? ", …" : ""
        say "  gold-bearing languages: #{langs.join(', ')}#{ellipsis}"
        say "  Try e.g. nabu vocab urn:nabu:proiel:caes-gal"
      end

      # Group an integer's digits into thousands (12345 → "12,345"). Plain string
      # work — no locale gem for one display nicety.
      def commafy(number)
        number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      # One display line of pristine text: newlines flattened, capped at 100
      # chars (treebank sentences are single lines; the cap guards outliers).
      def truncate_line(text, max = 100)
        line = text.tr("\n", " ")
        line.length > max ? "#{line[0, max]}…" : line
      end

      # Render dictionary entries whole (the CLI is the unbounded surface):
      # header with license label, gloss, the structured body, then the
      # resolved citations as show-able urns. Unresolved citations already
      # read inline in the body text.
      # +catalog+ (P24-1): when given, each entry's owner notes render after
      # its body — the note lane on the dictionary surface.
      def print_define_results(lemma, results, catalog: nil)
        if results.empty?
          return say("no dictionary entry for #{lemma} — #{@shelf_summary}; " \
                     "give a dictionary form (search --lemma finds attestations)")
        end

        crosswalk = define_crosswalk(results)
        results.each_with_index do |result, index|
          say "" if index.positive?
          print_define_entry(result)
          print_define_crosswalk(result, crosswalk, catalog)
          print_notes_footer(catalog, result) if catalog
        end
      end

      # P96 rider (the owner's 2026-09-04 challenge): the entry
      # crosswalk's value surfaces ON the card, not behind `nabu links`.
      # Per entry: a "first attested" line whenever a reference edge
      # carries one, and a "=" crosslink ONLY when the counterpart's
      # folded headword DIFFERS (the fold-invisible pairs — balzam↔bolzam
      # — where the curated identity does what no string search can;
      # same-headword pairs stay silent, define already shows them).
      # Absent links db = absent section, never an error.
      def define_crosswalk(results)
        config = Nabu::Config.load
        return {} unless File.exist?(config.links_path)

        journal = Nabu::Store::LinksJournal.connect(config.links_path, readonly: true)
        urns = results.map(&:urn)
        edges = journal[:links]
                .where(kind: "reference")
                .where(Sequel.|({ from_urn: urns }, { to_urn: urns }))
                .select(:from_urn, :to_urn, :detail).all
        edges.group_by { |e| urns.include?(e[:from_urn]) ? e[:from_urn] : e[:to_urn] }
      rescue Sequel::Error
        {}
      ensure
        journal&.disconnect
      end

      def print_define_crosswalk(result, crosswalk, catalog)
        own_folded = Nabu::Normalize.search_form(result.headword, language: result.language)
        Array(crosswalk[result.urn]).each do |edge|
          other = edge[:from_urn] == result.urn ? edge[:to_urn] : edge[:from_urn]
          if (attested = edge[:detail].to_s[/first attested: (.+)\z/, 1])
            say "  first attested: #{attested.strip}"
          end
          counterpart = dict_entry_headword(catalog, other)
          next unless counterpart && counterpart[:headword_folded] != own_folded

          say "  = #{counterpart[:headword]} — #{other} (the crosswalk joins spellings " \
              "no string search connects)"
        end
      end

      def dict_entry_headword(catalog, urn)
        return nil unless catalog

        @define_headwords ||= {}
        return @define_headwords[urn] if @define_headwords.key?(urn)

        @define_headwords[urn] =
          catalog[:dictionary_entries].where(urn: urn).select(:headword, :headword_folded).first
      end

      # One entry, the define house format — shared verbatim by `show` on a
      # dictionary-entry urn (P22-2), where a withdrawn entry reads honestly.
      # The language code rides the header (P46-r6, owner report: a WOLD hit
      # named no language — obvious for LSJ, load-bearing for the
      # multi-language shelves), the etym-entry style.
      def print_define_entry(result)
        lang = result.language.to_s.empty? ? "" : " [#{result.language}]"
        say "#{result.headword}#{lang} — #{result.dictionary_title} [#{result.license_class}]" \
            "#{' (withdrawn)' if result.withdrawn}  #{result.urn}"
        say "  gloss: #{result.gloss}" if result.gloss
        say ""
        say result.body
        print_reflexes(result.reflexes)
        print_resolved_citations(result)
        print_crossrefs(result)
      end

      # P123-1: entry→entry cross-references — a resolved pointer names
      # its target entry's urn (one `nabu show` away); an unresolved one
      # renders as its verbatim text, never a dead link. Compact cap like
      # the citations; --long shows all.
      def print_crossrefs(result)
        crossrefs = Array(result.crossrefs)
        return if crossrefs.empty?

        say ""
        say "cross-references:"
        shown = options[:long] ? crossrefs : crossrefs.first(12)
        shown.each do |crossref|
          line = "  #{crossref.label} (#{crossref.kind})"
          line += " → #{crossref.resolved_headword} #{crossref.resolved_urn}" if crossref.resolved_urn
          say line
        end
        rest = crossrefs.size - shown.size
        say "  … and #{rest} more (--long shows all)" if rest.positive?
      end

      # -- nabu signs (P53-2) ----------------------------------------------------

      def signs_dialect(name)
        return nil if name.nil?
        return name.to_sym if Nabu::AtfTokenizer::DIALECTS.map(&:to_s).include?(name)

        raise Thor::Error, "signs: unknown dialect #{name.inspect} — the known dialects are " \
                           "#{Nabu::AtfTokenizer::DIALECTS.join(', ')} (catf is the default)"
      end

      # Urn mode: language from the row (--lang overrides), the :etcsl
      # dialect auto-selected for the etcsl shelf (--dialect overrides).
      def signs_urn_result(urn, list:, catalog:, dialect:)
        result = Nabu::Query::Signs.new(sign_list: list, catalog: catalog)
                                   .run_urn(urn, language: options[:lang], dialect: dialect)
        raise Thor::Error, "signs: urn not found: #{urn}" if result.nil?

        result
      rescue Nabu::Query::Signs::Error => e
        raise Thor::Error, "signs: #{e.message}"
      end

      # The `nabu char` mold: readable columns, absent data ABSENT (a broken
      # token's row is its status; an unknown one says so plainly).
      def print_signs(result)
        say signs_header(result)
        result.lines.each do |line|
          say ""
          say "#{line.urn || "line #{line.number}"}  ·  #{line.text}"
          line.tokens.each { |token| print_signs_token(token) }
        end
        say ""
        say signs_footer(result)
      end

      def signs_header(result)
        parts = [result.mode == :urn ? result.urn : "raw ATF"]
        parts << result.language if result.language
        parts << "[#{result.source_slug}]" if result.source_slug
        parts << "dialect etcsl (c→š, j→ŋ)" if result.dialect == :etcsl
        parts.join("  ·  ")
      end

      def print_signs_token(token)
        columns = [token.input_value.ljust(14), (token.determinative ? "det" : "   "),
                   token.status.ljust(13), signs_token_detail(token)]
        say "  #{columns.join(' ')}".rstrip
        token.candidates.each do |candidate|
          say "  #{' ' * 19}#{candidate.status.ljust(13)} #{signs_candidate_detail(candidate)}"
        end
      end

      def signs_token_detail(token)
        case token.status
        when "ambiguous" then "#{token.candidates.size} candidates:"
        when "unknown" then "not in the sign list"
        when "broken" then nil
        else signs_candidate_detail(token)
        end
      end

      # sign name · codepoints · glyph · (%lang) · (form of X) — only what
      # the record holds; an unencoded sign says "unencoded". The form-of
      # tail is the kunga₃ fix: a sign and its same-named variant form of
      # ANOTHER sign must never render as indistinguishable twins.
      def signs_candidate_detail(token)
        parts = [token.sign_name]
        parts << (token.codepoints ? token.codepoints.join(" ") : "unencoded")
        parts << token.glyph if token.glyph
        parts << "(%#{token.language_qualifier})" if token.language_qualifier
        parts << "(form of #{token.form_of})" if token.form_of
        parts.compact.join("  ")
      end

      def signs_footer(result)
        tokens = result.lines.flat_map(&:tokens)
        tally = tokens.group_by(&:status).transform_values(&:size)
        parts = ["#{tokens.size} token(s)"]
        %w[deterministic qualified ambiguous no-codepoint broken unknown].each do |status|
          parts << "#{status} #{tally[status]}" if tally[status]
        end
        parts << "#{result.skipped_lines} structural line(s) skipped" if result.skipped_lines.positive?
        parts.join("  ·  ")
      end

      # -- the P65 `nabu char` dispatch lanes --------------------------------

      # The original P37-4 Han path; --json emits the P72-2 frozen contract
      # (the sign cards' P65 pattern extended to the Han card). A single
      # glyph OUTSIDE \p{Han} takes the reduced lane (P84-5) — the Han
      # card's shelf pipeline must never run for it (the define join's
      # Sanskrit stem expansion turned "a" into the TLS concept "AS").
      def han_char_card(config, input)
        return non_han_char_card(config, input) unless input.match?(/\p{Han}/)

        catalog = open_catalog(config)
        raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
        unless catalog.table_exists?(:dictionary_entries)
          raise Thor::Error, "no dictionary shelf in this catalog yet — run nabu sync unihan " \
                             "(or nabu rebuild after one)"
        end

        fulltext = open_fulltext(config)
        query = Nabu::Query::Char.new(catalog: catalog, fulltext: fulltext)
        card = query.run(input)
        if options[:json]
          say JSON.pretty_generate(Nabu::Query::Char.json_payload(input, card))
        else
          print_char_card(card, held_cjk: query.held_cjk_sources)
        end
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # The non-Han card. With the UCD identity floor synced (P85-B2) this is
      # the UNIVERSAL card (owner ruling: Shape C): name, category, numeric value and
      # decomposition for any writing system. Without it, the P84-5 reduced
      # card — glyph, codepoint, script probe — byte-identical (the feature-
      # module law). Pure Unicode either way, so no catalog is opened.
      def non_han_char_card(config, input, panels: nil)
        panels ||= char_ambiguity_panels(config, input)
        universal = Nabu::Ucd.load_default(config: config)&.then do |ucd|
          Nabu::Query::Char.universal(input, ucd)
        end
        return print_universal_char_card(input, universal, panels: panels) if universal

        reduced = Nabu::Query::Char.reduced(input)
        if options[:json]
          payload = Nabu::Query::Char.reduced_json_payload(input, reduced)
                                     .merge(char_panels_json(panels))
          return say(JSON.pretty_generate(payload))
        end

        say "#{reduced.glyph}  #{reduced.codepoint}#{"  ·  #{reduced.script}" if reduced.script}"
        noun = case reduced.script
               when "Hangul" then "a Hangul syllable"
               when nil then "not a Han character"
               else "a #{reduced.script} letter"
               end
        say ""
        say "#{reduced.glyph} is #{noun} — the char card's shelf lanes cover Han characters; " \
            "no CJK shelf claims it"
        print_ambiguity_panels(input, panels)
        say ""
        say "search: nabu search #{reduced.glyph}"
      end

      # -- the ambiguity layer (P86-5) ---------------------------------------
      # A single glyph can carry several identities at once: `a` is a Latin
      # letter AND a pinyin/romaji reading; `と` is a hiragana letter AND a
      # kun reading; `α` looks like `a` and `а`. The card leads with the
      # IDENTITY and composes every other lens as a labeled, capped panel;
      # `--as <lens>` narrows to one.

      def char_as_lens(config, input)
        case options[:as]
        when "identity" then identity_char_card(config, input)
        when "reading" then reading_lens_card(config, input)
        when "sign" then sign_lens_card(config, input)
        when "han" then han_char_card(config, input)
        else
          raise Thor::Error, "char --as: one of identity · reading · sign · han (got #{options[:as]})"
        end
      end

      # The pure identity lens: the universal card with no panels — works for
      # ANY code point, Han included (`char 木 --as identity`).
      def identity_char_card(config, input)
        raise Thor::Error, "char --as identity: the identity lens is one glyph (#{input})" unless input.each_char.one?

        non_han_char_card(config, input, panels: {})
      end

      def reading_lens_card(config, input)
        return if reading_char_card(config, input)

        raise Thor::Error, "#{input}: no held Han reading matches (kana kun/on · CAPS/lowercase " \
                           "romaji · pinyin) — is a dictionary shelf synced?"
      end

      def sign_lens_card(config, input)
        return cuneiform_char_card(config, input) if
          Nabu::CharDispatch.lane(input) == :cuneiform

        name_char_card(config, input)
      end

      # Gather the other-lens panels for a single glyph: the reverse-reading
      # matches (the same query the :name lane runs), the UTS #39 confusables
      # cluster, and (non-ASCII only — plain letters occur everywhere and
      # attest nothing) the corpus-attestation postings. Multi-char input
      # never panels.
      def char_ambiguity_panels(config, input)
        return {} unless input.each_char.one?

        panels = {}
        if (ucd = Nabu::Ucd.load_default(config: config))
          partners = ucd.confusables(input.each_char.first.ord)
                        .map { |other| [format("U+%04X", other), ucd.lookup(other)] }
          panels[:looks_like] = partners if partners.any?
        end
        catalog = open_catalog(config)
        if catalog&.table_exists?(:dictionary_entries)
          matches = Nabu::Query::Char.new(catalog: catalog).characters_for_reading(input)
          panels[:readings] = matches if matches.any?
        end
        if catalog && input.match?(/[^\x00-\x7F]/)
          fulltext = open_fulltext(config)
          corpus = Nabu::Query::Char.new(catalog: catalog, fulltext: fulltext)
                                    .universal_corpus(input)
          panels[:corpus] = corpus if corpus
        end
        panels
      ensure
        fulltext&.disconnect
        catalog&.disconnect
      end

      def print_ambiguity_panels(input, panels)
        if (matches = panels[:readings])
          shown = matches.first(Nabu::Query::Char::READING_PANEL_CAP)
          labels = shown.map do |match|
            kind = match.kind == "pinyin" ? "" : " (#{match.kind})"
            "#{match.glyph} #{match.reading}#{kind}"
          end
          say ""
          say "also a #{reading_panel_noun(matches)} — #{matches.size} Han character(s): " \
              "#{labels.join(' · ')}"
          say "  … nabu char #{input} --as reading for all #{matches.size}" if matches.size > shown.size
        end
        if (partners = panels[:looks_like])
          shown = partners.first(Nabu::Query::Char::LOOKS_LIKE_CAP)
          pieces = shown.map do |(hex, char)|
            [char&.glyph, hex, char&.display_name].compact.join(" ")
          end
          say ""
          say "looks like: #{pieces.join(' · ')}" \
              "#{" · … #{partners.size - shown.size} more" if partners.size > shown.size}"
        end
        print_corpus_panel(panels[:corpus])
      end

      # 88-B2: the last option-(a) members (owner-ruled 2026-08-28) render — encoded variants, named
      # sequences (capped, truncation announced), discouraged-sequence
      # warnings, Tangut/Nushu source fields. Absent = absent.
      def print_universal_extras(card)
        card.variants.each do |variant|
          say format("encoded variants: %<desc>s (U+%<sel>04X)",
                     desc: variant.description, sel: variant.selector)
        end
        shown = card.named_sequences.first(3) # const: a render cap, not a corpus census
        say "named sequences: #{shown.join(' · ')}" if shown.any?
        if card.named_sequences.size > shown.size
          say "named sequences: … #{card.named_sequences.size - shown.size} more"
        end
        card.discouraged.first(2).each do |row| # const: a render cap, not a corpus census
          preferred = row.preferred.split.map { |hex| Integer(hex, 16).chr(Encoding::UTF_8) }.join
          say "discouraged sequence (#{row.type}): heads #{row.sequence} — prefer #{preferred}"
        end
        return unless card.char_sources

        register, fields = card.char_sources
        pairs = fields.sort.map { |key, value| "#{key} #{value}" }
        say "#{register} sources: #{pairs.join(' · ')}"
      end

      # The B3 corpus line, era-honest: counts from a current-class index;
      # zero on a current-class index is a real zero; a miss on a legacy
      # (pre-widening) index names the rebuild instead of lying "0".
      def print_corpus_panel(corpus)
        return unless corpus

        say ""
        if corpus.counts.any?
          ranked = corpus.counts.sort_by { |_, docs| -docs }
          say "corpus attestation: #{ranked.map { |lang, docs| "#{lang || '?'} #{docs}" }.join(' · ')}"
        elsif corpus.class_stamp
          say "corpus attestation: no live passage carries it"
        else
          say "corpus attestation: the char index predates the P86 non-ASCII widening — " \
              "the next rebuild re-accumulates it"
        end
      end

      def reading_panel_noun(matches)
        kinds = matches.map(&:kind).uniq
        return "pinyin reading" if kinds == ["pinyin"]
        return "Japanese reading" if (kinds - %w[kun on]).empty?

        "Han reading"
      end

      def char_panels_json(panels)
        out = {}
        if (matches = panels[:readings])
          out["readings"] = matches.map do |match|
            { "glyph" => match.glyph, "reading" => match.reading, "kind" => match.kind }
          end
        end
        if (partners = panels[:looks_like])
          out["looks_like"] = partners.map do |(hex, char)|
            { "codepoint" => hex, "glyph" => char&.glyph, "name" => char&.display_name }
          end
        end
        if (corpus = panels[:corpus])
          out["corpus"] = { "counts" => corpus.counts, "class" => corpus.class_stamp }
        end
        out.empty? ? {} : { "panels" => out }
      end

      # The universal char card (P85-B2): the UCD identity layer, rendered.
      # Absent layers stay absent (binding-honesty) — numeric value, combining
      # class and decomposition print only when the character carries them.
      def print_universal_char_card(input, card, panels: {})
        payload = Nabu::Query::Char.universal_json_payload(input, card)
                                   .merge(char_panels_json(panels))
        return say(JSON.pretty_generate(payload)) if options[:json]

        say "#{card.glyph}  #{card.codepoint}#{"  ·  #{card.script}" if card.script}"
        say ""
        say "#{card.name} — #{card.category}"
        print_universal_context(card)
        say "numeric value: #{card.numeric}" if card.numeric
        say "combining class: #{card.combining_class}" if card.combining_class.positive?
        print_universal_decomposition(card.decomposition) if card.decomposition
        print_universal_charts(card)
        print_universal_extras(card)
        print_ambiguity_panels(input, panels)
        say ""
        say "search: nabu search #{card.glyph}"
      end

      # The member-context tier (P86-1): block, script identity, age, formal
      # aliases. Absent member → absent line (the P85 floor, byte-identical).
      def print_universal_context(card)
        say "block: #{card.block}" if card.block
        say "script: #{card.script} (#{card.script_code})" if card.script_code
        say "in Unicode since #{card.age}" if card.age
        card.numerals.each do |numeral|
          suffix = numeral.extended ? ", extended/sofit convention" : ""
          say "numeric (#{numeral.scheme}): #{numeral.value}#{suffix} — #{numeral.name}"
        end
        say "script context: #{card.script_context}" if card.script_context
        say "desk: #{card.script_desk}" if card.script_desk
        say "reading: #{card.reading}" if card.reading
        card.aliases.each do |a|
          say "#{a.type == 'correction' ? 'corrected name' : "#{a.type} alias"}: #{a.name}"
        end
      end

      # The NamesList charts annotation layer — informative, labeled as the
      # charts' voice, capped at render (truncation announced; caps live on
      # Nabu::Query::Char beside the card shape).
      def print_universal_charts(card)
        card.chart_aliases.each { |a| say "charts: = #{a}" }
        card.chart_notes.first(Nabu::Query::Char::CHART_NOTE_CAP).each { |n| say "charts: * #{n}" }
        if card.chart_notes.size > Nabu::Query::Char::CHART_NOTE_CAP
          say "charts: … #{card.chart_notes.size - Nabu::Query::Char::CHART_NOTE_CAP} more note(s)"
        end
        card.see_also.first(Nabu::Query::Char::CHART_SEE_ALSO_CAP).each do |ref|
          say "see also: #{"#{ref.glyph} " if ref.glyph}#{ref.codepoint} #{ref.text}".rstrip
        end
        return unless card.see_also.size > Nabu::Query::Char::CHART_SEE_ALSO_CAP

        say "see also: … #{card.see_also.size - Nabu::Query::Char::CHART_SEE_ALSO_CAP} more"
      end

      def print_universal_decomposition(decomp)
        pieces = decomp.parts.map do |part|
          "#{part.glyph} (#{part.codepoint}#{" #{part.name}" if part.name})"
        end
        label = decomp.kind ? "decomposes (#{decomp.kind})" : "decomposes"
        say "#{label}: #{pieces.join(' + ')}"
      end

      # The editorial/house-mark card (P85): what a single mark (⟦ ⌈ ⸀ ⿰ …)
      # MEANS in this library — its convention, the `--display` knob that
      # transforms it, and where it comes from. Pure config read (Nabu's own
      # convention, config/editorial_marks.yml), no catalog. The one card no
      # external Unicode tool can supply.
      def editorial_marks_char_card(config, input)
        mark = Nabu::EditorialMarks.lookup(input)
        # The dispatch set and the table are pinned to agree, so a routed mark
        # is always found; fall back to the universal/reduced card if it drifts.
        return non_han_char_card(config, input) unless mark

        if options[:json]
          return say(JSON.pretty_generate(
                       "glyph" => mark.glyph, "codepoint" => mark.codepoint, "class" => "editorial-mark",
                       "name" => mark.name, "meaning" => mark.meaning,
                       "display" => mark.display_rule, "seen_in" => mark.seen_in
                     ))
        end

        say "#{mark.glyph}  #{mark.codepoint}  ·  editorial mark"
        say ""
        say "#{mark.name} — #{mark.meaning}"
        say ""
        say "display: #{mark.display_rule}" if mark.display_rule
        say "seen in: #{mark.seen_in}" if mark.seen_in
      end

      def cuneiform_char_card(config, input)
        result = run_sign_card(config, input)
        emit_sign_card(result)
      end

      def hieroglyphic_char_card(config, input)
        emit_hiero_card(run_hiero_card(config, input))
      end

      # The multi-char NAME lane (P65-3): an OSL sign name/value first
      # (SZESZ, szesz, |ŠEŠ.AB| — C-ATF folds apply), then a Gardiner-style
      # Unikemet code (G5) — whichever held module resolves it wins; both
      # absent = name the modules. Non-name-shaped input (multi-char text
      # in another script) keeps the classic one-glyph grain error.
      def name_char_card(config, input)
        kana = input.match?(Nabu::Query::Char::KANA_INPUT)
        name_shaped = input.match?(Nabu::CharDispatch::NAME_SHAPE)
        reading_shaped = input.match?(Nabu::Query::Char::PINYIN_INPUT)
        unless kana || name_shaped || reading_shaped
          raise Thor::Error, "char: the card's grain is a single character — give one glyph " \
                             "(#{input}); search --char-component #{input.each_char.first} finds " \
                             "characters that contain one"
        end

        if name_shaped
          if Nabu::SignList.load_default(config: config)
            result = run_sign_card(config, input)
            return emit_sign_card(result) if result.card || result.candidates.any?
          end
          if Nabu::Hieroglyphs.load_default(config: config) && input.match?(Nabu::Query::HieroCard::CODE)
            hiero = run_hiero_card(config, input)
            return emit_hiero_card(hiero) if hiero.card
          end
        end
        return if (kana || reading_shaped) && reading_char_card(config, input)

        if options[:json]
          empty = Nabu::Query::SignCard::Result.new(input: input, card: nil, candidates: [])
          say JSON.pretty_generate(Nabu::Query::SignCard.json_payload(empty))
        else
          say "#{input}: resolved neither as an OSL sign name/value/list number, a Unikemet " \
              "Gardiner-style code, nor a held Han reading — said plainly (input shapes: " \
              "SAR · szesz · idx · MZL535 · 852 · G5 · wen · ひと)"
        end
      end

      # The reading→character lane (P65 gate feedback): pinyin against
      # unihan kMandarin, kana against kanjidic2 on/kun. Prints the match
      # list and answers true; false (silently) when no dictionary shelf or
      # no match, so the caller's honest miss line runs. --json emits the
      # frozen reading contract (P77-r15 — the last char lane to freeze).
      def reading_char_card(config, input)
        catalog = open_catalog(config)
        return false unless catalog&.table_exists?(:dictionary_entries)

        matches = Nabu::Query::Char.new(catalog: catalog).characters_for_reading(input)
        return false if matches.empty?

        if options[:json]
          say JSON.pretty_generate(Nabu::Query::Char.reading_json_payload(input, matches))
        else
          print_reading_matches(input, matches)
        end
        true
      ensure
        catalog&.disconnect
      end

      def print_reading_matches(input, matches)
        say "#{input}: #{matches.size} Han character(s) carry this reading — " \
            "nabu char <glyph> for a card:"
        labels = matches.map do |match|
          kind = match.kind == "pinyin" ? "" : " (#{match.kind})"
          "#{match.glyph} #{match.reading}#{kind}"
        end
        labels.each_slice(6) { |slice| say "  #{slice.join('   ')}" }
      end

      def run_sign_card(config, input)
        list = Nabu::SignList.load_default(config: config)
        unless list
          raise Thor::Error, "char: no cuneiform sign list held — run nabu sync osl (the sign " \
                             "card reads canonical/osl)"
        end

        fulltext = open_fulltext(config)
        catalog = open_catalog(config)
        begin
          Nabu::Query::SignCard.new(
            sign_list: list, readings: Nabu::CdliSignReadings.load_default(config: config),
            fulltext: fulltext, catalog: catalog,
            overlay: Nabu::EdubbaOverlay.load_default(config: config)
          ).run(input)
        ensure
          fulltext&.disconnect
          catalog&.disconnect
        end
      end

      def run_hiero_card(config, input)
        signs = Nabu::Hieroglyphs.load_default(config: config)
        raise Thor::Error, "char: no Egyptian sign spine held — run nabu sync unikemet" unless signs

        catalog = open_catalog(config)
        begin
          Nabu::Query::HieroCard.new(hieroglyphs: signs, catalog: catalog,
                                     overlay: Nabu::EdubbaOverlay.load_default(config: config)).run(input)
        ensure
          catalog&.disconnect
        end
      end

      def emit_sign_card(result)
        if options[:json]
          say JSON.pretty_generate(Nabu::Query::SignCard.json_payload(result))
        else
          print_sign_card(result)
        end
      end

      def emit_hiero_card(result)
        if options[:json]
          say JSON.pretty_generate(Nabu::Query::HieroCard.json_payload(result))
        else
          print_hiero_card(result)
        end
      end

      # The cuneiform sign card (P65-1): sections only where the held OSL /
      # CDLI readings / fulltext back them — the "absent, never —" rule.
      # Ambiguity lists ALL candidates, never one silently.
      def print_sign_card(result)
        return print_sign_card_miss(result) if result.card.nil?

        card = result.card
        header = [card.glyph, card.name].compact.join("  ")
        header += "  (deprecated)" if card.deprecated
        header += "  ·  #{(card.codepoints || ['unencoded']).join(' ')}"
        say header
        say card.uname if card.uname
        say "form of #{card.parent} — nabu char '#{card.parent}'" if card.parent
        say "aka: #{card.aka.join(' · ')}" if card.aka.any?
        print_sign_card_lists(card)
        print_sign_card_values(card)
        print_sign_card_glosses(card)
        print_sign_card_senses(card)
        print_sign_card_forms(card)
        print_sign_card_corpus(card)
        print_sign_didactic(card.didactic)
        print_sign_card_search(card)
      end

      # The Edubba cuneiform overlay section (P77-8, the hiero mold): the
      # certainty grade is LOAD-BEARING — "unclear" prints IN FRONT of
      # the meaning, never as a footnote.
      def print_sign_didactic(overlay)
        return if overlay.nil?

        say ""
        head = ["keyword \"#{overlay['keyword']}\"", overlay["value"] && "value #{overlay['value']}"]
               .compact.join("  ·  ")
        say "didactic (#{[overlay['course'],
                          overlay['chapter'] && "ch. #{overlay['chapter']}"].compact.join(' ')}): #{head}"
        if overlay["meaning"]
          grade = overlay["certainty"] == "unclear" ? "UNCLEAR (origin debated — not fact): " : ""
          say "  meaning: #{grade}#{overlay['meaning']}"
        end
        say "  origin: #{overlay['iconicity']}" if overlay["iconicity"]
        unless Array(overlay["confusables"]).empty?
          follow = overlay["confusables"].map { |name| "#{name} (nabu char #{name})" }.join("  ·  ")
          say "  confusable with: #{follow}"
        end
        say "  #{overlay['description']}" if overlay["description"]
        say "  codex: #{overlay['link']}" if overlay["link"]
        say "  #{overlay['attribution']}"
      end

      # P75 C-4: the follow-up affordance — a sign with reading values can
      # be searched as an OR over them (the inverse of this card).
      def print_sign_card_search(card)
        return if card.values.empty?

        say "search: nabu search --sign '#{card.glyph || card.name}'  (any reading value)"
      end

      def print_sign_card_senses(card)
        return if card.senses.empty?

        say ""
        say "senses (Wiktionary, kaikki extract):"
        card.senses.each { |sense| say "  #{sense.gloss}#{" (#{sense.pos})" if sense.pos}" }
      end

      def print_sign_card_miss(result)
        if result.candidates.any?
          say "#{result.input}: ambiguous — #{result.candidates.size} candidate signs " \
              "(all listed, never one silently):"
          result.candidates.each do |candidate|
            tail = +""
            tail << "  (form of #{candidate.form_of})" if candidate.form_of
            tail << "  (via #{candidate.via})" if candidate.via
            say "  #{candidate.glyph || 'unencoded'}  #{candidate.name}#{tail}  " \
                "—  nabu char '#{candidate.name}'"
          end
        else
          say "#{result.input}: not in the held OSL — said plainly"
        end
      end

      def print_sign_card_lists(card)
        return if card.lists.empty?

        say ""
        say "sign lists: #{card.lists.map { |list, nums| "#{list} #{nums.join(',')}" }.join('  ·  ')}"
      end

      def print_sign_card_values(card)
        return if card.values.empty?

        say ""
        rendered = card.values.map do |value|
          tail = +""
          tail << " (%#{value.language})" if value.language
          tail << " (deprecated)" if value.deprecated
          "#{value.value}#{tail}"
        end
        say "values (OSL): #{rendered.join(' · ')}"
      end

      def print_sign_card_glosses(card)
        glossed = card.glosses.select(&:meaning)
        return if glossed.empty?

        say ""
        say "meanings (CDLI sign readings):"
        glossed.each { |gloss| say "  #{gloss.reading} → #{gloss.meaning}" }
      end

      def print_sign_card_forms(card)
        return if card.forms.empty?

        say ""
        say "variant forms:"
        card.forms.each do |form|
          say "  #{form.glyph || 'unencoded'}  #{form.name}  —  nabu char '#{form.name}'"
        end
      end

      def print_sign_card_corpus(card)
        return if card.corpus.empty?

        say ""
        top = card.corpus.sort_by { |_, count| -count }
                         .map { |value, count| "#{value} #{count}" }.join("  ·  ")
        say "in the corpus (fulltext document counts, by spelled value): #{top}"
      end

      # The Egyptian sign card (P65-2): the Unikemet identity + the aes
      # hiero_inventar panel — absent upstream fields are absent lines.
      def print_hiero_card(result)
        card = result.card
        return say("#{result.input}: not in the held Unikemet file — said plainly") if card.nil?

        header = [card.glyph, card.codepoint].compact.join("  ")
        header += "  ·  #{card.jsesh} (Gardiner/JSesh)" if card.jsesh
        core = { "C" => "core", "L" => "legacy" }[card.core]
        header += "  ·  #{core}" if core
        say header
        say card.desc if card.desc
        say ""
        say "catalog: #{card.cat} (Unicode kEH_Cat)  ·  UniK #{card.unik}"
        say "function: #{card.func}" if card.func
        say "value: #{card.fval}" if card.fval
        concordances = []
        concordances << "Hieroglyphica #{card.hg}" if card.hg
        concordances << "IFAO #{card.ifao}" if card.ifao
        say "concordances: #{concordances.join('  ·  ')}" if concordances.any?
        say "alternate sequence: #{card.alt_seq}" if card.alt_seq
        print_hiero_didactic(card.didactic)
        return if card.corpus.empty?

        say ""
        lines = []
        if card.corpus["passages"]
          lines << "#{card.corpus['signs']} sign(s) across #{card.corpus['passages']} " \
                   "passage(s) (#{Nabu::Query::HieroCard::HIERO_SOURCES.keys.join(' + ')} annotations)"
        end
        # The AED per-text postings (P103-2) — text grain, its own line,
        # with the word-token grain and the damaged (<unclear>) share.
        lines << format_aed_hiero_postings(card.corpus) if card.corpus["aed_texts"]
        say "in the wild: #{lines.join(' · ')}"
      end

      def format_aed_hiero_postings(corpus)
        damaged = corpus["aed_unclear"].to_i.positive? ? ", #{corpus['aed_unclear']} damaged" : ""
        "#{corpus['aed_signs']} sign(s) in #{corpus['aed_words']} word(s) across " \
          "#{corpus['aed_texts']} text(s)#{damaged} (aed hieroglyph transcriptions)"
      end

      # The Edubba overlay section (P72-6). The certainty grade is
      # LOAD-BEARING: "unclear" is Edubba's never-present-as-fact rule,
      # so it prints IN FRONT of the gloss, not as a footnote.
      def print_hiero_didactic(overlay)
        return if overlay.nil?

        say ""
        head = ["keyword \"#{overlay['keyword']}\"", overlay["label"]].compact.join("  ·  ")
        say "didactic (#{[overlay['course'],
                          overlay['chapter'] && "ch. #{overlay['chapter']}"].compact.join(' ')}): #{head}"
        if overlay["voice"]
          grade = overlay["certainty"] == "unclear" ? "UNCLEAR (origin debated — not fact): " : ""
          say "  #{overlay['voice_kind']}: #{grade}#{overlay['voice']}"
        end
        unless Array(overlay["confusables"]).empty?
          follow = overlay["confusables"].map { |code| "#{code} (nabu char #{code})" }.join("  ·  ")
          say "  confusable with: #{follow}"
        end
        say "  #{overlay['description']}" if overlay["description"]
        say "  codex: #{overlay['link']}" if overlay["link"]
        say "  #{overlay['attribution']}"
      end

      # The character card (P37-4): each section printed only when a held
      # shelf backs it for this glyph (the "absent, never —" rule). The
      # diachronic column is what nabu adds over Jisho; the synchronic
      # sections match it field-for-field where the shelves reach.
      def print_char_card(card, held_cjk: [])
        return say("no dictionary shelf in this catalog yet — run nabu sync unihan") if card.nil?

        say "#{card.glyph}  #{card.codepoint}#{char_header_tail(card)}"
        print_char_decomposition(card)
        print_char_components(card)
        print_char_variants(card)
        print_char_ja_readings(card)
        print_char_sinoxenic(card)
        print_char_pedagogy(card)
        print_char_desk_reference(card)
        print_char_diachronic(card)
        print_char_corpus(card)
        print_char_search_affordances(card)
        print_char_absence(card, held_cjk)
      end

      # glyph · N strokes · radical M NAME — only the parts Unihan backs.
      def char_header_tail(card)
        parts = []
        parts << "#{card.total_strokes} strokes" if card.total_strokes
        parts << "radical #{card.radical.number} #{card.radical.glyph} #{card.radical.name}" if card.radical
        parts.empty? ? "" : "  ·  #{parts.join('  ·  ')}"
      end

      def print_char_decomposition(card)
        return if card.ids.empty?

        say ""
        say "decomposition (BabelStone IDS):"
        card.ids.each do |ids|
          tag = ids.sources ? " (#{ids.sources})" : ""
          say "  #{ids.sequence}#{tag}"
          ids.components.each do |component|
            say "    #{component} — nabu char #{component} · nabu search --char-component #{component}"
          end
        end
      end

      def print_char_components(card)
        return if card.components.empty?

        say ""
        say "components (KRADFILE index): #{card.components.join(' ')}"
      end

      def print_char_variants(card)
        return if card.variants.empty?

        say ""
        say "variants:"
        card.variants.each do |variant|
          say "  #{variant.relation}: #{variant.glyph} (#{variant.codepoint}) — nabu char #{variant.glyph}"
        end
      end

      def print_char_ja_readings(card)
        readings = card.readings_ja or return
        say ""
        say "readings (ja, KANJIDIC2):"
        say "  on: #{readings[:on].join('、')}" if readings[:on].any?
        say "  kun: #{readings[:kun].join('、')}" if readings[:kun].any?
        say "  nanori: #{readings[:nanori].join('、')}" if readings[:nanori].any?
        say "  meanings: #{readings[:meanings].join('; ')}" if readings[:meanings].any?
      end

      def print_char_sinoxenic(card)
        return if card.readings_sinoxenic.empty?

        say ""
        say "readings (sinoxenic, Unihan):"
        card.readings_sinoxenic.each { |label, value| say "  #{label}: #{value}" }
      end

      def print_char_pedagogy(card)
        pedagogy = card.pedagogy or return
        say ""
        labels = { "grade" => "Jōyō grade", "jlpt" => "JLPT", "freq" => "newspaper freq" }
        say "pedagogy: #{pedagogy.map { |k, v| "#{labels[k]} #{v}" }.join('  ·  ')}"
      end

      def print_char_desk_reference(card)
        return if card.desk_reference.empty?

        say ""
        say "desk reference: #{card.desk_reference.map { |k, v| "#{k} #{v}" }.join('  ·  ')}"
      end

      # The diachronic column — the half no dictionary site carries.
      def print_char_diachronic(card)
        print_char_shelf_block("Old Chinese (Baxter-Sagart)", card.old_chinese)
        print_char_shelf_block("Middle Chinese (Qieyun / Baxter-Sagart)", card.middle_chinese)
        print_char_shelf_block("early-Japan lexicography (HDIC)", card.early_japan)
        print_char_tls(card.tls)
      end

      def print_char_shelf_block(label, entries)
        return if entries.empty?

        say ""
        say "#{label}:"
        entries.each do |entry|
          say "  [#{entry.slug}] #{entry.gloss || entry.lines.first}"
          entry.lines.each { |line| say "    #{line}" }
        end
      end

      def print_char_tls(entries)
        return if entries.empty?

        say ""
        say "TLS (Thesaurus Linguae Sericae):"
        entries.each do |entry|
          attest = entry.attestations.positive? ? " — #{entry.attestations} attestation(s)" : ""
          say "  [#{entry.slug}] #{entry.gloss}#{attest}"
          entry.lines.each { |line| say "    #{line}" }
        end
      end

      def print_char_corpus(card)
        if card.corpus.nil?
          say ""
          say "corpus attestation: not indexed yet — nabu rebuild (or the next sync) builds " \
              "the char-postings index"
          return
        end
        return if card.corpus.empty?

        say ""
        totals = card.corpus.sort_by { |_, count| -count }
                            .map { |lang, count| "#{lang} #{count}" }.join("  ·  ")
        say "corpus attestation: #{totals}"
        # P72-5: the per-source provenance split, when more than one source
        # attests (a single-source panel would just repeat the line above).
        split = card.corpus_by_source || []
        return unless split.map(&:first).uniq.size > 1

        say "  by source: #{split.map { |slug, lang, docs| "#{slug} #{lang} #{docs}" }.join('  ·  ')}"
      end

      def print_char_search_affordances(card)
        say ""
        say "search: nabu search #{card.glyph}  ·  nabu search --char-component #{card.glyph}" \
            "#{"  ·  nabu search --radical #{card.radical.number}" if card.radical}"
      end

      # When NOTHING backed the card, say so honestly (the glyph is unknown to
      # every held shelf) rather than printing a bare header. P84-5: the hint
      # tells shelves-absent apart from char-not-covered — held CJK shelves
      # that stay silent on this glyph are named as held, and the sync points
      # only at the shelves actually missing from the dictionaries table.
      def print_char_absence(card, held_cjk)
        return unless card.held_shelves.empty? && card.ids.empty? && card.components.empty? &&
                      card.radical.nil? && (card.corpus || {}).empty?

        missing = Nabu::Query::Char::CJK_SHELF_SOURCES.keys - held_cjk
        say ""
        if held_cjk.empty?
          say "no held shelf carries #{card.glyph} yet — sync the CJK shelves (#{missing.join(', ')})"
        elsif missing.empty?
          say "the held CJK shelves (#{held_cjk.join(', ')}) don't carry #{card.glyph}"
        else
          say "the held CJK shelves (#{held_cjk.join(', ')}) don't carry #{card.glyph} — " \
              "sync the missing CJK shelves (#{missing.join(', ')})"
        end
      end

      # A reconstruction entry's descendant reflexes (P14-1): attested-here
      # cognates first with their gold-lemma passage counts, then an honest
      # one-line summary of the rest (the full tree is in the data; the
      # attested ones are the actionable ones).
      #
      # The tier rule (P26-0): attested_count IS the gold count — a silver
      # (automatic-lemmatization) count renders beside it as "(+N silver)",
      # and a silver-ONLY reflex gets its own labeled section, "silver N
      # passages". NEVER a bare number that could read as gold. The
      # equivalence tier (P34-3) rides the same contract with its own name:
      # "(+N equivalence)" beside gold, an equivalence-only section below —
      # scholar-curated Classical-Latin equivalents on non-Latin passages,
      # never attestation.
      def print_reflexes(reflexes)
        return if reflexes.empty?

        attested, uncounted = reflexes.partition(&:attested_count)
        silver_only, unattested = uncounted.partition(&:silver_count)
        equivalence_only, rest = unattested.partition(&:equivalence_count)
        unless attested.empty?
          say ""
          say "attested in this corpus (nabu search --lemma):"
          attested.sort_by { |r| -r.attested_count }.each do |r|
            say "  [#{r.language}] #{reflex_form(r)} — #{r.attested_count} " \
                "#{r.attested_count == 1 ? 'passage' : 'passages'}#{tier_suffixes(r)}"
          end
        end
        unless silver_only.empty?
          say ""
          say "silver-only (automatic lemmatization — not gold-attested; nabu search --lemma):"
          silver_only.sort_by { |r| -r.silver_count }.each do |r|
            say "  [#{r.language}] #{reflex_form(r)} — silver #{r.silver_count} " \
                "#{r.silver_count == 1 ? 'passage' : 'passages'}"
          end
        end
        unless equivalence_only.empty?
          say ""
          say "equivalence-only (scholar-curated Classical-Latin equivalents on non-Latin " \
              "passages — not attested in this language; nabu search --lemma):"
          equivalence_only.sort_by { |r| -r.equivalence_count }.each do |r|
            say "  [#{r.language}] #{reflex_form(r)} — equivalence #{r.equivalence_count} " \
                "#{r.equivalence_count == 1 ? 'passage' : 'passages'}"
          end
        end
        return if rest.empty?

        say ""
        options[:long] ? print_reflexes_expanded(rest) : print_reflexes_capped(rest)
      end

      # The labeled non-gold riders on a gold-attested line (P26-0 silver,
      # P34-3 equivalence) — each tier under its own name, never summed.
      def tier_suffixes(reflex)
        suffix = reflex.silver_count ? " (+#{reflex.silver_count} silver)" : ""
        suffix += " (+#{reflex.equivalence_count} equivalence)" if reflex.equivalence_count
        suffix
      end

      # Compact default (house compact-CLI rule): the first ten non-attested
      # reflexes inline, the tail honestly summarised as "… and N more".
      def print_reflexes_capped(rest)
        say "other reflexes (not attested here): " \
            "#{rest.first(10).map { |r| "[#{r.lang_code}] #{reflex_form(r)}" }.join(', ')}" \
            "#{" … and #{rest.size - 10} more" if rest.size > 10}"
      end

      # --long (P14-11): the WHOLE non-attested list, grouped by language so a
      # long tail (a Proto-Slavic root can name 25+ descendants) stays readable
      # — languages in first-seen (stored depth-first) order, forms within a
      # language in stored order. Nothing is elided under the flag.
      # P18-4 render verdict: each group header carries the code's NAME
      # inline when the library knows one ("[gkm · Medieval Greek]") — one
      # name per LINE, so the compact rule holds exactly where the owner's
      # pain was; the capped default stays code-only (ten names inline would
      # blow the line) and etym's footer points at `nabu language` instead.
      # P57-4: when Nabu::Lects is present the label prefers the RESOLVED
      # lect id + its composed registry name ("[grc:byz · Byzantine Greek]"
      # for gkm — the codemap default) over the old kaikki-census reading;
      # absent Lects, or a resolved id with no registry entry, unchanged.
      def print_reflexes_expanded(rest)
        say "other reflexes (not attested here) — all #{rest.size}, grouped by language:"
        rest.group_by(&:lang_code).each do |lang_code, group|
          say "  #{reflex_group_label(lang_code)} #{group.map { |r| reflex_form(r) }.join(', ')}"
        end
      end

      def reflex_group_label(lang_code)
        if @lects
          resolved = @lects.resolve(lang_code)
          lect = @lects.lect(resolved)
          return "[#{resolved} · #{lect.name}]" if lect
        end
        name = @languages&.name(lang_code)
        name ? "[#{lang_code} · #{name}]" : "[#{lang_code}]"
      end

      # P17-3: the per-edge loan label — a borrowed-flagged reflex reads
      # "(loan)"; unflagged and not-yet-reparsed (NULL) edges stay bare.
      # P76 U-6: the kaikki doubt tag appends " (uncertain)" — the WOLD
      # idiom, upstream word verbatim (conventions §12).
      def reflex_form(reflex)
        base = reflex.roman && reflex.roman != reflex.word ? "#{reflex.word} (#{reflex.roman})" : reflex.word
        base = "#{base} (loan)" if reflex.borrowed
        base = "#{base} (uncertain)" if reflex.respond_to?(:uncertain) && reflex.uncertain
        base
      end

      # etym (P14-1; multi-hop P17-3): one block per entry — where the walk
      # entered (matched reflex → *headword), the entry's own reflex list,
      # then the ancestor CHAIN, indented one step per shelf hop (the
      # shelf-visited walk: богъ → *bogъ ← *bogù ← *bʰag-). A loan edge
      # labels its arrow: "←(loan)". --long expands the cognate lists; the
      # chain itself is already bounded (each shelf enters once per walk).
      def print_etym_results(results)
        results.each_with_index do |result, index|
          say "" if index.positive?
          print_etym_entry(result, 0)
        end
        # P18-4: one footer line, the desk-reference pointer — the compact
        # render keeps raw codes, this names the way out.
        say ""
        say "codes: nabu language CODE — name, context, and what this library holds"
      end

      # P24-2: the crosswalk-miss path. When the dictionary shelf holds the
      # lemma (Vasmer's prose etymologies carry no reflex edges), render
      # those entries in the define house format under an honest header —
      # print_define_entry, zero renderer divergence. A genuine total miss
      # enumerates the crosswalk shelves DB-DRIVEN (Query::Etym
      # #crosswalk_shelves — the P11 DEFINE_LANGS hardcoded-list lesson),
      # keeping the '*form' quoting hint.
      def print_etym_fallback(lemma, entries, shelves:)
        if entries.empty?
          covered = shelves.empty? ? "no shelves yet (run nabu sync wiktionary-recon)" : shelves.join(", ")
          return say("no reconstruction names #{lemma} as a descendant, no reconstruction " \
                     "headword matches it, and no dictionary entry defines it — the crosswalk " \
                     "covers #{covered} (nabu language CODE explains any). Try the lemma's " \
                     "dictionary form, or a quoted '*form' for a direct lookup (quote the " \
                     "star — zsh expands a bare *)")
        end

        say "no reconstruction path in the crosswalk for #{lemma} — the dictionary shelf holds:"
        entries.each do |result|
          say ""
          print_define_entry(result)
        end
      end

      def print_etym_entry(result, depth)
        indent = "  " * depth
        arrow = if depth.positive?
                  result.edge_borrowed ? "←(loan) " : "← "
                else
                  ""
                end
        say "#{indent}#{arrow}#{etym_entry_line(result)}  #{result.urn}"
        say "#{indent}  gloss: #{result.gloss}" if result.gloss
        print_reflexes(result.cognates)
        result.ancestors.each do |ancestor|
          say ""
          print_etym_entry(ancestor, depth + 1)
        end
      end

      def etym_entry_line(result)
        via = result.matched_reflex
        prefix =
          if via
            "#{via.word} [#{lect_bracket(via.language, via.lect_id, via.lect_name)}]" \
              "#{' (loan)' if via.borrowed}#{' (uncertain)' if via.uncertain} → "
          else
            ""
          end
        "#{prefix}#{result.headword} [#{lect_bracket(result.language, result.lect_id, result.lect_name)}] — " \
          "#{result.dictionary_title} [#{result.license_class}]"
      end

      # P57-4 (etym display through the mapping): when Nabu::Lects is
      # present AND the resolved id has a registry entry, render "id ·
      # name" instead of the bare stored code — display-only, the raw code
      # is never touched. Absent either condition, the bracket is exactly
      # the raw code, unchanged.
      def lect_bracket(code, lect_id, lect_name)
        lect_id && lect_name ? "#{lect_id} · #{lect_name}" : code
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

      # P90-5 (lane 3): is +term+ a language the desks know — a lect id
      # the registry parses, or a code the names census can name? (The
      # membership test the front door needs; the language command itself
      # renders unknown codes as honest misses, which would swallow every
      # string.)
      def info_language?(config, term, lects)
        return true if lects&.lect(term)

        catalog = open_catalog(config)
        return false unless catalog

        !Nabu::Languages.new(catalog: catalog).name(term).nil?
      ensure
        catalog&.disconnect
      end

      # A script-dossier tag for +term+: the tag itself, or a case-blind
      # script NAME alias (glag / Glagolitic), else nil.
      def info_script_tag(term)
        tag = term.downcase
        return tag if Nabu::ScriptDossiers.lookup(tag)

        Nabu::ScriptDossiers.table.find { |_t, row| row["name"].to_s.casecmp?(term) }&.first
      end

      # P90-5 (lane 2): the script dossier card — the curated context
      # config/script_dossiers.yml holds (published as nabu-data
      # mul/script-dossiers) finally readable from the CLI.
      def print_script_card(tag, lects)
        dossier = Nabu::ScriptDossiers.lookup(tag)
        say "script #{dossier.name} (#{dossier.tag})"
        say_wrapped(dossier.context, indent: 2)
        if dossier.desk
          say "  desk:"
          say_wrapped(dossier.desk, indent: 4)
        end
        row = lects&.script_rows&.dig(dossier.tag)
        if row
          iso = row["iso15924"] ? ", ISO 15924 #{row['iso15924']}" : ""
          say "  registry: minted in the nabu-lects scripts table#{iso}"
        else
          say "  registry: nabu-lects not synced — the scripts-table row is unavailable"
        end
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

      def commas(count)
        count.to_s.gsub(/\B(?=(\d{3})+\z)/, ",")
      end

      # Wrap prose to the card's width, every line indented.
      def say_wrapped(text, indent:, width: 78)
        pad = " " * indent
        line = +""
        text.split(/\s+/).each do |word|
          if line.empty?
            line << word
          elsif pad.length + line.length + 1 + word.length > width
            say "#{pad}#{line}"
            line = +word
          else
            line << " " << word
          end
        end
        say "#{pad}#{line}" unless line.empty?
      end

      # --langs as an array: comma-joined on the CLI, validated by the query.
      def parse_langs(value)
        return nil if value.nil?

        value.split(",").map(&:strip).reject(&:empty?)
      end

      # cognates (P15-3): header with honest totals + the suppression count,
      # then one compact block per (verse, root) hit — the root line carries
      # the SHELF (a gem-pro meet with a Slavic witness reads as a borrowing;
      # see the command help), each witness its lemma and attested forms.
      def print_cognates(result)
        say "#{result.query} — work #{result.work} · shared-root verses across witnesses"
        say "  #{cognates_counts(result)}"
        if result.truncated
          say "  showing first #{result.groups.size} of #{result.total} hits — narrow the " \
              "target, or pass --long to render all"
        end
        result.groups.each { |group| print_cognates_group(group, result.documents) }
      end

      def cognates_counts(result)
        verses = result.groups.map(&:ref).uniq.size
        roots = result.groups.map { |group| group.root.urn }.uniq.size
        counts = if result.total.zero?
                   "no hits — no verse here has two witnesses on one root"
                 else
                   "#{plural(result.total, 'hit')} · #{plural(verses, 'verse')} · " \
                     "#{plural(roots, 'root')}"
                 end
        return counts if result.suppressed.zero?

        "#{counts}; #{result.suppressed} common-word #{result.suppressed == 1 ? 'hit' : 'hits'} " \
          "suppressed (--all shows them)"
      end

      def print_cognates_group(group, documents)
        say ""
        say "#{group.ref}  #{group.root.headword} [#{group.root.shelf} · #{group.root.license_class}]"
        if options[:long]
          say "    #{group.root.dictionary_title}#{" · gloss: #{group.root.gloss}" if group.root.gloss}"
        end
        group.witnesses.each do |witness|
          loan = witness.borrowed ? " (loan)" : ""
          say "    #{witness.language.ljust(4)} #{display_text(witness.lemma, witness.language)}" \
              "#{loan}#{cognates_surfaces(witness)}"
          next unless options[:long]

          witness.document_urns.each do |urn|
            doc = documents[urn]
            say "         #{urn}#{" — #{doc[:title]} [#{doc[:license_class]}]" if doc}"
          end
        end
      end

      # The attested forms, shown when they add anything over the lemma.
      def cognates_surfaces(witness)
        forms = witness.surfaces - [witness.lemma]
        return "" if forms.empty?

        " — attested as #{forms.map { |form| display_text(form, witness.language) }.join(', ')}"
      end

      # Compact default (house compact-CLI rule, the print_reflexes
      # precedent's inline-cap shape): TLS attestation citations (P34-4)
      # put thousands of resolved rows on common words (之 carries 2,587
      # attestations), so the first 12 print inline and the tail is
      # summarised; --long expands every one. LSJ/MW-scale entries sit
      # under the cap and never see it.
      def print_resolved_citations(result)
        resolved = result.citations.select(&:resolved_urn)
        return if resolved.empty?

        say ""
        say "resolved citations (in this corpus — nabu show <urn>):"
        shown = options[:long] ? resolved : resolved.first(12)
        shown.each { |citation| say "  #{citation.label} → #{citation.resolved_urn}" }
        rest = resolved.size - shown.size
        say "  … and #{rest} more (--long shows all)" if rest.positive?
      end

      # A print-free runner needs a sink for live progress; the CLI owns all
      # formatting and tty decisions here. Progress goes to $stderr (final counts
      # go to $stdout via `say`, so scripts piping stdout are unaffected). When
      # $stderr is a tty: git output streams raw (its own \r overwrites the line)
      # and a \r-updating "loading…" counter refreshes each tick. Non-tty: no git
      # streaming (callbacks stay nil) and one plain line per 100 documents.
      def progress_reporter
        tty = $stderr.tty?
        state = { stage: nil, started: nil, processed: 0, errored: 0, last: 0 }
        @progress_state = state
        Nabu::ProgressReporter.new(
          on_fetch_line: tty ? ->(line) { $stderr.print(line) } : nil,
          on_load_tick: load_tick(tty, state),
          on_stage: stage_tick(tty, state),
          on_note: progress_note(state),
          on_explain: verbose_narrator
        )
      end

      # --verbose (Ops::StageGuide): ONE narrator per invocation, so each
      # stage explains once however many reporters the command builds
      # (an axis sync builds one per member). Green on stderr beside the
      # stage lines; nil when not verbose, so the reporter's explain seam
      # is a no-op. +before+ closes an open \r stage line first.
      def verbose_narrator
        return nil unless options[:verbose]

        @verbose_narrator ||= Nabu::Ops::StageGuide::Narrator.new(
          io: $stderr, sources: verbose_source_slugs,
          before: -> { close_stage(@progress_state) if @progress_state }
        )
      end

      # The command's intro (what the run is about to do to the library),
      # printed before any work when --verbose is on.
      def explain_command(key)
        verbose_narrator&.intro(key)
      end

      # The registered slugs, so a bare-slug replay stage resolves to the
      # source-replay explanation.
      def verbose_source_slugs
        Nabu::SourceRegistry.load(Nabu::Config.load.sources_path).each_source.map(&:slug)
      rescue Nabu::Error
        []
      end

      # A durable header/tally line (owner UX rule 2026-10-07 — the
      # incremental verdict sweep's ETA header and closing tally): closes
      # any open stage first, then prints on tty and non-tty alike.
      def progress_note(state)
        lambda do |line|
          close_stage(state)
          $stderr.tty? ? $stderr.print("\r\e[K  #{line}\n") : warn("  #{line}")
        end
      end

      # Owner feedback (2026-07-18): a long rebuild must name the source it
      # is on and how long each stage took. A stage closes when the next one
      # opens (or at finish_progress), its line ending in final counts +
      # elapsed; sync paths never call stage, so they keep the bare counter.
      # +eta+ (P78-r2): when the runner consulted the stage_timings
      # history, the open line SPEAKS the estimate — including the honest
      # "first run — no estimate" — and non-tty (the caffeinate/drill logs,
      # where every owner-perceived "hang" of P77 was read) gets the open
      # line too, so the log names what is running BEFORE it finishes.
      def stage_tick(tty, state)
        lambda do |label, eta = nil|
          close_stage(state)
          state[:stage] = label
          state[:eta] = eta
          state[:started] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          state[:processed] = state[:errored] = state[:last] = 0
          suffix = eta ? "#{eta.render} " : ""
          if tty
            $stderr.print("\r\e[K  #{label}… #{suffix}")
          elsif eta&.real?
            # Non-tty prints the open line only when there is a REAL
            # estimate to speak (P78-r3: "first run — no estimate" on
            # every tiny shelf sync is noise in a log; the close line
            # with counts + elapsed is the record either way).
            warn("  #{label}… #{suffix}")
          end
        end
      end

      def close_stage(state)
        return if state[:stage].nil?

        line = "  #{state[:stage]}… #{stage_counts(state)}#{format_elapsed(state)}"
        $stderr.tty? ? $stderr.print("\r\e[K#{line}\n") : warn(line)
        state[:stage] = nil
      end

      # Zero docs is a timeline/facet/index stage, not an empty shelf — show
      # only the timing (compact-output convention: suppress zero fields).
      def stage_counts(state)
        return "" if state[:processed].zero? && state[:errored].zero?

        "#{state[:processed]} docs#{quarantine_suffix(state[:errored])} "
      end

      def format_elapsed(state)
        format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:started])
      end

      def load_tick(tty, state)
        lambda do |processed, errored|
          state[:processed] = processed
          state[:errored] = errored
          label = state[:stage] || "loading"
          left = time_left_suffix(state, processed)
          if tty
            $stderr.print("\r\e[K  #{label}… #{processed} docs#{quarantine_suffix(errored)}#{left}  ")
          elsif processed - state[:last] >= (state[:stage] ? 1000 : 100)
            state[:last] = processed
            warn("  #{label}… #{processed} docs#{quarantine_suffix(errored)}#{left}")
          end
        end
      end

      # P78-r2: the in-stage extrapolation — once ticks flow and the last
      # run recorded a row count, the observed rate projects the remainder
      # (" ~3m left"). Guarded: enough ticks and elapsed time to trust the
      # rate, and only while the recorded total still lies ahead (past it,
      # the estimate would be a lie — drift means more rows this run).
      def time_left_suffix(state, processed)
        basis = state[:eta].respond_to?(:basis_rows) ? state[:eta].basis_rows : nil
        return "" unless basis&.positive? && processed >= 100 && processed < basis

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:started]
        return "" if elapsed < 5

        " ~#{Nabu::Eta.format_seconds(elapsed / processed * (basis - processed))} left"
      end

      def quarantine_suffix(errored)
        errored.positive? ? " (#{errored} quarantined)" : ""
      end

      # Break off the \r-updated counter line before the final counts —
      # closing the open stage (with its timing) when there is one.
      def finish_progress
        if @progress_state && @progress_state[:stage]
          close_stage(@progress_state)
        elsif $stderr.tty?
          $stderr.print("\n")
        end
      end

      # P42-4: the one honest planner-hygiene line — printed only when a bulk
      # load or a rebuild actually refreshed the query-planner statistics,
      # silent otherwise (a sub-threshold sync, a clean-swept incremental run).
      def print_analyzed(analyzed)
        return unless analyzed

        say "  analyzed #{analyzed.scope} (planner stats refreshed, #{format('%.1f', analyzed.seconds)}s)"
      end

      # P39-4: the within-pass collision tail — silent at zero (house
      # compact-zero rule; collisions are pathological), loud when one bit.
      def format_collided(report)
        report.collided.positive? ? "  !#{report.collided} collision" : ""
      end

      # rebuild --incremental (P36-1): dirty sources re-derive through the
      # rebuild replay seam + per-source index refresh; clean ones are
      # skipped on their derivation stamp. Refusals (schema drift, orphan
      # rows, no catalog) are loud exit-1 errors — full rebuild required.
      # --parse-workers wins over the rebuild.parse_workers setting; nil
      # (neither given) lets Rebuild take the pool default.
      def rebuild_parse_workers(config)
        workers = options[:parse_workers]
        return config.parse_workers if workers.nil?
        raise Thor::Error, "--parse-workers must be at least 1 (got #{workers})" unless workers.to_i >= 1

        workers.to_i
      end

      def rebuild_incremental(config, registry, parse_workers)
        if options[:trust_derivations] && !Nabu::CodeVoucher.new.able?
          say "WARNING: --trust-derivations is INERT — the adapters tree has uncommitted " \
              "changes, so git cannot vouch for any source and every drift will REPLAY " \
              "(hours, not minutes). Commit or stash first, then re-run.", :yellow
        end
        incremental = Nabu::IncrementalRebuild.new(config: config, registry: registry,
                                                   trust_stages: options[:trust_stages],
                                                   trust_derivations: options[:trust_derivations],
                                                   full_links: options[:full_links],
                                                   parse_workers: parse_workers)
        if options[:dry_run]
          plan = incremental.plan(progress: progress_reporter)
          finish_progress
          return print_incremental_plan(plan)
        end

        explain_command(:rebuild_incremental)
        result = incremental.run(progress: progress_reporter)
        finish_progress
        print_incremental_result(result)
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      end

      # --dry-run --incremental: the owner's planning view — one clean/dirty
      # verdict per source, nothing touched.
      def print_incremental_plan(plan)
        say "Dry run — nothing will change."
        raise Thor::Error, "cannot rebuild incrementally: #{plan.refusal}" if plan.refusal

        say "Incremental rebuild against #{plan.db_path}:"
        say "  BUILDERS dirty — timeline/facets re-run (builder code changed)" if plan.builders_dirty
        say "  INDEX dirty — full fulltext re-derivation (index code changed)" if plan.index_dirty
        plan.verdicts.each do |verdict|
          case verdict.state
          in :clean then say "  clean   #{verdict.slug} (stamp #{verdict.stamp_short})"
          in :dirty then say "  dirty   #{verdict.slug} (#{verdict.reason})"
          in :skip then say "  skip    #{verdict.slug} (no canonical data)"
          end
        end
      end

      def print_incremental_result(result)
        say "Incremental rebuild against #{result.db_path}:"
        result.cleans.each { |clean| say "  #{clean.slug} clean (stamp #{clean.stamp_short})" }
        result.trusted.each { |item| say "  #{item.slug} trusted (re-stamped #{item.stamp_short} — no replay)" }
        result.outcomes.each { |outcome| say "  #{format_report(outcome.slug, outcome.report)}" }
        result.skips.each { |skip| say "  skip    #{skip.slug} (no canonical data — never synced)" }
        result.warnings.each do |outcome|
          say "  WARNING: #{outcome.slug} #{outcome.quarantine.message}", :yellow
        end
        summary = "  re-derived #{result.outcomes.size}, clean #{result.cleans.size}, " \
                  "skipped #{result.skips.size}"
        summary += ", trusted #{result.trusted.size}" if result.trusted.any?
        say summary
        say "  indexed #{result.indexed} passages" if result.indexed
        print_links_stage(result.links)
        result.link_failures.each do |failure|
          say "  WARNING: links re-mine failed for #{failure} — the links db has this gap", :yellow
        end
        print_analyzed(result.analyzed)
      end

      # The links stage's verdict line (LinkStamps::Outcome#summary); a
      # self-check drift is an incident — red, never folded into the line.
      def print_links_stage(links)
        return if links.nil?

        say "  #{links.summary}", links.drift.empty? ? nil : :red
        links.drift.each do |line|
          say "  LINKS DRIFT: #{line} — a stamp lied; the fresh mine is kept", :red
        end
      end

      # --dry-run: report the plan, touch nothing.
      def print_plan(plan)
        say "Dry run — nothing will change."
        say "Would drop catalog db: #{plan.db_path} (#{plan.db_exists ? 'exists' : 'absent'})"
        plan.items.each do |slug, action|
          say(action == :replay ? "  replay  #{slug}" : "  skip    #{slug} (no canonical data)")
        end
      end

      # Real run: per-source counts, skips, warnings, then a grand total.
      def print_result(result)
        existed = result.db_existed ? "" : " (did not exist)"
        say "Dropped catalog db: #{result.db_path}#{existed}"
        result.outcomes.each { |outcome| say "  #{format_report(outcome.slug, outcome.report)}" }
        result.skips.each { |skip| say "  skip    #{skip.slug} (no canonical data — never synced)" }
        # DELTA-aware (P18-7): silence when a source's errored count matches its
        # recorded ledger baseline; a change (or first recording) speaks.
        result.warnings.each do |outcome|
          say "  WARNING: #{outcome.slug} #{outcome.quarantine.message}", :yellow
        end
        say "  #{format_report('TOTAL', total_report(result))}"
        say "  indexed #{result.indexed} passages"
        if result.axes
          say "  dated/placed #{result.axes.total} documents " \
              "(hgv #{result.axes.hgv}, goo300k #{result.axes.goo300k}, imp #{result.axes.imp}, " \
              "oracc #{result.axes.oracc}, torot #{result.axes.torot}, coptic #{result.axes.coptic}, " \
              "edh #{result.axes.edh}, damaskini #{result.axes.damaskini}, corph #{result.axes.corph}, " \
              "riig #{result.axes.riig}, tla-hf #{result.axes.tla_hf}, aes #{result.axes.aes}, " \
              "ceipom #{result.axes.ceipom}, " \
              "isicily #{result.axes.isicily}, " \
              "open-etruscan #{result.axes.open_etruscan}, " \
              "lexlep #{result.axes.lexlep}, tir #{result.axes.tir}, " \
              "iip #{result.axes.iip}, cdli #{result.axes.cdli}, " \
              "rundata #{result.axes.rundata}, openiti #{result.axes.openiti})"
        end
        print_links_stage(result.links)
        result.link_failures.each do |failure|
          say "  WARNING: links re-mine failed for #{failure} — the links db has this gap", :yellow
        end
        print_analyzed(result.analyzed)
        return unless result.facets&.rows&.positive? # zero-signal silence (compact rule)

        say "  facets #{result.facets.rows} rows across #{result.facets.documents} documents"
      end

      # The P36-0 profile table: every source's load and every corpus stage,
      # heaviest first with its share of the grand total, then a stage-share
      # summary (parse/insert inside load; corpus index total) — the numbers
      # that tier P36-2 (bulk load) vs P36-3 (parallel parse). Print-only:
      # the profile is in-memory observability, never persisted, so `nabu
      # rebuild` regenerates it wholesale every run.
      def print_profile(profile)
        return if profile.nil? || profile.empty?

        width = [profile.rows.map { |label, _, _| label.to_s.length }.max || 0, 18].max
        say ""
        say "Rebuild profile — wall time by stage (heaviest first):"
        profile.rows.each do |label, secs, share|
          say format("  %-#{width}s  %10s  %5.1f%%", label, format_duration(secs), share * 100)
        end
        say "  #{'-' * (width + 20)}"
        say format("  %-#{width}s  %10s   (of load)", "parse (+fold)", format_duration(profile.parse_total))
        say format("  %-#{width}s  %10s   (of load)", "insert", format_duration(profile.insert_total))
        say format("  %-#{width}s  %10s", "load total", format_duration(profile.load_total))
        say format("  %-#{width}s  %10s", "corpus index total", format_duration(profile.index_total))
        say format("  %-#{width}s  %10s", "GRAND TOTAL", format_duration(profile.grand_total))
        say "  note: fts+lemma is one fused pass; parse/insert are per-document samples inside load."
        say "  note: text-normalization/fold (search_form) runs at Passage build, so it is inside parse."
      end

      def format_report(label, report)
        "#{label.ljust(24)} +#{report.added} added  ~#{report.updated} updated  " \
          "=#{report.skipped} skipped  -#{report.withdrawn} withdrawn  !#{report.errored} errored" \
          "#{format_collided(report)}"
      end

      def total_report(result)
        reports = result.outcomes.map(&:report)
        Nabu::Store::LoadReport.new(
          added: reports.sum(&:added), updated: reports.sum(&:updated),
          skipped: reports.sum(&:skipped), withdrawn: reports.sum(&:withdrawn),
          errored: reports.sum(&:errored), skipped_by_rule: reports.sum(&:skipped_by_rule),
          collided: reports.sum(&:collided)
        )
      end

      # --remote (P5-3): the no-clone upstream probe. Pins + baselines live in
      # the history ledger (P7-1), which the probe writes (baseline recording),
      # so this is a write path: create + migrate + lift. Its own exit-1 raise.
      def run_remote_health
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        catalog = open_catalog(config)
        view = focus_view(config, registry, catalog: catalog)
        catalog&.disconnect
        warn_focus_drift(view)
        ledger = open_or_create_ledger(config)
        report = Nabu::Health::RemoteProbe.new(
          registry: view.registry, ledger: ledger, canonical_dir: config.canonical_dir
        ).run(progress: remote_health_ticker)
        $stderr.print("\r\e[K") if $stderr.tty? # clear the ticker before the table
        print_remote_health(report)
        print_focus_note(view, view.registry_hidden_slugs)
        # A gone upstream is the only red finding; the table is already on stdout,
        # so raise for the exit-1 signal (Thor prints the summary to stderr).
        raise Thor::Error, remote_health_failure(report) if report.any_gone?
      ensure
        ledger&.disconnect
      end

      # The transient probe ticker (P31 rider — the same owner ask as the
      # P28-5 rebuild progress): on a TTY, one stderr line naming the source
      # currently on the wire, overwritten in place and cleared before the
      # table prints. Non-TTY prints nothing — the table already lists every
      # source, and pipes stay clean (compact-output convention).
      def remote_health_ticker
        return nil unless $stderr.tty?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        lambda do |slug, index, total|
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          suffix = elapsed >= 1 ? format(" %ds", elapsed) : ""
          $stderr.print("\r\e[K  probing #{index}/#{total} #{slug}…#{suffix}")
        end
      end

      # --backfill-pins (P15-7): record ledger pins for sources synced before
      # the pins ledger existed (P7) — the ones that read "unpinned". No
      # network, read-only on canonical/ (a local git rev-parse / state-file
      # read); writes ONLY the ledger pins, idempotently. A write path, so the
      # ledger is opened + migrated + lifted like the remote probe's.
      def run_backfill_pins
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        ledger = open_or_create_ledger(config)
        recorded = Nabu::Health::RemoteProbe.new(
          registry: registry, ledger: ledger, canonical_dir: config.canonical_dir
        ).backfill_pins
        print_backfill(recorded)
      ensure
        ledger&.disconnect
      end

      def print_backfill(recorded)
        if recorded.empty?
          return say("backfill-pins: nothing to backfill — every synced source already carries its ledger pin.")
        end

        width = recorded.map { |row| row.slug.length }.max
        recorded.each do |row|
          say "#{row.slug.ljust(width)}  pinned #{row.sha[0, 12]}  (#{backfill_origin(row.origin)})"
        end
        say "backfill-pins: recorded #{pluralize(recorded.size, 'pin')} " \
            "(ledger only; canonical/ untouched, no network)."
      end

      def backfill_origin(origin)
        origin == :git_clone ? "backfilled-from-local-clone" : "backfilled-from-state-file"
      end

      # --accept-creep (P43-0, D42-c): the owner reviewed a quarantine-creep
      # anomaly and accepts the source's CURRENT baseline. Durable by design —
      # the acceptance lives in the history ledger (migration 008), so a
      # rebuild never un-quiets a ruled-on alarm. A write path: create +
      # migrate + lift, its own ledger lifetime. The active-anomaly probe runs
      # BEFORE the acceptance lands (recording first would quiet the very
      # finding the honesty line reports on).
      def run_accept_creep(slug)
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        if registry[slug].nil?
          raise Thor::Error, "accept-creep: unknown source '#{slug}' — not in #{config.sources_path}"
        end

        ledger = open_or_create_ledger(config)
        active = Nabu::Health::QuarantineBaseline.creep_finding(ledger, slug, path: config.creep_acceptances_path)
        accepted = Nabu::Health::QuarantineBaseline.accept!(ledger, slug, note: options[:note],
                                                                          path: config.creep_acceptances_path)
        if accepted.nil?
          raise Thor::Error, "accept-creep: no quarantine baseline recorded for '#{slug}' — nothing to accept " \
                             "(a baseline is recorded at the source's first ok sync or rebuild)"
        end
        say "accepted quarantine baseline #{accepted} for #{slug} — the creep alarm re-arms past #{accepted}"
        # Pre-accepting (no live anomaly, or one an earlier acceptance already
        # quiets to the info note) is allowed but never passes silently.
        say "(no active creep anomaly for #{slug} — recorded as a pre-acceptance)" if active.nil? || !anomaly?(active)
      ensure
        ledger&.disconnect
      end

      # --accept-shed (P102-1): the owner reviewed a withdrawal-creep
      # anomaly (a one-time upstream curation event) and accepts the source's
      # CURRENT shed count. Durable in local/config/shed_acceptances.yml (the
      # P70 posture — config only; shed is measured live from the catalog).
      # The active-anomaly probe runs BEFORE the acceptance lands.
      def run_accept_shed(slug)
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        if registry[slug].nil?
          raise Thor::Error, "accept-shed: unknown source '#{slug}' — not in #{config.sources_path}"
        end

        catalog = open_catalog(config)
        raise Thor::Error, "accept-shed: no catalog — nothing to measure" if catalog.nil?

        source = Nabu::Store::Source.first(slug: slug)
        raise Thor::Error, "accept-shed: '#{slug}' has no documents in this catalog — nothing to accept" if source.nil?

        shed = Nabu::Store::Document.where(source_id: source.id)
                                    .where(Sequel.|({ withdrawn: true }, { retired_upstream: true }))
                                    .count
        total = Nabu::Store::Document.where(source_id: source.id).count
        active = Nabu::Health::ShedAcceptance.finding(
          plain: Nabu::Health::TrendRules.withdrawal_creep(shed: shed, total: total),
          acceptance: Nabu::Health::ShedAcceptance.latest(config.shed_acceptances_path, slug),
          shed: shed
        )
        Nabu::Health::ShedAcceptance.accept!(path: config.shed_acceptances_path, slug: slug,
                                             shed: shed, note: options[:note])
        say "accepted withdrawal shed #{shed}/#{total} for #{slug} — the creep alarm re-arms past #{shed}"
        say "(no active shed anomaly for #{slug} — recorded as a pre-acceptance)" if active.nil? || !anomaly?(active)
      ensure
        catalog&.disconnect
      end

      # A finding that affects (or warns toward) the exit code — as opposed to
      # an info-grade note like an already-quieted creep.
      def anomaly?(finding)
        finding.loud? || finding.soft?
      end

      # Bare health (P5-5): run-history trends + live golden replay, no network.
      # open_catalog binds the Store models the LocalCheck queries; open_ledger
      # binds the run history (absent ledger = empty history, honestly). Exit 1
      # on any loud finding (quarantine spike, >15% creep, a lost golden query);
      # soft warnings (collapse, 5–15% creep, stale) stay exit 0.
      def run_local_health
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        catalog = open_catalog(config)
        view = focus_view(config, registry, catalog: catalog)
        warn_focus_drift(view)
        fulltext = catalog ? open_fulltext(config) : nil
        ledger = open_ledger(config)
        report = Nabu::Health::LocalCheck.new(
          registry: view.registry, catalog: catalog, fulltext: fulltext, ledger: ledger,
          golden_queries: Nabu::Health::LocalCheck.golden_queries,
          canonical_dir: config.canonical_dir,
          creep_acceptances_path: config.creep_acceptances_path,
          shed_acceptances_path: config.shed_acceptances_path,
          workdir_resolver: config.method(:source_workdir),
          place_ref_errata_path: File.join(config.config_dir, "place_ref_errata.yml"),
          lects: Nabu::Lects.load_default(config: config),
          links_journal_path: config.links_path
        ).run
        seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        print_local_health(report, all: options[:all], seconds: seconds)
        print_focus_note(view, view.registry_hidden_slugs)
        # The ONE loud summary (P98-1): the quiet path said its
        # verdict inside print_local_health; the loud path raises it instead,
        # so exactly one summary line prints either way.
        raise Thor::Error, Nabu::Health::BoardView.verdict(report, seconds: seconds) if report.any_loud?
      ensure
        catalog&.disconnect
        fulltext&.disconnect
        ledger&.disconnect
      end

      # Per-source trend rows (BoardView-filtered; --all = full board), then
      # the golden-replay section, then the single verdict (quiet path only —
      # the loud verdict rides the Thor::Error) and the probe hint.
      def print_local_health(report, all:, seconds:)
        print_source_health(report.sources, all: all)
        # Library-wide invariant findings (P18-7: pending migrations) — printed
        # only when present, so a green library shows nothing new here.
        report.global.each { |finding| say "#{finding_tag(finding)} #{finding.message}" }
        print_golden_health(report)
        say Nabu::Health::BoardView.verdict(report, seconds: seconds) unless report.any_loud?
        say "Hint: run `nabu health --remote` for the no-clone upstream probe."
      end

      def print_source_health(sources, all:)
        return say("No sources registered.") if sources.empty?

        width = sources.map { |source| source.slug.length }.max
        Nabu::Health::BoardView.visible(sources, all: all).each { |source| print_source_row(source, width) }
        say Nabu::Health::BoardView.rollup(sources) unless all
      end

      # A healthy source is one "ok" line; a flagged one repeats its slug column
      # blank for continuation findings so multi-finding sources stay aligned.
      def print_source_row(source, width)
        return say("#{source.slug.ljust(width)}  ok") if source.findings.empty?

        source.findings.each_with_index do |finding, index|
          label = index.zero? ? source.slug.ljust(width) : " " * width
          say "#{label}  #{finding_tag(finding)} #{finding.message}"
        end
      end

      def finding_tag(finding)
        { loud: "ANOMALY", soft: "warning", info: "note" }.fetch(finding.severity)
      end

      def print_golden_health(report)
        case report.corpus
        when :absent
          return say("golden replay: no corpus — run nabu sync or nabu rebuild")
        when :no_index
          return say("golden replay: no fulltext index — run nabu sync or nabu rebuild")
        end

        lost = report.golden.select(&:lost?)
        lost.each { |result| say "golden query lost: #{result.query}  (expected #{result.expect_urn})" }
        found = report.golden.count { |result| result.status == :found }
        skipped = report.golden.count { |result| result.status == :skipped }
        say "golden replay: #{found} found, #{lost.size} lost, #{skipped} skipped (source not in this corpus)"
      end

      # Render the remote probe: one aligned row per source (slug, liveness,
      # drift, license) plus any trailing detail, then a one-line summary.
      def print_remote_health(report)
        rows = report.rows
        return say("No sources registered.") if rows.empty?

        slug_w = rows.map { |row| row.slug.length }.max
        live_w = rows.map { |row| live_cell(row.liveness).length }.max
        drift_w = rows.map { |row| drift_cell(row.drift).length }.max
        rows.each do |row|
          line = "#{row.slug.ljust(slug_w)}  #{live_cell(row.liveness).ljust(live_w)}  " \
                 "#{drift_cell(row.drift).ljust(drift_w)}  #{license_cell(row.license)}#{health_detail(row)}"
          say line.rstrip
        end
        say remote_health_summary(report)
      end

      def live_cell(liveness)
        { alive: "alive", moved: "MOVED", gone: "GONE" }.fetch(liveness.status)
      end

      def drift_cell(drift)
        { current: "current", behind: "behind", unpinned: "unpinned",
          never_synced: "never-synced", unknown: "—", multi: "multi-repo",
          frozen: "frozen", local: "local" }.fetch(drift)
      end

      # :unchecked renders as NOTHING — "license: unchecked" reads like a
      # problem when it only means "no machine-checkable license artifact
      # upstream" (non-github, or a repo without a top-level license file).
      # The verdict still lands in the ledger; the row just doesn't speak
      # (owner rule, conventions §10: suppress zero-signal fields).
      def license_cell(license)
        { baseline_recorded: "license: baseline recorded", unchanged: "license: ok",
          changed: "license: CHANGED", unchecked: "" }.fetch(license.status)
      end

      # Trailing context: why an upstream is not alive, or why a license row is
      # flagged. Kept off the aligned columns so the table stays readable.
      def health_detail(row)
        bits = []
        bits << row.liveness.detail if row.liveness.detail && row.liveness.status != :alive
        bits << row.drift_detail if row.drift_detail && %i[behind unpinned].include?(row.drift)
        bits << row.license.detail if row.license.status == :changed
        bits.empty? ? "" : "   #{bits.join(' · ')}"
      end

      def remote_health_summary(report)
        rows = report.rows
        counts = { alive: 0, moved: 0, gone: 0 }
        rows.each { |row| counts[row.liveness.status] += 1 }
        behind = rows.count { |row| row.drift == :behind }
        parts = [pluralize(rows.size, "source"), "#{counts[:alive]} alive"]
        parts << "#{counts[:moved]} moved" if counts[:moved].positive?
        parts << "#{counts[:gone]} gone" if counts[:gone].positive?
        parts << "#{behind} behind" if behind.positive?
        parts.join(", ")
      end

      def remote_health_failure(report)
        gone = report.rows.count { |row| row.liveness.status == :gone }
        "health: #{pluralize(gone, 'upstream')} gone — see the table above"
      end

      # -- mcp entrypoint plumbing (P8-2) ----------------------------------

      # The enabled-slug set nabu_status defaults to (P44-r3b). READ-ONLY: unlike
      # the CLI's effective_profile, the MCP server never WRITES a migration
      # (serving is not the moment to touch config). It mirrors the same three
      # cases in memory: a present config governs; an absent config on a built
      # box uses the catalog's synced sources (no visibility loss); a fresh box
      # falls to the quickstart default. nil is never returned — an explicit set
      # (possibly empty) so the tool filters honestly.
      def mcp_enabled_slugs(config, registry)
        if Nabu::Profile.exist?(config.profile_path)
          return Nabu::Focus.resolve(Nabu::Profile.load(config.profile_path), registry).slugs
        end

        present = mcp_catalog_slugs(config) & registry.slugs
        present.empty? ? Nabu::Profile.default_entries(registry) : present
      end

      # The catalog's source slugs, read-only, for the MCP enablement fallback —
      # [] when there is no catalog yet.
      def mcp_catalog_slugs(config)
        return [] unless File.exist?(config.catalog_path)

        db = Nabu::Store.connect(config.catalog_path, readonly: true)
        db.table_exists?(:sources) ? db[:sources].select_map(:slug) : []
      ensure
        db&.disconnect
      end

      # The diagnostics sink for `nabu mcp`: stderr by default, or a file opened
      # for append (line-buffered) when --log FILE is given. NEVER stdout —
      # stdout is the JSON-RPC protocol channel.
      def mcp_log(path)
        return $stderr if path.to_s.strip.empty?

        # No block form: the log must stay open for the whole server lifetime;
        # `mcp` closes it in its ensure.
        file = File.open(path, "a") # rubocop:disable Style/FileOpen
        file.sync = true
        file
      end

      # SIGINT/SIGTERM → clean shutdown with EOF semantics: exit 0, unwinding the
      # command's ensure (which closes the log). A client that stops the server
      # by closing our stdin gets the same path via the run loop reaching EOF.
      def install_mcp_signal_traps
        %w[INT TERM].each { |signal| trap(signal) { exit(0) } }
      end

      # Open the catalog db for reading if it has been built; nil otherwise so
      # status degrades gracefully to registry-only output.
      def open_catalog(config)
        return nil unless File.exist?(config.catalog_path)

        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.setup!(db)
        db
      end

      # Open the catalog for writing, creating + migrating it if this is the
      # first sync before any rebuild. Migrations are idempotent (only pending
      # ones run), so this is safe on an existing db too. Callers that also
      # open the ledger MUST open it first (open_or_create_ledger lifts a
      # pre-P7-1 catalog's history before migration 005 drops those tables).
      def open_or_create_catalog(config)
        require "fileutils"
        FileUtils.mkdir_p(File.dirname(config.catalog_path))
        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.migrate!(db)
        Nabu::Store.setup!(db)
        db
      end

      # Open the history ledger for reading; nil when absent (fresh machine —
      # read paths treat that as empty history) or not yet migrated.
      def open_ledger(config)
        return nil unless File.exist?(config.history_path)

        db = Nabu::Store::Ledger.connect(config.history_path)
        return Nabu::Store::Ledger.setup!(db) if db.table_exists?(:runs)

        db.disconnect
        nil
      end

      # Open the history ledger for writing: create + migrate it, and lift a
      # pre-P7-1 catalog's runs/pins/baselines into it (one-shot; the catalog
      # is then migrated forward, dropping the moved tables).
      def open_or_create_ledger(config)
        Nabu::Store::Ledger.open_with_lift!(
          history_path: config.history_path, catalog_path: config.catalog_path
        )
      end
    end
  end
end

# The CLI command areas (pure carve-outs of the one CLI class above).
require_relative "cli/sync"
require_relative "cli/census"
