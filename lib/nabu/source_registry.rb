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
  # class, license, upstream URL — all from the adapter manifest) AND
  # enablement (revised 2026-07-04; re-affirmed P23-3b: status/list/MCP read
  # `enabled` from the registry directly, since the db row only mirrors a
  # sources.yml flip at the source's next sync); the catalog db owns sync
  # history (last_sync_*). #sync_source! reconciles the two, writing metadata
  # + enabled into the sources row while preserving db-owned state.
  class SourceRegistry
    # Closed set (docs/maintenance-and-extension.md §2): live syncs in `--all`,
    # manual never does, frozen is a one-shot dead-project snapshot, and
    # local (P19-1, architecture §16) has NO upstream at all — no network,
    # ever; sync re-scans the canonical tree (LocalFetch), the drift probe
    # short-circuits to a frozen-style "local" verdict, and the license comes
    # from the shelf's own manifest/data, never from a fetched file.
    SYNC_POLICIES = %w[live manual frozen local].freeze
    DEFAULT_SYNC_POLICY = "manual"

    # One registry line. adapter_class_name is a String resolved on demand.
    # +translations+ (P7-4): per-source opt-in to ingesting parallel
    # translations (default false — corpora stay original-only unless the
    # owner flips it in sources.yml). +license_watch+ (P16-5): an optional
    # URL whose body the remote probe hash-compares against the pin baseline
    # — the license-drift check for upstreams whose terms live in a README
    # or a repository record page rather than a github LICENSE file (nil =
    # not watched; the probe's default per-strategy check applies).
    # +fuzzy_index+ (P16-4): per-source opt-in to the trigram fragment index
    # (search --fuzzy). This is an OWNER POSTURE, not adapter metadata: the
    # documentary scope exists because of index economics (design §4: the
    # documentary shelves cost ~250–270 MB, the whole corpus 3.6–4.1 GB), so
    # the flag lives here beside enabled/translations — flipped per-source in
    # sources.yml with a sign-off comment, no code change when a future
    # documentary source (inscriptions) joins. A manifest field was rejected
    # (the manifest is intrinsic upstream identity/license, and editing it IS
    # code spelunking); a constant was rejected by the design itself ("a
    # config list, not a hardcode").
    Entry = Data.define(:slug, :adapter_class_name, :enabled, :sync_policy, :translations,
                        :license_watch, :fuzzy_index) do
      def initialize(slug:, adapter_class_name:, enabled:, sync_policy:, translations: false,
                     license_watch: nil, fuzzy_index: false)
        super
      end

      # Resolve the adapter constant lazily. A bad/missing class is a
      # configuration error, not a crash: surface it as a ValidationError
      # naming both the class and the source.
      def adapter_class
        Object.const_get(adapter_class_name)
      rescue NameError
        raise ValidationError, "unknown adapter class #{adapter_class_name} for source #{slug}"
      end

      # Construct the adapter this entry configures — THE construction seam
      # for sync/rebuild/verify, so every pipeline agrees on the flag. Flag
      # off (the default) is the plain no-arg construction every adapter
      # supports; flag on passes `translations: true`, and an adapter without
      # that keyword is a configuration error naming source and class, not an
      # ArgumentError crash.
      def build_adapter
        return adapter_class.new unless translations

        begin
          adapter_class.new(translations: true)
        rescue ArgumentError
          raise ValidationError, "source #{slug}: adapter #{adapter_class_name} does not support " \
                                 "`translations: true` (no translations: keyword on its initializer)"
        end
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
        enabled: enabled!(slug, config), sync_policy: sync_policy!(slug, config),
        translations: boolean!(slug, config, "translations"),
        license_watch: license_watch!(slug, config),
        fuzzy_index: boolean!(slug, config, "fuzzy_index")
      )
    end
    private_class_method :build_entry

    # nil (not watched) or an absolute http(s) URL String — anything else is
    # a configuration error naming the slug, caught at load, not probe time.
    def self.license_watch!(slug, config)
      url = config.fetch("license_watch", nil)
      return nil if url.nil?
      return url if url.is_a?(String) && url.match?(%r{\Ahttps?://\S+\z})

      raise ValidationError,
            "source #{slug.inspect}: license_watch must be an http(s) URL, got #{url.inspect}"
    end
    private_class_method :license_watch!

    def self.enabled!(slug, config)
      boolean!(slug, config, "enabled")
    end
    private_class_method :enabled!

    def self.boolean!(slug, config, key)
      value = config.fetch(key, false)
      return value if [true, false].include?(value)

      raise ValidationError, "source #{slug.inspect}: #{key} must be true or false, got #{value.inspect}"
    end
    private_class_method :boolean!

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

    # Slugs opted into the trigram fragment index (search --fuzzy, P16-4) —
    # what the Indexer scopes its trigram pass to. Registration order.
    def fuzzy_slugs
      @entries.each_value.select(&:fuzzy_index).map(&:slug)
    end

    def empty?
      @entries.empty?
    end

    def size
      @entries.size
    end
  end
end
