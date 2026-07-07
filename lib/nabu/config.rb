# frozen_string_literal: true

require "yaml"

module Nabu
  # Loads runtime configuration from config/nabu.yml. Every key is optional;
  # missing keys (or a missing file) fall back to project-relative defaults so
  # a fresh checkout works with no configuration at all.
  #
  #   config = Nabu::Config.load
  #   config.canonical_dir  # => "<project>/canonical"
  #   config.db_dir         # => "<project>/db"
  class Config
    # Project root: two levels up from lib/nabu/config.rb.
    PROJECT_ROOT = File.expand_path("../..", __dir__)
    DEFAULT_CONFIG_PATH = File.join(PROJECT_ROOT, "config", "nabu.yml")

    DEFAULT_CANONICAL_DIR = "canonical"
    DEFAULT_DB_DIR = "db"
    DEFAULT_SOURCES_PATH = File.join("config", "sources.yml")
    CATALOG_DB_FILENAME = "catalog.sqlite3"
    FULLTEXT_DB_FILENAME = "fulltext.sqlite3"
    HISTORY_DB_FILENAME = "history.sqlite3"

    attr_reader :canonical_dir, :db_dir, :sources_path, :config_path

    # Build a Config from a YAML file. Relative paths in the file resolve
    # against +root+; absolute paths are used verbatim.
    def self.load(path: DEFAULT_CONFIG_PATH, root: PROJECT_ROOT)
      data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      paths = data.fetch("paths", nil) || {}
      new(
        canonical_dir: resolve(paths["canonical"], default: DEFAULT_CANONICAL_DIR, root: root),
        db_dir: resolve(paths["db"], default: DEFAULT_DB_DIR, root: root),
        sources_path: resolve(paths["sources"], default: DEFAULT_SOURCES_PATH, root: root),
        config_path: path
      )
    end

    def self.resolve(value, default:, root:)
      relative = value.to_s.strip.empty? ? default : value.to_s
      File.expand_path(relative, root)
    end
    private_class_method :resolve

    def initialize(canonical_dir:, db_dir:, sources_path:, config_path:)
      @canonical_dir = canonical_dir
      @db_dir = db_dir
      @sources_path = sources_path
      @config_path = config_path
    end

    # The catalog SQLite file (architecture §5), derived from db_dir.
    def catalog_path
      File.join(db_dir, CATALOG_DB_FILENAME)
    end

    # The FTS5 fulltext index (architecture §2: "one SQLite file per concern").
    # Separate from the catalog on purpose — the catalog is small and precious,
    # the index is derived-of-derived and rebuilt at will.
    def fulltext_path
      File.join(db_dir, FULLTEXT_DB_FILENAME)
    end

    # The history ledger (architecture §5, P7-1): runs, pins, license
    # baselines, durable revisions. NOT derived from canonical/ — the one db
    # under db/ that `nabu rebuild` never touches and backups must include.
    def history_path
      File.join(db_dir, HISTORY_DB_FILENAME)
    end
  end
end
