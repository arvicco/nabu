# frozen_string_literal: true

require "thor"
require_relative "version"

module Nabu
  # Command-line entry point. Only `version` is functional in Phase 0; the
  # ingest/query subcommands are stubs that report "not implemented" and exit 1
  # so scripts and CI can rely on the failure signal before the real work lands.
  class CLI < Thor
    # Raise Thor::Error (rather than aborting the process abruptly) so failures
    # surface a clean stderr message and a non-zero exit status.
    def self.exit_on_failure?
      true
    end

    desc "version", "Print the Nabu version"
    def version
      say Nabu::VERSION
    end

    desc "sync SOURCE", "Fetch and load a source into the store (not yet implemented)"
    def sync(*_args)
      not_implemented!("sync")
    end

    desc "status", "Show per-source sync status and passage counts"
    def status
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      db = open_catalog(config)
      say Nabu::StatusReport.render(registry: registry, db: db)
    ensure
      db&.disconnect
    end

    desc "rebuild", "Rebuild the derived db/ from canonical/ (not yet implemented)"
    def rebuild(*_args)
      not_implemented!("rebuild")
    end

    desc "search QUERY", "Search the corpus (not yet implemented)"
    def search(*_args)
      not_implemented!("search")
    end

    desc "show URN", "Show a passage or document (not yet implemented)"
    def show(*_args)
      not_implemented!("show")
    end

    no_commands do
      def not_implemented!(command)
        raise Thor::Error, "#{command}: not implemented"
      end

      # Open the catalog db for reading if it has been built; nil otherwise so
      # status degrades gracefully to registry-only output.
      def open_catalog(config)
        return nil unless File.exist?(config.catalog_path)

        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.setup!(db)
        db
      end
    end
  end
end
