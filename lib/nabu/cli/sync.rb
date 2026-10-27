# frozen_string_literal: true

# Nabu::CLI — acquisition commands: sync, quickstart, ingest. Carved out of
# lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    desc "sync [SOURCE...]", "Fetch and load sources, an axis's members, or --all live sources"
    long_desc <<~HELP, wrap: false
      Fetch and load into the store. The positional NAME resolves GROUP
      FIRST (the registry's closed group vocabulary — `core`: the registry
      instruments, also swept by quickstart; `signs`: every shelf the
      sign/char capability reads, so `nabu enable signs && nabu sync signs`
      restores the whole capability on a fresh box), then EXACT SLUG, then
      axis: a source slug syncs that one source (the explicit request — a
      disabled source syncs anyway, with a note); a name that is
      not a slug but IS a research axis (config/axes.yml) expands to the
      axis's members. Axis names can never equal source slugs (a load-time
      guarantee), so the resolution is unambiguous.

      Axis expansion is PURE fan-out onto the per-source path: each member
      syncs exactly as `sync <slug>` would, per-source report lines
      byte-unchanged, under a one-line axis header. The asymmetry to know:
      an axis expansion is NOT an explicit per-source request, so DISABLED
      members are SKIPPED — reported by name on one `skipped (unwired): …`
      line, never silently — whereas `sync <disabled-slug>` (explicit) still
      syncs. `--axis a,b` selects several axes and prints one group each, in
      order. `--all` is a flat batch (enabled + live sources), never grouped.

      PREREQUISITES ride first (P77 riders, owner rulings 2026-08-13):
      core is the minimum set a new install carries — on the box's first
      real sync request, any never-synced core member (the registry
      instruments) syncs automatically before the requested work. The
      same sweep covers the requested source's `requires:` chain (the
      package-manager rule: sources.yml declares hard functional
      dependencies — nabu-places needs its three gazetteers — and
      syncing a dependent syncs its never-synced requirements first;
      `nabu status <slug>` shows requires/needed-by). --parse-only never
      triggers either; `nabu sync core` (or the member by name) re-runs
      a sweep explicitly.

      Several names run as an explicit batch (P90-3): each argument
      resolves exactly as a lone one would, in argument order, each with
      its own report block; one member's failure is contained (later
      members still run) and the batch exits non-zero at the end naming
      the failures. --parse-only/--force apply to every member;
      --all/--axis refuse combination with an explicit list.

      Examples:
        nabu sync sblgnt          # one source (explicit; disabled syncs anyway)
        nabu sync sblgnt proiel iswoc --parse-only   # an explicit batch, in order
        nabu sync celtic          # the celtic axis's enabled members
        nabu sync --axis celtic,italic --parse-only
        nabu sync --all
    HELP
    option :all, type: :boolean, default: false,
                 desc: "Sync every enabled kind: source with sync_policy: auto"
    option :axis, type: :string, banner: "NAME[,NAME...]",
                  desc: "Sync the enabled members of one or more research axes (config/axes.yml), " \
                        "grouped; disabled members are skipped by name (an axis is not an explicit request)"
    option :parse_only, type: :boolean, default: false,
                        desc: "Skip fetch; re-parse the snapshot already on disk"
    option :fetch_only, type: :boolean, default: false,
                        desc: "Fetch into canonical (breaker + bookkeeping), then stop; " \
                              "parse/load/index deferred to a later sync or rebuild"
    option :force, type: :boolean, default: false,
                   desc: "Override the >20% withdrawal circuit breaker"
    option :redownload, type: :boolean, default: false,
                        desc: "Wipe the source's canonical snapshot (attic preserved) and re-acquire " \
                              "from scratch, regardless of any resumable/partial state"
    option :grant_acknowledged, type: :boolean, default: false,
                                desc: "Acknowledge a grant-required source's terms non-interactively " \
                                      "(scripted use); records the acknowledgment, then syncs. Single-source only."
    option :review, type: :string, banner: "CMD",
                    desc: "Pipe a JSON sync brief to CMD's stdin at sync end (advisory; " \
                          "the hook's exit status is reported, never fails the sync). " \
                          "Example: --review script/review-sync-claude. Single-source sync only."
    option :verbose, type: :boolean, default: false, desc: Nabu::Ops::StageGuide::OPTION_DESC
    def sync(*slugs)
      # --redownload refusals up front (P44-i1): contradictory with
      # --parse-only (nothing to re-download if we skip fetch), and
      # per-source by design (a wipe is an explicit, named decision).
      raise Thor::Error, "sync: --fetch-only contradicts --parse-only" if options[:fetch_only] && options[:parse_only]

      if options[:redownload]
        raise Thor::Error, "sync: --redownload contradicts --parse-only" if options[:parse_only]
        raise Thor::Error, "sync: --redownload is per-source — name one slug" if options[:all] || options[:axis]
      end
      # P90-3 (lane 1): an explicit multi-slug list is its own batch
      # shape — the selector flags name a DIFFERENT batch, so combining is
      # ambiguous intent and refuses loudly. The per-source flags
      # (--parse-only/--force/--redownload) apply to every member; the
      # single-source-only flags keep their contract.
      if slugs.size > 1
        raise Thor::Error, "sync: --all cannot combine with an explicit list — name slugs OR --all" if options[:all]
        raise Thor::Error, "sync: --axis cannot combine with an explicit list — name slugs OR --axis" if options[:axis]
        raise Thor::Error, "sync: --grant-acknowledged is single-source — name one slug" if options[:grant_acknowledged]
        raise Thor::Error, "sync: --review is single-source — name one slug" if options[:review]
      end
      config = Nabu::Config.load
      # P62 rider: the quarter-second write-lock pre-flight — a concurrent
      # sync/rebuild/apply fails HERE with one sentence, not minutes into a
      # load with a BusyException stack.
      Nabu::Store.assert_writable!(config.catalog_path)
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # Ledger FIRST: open_or_create_ledger lifts a pre-P7-1 catalog's history
      # before open_or_create_catalog migrates the moved tables away.
      ledger = open_or_create_ledger(config)
      db = open_or_create_catalog(config)
      runner = Nabu::SyncRunner.new(config: config, registry: registry, db: db, ledger: ledger)
      enabled = sync_enabled_slugs(config, registry, db)
      explain_command(sync_intro_key)
      if slugs.size <= 1
        run_sync(runner, registry, slugs.first, db, ledger, enabled: enabled)
      else
        run_sync_list(runner, registry, slugs, db, ledger, enabled: enabled)
      end
    rescue Nabu::Error => e
      # Unknown slug (ValidationError), fetch failure (FetchError), ... all
      # surface as a clean stderr message and exit 1.
      raise Thor::Error, e.message
    rescue Sequel::DatabaseError => e
      # The probe narrows the collision window but cannot close it — a
      # writer arriving MID-RUN still lands here. The busy shape gets the
      # same clean sentence (the sync is resumable; re-run when free);
      # anything else stays a loud unknown.
      raise unless Nabu::Store.busy_error?(e)

      raise Thor::Error,
            "#{Nabu::CatalogBusyError.new(config.catalog_path).message} (the interrupted sync is resumable)"
    ensure
      db&.disconnect
      ledger&.disconnect
    end

    # -- quickstart (P18-2): the starter shelf --------------------------------

    # One starter source: its registry slug, its measured canonical footprint
    # (du -sh of the live tree, git history included), and what it unlocks.
    StarterSource = Data.define(:slug, :size, :blurb)

    # The curated starter shelf: the smallest set of real sources that delivers
    # the library's three signature surfaces in minutes — align "MARK 2.3"
    # (seven witnesses: sblgnt + the five PROIEL NT texts + the ISWOC
    # West-Saxon Mark), search --lemma (PROIEL gold annotations), and
    # define λόγος / virtus (LSJ + Lewis & Short). Sizes measured 2026-07-13.
    # vulgate/eng-web were weighed and excluded: each is a full open-bibles
    # clone (357 MB) for one USFX file — the first "grow the library" step
    # instead. Order: quick wins first, the big dictionary clone last.
    STARTER_SOURCES = [
      StarterSource.new(slug: "sblgnt", size: "~11 MB",
                        blurb: "SBL Greek New Testament — the align hub's second Greek witness (CC BY)"),
      StarterSource.new(slug: "proiel", size: "~175 MB",
                        blurb: "PROIEL treebank — NT in Greek, Latin, Gothic, Armenian, OCS; gold lemmas (nc)"),
      StarterSource.new(slug: "iswoc", size: "~30 MB",
                        blurb: "ISWOC treebank — the West-Saxon gospels, Old English (nc)"),
      StarterSource.new(slug: "lexica", size: "~480 MB",
                        blurb: "LSJ + Lewis & Short — the dictionary shelf (CC BY-SA)")
    ].freeze

    # The whole shelf on disk (sum of the measured sizes above).
    STARTER_TOTAL = "~690 MB"

    # Class-method accessor so tests can pin a fixture-backed starter list
    # (the Config.load swap pattern) without touching the shipped constant.
    def self.starter_sources = STARTER_SOURCES

    desc "quickstart", "Sync the starter shelf (#{STARTER_SOURCES.map(&:slug).join(' → ')}) " \
                       "and print what to try first"
    long_desc <<~HELP, wrap: false
      The zero-to-first-marvel path for a fresh clone: sync the curated STARTER
      SHELF — four small sources, #{STARTER_TOTAL} canonical on disk (measured
      2026-07-13), minutes on an ordinary connection — then print the first
      three commands to try:

        sblgnt   ~11 MB    SBL Greek New Testament (CC BY)
        proiel   ~175 MB   PROIEL treebank: the NT in Greek, Latin, Gothic,
                           Armenian, and Old Church Slavonic, with gold
                           lemma/morphology annotations (nc)
        iswoc    ~30 MB    ISWOC treebank: the West-Saxon gospels — Old
                           English as an alignment witness (nc)
        lexica   ~480 MB   LSJ + Lewis & Short, the dictionary shelf (CC BY-SA)

      Together they light the three signature surfaces: `align "MARK 2.3"`
      (one verse across seven witnesses), `search --lemma λέγω`
      (dictionary-form search over the gold treebanks — λέγουσι, εἶπας,
      εἰπεῖν all found), and `define λόγος` / `define virtus` (the full
      dictionary entries, citations resolved into your own catalog).

      Before the shelf, the CORE group syncs automatically — the registry
      instruments the library itself depends on (nabu-lects, nabu-places,
      cigs: a few hundred KB total), pre-enabled by nature. `nabu sync
      core` re-runs just that sweep any time.

      Each source syncs through its NORMAL path (fetch → load → index), so
      the command is idempotent — a re-run is an ordinary re-sync — and one
      source's failure never stops the rest: failures are reported at the
      end, and the exit status is 1 if any source failed. --dry-run prints
      the set (with sizes) and exits without touching the network.

      Examples:
        nabu quickstart             # sync the starter shelf, then try the printed commands
        nabu quickstart --dry-run   # what would be synced, and why

      Use cases: a new install's first minutes; the README/site Quickstart's
      one command; rebuilding a demo box.
    HELP
    option :dry_run, type: :boolean, default: false,
                     desc: "Print the starter set (slugs, sizes, what each unlocks) and exit without syncing"
    # The pre-rename spelling of --dry-run (the house preview flag), kept
    # as a hidden alias so existing scripts and docs keep working.
    option :list, type: :boolean, default: false, hide: true
    def quickstart
      return print_starter_list if options[:dry_run] || options[:list]

      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # Ledger FIRST, as in sync: open_or_create_ledger lifts a pre-P7-1
      # catalog's history before open_or_create_catalog migrates it away.
      ledger = open_or_create_ledger(config)
      db = open_or_create_catalog(config)
      runner = Nabu::SyncRunner.new(config: config, registry: registry, db: db, ledger: ledger)
      # P44-r3c: quickstart ENABLES its set before syncing — additive into
      # the enablement config (never overwriting an existing profile's
      # entries), so the sync gate passes deterministically and a fresh
      # box's profile is written explicitly rather than by migration grace.
      enable_starter_set(config)
      # P63 rider (owner ruling 2026-08-09): the CORE group (nabu-lects,
      # nabu-places, cigs — the registry instruments) syncs automatically
      # first: tiny fetches that light the lect/place layers before the
      # corpus shelf arrives. Pre-enabled by nature (modules), failures
      # contained like starter failures.
      say "core group first (requires-closed): #{registry.requires_closure(registry.core_members).join(' · ')}"
      failures = run_core_syncs(runner, registry)
      failures += run_starter_syncs(runner)
      print_quickstart_epilogue(failures)
      unless failures.empty?
        raise Thor::Error, "quickstart: #{failures.size} of #{self.class.starter_sources.size} starter " \
                           "sources failed — re-run bin/nabu quickstart, or sync each by name (bin/nabu sync <slug>)"
      end
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    ensure
      db&.disconnect
      ledger&.disconnect
    end

    desc "ingest FILE|URL...", "File your own PDFs, scans and articles into the local-library shelf"
    long_desc <<~HELP, wrap: false
      The intake front door for canonical memory (architecture §16): copy
      files (never move — your originals stay put) into
      canonical/local-library/<collection>/, categorize them, append one
      manifest entry each, then run the shelf's ordinary sync and print the
      minted urns. This is the ONE sanctioned write path onto the library
      shelf; after it, the files are searchable, showable, linkable corpus
      members like everything else.

      Arguments may be http(s) URLs: the file is DOWNLOADED first (redirect
      chains followed — archive.org's mirror hop included), then flows
      through the exact same intake as a local file, and the manifest
      entry additionally records the URL you gave in a source_url: lane
      (mirror-node URLs rotate; yours is the stable identity — it also
      prefills the provenance candidate). A failed download is one honest
      FAILED line naming the HTTP status — and aborts the batch (below).

      Candidate metadata is derived mechanically first — PDF Info metadata
      and a first-page text sample via mutool (degrading gracefully to
      filename heuristics where mutool is absent), the sha256 always — then
      categorized in one of three modes:

        interactive (TTY default)  one prompt per field, candidates
                                   prefilled; Enter keeps the [default],
                                   '-' clears a field. license_class
                                   DEFAULTS to research_private (never
                                   served or redistributed) — stated at
                                   the prompt; raise it per item only for
                                   genuinely open material.
        --assist CMD               pipe a JSON brief (nabu.ingest-assist/1:
                                   derived candidates + text sample) to
                                   CMD's stdin, parse a suggested entry
                                   from its stdout, and PREFILL the
                                   interactive prompts with it — AI
                                   suggests, you confirm; nothing lands
                                   unreviewed unless you also pass --yes.
                                   Bundled example:
                                   script/ingest-assist-claude (claude -p
                                   with the nabu MCP tools).
        --yes                      scripted: accept the candidates plus
                                   any --title/--creator/--year/--languages/
                                   --tags/--related/--provenance/
                                   --license-class flags, no prompts —
                                   for bulk drops.

      The default collection is "#{Nabu::Ingest::DEFAULT_COLLECTION}" — pass
      --collection for anything you want shelved by topic. Mind that the
      collection is part of the minted urn (frozen forever), so file
      deliberately: a later re-file is honestly a new document.

      Atomicity and honesty: the batch lands WHOLE or not at all —
      everything fallible (downloads, existence and no-executables checks,
      categorization, validation against the manifest's own rules) runs
      BEFORE any write, so a defect anywhere is one named FAILED line per
      problem, the other files say "aborted", canonical/ stays untouched,
      exit 1. A file whose bytes are already catalogued anywhere in the
      shelf is a no-op with a message; the same NAME with new bytes
      replaces the copy and the sync records an ordinary revision.

      --shelf language CODE scaffolds a language DOSSIER instead — the same
      front door for all canonical memory: prompts (same three modes; flags
      --name/--family/--context) for the front matter and a context line,
      writes canonical/local-language/CODE.md through the shelf's gateway,
      and syncs. A scaffold, not an editor: an existing dossier is a no-op
      pointing at the file.

      --shelf source SLUG scaffolds a SOURCE dossier the same way (P24-0):
      prompts (flags --description/--themes/--key-works) with the
      description prefilled from the registered source's name, writes
      canonical/local-source/SLUG.md through Nabu::SourceShelf, and syncs.
      SLUG must be registered in config/sources.yml — dossiers describe
      held shelves.

      Examples:
        nabu ingest ~/scans/vaillant-1950-manuel.pdf --collection slavistics
        nabu ingest https://archive.org/download/handbuchderaltbu00lesk/handbuchderaltbu00lesk.pdf
        nabu ingest paper.pdf --assist script/ingest-assist-claude
        nabu ingest notes.txt --yes --title "Reading notes" --languages eng \\
          --related urn:nabu:ccmh:mar:mt --license-class open
        nabu ingest --shelf language zle-ort
        nabu ingest --shelf source edh --themes epigraphy,prosopography
    HELP
    option :collection, type: :string, banner: "NAME",
                        desc: "Target collection under canonical/local-library/ " \
                              "(default #{Nabu::Ingest::DEFAULT_COLLECTION}; becomes part of the urn)"
    option :assist, type: :string, banner: "CMD",
                    desc: "AI-assist hook: JSON brief to CMD's stdin, suggested entry from its stdout " \
                          "(prefills the prompts; example: script/ingest-assist-claude)"
    option :yes, type: :boolean, default: false,
                 desc: "No prompts: accept the derived/assist/flag values (scripted bulk drops)"
    option :title, type: :string, desc: "Title (one file only)"
    option :creator, type: :string, desc: "Creator/author"
    option :year, type: :numeric, desc: "Publication year"
    option :languages, type: :string, banner: "chu,deu", aliases: ["--lang"],
                       desc: "Language codes, comma-separated (--lang is the standing alias)"
    option :tags, type: :string, banner: "grammar,ocs", desc: "Tags, comma-separated"
    option :related, type: :string, banner: "URN,CODE",
                     desc: "Related urns/language codes, comma-separated (urns become links-journal edges)"
    option :provenance, type: :string, desc: "Where this copy came from"
    option :license_class, type: :string, banner: "CLASS",
                           desc: "License class (default research_private — never served or redistributed)"
    option :shelf, type: :string, banner: "language|source",
                   desc: "Ingest into another local shelf: `--shelf language CODE` / `--shelf source SLUG` " \
                         "scaffolds a dossier"
    option :name, type: :string, desc: "With --shelf language: the language's name"
    option :family, type: :string, desc: "With --shelf language: the family lane"
    option :context, type: :string, desc: "With --shelf language: one context line (free prose)"
    option :description, type: :string,
                         desc: "With --shelf source: the 1–3 sentence content description (the load-bearing lane)"
    option :themes, type: :string, banner: "epigraphy,onomastics",
                    desc: "With --shelf source: themes, comma-separated"
    option :key_works, type: :string, banner: "URN,URN",
                       desc: "With --shelf source: key works as catalog urns, comma-separated"
    def ingest(*paths)
      config = Nabu::Config.load
      return ingest_shelf(config, paths) if options[:shelf]

      if paths.empty?
        raise Thor::Error, "ingest: give at least one file or url (or --shelf language CODE / " \
                           "--shelf source SLUG)"
      end

      %w[name family context description themes key_works].each do |flag|
        raise Thor::Error, "ingest: --#{flag.tr('_', '-')} only applies with --shelf language/source" if options[flag]
      end
      raise Thor::Error, "ingest: --title names one file's title — ingest that file alone" \
        if options[:title] && paths.size > 1

      outcomes = build_ingest_engine(config).add_files(
        paths, collection: options[:collection] || Nabu::Ingest::DEFAULT_COLLECTION
      )
      outcomes.each { |outcome| print_ingest_outcome(outcome) }
      if outcomes.any? { |outcome| %i[added revised].include?(outcome.status) }
        run_shelf_sync(config, Nabu::LibraryShelf::SLUG)
        print_ingest_epilogue(outcomes)
      end
      failed = outcomes.reject(&:ok?)
      raise Thor::Error, "ingest: #{failed.size} of #{outcomes.size} file(s) failed — see above" unless failed.empty?
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    end

    # Changed paths named on a kind: module's sync line before the "+N
    # more" tail (the same house render-cap rule).
    # const: a render cap, not a corpus census
    MODULE_CHANGED_SHOWN = 5

    no_commands do
      # The registry entry for one slug, nil when the catalog source is not
      # (or no longer) registered — the card words that honestly.
      def registry_entry(config, slug)
        Nabu::SourceRegistry.load(config.sources_path)[slug]
      end

      def sync_intro_key
        return :sync_fetch_only if options[:fetch_only]

        options[:parse_only] ? :sync_parse_only : :sync
      end

      # sync dispatch (P35-2): --all first (flat batch), then --axis (grouped),
      # then the positional NAME resolved EXACT-SLUG-FIRST-THEN-AXIS. The
      # slug/axis namespaces can never collide (a load-time guarantee), so a
      # name that is not a slug but is an axis is unambiguous; a name that is
      # neither is the unknown-target error (naming BOTH namespaces). A nil
      # name falls to sync_one's own "slug or --all" guard, unchanged.
      # P90-3 (lane 1): the explicit multi-slug batch. Each argument
      # resolves EXACTLY as a lone argument would (group, slug, axis — the
      # ordinary run_sync dispatch), in ARGUMENT order, each with its own
      # report block. One member's failure is contained and reported —
      # later members still run (the fetch lock is per-source) — and the
      # batch exits non-zero at the end naming every failure.
      def run_sync_list(runner, registry, slugs, db, ledger, enabled:)
        failures = []
        slugs.each do |slug|
          run_sync(runner, registry, slug, db, ledger, enabled: enabled)
        rescue Nabu::ManualDrop::AwaitingAcquisition => e
          say e.message
        rescue Nabu::Error, Thor::Error => e
          failures << slug
          warn e.message
        end
        synced = slugs.size - failures.size
        return say "synced #{synced}" if failures.empty?

        raise Thor::Error, "sync: synced #{synced}, failed #{failures.size} (#{failures.join(', ')})"
      end

      def run_sync(runner, registry, slug, db, ledger, enabled:)
        if options[:all]
          auto_sync_core!(runner, registry, slug, db)
          return sync_all(runner, enabled: enabled)
        end
        return sync_axes(runner, registry, options[:axis].split(","), db, ledger) if options[:axis]

        # P63 rider + P68-4: `sync <group>` sweeps a registered group —
        # "core" (the registry instruments; modules, no enablement dance)
        # and "signs" (the sign/char restore set: `nabu enable signs &&
        # nabu sync signs` makes the capability whole on a fresh box).
        # Failures are reported per member and never stop the rest.
        if Nabu::SourceRegistry::GROUPS.include?(slug)
          auto_sync_core!(runner, registry, slug, db)
          return sync_group(slug, runner, registry, db, ledger, enabled)
        end

        if slug.nil? || registry[slug]
          # P44-r3b: the enablement acquisition gate is on the EXPLICIT
          # single-source path only. Axis fan-out keeps its registry-enabled
          # membership rule (below); --all applies the enabled-set filter itself.
          enforce_enablement!(registry[slug], enabled) unless slug.nil?
          auto_sync_core!(runner, registry, slug, db)
          return sync_one(runner, registry, slug, db, ledger)
        end
        return sync_axes(runner, registry, [slug], db, ledger) if registry.axes[slug]

        raise Thor::Error, unknown_sync_target_message(registry, slug)
      end

      # The group sweep (core P63; generalized P68-4): each member through
      # the ORDINARY sync_one path (byte-identical per-source reports), one
      # member's failure contained and reported at the end. A Manual
      # Adapter member in the awaiting state counts as awaiting, not
      # failed. The enablement gate applies per SOURCE member (modules are
      # machinery — exempt inside the gate itself); a not-yet-enabled
      # member is a contained failure carrying the enable hint, so
      # `sync signs` before `enable signs` explains itself member by member.
      def sync_group(name, runner, registry, db, ledger, enabled)
        # The sweep closes over requires (P77-r4): `sync core` honors the
        # members' own chains — the seeded nabu-places gazetteers ride.
        members = registry.requires_closure(registry.group_members(name))
        raise Thor::Error, "sync #{name}: no #{name}-group sources registered" if members.empty?

        say "#{name} group: #{members.join(' · ')}"
        failures = []
        members.each do |member|
          enforce_enablement!(registry[member], enabled)
          sync_one(runner, registry, member, db, ledger)
        rescue Nabu::ManualDrop::AwaitingAcquisition => e
          say e.message
        rescue Nabu::Error, Thor::Error => e
          failures << member
          warn "#{member}: #{e.message}"
        end
        return if failures.empty?

        raise Thor::Error, "sync #{name}: #{failures.size} of #{members.size} failed — #{failures.join(', ')}"
      end

      # The enabled-slug set governing sync acquisition (P44-r3b), or nil when
      # the box is UNCONFIGURED (no enablement config file AND no library yet) —
      # bootstrap, where sync stays ungated so a fresh box can acquire its first
      # source without an enable dance. A present file or a built catalog means
      # the profile governs.
      def sync_enabled_slugs(config, registry, db)
        return nil unless Nabu::Profile.exist?(config.profile_path) || catalog_has_sources?(db)

        Nabu::Focus.resolve(effective_profile(config, registry, catalog: db), registry).slugs
      end

      def catalog_has_sources?(db)
        db&.table_exists?(:sources) && db[:sources].any?
      end

      # The sync acquisition gate (P44-r3b): a real fetch of a non-enabled
      # kind: source is refused with the enable on-ramp. Exemptions: --parse-only
      # (repair/rebuild re-derives already-synced data — never an acquisition),
      # an unconfigured box (enabled nil — bootstrap), and non-source rows
      # (shelves are the owner's own; modules are machinery). A blocked source's
      # grant terms are a separate, later gate (enforce_grant!).
      def enforce_enablement!(entry, enabled)
        return if options[:parse_only]
        return if enabled.nil?
        return unless entry&.source?
        return if enabled.include?(entry.slug)

        raise Thor::Error,
              "#{entry.slug} is not enabled on this box — enable it first: nabu enable #{entry.slug} " \
              "(or re-derive already-synced data with nabu sync #{entry.slug} --parse-only)"
      end

      # sync <axis> / --axis a,b: expand each named axis to its members and
      # sync them through the ORDINARY per-source path (sync_one), so every
      # per-source report line is byte-identical to a direct sync — grouping
      # is pure fan-out. One axis header precedes each group; DISABLED members
      # are skipped (an axis expansion is not an explicit per-source request)
      # and named on one `skipped (unwired): …` line, never silently. A slug
      # reachable via two selected axes syncs once, under its first group.
      def sync_axes(runner, registry, names, db, ledger)
        names = names.map(&:strip).reject(&:empty?)
        raise Thor::Error, "sync --axis: name at least one axis — known axes: #{axis_menu(registry)}" if names.empty?

        unknown = names.reject { |name| registry.axes[name] }
        unless unknown.empty?
          name = unknown.first
          if registry.functional_set?(name)
            hint = Nabu::SourceRegistry::GROUPS.include?(name) ? name : "core"
            raise Thor::Error, "sync --axis: #{name.inspect} is a functional set, not a desk axis — " \
                               "run `nabu sync #{hint}` (the group sweep)"
          end

          raise Thor::Error, "sync --axis: unknown axis #{name.inspect} — known axes: #{axis_menu(registry)}"
        end

        auto_sync_core!(runner, registry, nil, db,
                        extra: names.flat_map { |name| registry.axis_members(name) }.uniq)
        synced = []
        names.each { |name| sync_axis_group(runner, registry, name, db, ledger, synced) }
      end

      # One axis's group: the header, then each not-yet-synced WIRED member
      # through sync_one, then the named skip line for the unwired members.
      def sync_axis_group(runner, registry, name, db, ledger, synced)
        wired, unwired = registry.axis_members(name).partition { |member| registry[member].wired }
        # P46-r1: modules are PERMANENTLY wired: false (registry invariant) —
        # their sync is an explicit owner act (`sync <slug>`), so the batch
        # skip is right, but the label must name the nature, not "unwired".
        modules, unwired = unwired.partition { |member| registry[member].feature_module? }
        # P42-r1: an axis expansion is a batch, not an explicit per-source
        # request, so a grant-blocked member is SKIPPED with the honest line —
        # never prompted mid-group (the prompt is reserved for `sync <slug>`).
        gate = Nabu::GrantGate.new(ledger: ledger, grants_path: Nabu::Config.load.grants_path)
        grant_blocked, runnable = wired.partition { |member| gate.blocked?(registry[member]) }
        say axis_header(registry.axes[name])
        (runnable - synced).each do |member|
          sync_one(runner, registry, member, db, ledger)
          synced << member
        end
        say "skipped (unwired): #{unwired.join(', ')}" unless unwired.empty?
        say "skipped (module — sync directly): #{modules.join(', ')}" unless modules.empty?
        (grant_blocked - synced).each do |member|
          say Nabu::GrantGate.skip_line(member)
          synced << member
        end
      end

      # The one-line axis header: the hat's persona verbatim (first-class
      # render data, P35-0), grouping the members below it.
      def axis_header(axis)
        "axis #{axis.name} — #{axis.persona}"
      end

      # The known-axes menu for error messages, honest when none are defined.
      def axis_menu(registry)
        names = registry.axes.names
        names.empty? ? "(none defined)" : names.join(", ")
      end

      # A name that is neither source slug nor axis: name both namespaces so
      # the user sees the axes too (the error the unknown-slug path grew into).
      def unknown_sync_target_message(registry, name)
        slugs = registry.slugs.empty? ? "(none)" : registry.slugs.join(", ")
        "unknown source or axis #{name.inspect} — sources: #{slugs}; axes: #{axis_menu(registry)}"
      end

      # sync <slug>: explicit, unconditional (disabled sources allowed, with a
      # note). A tripped breaker prints its counts + the --force hint and exits 1.
      def sync_one(runner, registry, slug, db, ledger)
        raise Thor::Error, "sync: give a source slug or --all" if slug.nil?

        entry = registry[slug]
        # P39-0: name a non-source row's nature up front, so an owner who fires
        # `sync kr-gaiji` / `sync local-notes` knows what it does (and does not) do.
        say kind_nature_note(entry), :yellow if entry && !entry.source?
        # The verification-pending note belongs to kind: source rows alone —
        # module/shelf rows verify their channel once and stay wired (the
        # 2026-08-18 wired-semantics ruling: wired = channel verified, for
        # every kind; --all participation is governed by kind + sync_policy).
        if entry && !entry.wired && entry.source?
          say "Note: #{slug} is not wired yet (this sync is the verification); syncing anyway (explicit request).",
              :yellow
        end
        # P42-r1: the fetch-grant gate — a permission-bound source needs a
        # recorded acknowledgment before its first fetch (interactive here, on
        # the explicit path; the batch paths pre-skip blocked sources).
        # The credentials seam: a gated upstream with nothing stored refuses
        # FIRST — before the grant prompt, the redownload wipe, or any network.
        enforce_credentials!(entry, config_for_runner(runner)) unless options[:parse_only]
        enforce_grant!(entry, ledger)
        redownload_wipe!(config_for_runner(runner), slug) if options[:redownload]
        # P78-r2: the runs history already answers "how long does this
        # usually take" — say it up front, before the wait begins. Coarse on
        # purpose (fetch variance, parse-only runs); silent for a first sync.
        if (eta = Nabu::Eta.last_sync(ledger, slug: slug))
          say "#{slug}: last sync took #{Nabu::Eta.format_seconds(eta.seconds)}"
        end
        outcome = runner.sync(slug, parse_only: options[:parse_only], fetch_only: options[:fetch_only],
                                    force: options[:force], progress: progress_reporter)
        finish_progress
        raise Thor::Error, "#{slug}: #{outcome.breaker.message}" if outcome.aborted?

        say format_sync_outcome(outcome)
        print_discovery_accounting(outcome)
        print_sync_warnings(outcome)
        print_analyzed(outcome.analyzed)
        print_citation_coverage(entry, db)
        run_review_hook(outcome, db, ledger) if options[:review]
      end

      # The fetch-grant gate (P42-r1) for an EXPLICIT `sync <slug>`. A grant-
      # required source with no recorded acknowledgment shows its terms and
      # requires a typed `granted` (or the scripted --grant-acknowledged flag),
      # recording the acknowledgment durably in the ledger; refusal or a no-TTY
      # environment aborts with the request scaffold (the on-ramp, never a bare
      # wall). A non-grant or already-acknowledged source passes silently — so
      # this is a no-op for every ordinary source and every second sync.
      def enforce_grant!(entry, ledger)
        return unless entry&.grant_required?

        gate = Nabu::GrantGate.new(ledger: ledger, grants_path: Nabu::Config.load.grants_path)
        return if gate.acknowledged?(entry.slug)

        if options[:grant_acknowledged]
          gate.record!(slug: entry.slug, terms: entry.grant.terms, how: "flag")
          return say("#{entry.slug}: grant acknowledged (--grant-acknowledged) — recorded.", :yellow)
        end

        # No TTY to prompt: abort honestly with the terms + request scaffold,
        # BEFORE any fetch (the ingest/note precedent).
        raise Thor::Error, Nabu::GrantGate.abort_message(entry) unless $stdin.tty?

        say Nabu::GrantGate.notice(entry), :yellow
        say Nabu::GrantGate.prompt_line(entry)
        # Plain $stdin.gets, NOT Thor's ask (the note precedent): ask routes
        # through Readline, invisible to the suite's $stdin double and to pipes.
        answer = $stdin.gets
        raise Thor::Error, Nabu::GrantGate.abort_message(entry) unless Nabu::GrantGate.acknowledged_answer?(answer)

        gate.record!(slug: entry.slug, terms: entry.grant.terms, how: "typed")
        say "#{entry.slug}: grant acknowledged — recorded. Syncing.", :green
      end

      # P39-0: the one-line nature note for a non-source sync target. A module
      # refreshes reference machinery and mints no catalog rows; a shelf is
      # gateway-written owner memory re-scanned locally with no network.
      # --redownload (P44-i1, owner ruling): wipe the source's canonical
      # snapshot and re-acquire from scratch — the operator's override for
      # any partial/wedged state the fetcher believes is resumable. The
      # ATTIC is preserved (it is history, not snapshot); everything else
      # under canonical/<slug> goes, announced. Composes with the atomic
      # fresh-clone path: the re-acquisition either lands whole or not at
      # all. Refused with --parse-only (contradictory) and --all (wipe is
      # a per-source, explicit decision).
      def redownload_wipe!(config, slug)
        dir = config.source_workdir(slug)
        return unless Dir.exist?(dir)

        kept_attic = false
        Dir.children(dir).sort.each do |child|
          if child == ".attic"
            kept_attic = true
            next
          end
          FileUtils.remove_entry_secure(File.join(dir, child))
        end
        say "redownload: wiped canonical/#{slug}#{' (attic preserved)' if kept_attic} — re-acquiring from scratch",
            :yellow
      end

      def config_for_runner(runner)
        runner.config
      end

      # A source declaring `credentials: NAME` with nothing stored refuses
      # with the gateway command (the runner re-checks at fetch time).
      def enforce_credentials!(entry, config)
        return if entry.nil? || entry.credentials.nil?
        return if Nabu::Credentials.new(path: config.credentials_path)[entry.credentials]

        raise Thor::Error, Nabu::Credentials.required_message(entry.credentials)
      end

      def kind_nature_note(entry)
        if entry.feature_module?
          "#{entry.slug}: feature module — refreshes canonical reference data; mints no catalog rows."
        else
          "#{entry.slug}: local memory shelf — gateway-written owner data; sync re-scans canonical (no network)."
        end
      end

      # P18-7, the optional AI-review rider: assemble the JSON brief and pipe
      # it to the --review command. The hook's output is relayed and its exit
      # status REPORTED — never raised: the sync already happened, and a
      # review's failure is advisory information, not a sync failure.
      def run_review_hook(outcome, db, ledger)
        result = Nabu::ReviewHook.run(
          command: options[:review],
          brief: Nabu::ReviewHook.brief(outcome: outcome, db: db, ledger: ledger)
        )
        result.output.each_line { |line| say "  review| #{line.chomp}" }
        if result.ok?
          say "  review hook: exit 0"
        else
          status = result.status ? "exit #{result.status}" : "could not start"
          say "  review hook: #{status} (advisory — sync unaffected)", :yellow
        end
      end

      # P17-4 per-siglum citation coverage: an adapter that declares
      # .citation_coverage (MW → GRETIL) gets its live-resolution accounting
      # printed after every sync — the survey's projections as verifiable
      # output, recomputed against THIS catalog, never faked.
      def print_citation_coverage(entry, db)
        adapter_class = entry&.adapter_class
        return unless adapter_class.respond_to?(:citation_coverage)

        adapter_class.citation_coverage(catalog: db).each { |line| say("  #{line}") }
      end

      # sync --all: the ENABLED, live source set (P44-r3b), reported one per
      # line, never aborting the batch on one source's error. The enabled-set
      # filter is passed to the runner (nil = unconfigured/bootstrap or a repair
      # --parse-only run → the registry's live-enabled sweep, unchanged). The
      # summary line names the enabled scope honestly.
      def sync_all(runner, enabled:)
        filter = options[:parse_only] ? nil : enabled
        results = runner.sync_all(parse_only: options[:parse_only], fetch_only: options[:fetch_only],
                                  force: options[:force], progress: progress_reporter, enabled: filter)
        finish_progress
        return say("Nothing to sync: no wired, auto-cadence sources.") if results.empty?

        say "syncing #{pluralize(results.size, 'enabled source')}:"
        results.each do |slug, result|
          say("  #{sync_all_line(slug, result)}")
          next unless result.is_a?(Nabu::SyncRunner::Outcome)

          print_discovery_accounting(result)
          print_sync_warnings(result)
          print_analyzed(result.analyzed)
        end
      end

      def sync_all_line(slug, result)
        # P42-r1: a grant-blocked source was skipped, not run — the honest line.
        return Nabu::GrantGate.skip_line(result.slug) if result.is_a?(Nabu::SyncRunner::GrantRequired)
        return "#{slug.ljust(24)} FAILED — #{result.message}" unless result.is_a?(Nabu::SyncRunner::Outcome)
        return "#{slug.ljust(24)} ABORTED — #{result.breaker.message}" if result.aborted?

        format_sync_outcome(result)
      end

      # P5-5 inline deviation warnings: advisory one-liners after the counts line,
      # in yellow, never affecting the exit code. Empty on a clean sync.
      def print_sync_warnings(outcome)
        outcome.warnings.each { |finding| say("  ! #{finding.message}", :yellow) }
      end

      # -- quickstart (P18-2) -------------------------------------------------

      # `quickstart --dry-run`: the starter set, sizes, and what each source
      # unlocks — no network, no db, nothing created.
      # Additively enable the starter slugs in the enablement config
      # (P44-r3c). Existing entries are preserved; the save carries the
      # enablement header, so the file governs from here on.
      def enable_starter_set(config)
        profile = Nabu::Profile.exist?(config.profile_path) ? Nabu::Profile.load(config.profile_path) : Nabu::Profile.new([])
        slugs = self.class.starter_sources.map(&:slug)
        merged = (profile.entries + slugs).uniq
        return if merged.sort == profile.entries.sort

        Nabu::Profile.new(merged).save(config.profile_path)
        # stderr, the r3b enablement-honesty convention: data stdout stays
        # byte-identical/pipe-clean.
        warn "enabled the starter shelf: #{slugs.join(', ')} (config/profile.yml)"
      end

      def print_starter_list
        say "starter shelf (#{STARTER_TOTAL} canonical, minutes to sync):"
        self.class.starter_sources.each do |starter|
          say "  #{starter.slug.ljust(8)} #{starter.size.rjust(8)}  #{starter.blurb}"
        end
        say "sync it: bin/nabu quickstart"
      end

      # Sync the starter list IN ORDER through the normal per-source path
      # (fetch → load → index — SyncRunner#sync, the same code `nabu sync
      # <slug>` runs, so the command is idempotent by construction). One
      # source's failure never stops the rest (sync --all's posture): failures
      # collect as [slug, message] pairs and report after the batch. An
      # unregistered starter slug fails the same way (ValidationError is a
      # Nabu::Error), never aborting the run.
      # The quickstart core sweep (P63 rider): same containment contract as
      # the starter loop — a failed member is reported and counted, an
      # awaiting Manual Adapter member prints its card and counts as neither.
      # P77 rider (owner ruling 2026-08-13): core is the MINIMUM SET a new
      # install carries — auto-enabled by nature (modules are exempt from
      # the enablement gate) and AUTO-SYNCED on the box's first real sync
      # request: any core member without a sources row yet syncs first,
      # riding the requested sync. P77-r3 extends the same sweep to the
      # requested source's `requires:` chain (the package-manager rule:
      # syncing a dependent syncs its never-synced requirements first).
      # --parse-only never acquires; an explicit `sync core` (or a core
      # member by name) IS the sweep already; a member that once synced
      # never re-rides (its row exists — `nabu sync core` is the explicit
      # re-run). Failures (and ManualDrop acquisition cards) are contained
      # so the requested sync still runs.
      def auto_sync_core!(runner, registry, slug, db, extra: [])
        # fetch-only defers all loading, so the core pre-sweep (which loads)
        # defers with it — the deferred parse's own sync runs it.
        return if options[:parse_only] || options[:fetch_only]

        members = registry.core_members
        # A request that IS the core sweep (the group, or a member by name)
        # never re-triggers it — but chains still ride. The sweep set
        # closes over requires: the CORE MEMBERS' own chains too (the P77
        # survey's coverage finding), plus the requested slug's and any
        # +extra+ base an axis fan-out passes; the extras themselves sync
        # on their own path, only their chains ride here.
        core_wanted = slug == "core" || members.include?(slug) ? [] : members
        base = core_wanted + extra
        base += [slug] if slug && registry[slug]
        needed = registry.requires_closure(base.uniq) - [slug] - extra
        missing = needed - synced_slugs(db, needed)
        # A grant-gated or blocked requirement never rides an implicit
        # sweep — acknowledging terms is an explicit act (the sync --all
        # GrantRequired posture).
        gated = missing.select { |m| registry[m]&.grant_required? || registry.blocked?(m) }
        unless gated.empty?
          say "prerequisites skipped (grant-gated — sync each by name to acknowledge): #{gated.join(' · ')}"
          missing -= gated
        end
        return if missing.empty?

        core_missing = missing & core_wanted
        chain_missing = missing - core_wanted
        say "core set first (owner ruling 2026-08-13): #{core_missing.join(' · ')}" unless core_missing.empty?
        unless chain_missing.empty?
          labeled = chain_missing.map do |member|
            "#{member} (for #{(registry.required_by(member) & (base + needed)).uniq.join(', ')})"
          end
          say "dependency chain first: #{labeled.join(' · ')}"
        end
        failures = run_core_syncs(runner, registry, members: missing)
        return if failures.empty?

        warn "prerequisite auto-sync: #{failures.map(&:first).join(', ')} failed — " \
             "continuing with the requested sync (`nabu sync core` / the member by name re-runs it)"
      end

      # "Synced" = at least one SUCCESSFUL sync (last_sync_at is written
      # only after a completed load) — a row minted by a failed or
      # awaiting-acquisition attempt must NOT count, or the sweep would
      # never retry a requirement whose first attempt printed the
      # ManualDrop card (the P77 survey's sentinel finding).
      def synced_slugs(db, members)
        return [] unless db&.table_exists?(:sources)

        db[:sources].where(slug: members).exclude(last_sync_at: nil).select_map(:slug)
      end

      def run_core_syncs(runner, registry, members: registry.requires_closure(registry.core_members))
        failures = []
        members.each do |member|
          outcome = runner.sync(member, progress: progress_reporter)
          finish_progress
          if outcome.aborted?
            failures << [member, outcome.breaker.message]
          else
            say format_sync_outcome(outcome)
          end
        rescue Nabu::ManualDrop::AwaitingAcquisition => e
          finish_progress
          say e.message
        rescue Nabu::Error => e
          finish_progress
          failures << [member, e.message]
          warn "#{member}: #{e.message}"
        end
        failures
      end

      def run_starter_syncs(runner)
        failures = []
        self.class.starter_sources.each do |starter|
          outcome = runner.sync(starter.slug, progress: progress_reporter)
          finish_progress
          if outcome.aborted?
            failures << [starter.slug, outcome.breaker.message]
          else
            say format_sync_outcome(outcome)
            print_discovery_accounting(outcome)
            print_sync_warnings(outcome)
            print_analyzed(outcome.analyzed)
          end
        rescue Nabu::Error => e
          finish_progress
          failures << [starter.slug, e.message]
        end
        failures
      end

      # The "try these" epilogue: any failures first (so what follows is read
      # against an honest shelf), then the three marvels with their
      # expected-shape hints, then the growth pointer. Compact house style.
      def print_quickstart_epilogue(failures)
        unless failures.empty?
          say ""
          failures.each { |slug, message| say("  #{slug.ljust(8)} FAILED — #{message}", :red) }
        end
        say ""
        say "try these:"
        say %(  bin/nabu align "MARK 2.3"      # one verse, seven witnesses: Greek ×2, Latin, Gothic, OCS, Old English)
        say "  bin/nabu search --lemma λέγω    # every inflection over the gold treebanks: λέγουσι, εἶπας, εἰπεῖν…"
        say "  bin/nabu define λόγος           # the whole LSJ entry, citations resolved (Latin: define virtus)"
        say "grow the library: bin/nabu sync --all (live sources) or bin/nabu sync <slug> — " \
            "the menu is config/sources.yml, the shelf map docs/library.md"
      end

      # -- ingest (P19-5): the canonical-memory intake front door ---------------

      # `--shelf X`: the canonical-memory scaffold front doors, one per
      # local dossier shelf (language P19-5, source P24-0).
      def ingest_shelf(config, args)
        case options[:shelf]
        when "language" then ingest_language(config, args)
        when "source" then ingest_source(config, args)
        else
          raise Thor::Error, "ingest: unknown shelf #{options[:shelf].inspect} — `--shelf language CODE` " \
                             "and `--shelf source SLUG` are the front doors"
        end
      end

      # `--shelf language CODE`: scaffold a dossier through LanguageShelf
      # (the shelf's sanctioned gateway), then sync the dossier shelf. THIN
      # by design — a skeleton, not an editor.
      def ingest_language(config, codes)
        raise Thor::Error, "ingest --shelf language: give exactly one CODE (e.g. zle-ort)" unless codes.size == 1

        %w[collection title creator year languages tags related provenance license_class].each do |flag|
          next unless options[flag]

          raise Thor::Error, "ingest: --#{flag.tr('_', '-')} is a library-shelf field — " \
                             "with --shelf language use --name/--family/--context"
        end
        %w[description themes key_works].each do |flag|
          next unless options[flag]

          raise Thor::Error, "ingest: --#{flag.tr('_', '-')} is a source-shelf field — " \
                             "with --shelf language use --name/--family/--context"
        end
        shelf = Nabu::LanguageShelf.new(dir: Nabu::LanguageShelf.dir(config))
        engine = Nabu::Ingest.new(resolver: ingest_resolver, assist_command: options[:assist],
                                  overrides: ingest_overrides(%w[name family context]),
                                  notify: ingest_notify)
        outcome = engine.scaffold_language(codes.first, language_shelf: shelf)
        print_ingest_outcome(outcome)
        return unless outcome.status == :added

        run_shelf_sync(config, Nabu::LanguageShelf::SLUG)
        say ""
        say "try: bin/nabu language #{codes.first}"
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      end

      # `--shelf source SLUG` (P24-0): scaffold a source dossier through
      # SourceShelf (the third sanctioned gateway), then sync. The
      # description prompt prefills from the registered source's name.
      def ingest_source(config, slugs)
        raise Thor::Error, "ingest --shelf source: give exactly one SLUG (e.g. edh)" unless slugs.size == 1

        %w[collection title creator year languages tags related provenance license_class name family
           context].each do |flag|
          next unless options[flag]

          raise Thor::Error, "ingest: --#{flag.tr('_', '-')} is another shelf's field — " \
                             "with --shelf source use --description/--themes/--key-works"
        end
        slug = slugs.first
        entry = registry_entry(config, slug)
        if entry.nil?
          raise Thor::Error, "ingest --shelf source: #{slug.inspect} is not a registered source " \
                             "(config/sources.yml) — dossiers describe held shelves"
        end
        shelf = Nabu::SourceShelf.new(dir: Nabu::SourceShelf.dir(config))
        engine = Nabu::Ingest.new(resolver: ingest_resolver, assist_command: options[:assist],
                                  overrides: ingest_overrides(Nabu::Ingest::SOURCE_FIELDS),
                                  notify: ingest_notify)
        outcome = engine.scaffold_source(slug, source_shelf: shelf, source_name: entry.manifest.name)
        print_ingest_outcome(outcome)
        return unless outcome.status == :added

        run_shelf_sync(config, Nabu::SourceShelf::SLUG)
        say ""
        say "try: bin/nabu list #{slug}"
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      end

      def build_ingest_engine(config)
        shelf = Nabu::LibraryShelf.new(dir: Nabu::LibraryShelf.dir(config))
        Nabu::Ingest.new(
          shelf: shelf, resolver: ingest_resolver, assist_command: options[:assist],
          overrides: ingest_overrides(Nabu::Ingest::LIBRARY_FIELDS), notify: ingest_notify
        )
      end

      # The three categorization modes, decided here: --yes accepts, a TTY
      # prompts (Thor ask, injectable into the engine as a plain callable),
      # anything else is an honest refusal — assist suggestions never land
      # unreviewed by accident.
      def ingest_resolver
        return Nabu::Ingest::AcceptResolver.new if options[:yes]

        unless $stdin.tty?
          raise Thor::Error, "ingest: interactive categorization needs a TTY — pass --yes " \
                             "(fields from flags), or run in a terminal"
        end
        # The header prints at the FIRST prompt, not at resolver construction:
        # the engine's staging pass (existence checks, downloads) must be
        # able to fail BEFORE any interactive furniture appears (the
        # 2026-07-14 archive.org incident, P20-0).
        header_printed = false
        Nabu::Ingest::PromptResolver.new(
          ask: lambda do |label, default|
            unless header_printed
              say "categorize (Enter keeps the [default]; '-' clears a field):"
              header_printed = true
            end
            default ? ask("  #{label}", default: default) : ask("  #{label}:")
          end,
          # An invalid answer's one-line reason (P20-1) — the prompt repeats.
          warn: ->(line) { say "  ! #{line}", :yellow }
        )
      end

      def ingest_overrides(keys)
        keys.each_with_object({}) do |key, map|
          value = options[key]
          map[key] = value unless value.nil?
        end
      end

      # Advisory engine notes (assist diagnostics, degrade notes) — yellow,
      # never affecting the exit code.
      def ingest_notify
        ->(line) { say "  #{line}", :yellow }
      end

      def print_ingest_outcome(outcome)
        case outcome.status
        when :added then say "  added    #{outcome.file} #{outcome.message}"
        when :revised then say "  revised  #{outcome.file} — #{outcome.message}"
        when :skipped then say "  skipped  #{outcome.file} — #{outcome.message}"
        when :aborted then say "  aborted  #{outcome.file} — #{outcome.message}", :yellow
        else say "  FAILED   #{outcome.file} — #{outcome.message}", :red
        end
      end

      # Minted urns + the compact "try:" epilogue: show always; search only
      # when the file actually yielded text (metadata-only scans are not
      # searchable — honesty over symmetry); links when the entry asserted
      # related urns (they just became reference edges).
      def print_ingest_epilogue(outcomes)
        added = outcomes.select { |outcome| outcome.status == :added }
        return if added.empty?

        say ""
        say "minted:"
        added.each { |outcome| say "  #{outcome.urn}" }
        say "try:"
        first = added.first
        say "  bin/nabu show #{first.urn}"
        if first.search_term
          say "  bin/nabu search #{first.search_term} --license " \
              "#{first.entry['license_class'] || Nabu::LibraryManifest::DEFAULT_LICENSE_CLASS}"
        end
        linked = added.find { |outcome| (outcome.entry["related"] || []).any? { |r| r.start_with?("urn:") } }
        say "  bin/nabu links #{linked.urn}" if linked
      end

      # Run one local shelf's ordinary sync (fetch = the LocalFetch re-scan;
      # no network) and print the standard sync accounting.
      def run_shelf_sync(config, slug)
        registry = Nabu::SourceRegistry.load(config.sources_path)
        ledger = open_or_create_ledger(config)
        db = open_or_create_catalog(config)
        runner = Nabu::SyncRunner.new(config: config, registry: registry, db: db, ledger: ledger)
        outcome = runner.sync(slug, progress: progress_reporter)
        finish_progress
        raise Thor::Error, "#{slug}: #{outcome.breaker.message}" if outcome.aborted?

        say format_sync_outcome(outcome)
        print_discovery_accounting(outcome)
        print_sync_warnings(outcome)
      ensure
        db&.disconnect
        ledger&.disconnect
      end

      # P11-7 discovery accounting: classify every content-pattern file
      # selected / skipped-by-rule / unrecognized, combining the loader's fate
      # of discovered refs (loaded → selected; parse-skipped → skipped-by-rule;
      # quarantined → unrecognized) with the adapter's discovery census (0-byte
      # skeletons, non-editions → skipped-by-rule; a tree with no ingestible
      # content → unrecognized). unrecognized ≥ 1 is rendered loudly, with its
      # notes, so a silent-ingestion gap can never hide again.
      def print_discovery_accounting(outcome)
        report = outcome.load_report
        discovery = outcome.discovery
        return unless report && discovery
        # A kind: module discovers nothing by invariant — "0 selected" is
        # the same document-grain noise the summary line suppresses.
        return if outcome.module_delta

        selected = report.added + report.updated + report.skipped
        skipped = report.skipped_by_rule + discovery.skipped_by_rule
        # A collided document (P39-4) was discovered but rejected keep-first, so
        # it belongs in the loud not-ingested bucket, never among the selected.
        unrecognized = report.errored + report.collided + discovery.unrecognized
        say("  discovery: #{selected} selected · #{skipped} skipped-by-rule · " \
            "#{unrecognized} unrecognized", unrecognized.positive? ? :yellow : nil)
        discovery.notes.each { |note| say("  ! #{note}", :yellow) }
      end

      def format_sync_outcome(outcome)
        # A kind: module row holds zero documents by invariant — its line
        # reports what moved instead (format_module_sync_outcome).
        return format_module_sync_outcome(outcome) if outcome.module_delta

        # P43-i1: an id-sweep fetch (trismegistos) has no single content
        # sha — its FetchReport carries sha: nil honestly. Render the
        # report's presence, not a sliced nil.
        fetched = if outcome.fetch_report
                    outcome.fetch_report.sha ? outcome.fetch_report.sha[0, 12] : "fetched"
                  else
                    "parse-only"
                  end
        report = outcome.load_report
        # --fetch-only: no load ran — say so instead of rendering nil counts.
        return "#{outcome.slug.ljust(24)} #{fetched}  parse+load deferred (fetch-only)" if report.nil?

        "#{outcome.slug.ljust(24)} #{fetched}  " \
          "+#{report.added} added  ~#{report.updated} updated  " \
          "=#{report.skipped} skipped  -#{report.withdrawn} withdrawn  !#{report.errored} errored" \
          "#{format_collided(report)}#{format_sync_dictionary_lane(outcome.dictionary_lane)}" \
          "#{format_sync_indexed(outcome)}#{format_sync_references(outcome.references)}" \
          "#{format_sync_enrichments(outcome.enrichments)}#{format_sync_place_index(outcome.place_index)}" \
          "#{format_sync_person_index(outcome.person_index)}#{format_sync_lect_staging(outcome.lect_staging)}"
      end

      # The kind: module summary line: the document counters suppressed
      # (a module mints none, so "+0 added" was noise), replaced by the ref
      # movement, the changed files (capped, honest count), and the seam
      # census with its delta where the module's seam has one
      # (Nabu::ModuleCensus). A census-less module moved shows its file
      # list alone — never fake zeros.
      def format_module_sync_outcome(outcome)
        delta = outcome.module_delta
        parts = [outcome.slug.ljust(24), module_ref_movement(delta)]
        changed = delta.changed
        parts << " #{module_changed_files(changed)}" if changed && !changed.empty?
        if delta.census && !delta.census.empty?
          parts << " #{Nabu::ModuleCensus.render(delta.census, previous: delta.previous_census)}"
        end
        parts.join(" ")
      end

      def module_ref_movement(delta)
        width = Nabu::ModuleCensus::SHA_WIDTH
        before = delta.before&.slice(0, width)
        after = delta.after&.slice(0, width)
        return before ? "parse-only at #{before}" : "parse-only" unless delta.fetched
        return "fetched" if after.nil?
        return (delta.held_before ? "fetched at #{after}" : "cloned at #{after}") if before.nil?
        return "unchanged at #{after}" if delta.before == delta.after

        "#{before}..#{after}"
      end

      def module_changed_files(paths)
        shown = paths.first(MODULE_CHANGED_SHOWN).join(", ")
        more = paths.size > MODULE_CHANGED_SHOWN ? " +#{paths.size - MODULE_CHANGED_SHOWN} more" : ""
        "#{paths.size} #{paths.size == 1 ? 'file' : 'files'} changed: #{shown}#{more}"
      end

      # P99-5 (the P59-4 front-door bullet): the synced source's
      # unstaged share — visible at exactly the moment new documents
      # arrive. Silent when nil (no registry / nothing stageable) or
      # fully staged (the compact-zero rule).
      def format_sync_lect_staging(census)
        return "" if census.nil? || census.unstaged.zero?

        "  lect: #{commafy(census.unstaged)}/#{commafy(census.stageable)} " \
          "unstaged (#{census.codes.join(', ')})"
      end

      # P104-4: the secondary dictionary lane's tail — silent for every
      # lane-less source (nil); entry-grained, compact (zero components
      # suppressed, house style), so the primary document counts and the
      # lane's entry counts never blur into one number.
      def format_sync_dictionary_lane(report)
        return "" if report.nil?

        parts = []
        parts << "+#{report.added}" if report.added.positive?
        parts << "~#{report.updated}" if report.updated.positive?
        parts << "=#{report.skipped}" if report.skipped.positive?
        parts << "-#{report.withdrawn}" if report.withdrawn.positive?
        parts << "!#{report.errored}" if report.errored.positive?
        "  dict #{parts.empty? ? '0' : parts.join(' ')} entries"
      end

      # P26-5: syncs index incrementally, so the count is the SOURCE's live
      # passage rows — "indexed 17942 passages (corph)" — never the corpus
      # total (which would imply work that no longer happens). Suppressed for
      # index-inert shelves (indexed nil — no index work at all) and for
      # zero-passage grains like dictionaries (compact zero-field rule).
      def format_sync_indexed(outcome)
        return "" if outcome.indexed.nil? || outcome.indexed.zero?

        "  indexed #{outcome.indexed} passages (#{outcome.slug})"
      end

      # P19-4: the reference-edge tail for a local-shelf sync — silent when
      # the source mints no reference edges (references nil), compact
      # otherwise (zero counts suppressed, house style).
      def format_sync_references(refs)
        return "" if refs.nil?

        parts = []
        parts << "+#{refs.edges_written}" if refs.edges_written.positive?
        parts << "~#{refs.edges_refreshed}" if refs.edges_refreshed.positive?
        parts << "-#{refs.superseded_edges}" if refs.superseded_edges.positive?
        # P43-i1: producers that census unknown upstream ids say so — a
        # third of the first TM sweep was "not in our database", and a
        # silent zero would misread as full coverage.
        parts << "?#{refs.unknown_ids} unknown upstream" if refs.respond_to?(:unknown_ids) && refs.unknown_ids.positive?
        counts = parts.empty? ? "0" : parts.join(" ")
        "  refs #{counts}"
      end

      # P44-7: the meter-enrichment tail for a pedecerto sync — silent when the
      # source mints no enrichments (nil). The HONEST CENSUS the packet demands:
      # matched vs unmatched LINES (unmatched = works we do not hold or citation
      # mismatches), never hidden. "meter 41 lines matched, 12 unmatched (2 works)".
      def format_sync_enrichments(enr)
        return "" if enr.nil?

        works = enr.mapped_works + enr.unmapped_works
        "  meter #{enr.matched} lines matched, #{enr.unmatched} unmatched " \
          "(#{plural(enr.mapped_works, 'work')} of #{works})#{format_malformed_files(enr.malformed_files)}"
      end

      # P45-6: the place-index tail for a pleiades sync — silent for every
      # source that derives no place index (nil, including a pleiades
      # parse-only sync before the first fetch). "place index 42242 places
      # derived (3.1s)".
      def format_sync_place_index(census)
        return "" if census.nil?

        parts = []
        parts << "place index #{census.places} places" if census.places
        # The tm→pleiades crosswalk rides the edh/pleiades producers
        # (Nabu::TmPleiadesCrosswalk) — "crosswalk 8401 tm→pleiades pairs".
        if census.respond_to?(:crosswalk_pairs) && census.crosswalk_pairs
          parts << "crosswalk #{census.crosswalk_pairs} tm→pleiades pairs"
        end
        "  #{parts.join(' + ')} derived (#{format('%.1f', census.seconds)}s)"
      end

      # P97-2: the person-index tail — silent for every source deriving
      # no persons. "person index 661351 persons derived (41.2s)".
      def format_sync_person_index(census)
        return "" if census.nil?

        "  person index #{census.persons} persons derived (#{format('%.1f', census.seconds)}s)"
      end

      # The P44-i3b honesty tail: unreadable upstream files are named (the
      # status-footer idiom — a bare count is a guessing game), first three
      # outright, the rest as a count.
      def format_malformed_files(names)
        return "" if names.empty?

        shown = names.first(3).join(", ")
        more = names.size > 3 ? " +#{names.size - 3} more" : ""
        "; #{names.size} malformed upstream, skipped: #{shown}#{more}"
      end
    end
  end
end
