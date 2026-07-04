# frozen_string_literal: true

require "yaml"

module Nabu
  # The source registry (architecture §5, config/sources.yml): the authoritative
  # list of corpora Nabu knows about — which adapter class ingests each, whether
  # it is enabled, and its sync policy. Parsed and validated up front; adapter
  # classes resolve *lazily* (per entry, on demand) so `nabu status`/listing
  # never require every adapter to be loadable.
  #
  # Split of authority: the registry owns identity + metadata (name, adapter
  # class, license, upstream URL — all from the adapter manifest); the catalog
  # db owns runtime state (enabled, last_sync_*). #sync_source! reconciles the
  # two, writing metadata into the sources row while preserving db-owned state.
  class SourceRegistry
    # Closed set (docs/maintenance-and-extension.md §2): live syncs in `--all`,
    # manual never does, frozen is a one-shot dead-project snapshot.
    SYNC_POLICIES = %w[live manual frozen].freeze
    DEFAULT_SYNC_POLICY = "manual"

    # One registry line. adapter_class_name is a String resolved on demand.
    Entry = Data.define(:slug, :adapter_class_name, :enabled, :sync_policy) do
      # Resolve the adapter constant lazily. A bad/missing class is a
      # configuration error, not a crash: surface it as a ValidationError
      # naming both the class and the source.
      def adapter_class
        Object.const_get(adapter_class_name)
      rescue NameError
        raise ValidationError, "unknown adapter class #{adapter_class_name} for source #{slug}"
      end

      # The adapter's static metadata (Nabu::SourceManifest). Forces
      # resolution of the adapter class.
      def manifest
        adapter_class.manifest
      end

      # Upsert this source's row from slug + manifest. Registry is authoritative
      # for identity/metadata (name, adapter_class, license, license_class,
      # upstream_url) AND for `enabled` — the owner flips enabled in
      # sources.yml with a sign-off comment, and `sync --all` reads the yaml,
      # so the db row mirrors it on every reconcile (revised 2026-07-04; the
      # original db-owns-enabled split left `status` showing stale rows
      # forever). The db stays authoritative for sync history (last_sync_*).
      # Returns the Store::Source row.
      def sync_source!(db)
        attrs = {
          name: manifest.name, adapter_class: adapter_class_name,
          license: manifest.license, license_class: manifest.license_class,
          upstream_url: manifest.upstream_url, enabled: enabled
        }
        db.transaction do
          row = Store::Source.first(slug: slug)
          if row
            # Sequel's #update returns nil when no column actually changed
            # (unchanged re-sync), so return the row itself, not #update's value.
            row.update(attrs)
            next row
          end

          Store::Source.create(**attrs, slug: slug)
        end
      end
    end

    # Parse config/sources.yml at +path+. A missing or empty file is a valid,
    # empty registry. Any structural or per-entry problem raises
    # Nabu::ValidationError naming the offending slug.
    def self.load(path)
      data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      unless data.is_a?(Hash)
        raise ValidationError, "sources registry must be a mapping of slug => entry, got #{data.class}"
      end

      new(data.map { |slug, config| build_entry(slug, config) })
    end

    def self.build_entry(slug, config)
      unless slug.is_a?(String) && slug.match?(Model::Validation::SLUG_SHAPE)
        raise ValidationError, "source #{slug.inspect}: slug must be a lowercase slug ([a-z0-9_-])"
      end
      unless config.is_a?(Hash)
        raise ValidationError, "source #{slug.inspect}: entry must be a mapping, got #{config.class}"
      end

      adapter = config["adapter"]
      unless adapter.is_a?(String) && !adapter.strip.empty?
        raise ValidationError, "source #{slug.inspect}: adapter must be a class-name String, got #{adapter.inspect}"
      end

      Entry.new(
        slug: slug, adapter_class_name: adapter,
        enabled: enabled!(slug, config), sync_policy: sync_policy!(slug, config)
      )
    end
    private_class_method :build_entry

    def self.enabled!(slug, config)
      enabled = config.fetch("enabled", false)
      return enabled if [true, false].include?(enabled)

      raise ValidationError, "source #{slug.inspect}: enabled must be true or false, got #{enabled.inspect}"
    end
    private_class_method :enabled!

    def self.sync_policy!(slug, config)
      policy = config.fetch("sync_policy", DEFAULT_SYNC_POLICY)
      return policy if SYNC_POLICIES.include?(policy)

      raise ValidationError,
            "source #{slug.inspect}: sync_policy must be one of #{SYNC_POLICIES.join(', ')}, got #{policy.inspect}"
    end
    private_class_method :sync_policy!

    def initialize(entries)
      @entries = entries.to_h { |entry| [entry.slug, entry] }
    end

    # Yield each Entry in registration order; returns an Enumerator without a
    # block.
    def each_source(&block)
      return enum_for(:each_source) { @entries.size } unless block

      @entries.each_value(&block)
      self
    end

    def [](slug)
      @entries[slug]
    end

    def slugs
      @entries.keys
    end

    def empty?
      @entries.empty?
    end

    def size
      @entries.size
    end
  end
end
