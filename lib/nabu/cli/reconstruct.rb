# frozen_string_literal: true

require "date"
require "yaml"
require_relative "../ops/reconstruction/plan"
require_relative "../ops/reconstruction/verify"
require_relative "../ops/reconstruction/backup_set"
require_relative "../ops/reconstruction/manifest"

# Nabu::CLI — the `nabu reconstruct` subcommand family (ReconstructCLI).
# Carved out of lib/nabu/cli.rb, the registry that loads it.
module Nabu
  # `nabu reconstruct`: the bare-clone story as two read-only desk cards —
  # the ordered bootstrap plan with this box's measured ETAs, and the probe
  # battery a (re)constructed box answers against the published census.
  # Both touch only precompiled data (ledger rows, source_stats, one bounded
  # probe per source); an absent store is an honest "unmeasured", never a scan.
  class ReconstructCLI < Thor
    namespace "reconstruct"

    CAPABILITIES_PATH = File.join(Config::PROJECT_ROOT, "config", "capabilities.yml")
    CENSUS_PATH = File.join(Config::PROJECT_ROOT, "site", "_data", "census.yml")

    desc "plan", "The ordered bootstrap plan from a bare clone, with this box's measured estimates"
    long_desc <<~HELP, wrap: false
      Prints, in order: the tool bootstraps (rake tools:*), the sister/module
      sources (fetched first), every wired source by reconstruction class
      (summed last-sync compute + the unmeasured count; the rail sources'
      cone math at their observed cadence), the owner-fired rebuild (summed
      stage timings) and the enrichment layers (config/capabilities.yml),
      then a headline — and the backup-critical set no step reconstructs:
      local/ (rulings, grants, shelves, the ledger) and atticked bytes.
      Read-only; estimates are approximate and labeled.
    HELP
    def plan
      config = Nabu::Config.load
      ledger = open_readonly(config.history_path)
      classes = Nabu::Ops::Reconstruction::SourceClass.from_config(config)
      report = Nabu::Ops::Reconstruction::Plan.new(
        registry: Nabu::SourceRegistry.load(config.sources_path), verdicts: classes.verdicts, ledger: ledger,
        capabilities: YAML.safe_load_file(CAPABILITIES_PATH), canonical_dir: config.canonical_dir,
        local_dir: config.local_dir, mined_layers: Nabu::Store::MinedLinks.layers_at(config.mined_links_path)
      ).build
      say Nabu::Ops::Reconstruction::Plan.render(report)
    ensure
      ledger&.disconnect
    end

    desc "backupset", "The combined path: the computed set to back up, with the re-sync remainder summed"
    long_desc <<~HELP, wrap: false
      Between a full backup and the bare-clone rebuild sits the practical
      strategy: back up only what is expensive or impossible to re-acquire —
      local/ (the instance), the vectors enrichment, every paced-rail tree,
      every tree whose last re-sync measured at/past the threshold, and the
      attic subtrees of everything else — and re-sync the rest from
      upstream. Prints the set with reasons and sizes, the remainder's
      summed measured compute, and the restore order. Read-only.
    HELP
    option :threshold, type: :numeric, default: 30,
                       desc: "minutes of last-sync time that put a tree in the set"
    option :sizes, type: :boolean, default: true, desc: "size each entry with du (skip for an instant card)"
    def backupset
      config = Nabu::Config.load
      ledger = open_readonly(config.history_path)
      classes = Nabu::Ops::Reconstruction::SourceClass.from_config(config)
      result = Nabu::Ops::Reconstruction::BackupSet.new(
        registry: Nabu::SourceRegistry.load(config.sources_path), verdicts: classes.verdicts, ledger: ledger,
        canonical_dir: config.canonical_dir, local_dir: config.local_dir, vectors_path: config.vectors_path,
        threshold: (options[:threshold] * 60).to_i, sizes: options[:sizes]
      ).build
      say Nabu::Ops::Reconstruction::BackupSet.render(result)
    ensure
      ledger&.disconnect
    end

    desc "verify", "Probe the live library against the published census: counts, presence, FTS canaries, homes"
    long_desc <<~HELP, wrap: false
      Four read-only probes: the census diff (live documents, passages,
      language codes and live sources vs site/_data/census.yml — drift is
      expected when the library moved since the stamp), per-source presence,
      one FTS canary per live source (a deterministic sample passage probed
      in the index by its own rowid — loaded-but-unsearchable is the
      failure it catches), and every MCP tool's data homes on disk.
      Exits 0; --strict exits 1 on any drift, empty source, canary miss
      or missing home.

      --against MANIFEST verifies against a reference box's manifest
      (schema 1) instead of the census: per-source counts (carried trees
      must match exactly; resynced trees may drift), the manifest's own
      canaries resolved by urn, and the reference census. With --strict,
      only failure-class findings exit 1 (carried mismatch, missing
      source, failing canary, missing home) — never resynced drift.
    HELP
    option :strict, type: :boolean, default: false, desc: "exit 1 on any drift, miss or gap"
    option :against, type: :string, banner: "MANIFEST", desc: "verify against a reference box's manifest"
    def verify
      manifest = load_against_manifest(options[:against])
      config = Nabu::Config.load
      unless File.exist?(config.catalog_path)
        say "reconstruct verify: no catalog at #{config.catalog_path} — a bare clone; sync, then rebuild, then verify"
        return
      end

      catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
      fulltext = File.exist?(config.fulltext_path) ? Nabu::Store.connect(config.fulltext_path, readonly: true) : nil
      result = Nabu::Ops::Reconstruction::Verify.new(
        registry: Nabu::SourceRegistry.load(config.sources_path), catalog: catalog, fulltext: fulltext,
        census_path: CENSUS_PATH, capabilities: YAML.safe_load_file(CAPABILITIES_PATH),
        homes: Nabu::Ops::Reconstruction::Verify::Homes.from_config(config), against: manifest
      ).run
      say Nabu::Ops::Reconstruction::Verify.render(result)
      strict = options[:strict]
      raise Thor::Error, "reconstruct verify --strict: drift, misses or gaps (above)" if result.failed?(strict: strict)
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "manifest", "The portable reference manifest: census, per-source canaries, carried-tree digests"
    long_desc <<~HELP, wrap: false
      Prints (or writes with --out) the schema-1 reference manifest a second
      box proves its arrival against: the git commit and date, the census,
      every live public source's transport (carried in the backup set, or
      resynced), counts and its verify canary, and a content digest of every
      backup-set path. The manifest is PRIVATE (it names access-gated
      holdings) — write it outside the repo tree. Digesting reads every
      carried byte; --no-trees skips it for an instant manifest.
    HELP
    option :out, type: :string, desc: "write the manifest here instead of stdout"
    option :trees, type: :boolean, default: true, desc: "digest the backup-set trees (reads every carried byte)"
    def manifest
      config = Nabu::Config.load
      unless File.exist?(config.catalog_path)
        raise Thor::Error, "reconstruct manifest: no catalog at #{config.catalog_path} — nothing to describe"
      end

      catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
      ledger = open_readonly(config.history_path)
      registry = Nabu::SourceRegistry.load(config.sources_path)
      set = Nabu::Ops::Reconstruction::BackupSet.new(
        registry: registry, verdicts: Nabu::Ops::Reconstruction::SourceClass.from_config(config).verdicts,
        ledger: ledger, canonical_dir: config.canonical_dir, local_dir: config.local_dir,
        vectors_path: config.vectors_path, sizes: false
      ).build
      manifest = Nabu::Ops::Reconstruction::Manifest.new(
        registry: registry, catalog: catalog, entry_paths: set.entries.map(&:path), root: Config::PROJECT_ROOT,
        canonical_dir: config.canonical_dir, trees: options[:trees], as_of: Date.today.iso8601,
        commit: Nabu::Shell.run("git", "-C", Config::PROJECT_ROOT, "rev-parse", "HEAD").strip
      ).build
      if options[:out]
        Nabu::Ops::Reconstruction::Manifest.write(manifest, options[:out])
        say "reconstruct manifest: wrote #{options[:out]} (private — keep it out of the repo tree)"
      else
        say Nabu::Ops::Reconstruction::Manifest.render(manifest)
      end
    ensure
      catalog&.disconnect
      ledger&.disconnect
    end

    desc "check MANIFEST", "Re-digest a manifest's carried trees here: did the transported bytes arrive intact?"
    long_desc <<~HELP, wrap: false
      Loads a reference manifest (reconstruct manifest --out) and re-digests
      each trees[] path under --root (default: the project root), comparing
      bytes and sha256. One line per tree — ok / MISMATCH / ABSENT — and a
      nonzero exit on any mismatch or absence. Read-only.
    HELP
    option :root, type: :string, desc: "the tree the manifest's paths resolve against (default: the project root)"
    def check(path)
      manifest = Nabu::Ops::Reconstruction::Manifest.load(path)
      rows = Nabu::Ops::Reconstruction::Manifest.check(manifest, root: options[:root] || Config::PROJECT_ROOT)
      say Nabu::Ops::Reconstruction::Manifest.render_check(rows, reference: manifest["reference"])
      bad = rows.count { |row| row.status != :ok }
      raise Thor::Error, "reconstruct check: #{bad} tree(s) mismatched or absent (above)" if bad.positive?
    end

    no_commands do
      def open_readonly(path)
        File.exist?(path) ? Nabu::Store.connect(path, readonly: true) : nil
      end

      def load_against_manifest(path)
        return nil if path.nil?

        Nabu::Ops::Reconstruction::Verify.load_manifest(path)
      rescue Nabu::Ops::Reconstruction::Verify::ManifestError => e
        raise Thor::Error, "reconstruct verify --against: #{e.message}"
      end
    end
  end
end
