# frozen_string_literal: true

require "fileutils"

module Nabu
  # The one-shot pre-P71 → P71 layout move (`nabu migrate-local`): instance
  # files that lived under config/ before the local/ elevation (owner-ruled
  # 2026-08-11) move to their local/config/ home. Idempotent; a file already
  # at home is NEVER clobbered — a lingering legacy copy beside a home copy
  # is reported as a conflict for the owner to reconcile by hand (the
  # legacy fallback in Config already prefers the home once it exists).
  module LocalMigration
    # The instance files (Config#instance_path's clientele).
    INSTANCE_FILES = %w[
      grants.yml creep_acceptances.yml link_scopes.yml lect_rulings.yml profile.yml
    ].freeze

    Result = Data.define(:moved, :conflicts)

    module_function

    def run(config:)
      moved = []
      conflicts = []
      INSTANCE_FILES.each do |name|
        legacy = File.join(config.config_dir, name)
        home = File.join(config.local_config_dir, name)
        next unless File.exist?(legacy)

        if File.exist?(home)
          conflicts << name
          next
        end

        FileUtils.mkdir_p(File.dirname(home))
        FileUtils.mv(legacy, home)
        moved << name
      end
      migrate_ledger(config, moved, conflicts)
      Result.new(moved: moved, conflicts: conflicts)
    end

    # P71-1: the ledger (db/history.sqlite3) moves to local/ WITH its live
    # WAL sidecars — the main file alone would be a stale (or, mid-write,
    # torn) snapshot; a home copy is never clobbered. Run this with no
    # nabu process holding the ledger open (the CLI command is standalone).
    def migrate_ledger(config, moved, conflicts)
      name = Config::HISTORY_DB_FILENAME
      legacy = File.join(config.db_dir, name)
      home = File.join(config.local_dir, name)
      return unless File.exist?(legacy)

      if File.exist?(home)
        conflicts << name
        return
      end

      FileUtils.mkdir_p(File.dirname(home))
      ["", "-wal", "-shm"].each do |suffix|
        next unless File.exist?("#{legacy}#{suffix}")

        FileUtils.mv("#{legacy}#{suffix}", "#{home}#{suffix}")
      end
      moved << name
    end
  end
end
