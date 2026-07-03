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

    attr_reader :canonical_dir, :db_dir, :config_path

    # Build a Config from a YAML file. Relative paths in the file resolve
    # against +root+; absolute paths are used verbatim.
    def self.load(path: DEFAULT_CONFIG_PATH, root: PROJECT_ROOT)
      data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      paths = data.fetch("paths", nil) || {}
      new(
        canonical_dir: resolve(paths["canonical"], default: DEFAULT_CANONICAL_DIR, root: root),
        db_dir: resolve(paths["db"], default: DEFAULT_DB_DIR, root: root),
        config_path: path
      )
    end

    def self.resolve(value, default:, root:)
      relative = value.to_s.strip.empty? ? default : value.to_s
      File.expand_path(relative, root)
    end
    private_class_method :resolve

    def initialize(canonical_dir:, db_dir:, config_path:)
      @canonical_dir = canonical_dir
      @db_dir = db_dir
      @config_path = config_path
    end
  end
end
