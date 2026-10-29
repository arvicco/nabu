# frozen_string_literal: true

# Nabu::CLI — operations commands: migrate-local, rebuild, verify, health,
# backup, mcp. Carved out of lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    # A one-time instance migration: hidden from `nabu help` (every box has
    # run it), still callable — the legacy-config refusals name it as the fix.
    desc "migrate-local", "Move the instance files (rulings, grants, profile…) from config/ to local/config/ (P71)",
         hide: true
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

      --http serves the SAME tools over the MCP streamable-HTTP transport
      instead (POST JSON-RPC to /mcp; JSON responses, sessions via the
      Mcp-Session-Id header; no server-initiated SSE stream — see
      Nabu::MCP::HttpTransport for the exact subset). PORT sets the port
      (default 8080), NABU_MCP_HOST the bind address (default 127.0.0.1;
      a container sets 0.0.0.0), NABU_MCP_ALLOWED_ORIGINS extra browser
      origins (loopback origins always pass). Runs until SIGINT/SIGTERM.

      Examples:
        nabu mcp                       # a client spawns this; speaks JSON-RPC on stdio
        nabu mcp --log /tmp/nabu-mcp.log   # tee diagnostics to a file (stdout stays clean)
        PORT=8081 nabu mcp --http      # streamable HTTP on http://127.0.0.1:8081/mcp
    HELP
    option :log, type: :string, banner: "FILE",
                 desc: "Append diagnostics to FILE instead of stderr (stdout is the protocol channel)"
    option :http, type: :boolean, default: false,
                  desc: "Serve the MCP streamable-HTTP transport on POST /mcp instead of stdio " \
                        "(port from PORT, default #{Nabu::MCP::HttpServer::DEFAULT_PORT}; bind address " \
                        "from NABU_MCP_HOST, default #{Nabu::MCP::HttpServer::DEFAULT_HOST})"
    def mcp
      config = Nabu::Config.load
      log = mcp_log(options[:log])
      tools = mcp_tools(config)
      install_mcp_signal_traps
      return serve_mcp_http(tools, log) if options[:http]

      $stdout.sync = true
      # stdout carries protocol only; every diagnostic goes to the log IO.
      Nabu::MCP::Server.new(tools: tools, log: log).run($stdin, $stdout)
    ensure
      log.close if log && !log.equal?($stderr)
    end

    no_commands do
      # The read-only tool layer every MCP transport serves — ONE builder, so
      # stdio and HTTP cannot drift apart (same openers, same watchdog, same
      # license etiquette).
      def mcp_tools(config)
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
          # The mined-layers store rides the same handle (Store::LinkLayers).
          links: Nabu::ReadonlyOpener.new(config.links_path, config.mined_links_path) do
            Nabu::Store::LinkLayers.open_readonly(config)
          end,
          # The vector store, read-only (P93-5): nabu_search's similar_to.
          # Absent file = never embedded (the honest-note state).
          vectors: Nabu::ReadonlyOpener.new(config.vectors_path) do
            Nabu::Store.connect(config.vectors_path, readonly: true)
          end
        }
        Nabu::ReadonlyOpener.watch(openers.values)
        Nabu::MCP::Tools.new(
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
          lect_override_tiers: Nabu::Lects.override_tiers(config.lect_overrides_paths),
          # The facet map (static, loaded once): the token-sense rules behind
          # nabu_search's `sense` desk and nabu_show's `senses` flag.
          facet_map: Nabu::FacetMap.load_default(config: config),
          # The reference-scan anchors (static, loaded once): nabu_define /
          # nabu_show citations of configured print works point at the scan.
          scan_anchors: Nabu::Query::ScanAnchors.load_default(config: config)
        )
      end

      # `nabu mcp --http`: the streamable-HTTP transport (HttpTransport has
      # the spec subset). One Server per session, all over the same tools.
      def serve_mcp_http(tools, log)
        host = Nabu::MCP::HttpServer.host_from(ENV)
        port = Nabu::MCP::HttpServer.port_from(ENV)
        transport = Nabu::MCP::HttpTransport.new(
          server_factory: -> { Nabu::MCP::Server.new(tools: tools, log: log) },
          allowed_origins: Nabu::MCP::HttpServer.allowed_origins_from(ENV), log: log
        )
        listener = Nabu::MCP::HttpServer.listen(host: host, port: port)
        log.puts("nabu-mcp: streamable HTTP on http://#{host}:#{listener.local_address.ip_port}" \
                 "#{Nabu::MCP::HttpTransport::ENDPOINT}")
        Nabu::MCP::HttpServer.new(transport: transport, log: log).run(listener)
      rescue Nabu::Error, SystemCallError => e
        raise Thor::Error, "mcp --http: #{e.message}"
      ensure
        listener&.close
      end
    end

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

    no_commands do
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
          links_journal_path: config.links_path,
          mined_links_path: config.mined_links_path
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
    end
  end
end
