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
    DEFAULT_ALIGNMENTS_PATH = File.join("config", "alignments.yml")
    DEFAULT_DISPLAY_PATH = File.join("config", "display.yml")
    CATALOG_DB_FILENAME = "catalog.sqlite3"
    FULLTEXT_DB_FILENAME = "fulltext.sqlite3"
    HISTORY_DB_FILENAME = "history.sqlite3"
    LINKS_DB_FILENAME = "links.sqlite3"

    attr_reader :canonical_dir, :db_dir, :sources_path, :alignments_path, :display_path,
                :config_path, :backup_target

    # Build a Config from a YAML file. Relative paths in the file resolve
    # against +root+; absolute paths are used verbatim.
    #
    # Fresh-machine plumbing (P7-2): the config path and root default from the
    # environment (NABU_CONFIG / NABU_ROOT) so an operator restoring onto a new
    # machine can point every `nabu` command at the restored tree without
    # editing code — `NABU_ROOT=/restored NABU_CONFIG=/restored/config/nabu.yml
    # bundle exec bin/nabu rebuild`. Explicit keyword args (the whole test
    # suite, the drill) always win over the environment.
    def self.load(path: env_config_path, root: env_root)
      data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      paths = data.fetch("paths", nil) || {}
      backup = data.fetch("backup", nil) || {}
      new(
        canonical_dir: resolve(paths["canonical"], default: DEFAULT_CANONICAL_DIR, root: root),
        db_dir: resolve(paths["db"], default: DEFAULT_DB_DIR, root: root),
        sources_path: resolve(paths["sources"], default: DEFAULT_SOURCES_PATH, root: root),
        alignments_path: resolve(paths["alignments"], default: DEFAULT_ALIGNMENTS_PATH, root: root),
        display_path: resolve(paths["display"], default: DEFAULT_DISPLAY_PATH, root: root),
        config_path: path,
        backup_target: resolve_optional(backup["target"], root: root)
      )
    end

    def self.env_config_path
      value = ENV.fetch("NABU_CONFIG", nil)
      value.to_s.strip.empty? ? DEFAULT_CONFIG_PATH : value
    end
    private_class_method :env_config_path

    def self.env_root
      value = ENV.fetch("NABU_ROOT", nil)
      value.to_s.strip.empty? ? PROJECT_ROOT : value
    end
    private_class_method :env_root

    def self.resolve(value, default:, root:)
      relative = value.to_s.strip.empty? ? default : value.to_s
      File.expand_path(relative, root)
    end
    private_class_method :resolve

    # A path that stays nil when unset (the backup target has no default — the
    # owner wires the real external-volume destination, or passes --to).
    def self.resolve_optional(value, root:)
      return nil if value.to_s.strip.empty?

      File.expand_path(value.to_s, root)
    end
    private_class_method :resolve_optional

    def initialize(canonical_dir:, db_dir:, sources_path:, config_path:,
                   alignments_path: File.join(File.dirname(sources_path), "alignments.yml"),
                   display_path: File.join(File.dirname(sources_path), "display.yml"),
                   backup_target: nil)
      @canonical_dir = canonical_dir
      @db_dir = db_dir
      @sources_path = sources_path
      @alignments_path = alignments_path
      @display_path = display_path
      @config_path = config_path
      @backup_target = backup_target
    end

    # The directory holding the config files (nabu.yml + sources.yml) — the
    # `config/` section of the backup set (P7-2). Derived from the config file's
    # own location so it follows a restored/relocated tree.
    def config_dir
      File.dirname(config_path)
    end

    # The gaiji resolution maps directory (P37-3): config/gaiji/<source>.tsv,
    # the curated faithful ref→glyph maps the `reading` mode consults. Derived
    # from display.yml's own location so it follows a relocated/restored tree.
    def gaiji_dir
      File.join(File.dirname(display_path), "gaiji")
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

    # The links journal (architecture §15, P16-1): batch-mined cross-reference
    # edges. A function of (canonical, params, code version) — NOT of canonical
    # alone — so, like the ledger, `nabu rebuild` never touches it; unlike the
    # ledger it is cheap to regenerate (a re-mine), so backups may skip it.
    def links_path
      File.join(db_dir, LINKS_DB_FILENAME)
    end
  end
end
