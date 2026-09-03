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
    DEFAULT_LOCAL_DIR = "local"
    DEFAULT_SOURCES_PATH = File.join("config", "sources.yml")
    DEFAULT_ALIGNMENTS_PATH = File.join("config", "alignments.yml")
    DEFAULT_DISPLAY_PATH = File.join("config", "display.yml")
    DEFAULT_PROFILE_PATH = File.join("config", "profile.yml")
    CATALOG_DB_FILENAME = "catalog.sqlite3"
    FULLTEXT_DB_FILENAME = "fulltext.sqlite3"
    VECTORS_DB_FILENAME = "vectors.sqlite3"
    HISTORY_DB_FILENAME = "history.sqlite3"
    LINKS_DB_FILENAME = "links.sqlite3"
    LECTS_DB_FILENAME = "lects.sqlite3"

    attr_reader :canonical_dir, :db_dir, :local_dir, :sources_path, :alignments_path,
                :display_path, :config_path, :backup_target

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
      # P71-0: local/config/settings.yml is the INSTANCE overlay over the
      # committed nabu.yml — box-specific values (backup.target, absolute
      # path overrides) live there, never in the repo. local_dir itself
      # resolves from the BASE file only (no circularity).
      local_dir = resolve((data.fetch("paths", nil) || {})["local"], default: DEFAULT_LOCAL_DIR, root: root)
      data = overlay_settings(data, local_dir)
      paths = data.fetch("paths", nil) || {}
      backup = data.fetch("backup", nil) || {}
      new(
        canonical_dir: resolve(paths["canonical"], default: DEFAULT_CANONICAL_DIR, root: root),
        db_dir: resolve(paths["db"], default: DEFAULT_DB_DIR, root: root),
        local_dir: local_dir,
        sources_path: resolve(paths["sources"], default: DEFAULT_SOURCES_PATH, root: root),
        alignments_path: resolve(paths["alignments"], default: DEFAULT_ALIGNMENTS_PATH, root: root),
        display_path: resolve(paths["display"], default: DEFAULT_DISPLAY_PATH, root: root),
        profile_path: resolve_optional(paths["profile"], root: root),
        config_path: path,
        backup_target: resolve_optional(backup["target"], root: root)
      )
    end

    # Deep-merge local/config/settings.yml over the nabu.yml data (the
    # overlay wins; hashes merge recursively, scalars replace).
    def self.overlay_settings(data, local_dir)
      settings_path = File.join(local_dir, "config", "settings.yml")
      return data unless File.exist?(settings_path)

      deep_merge(data, YAML.safe_load_file(settings_path) || {})
    end
    private_class_method :overlay_settings

    def self.deep_merge(base, overlay)
      base.merge(overlay) do |_key, old, new|
        old.is_a?(Hash) && new.is_a?(Hash) ? deep_merge(old, new) : new
      end
    end
    private_class_method :deep_merge

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
                   local_dir: nil,
                   alignments_path: File.join(File.dirname(sources_path), "alignments.yml"),
                   display_path: File.join(File.dirname(sources_path), "display.yml"),
                   profile_path: nil,
                   backup_target: nil)
      @canonical_dir = canonical_dir
      @db_dir = db_dir
      # P71-0: local/ sits beside config/ at the tree root by default —
      # derived from the config file's own location so it follows a
      # relocated/restored tree (the config_dir pattern).
      @local_dir = local_dir || File.expand_path(File.join("..", DEFAULT_LOCAL_DIR), File.dirname(config_path))
      @sources_path = sources_path
      @alignments_path = alignments_path
      @display_path = display_path
      @profile_path = profile_path
      @config_path = config_path
      @backup_target = backup_target
      @fallback_warned = {}
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

    # The per-source lect resolution overrides (P57-3): config/lect_overrides.yml,
    # NABU-SPECIFIC knowledge about how one particular source uses a code
    # (universal defaults live in the nabu-lects module's own codemap.yml).
    # Derived from config_dir so it follows a relocated/restored tree (the
    # gaiji_dir pattern).
    def lect_overrides_path
      File.join(config_dir, "lect_overrides.yml")
    end

    # The artifact-script rows (P61-3, D60-b): source → code → the
    # ARTIFACT's script where it differs from the held surface, compiled
    # into document_axes by Store::ArtifactScripts.derive!.
    def artifact_scripts_path
      File.join(config_dir, "artifact_scripts.yml")
    end

    # The facet→lect assignment rules (P58-2): owner-ratified document-group
    # rules `nabu lect apply-rules` compiles into the lect journal.
    def lect_facet_rules_path
      File.join(config_dir, "lect_facet_rules.yml")
    end

    # -- P71-0: the overlay-merge pairs (owner-ruled 2026-08-11) ----------
    # Per-source curation stays PROJECT config (git-shared), and a
    # same-named file under local/config/ merges over it functionally —
    # same-key local wins, keyed lists concat with local precedence.
    # Loaders take these pairs in order (later wins); missing files skip.

    def lect_overrides_paths
      overlay_pair("lect_overrides.yml")
    end

    def lect_facet_rules_paths
      overlay_pair("lect_facet_rules.yml")
    end

    def postures_paths
      overlay_pair("postures.yml")
    end

    # The mirror direction (same ruling): lect rulings' HOME is the
    # instance file, and a config/ copy may exist if a per-document
    # ruling is ever publicized — both merge, the instance winning.
    def lect_rulings_paths
      home = lect_rulings_path
      public_copy = File.join(config_dir, "lect_rulings.yml")
      home == public_copy ? [home] : [public_copy, home]
    end

    # The box profile (`nabu enable` state; local/config/ since P71 — it
    # was ALWAYS instance data, gitignored even when it sat in config/).
    # An explicit profile_path (tests, paths.profile) wins verbatim.
    def profile_path
      @profile_path || instance_path("profile.yml")
    end

    # The owner shelves' parent (P71-2): local/shelves/<slug> — the five
    # local-* shelf sources elevated out of canonical/ (slug identity and
    # URNs untouched; only the parent dir moved).
    def shelves_dir
      File.join(local_dir, "shelves")
    end

    # THE workdir resolver (P71-2, the local/ elevation): a local-* shelf
    # source lives under local/shelves/, every other source under
    # canonical/. Loud legacy fallback per shelf while a pre-P71 copy
    # still sits under canonical/ (split-brain beats silent divergence —
    # `nabu migrate-local` moves it).
    def source_workdir(slug)
      return File.join(canonical_dir, slug) unless slug.to_s.start_with?("local-")

      home = File.join(shelves_dir, slug)
      legacy = File.join(canonical_dir, slug)
      return home if Dir.exist?(home) || !Dir.exist?(legacy)

      unless @fallback_warned[slug]
        @fallback_warned[slug] = true
        warn "nabu: the #{slug} shelf still lives under canonical/ (pre-P71 layout) — " \
             "run `nabu migrate-local` to move it under local/shelves/"
      end
      legacy
    end

    # The instance config directory (P71-0, the local/ elevation —
    # owner-ruled 2026-08-11): local/config/ holds everything that makes
    # THIS instance this instance — the owner's rulings, grants, creep
    # acceptances, link scopes, the settings overlay. Never in the public
    # repo; part of the backup's permanent set.
    def local_config_dir
      File.join(local_dir, "config")
    end

    # Grant acknowledgments (P70; local since P71): the SOURCE OF TRUTH
    # for the owner's recorded grant agreements (frozen terms + how) —
    # the ledger row is a historical mirror; restore needs only this file.
    def grants_path
      instance_path("grants.yml")
    end

    # Quarantine-creep acceptances (P70; local since P71): the owner's
    # --accept-creep rulings; the ledger table is historical.
    def creep_acceptances_path
      instance_path("creep_acceptances.yml")
    end

    # Batch-mined link scopes (P70-3b; local since P71): the durable
    # record of the parameterized miners' scopes; rebuild's links stage
    # replays them.
    def link_scopes_path
      instance_path("link_scopes.yml")
    end

    # Per-document owner lect rulings (P70; local since P71): the SOURCE
    # OF TRUTH for hand rulings — `lect assign` writes here first; the
    # journal row is the derived representation; rebuild re-derives the
    # whole journal from this file + rules + infer-dates.
    def lect_rulings_path
      instance_path("lect_rulings.yml")
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

    # The semantic-vector store (P93-4, №R-36; architecture's named home).
    # Lives in db/ but is EXPENSIVE-derived (~22h to regenerate): rebuild
    # deletes the catalog/fulltext files by name and never this one —
    # `nabu embed` maintains it incrementally, keyed (model, urn, text
    # sha), so its rows stay valid across rebuilds by construction.
    def vectors_path
      File.join(db_dir, VECTORS_DB_FILENAME)
    end

    # The history ledger (architecture §5, P7-1). LOCAL-INSTANCE since
    # P71-1 (the local/ elevation): its runs/revisions/pins are the
    # instance's operational history — preserved by the backup's
    # permanent set, not blessed to die — and its move OUT of db/ makes
    # db/ 100% derived by construction. Loud legacy fallback while a
    # pre-P71 copy sits at db/history.sqlite3.
    def history_path
      home = File.join(local_dir, HISTORY_DB_FILENAME)
      legacy = File.join(db_dir, HISTORY_DB_FILENAME)
      return home if File.exist?(home) || !File.exist?(legacy)

      unless @fallback_warned[HISTORY_DB_FILENAME]
        @fallback_warned[HISTORY_DB_FILENAME] = true
        warn "nabu: the ledger still lives at db/#{HISTORY_DB_FILENAME} (pre-P71 layout) — " \
             "run `nabu migrate-local` to move it under local/"
      end
      legacy
    end

    # The links journal (architecture §15, P16-1): batch-mined cross-reference
    # edges. DERIVED since P70: `nabu rebuild`'s links stage wipes and
    # re-mines it (slug-scoped producers from the registry, batch scopes
    # replayed from config/link_scopes.yml), so backups may skip it.
    def links_path
      File.join(db_dir, LINKS_DB_FILENAME)
    end

    # The lect-assignment journal (P58-1): per-document code → lect rulings,
    # the persistence for Nabu::Lects' overlay tier. DERIVED since P70:
    # `nabu rebuild`'s lect-journal stage re-derives it from
    # config/lect_rulings.yml + the compiled rules + infer-dates, so backups
    # may skip it (the two-folder contract keeps every ruling in config/).
    def lects_journal_path
      File.join(db_dir, LECTS_DB_FILENAME)
    end

    private

    def overlay_pair(name)
      [File.join(config_dir, name), File.join(local_config_dir, name)]
    end

    # The instance-file resolution (P71-0): home is local/config/<name>.
    # A pre-P71 box whose file still sits at config/<name> keeps reading
    # AND writing the legacy copy — split-brain (old rulings in config/,
    # new appends in local/) would be strictly worse than the old layout —
    # and the fallback says so out loud, once per file per process,
    # naming the migration command.
    def instance_path(name)
      home = File.join(local_config_dir, name)
      legacy = File.join(config_dir, name)
      return home if File.exist?(home) || !File.exist?(legacy)

      unless @fallback_warned[name]
        @fallback_warned[name] = true
        warn "nabu: #{name} still lives at config/ (pre-P71 layout) — run `nabu migrate-local` " \
             "to move the instance files under local/config/"
      end
      legacy
    end
  end
end
