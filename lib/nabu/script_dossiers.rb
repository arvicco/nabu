# frozen_string_literal: true

require "yaml"

module Nabu
  # The per-script curated dossiers (config/script_dossiers.yml, P86-4c) —
  # the human-written context beneath a script's mechanical identity: what
  # the writing system is, and how THIS library's shelves hold it. Keys are
  # the registry's script tags; the suite guard pins the two tables to
  # agree exactly (tags AND display names), so a nabu-lects mint without a
  # dossier turns the suite red — the drift-guard family.
  #
  # Published as nabu-data `mul/script-dossiers` (the wylie-fold pattern:
  # this file is the source of truth, the dataset is its public mirror);
  # the card reads THIS file, so a fresh install answers identically.
  module ScriptDossiers
    PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "script_dossiers.yml")

    # One script's curated layer. +desk+ (how our shelves hold it) is nil
    # where nothing shelf-specific applies.
    Dossier = Data.define(:tag, :name, :context, :desk)

    # The whole table, memoized per path: tag => raw row hash.
    def self.table(path: PATH)
      (@table ||= {})[path] ||= YAML.safe_load_file(path)
    end

    def self.reset! = (@table = nil)

    # +tag+ is the registry's lowercased script tag ("runr"); an ISO 15924
    # spelling ("Runr") folds. nil when no dossier exists.
    def self.lookup(tag, path: PATH)
      row = table(path: path)[tag.to_s.downcase] or return nil
      Dossier.new(tag: tag.to_s.downcase, name: row.fetch("name"),
                  context: row.fetch("context").strip, desk: row["desk"]&.strip)
    end
  end
end
