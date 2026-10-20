# frozen_string_literal: true

# Nabu::CLI — the `nabu layer` subcommand family (LayerCLI). Carved out of
# lib/nabu/cli.rb, the registry that loads it.
module Nabu
  # `nabu layer` (P61-2): the core-layers front door. One command today —
  # the generalized suggest census (lect + dating + places + script
  # sections, all rendered by LectCLI#suggest, which `nabu lect suggest`
  # keeps aliasing). New layer-wide commands land here, not on LectCLI.
  class LayerCLI < Thor
    namespace "layer"

    desc "suggest SLUG", "The core-layers census: lect, dating, places and script postures in one report"
    def suggest(slug = nil)
      LectCLI.new.suggest(slug)
    end

    desc "dates SLUG", "Re-project one source's metadata-dates timeline lane from the catalog (idempotent)"
    long_desc <<~HELP, wrap: false
      Drops and re-projects the source's document_axes rows through
      Store::TimelineBuilder::MetadataDates — the same projection every
      sync and rebuild runs, callable alone so a newly registered shape
      reaches an ALREADY-LOADED source without re-parsing it (P92-6:
      okhc's 490k year rows project in one catalog pass, not a 1.2M-doc
      re-parse). The source must be registered in MetadataDates::SHAPES.
    HELP
    def dates(slug)
      config = Nabu::Config.load
      raise Thor::Error, "layer dates: no catalog at #{config.catalog_path}" unless File.exist?(config.catalog_path)
      unless Nabu::Store::TimelineBuilder::MetadataDates::SHAPES.key?(slug)
        raise Thor::Error, "layer dates: #{slug} is not registered in MetadataDates::SHAPES"
      end

      begin
        Nabu::Store.assert_writable!(config.catalog_path)
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      end

      catalog = Nabu::Store.connect(config.catalog_path)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rows = Nabu::Store::TimelineBuilder::MetadataDates.refresh_source!(catalog: catalog, slug: slug,
                                                                         canonical_dir: config.canonical_dir)
      say "metadata-dates lane (#{slug}): #{rows} rows projected " \
          "(#{format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)})"
    ensure
      catalog&.disconnect
    end

    desc "artifacts", "Re-derive the artifact-script lane from config/artifact_scripts.yml (idempotent)"
    long_desc <<~HELP, wrap: false
      Compiles the owner-ruled artifact-script rows (source → code → the
      ARTIFACT's script where it differs from the held surface, D60-b) into
      document_axes under the "artifact-script" lane — wholesale supersede,
      a pure function of stored codes + config, also re-derived by rebuild.
    HELP
    def artifacts
      config = Nabu::Config.load
      raise Thor::Error, "layer artifacts: no catalog at #{config.catalog_path}" unless File.exist?(config.catalog_path)

      begin
        Nabu::Store.assert_writable!(config.catalog_path)
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      end

      catalog = Nabu::Store.connect(config.catalog_path)
      report = Nabu::Store::ArtifactScripts.derive!(
        catalog, config_path: config.artifact_scripts_path,
                 registry: Nabu::Lects.load_default(config: config)
      )
      say "artifact-script lane: #{report.minted} rows (#{report.sources.join(', ')})"
    ensure
      catalog&.disconnect
    end
  end
end
