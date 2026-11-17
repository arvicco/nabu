# frozen_string_literal: true

require "yaml"
require_relative "../ops/reconstruction/plan"
require_relative "../ops/reconstruction/verify"

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
    HELP
    option :strict, type: :boolean, default: false, desc: "exit 1 on any drift, miss or gap"
    def verify
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
        homes: Nabu::Ops::Reconstruction::Verify::Homes.from_config(config)
      ).run
      say Nabu::Ops::Reconstruction::Verify.render(result)
      strict = options[:strict]
      raise Thor::Error, "reconstruct verify --strict: drift, misses or gaps (above)" if result.failed?(strict: strict)
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    no_commands do
      def open_readonly(path)
        File.exist?(path) ? Nabu::Store.connect(path, readonly: true) : nil
      end
    end
  end
end
