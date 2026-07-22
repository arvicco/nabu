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
    # Closed set (docs/maintenance-and-extension.md §2), the honest CADENCE
    # vocabulary (P39-0): `auto` is swept by `sync --all` (the perseus/first1k
    # pair — continuously-updated upstreams); `manual` is owner-fired by name
    # (size/pacing — the upstream may be very much alive, we just pull it on
    # purpose); `frozen` is a dead-project / immutable snapshot. The old `live`
    # value became `auto`; the old `local` value is GONE — a no-upstream shelf
    # is now `kind: shelf` (below), which IMPLIES the local fetch strategy.
    SYNC_POLICIES = %w[auto manual frozen].freeze
    DEFAULT_SYNC_POLICY = "manual"

    # The registry KINDS (P39-0): what a row IS. The 84-row registry conflated
    # three natures under one `sync_policy` key; kind separates them.
    #   source (default, may be omitted) — a text/reference corpus that mints
    #     catalog rows and declares a sync_policy cadence.
    #   shelf — an owner-authored, gateway-written local MEMORY shelf (the four
    #     local-* rows): no network, the local fetch strategy, up=local. kind
    #     IMPLIES the local fetch, so a shelf row declares NO sync_policy.
    #   module — MACHINERY only (kr-gaiji, bridging): a sanctioned fetch that
    #     mints ZERO catalog rows, so there is nothing to serve or enable
    #     (enabled: false is required) and nothing for `sync --all` to sweep.
    KINDS = %w[source shelf module].freeze
    DEFAULT_KIND = "source"

    # The `siblings:` marker for the CTS dotted-version form (P34-0): the
    # source mints urn:cts documents whose editions share a work prefix and
    # differ in the trailing dotted version token. Non-CTS sources declare a
    # LIST of variant-tail patterns instead (see siblings! below).
    CTS_SIBLINGS = "cts"

    # The lemma-index tiers (P26-0). ABSENT = gold — every adapter that
    # existed before the tier did keeps its meaning with zero registry churn;
    # a source whose lemmatization is AUTOMATIC (Diorisis-style) declares
    # `lemma_tier: silver` and its passage_lemmas rows carry the label all
    # the way to the render (attested_count stays gold-only everywhere).
    # "equivalence" (P34-3, owner-decided): scholar-curated CROSS-LANGUAGE
    # equivalence — CEIPoM's Classical-Latin-equivalent column minting Latin
    # keys on non-Latin passages. A different honesty from silver (silver
    # means upstream-automatic; this is curated, but it is not attestation
    # in the key's language either), so it is its own label at every render
    # and --gold-only excludes it like any non-gold tier.
    LEMMA_TIERS = %w[gold silver equivalence].freeze
    DEFAULT_LEMMA_TIER = "gold"

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
    # +lemma_tier+ (P26-0): the tier this source's lemma annotations enter the
    # passage_lemmas index under (LEMMA_TIERS; default gold — absent means
    # gold, so existing entries never change).
    # +classes+ (P33-0): the acquisition scope of a many-repo source
    # (kanripo `classes: [KR1, KR3, KR4]`) — an owner posture like
    # enabled/translations, passed to the adapter's `classes:` keyword by
    # build_adapter. nil (the default) leaves the adapter's own default
    # scope; the adapter validates the class vocabulary.
    # +siblings+ (P34-0): the `--parallel` work-pattern declaration — HOW
    # this source's sibling documents spell their variant suffixes. Either
    # CTS_SIBLINGS (the dotted-version form) or a list of "-"-leading tail
    # patterns (`["-en"]`, `["-(eng|ita|dipl)"]`, `["-[a-z]+"]`), each a
    # regex fragment anchored by the compiler (Query::SiblingFamilies).
    # nil (the default) = the source mints no parallel siblings. Declaring
    # a tail is a CENSUS CLAIM: no upstream document id may end in it —
    # the per-source freeze the retired regex constants used to encode.
    # +axes+ (P35-0): the source's research-axis memberships — a non-empty
    # list of names defined in config/axes.yml (AxisRegistry), validated at
    # load. Axes are TAGS (multi-membership deliberate, whole-source grain);
    # once a definitions file exists EVERY source must declare >= 1, and an
    # axis name may never equal a source slug (the resolution guarantee for
    # `nabu sync <axis>` / `list --axis`, P35-1/2). [] only in bootstrap/
    # test mode (no axes.yml beside the sources file).
    # +kind+ (P39-0): the row's nature (KINDS; default source). shelf/module
    # carry a sync_policy internally only for uniform construction — it is
    # never rendered or swept for them (enablement + cadence are moot; the
    # up= column reads structurally as local/module).
    Entry = Data.define(:slug, :adapter_class_name, :enabled, :sync_policy, :kind, :translations,
                        :license_watch, :fuzzy_index, :lemma_tier, :classes, :siblings, :axes) do
      def initialize(slug:, adapter_class_name:, enabled:, sync_policy:, kind: DEFAULT_KIND,
                     translations: false, license_watch: nil, fuzzy_index: false,
                     lemma_tier: DEFAULT_LEMMA_TIER, classes: nil, siblings: nil, axes: [])
        super
      end

      # kind predicates (P39-0). shelf? drives the local fetch strategy (no
      # network, up=local) at the probe, status, and health-integrity seams;
      # feature_module? is machinery-only (up=module, no holdings, no sweep).
      def shelf? = kind == "shelf"
      def feature_module? = kind == "module"
      def source? = kind == "source"

      # Resolve the adapter constant lazily. A bad/missing class is a
      # configuration error, not a crash: surface it as a ValidationError
      # naming both the class and the source.
      def adapter_class
        Object.const_get(adapter_class_name)
      rescue NameError
        raise ValidationError, "unknown adapter class #{adapter_class_name} for source #{slug}"
      end

      # Construct the adapter this entry configures — THE construction seam
      # for sync/rebuild/verify, so every pipeline agrees on the flags. All
      # flags off (the default) is the plain no-arg construction every
      # adapter supports; `translations: true` and a `classes:` list pass as
      # keywords, and an adapter without the keyword is a configuration
      # error naming source and class, not an ArgumentError crash.
      def build_adapter
        kwargs = {}
        kwargs[:translations] = true if translations
        kwargs[:classes] = classes if classes
        return adapter_class.new if kwargs.empty?

        begin
          adapter_class.new(**kwargs)
        rescue ArgumentError
          raise ValidationError, "source #{slug}: adapter #{adapter_class_name} does not support " \
                                 "`#{kwargs.keys.join(', ')}` (missing keyword on its initializer)"
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
    # Nabu::ValidationError naming the offending slug. Axis definitions load
    # from the SIBLING axes.yml by default (override via +axes_path+, tests
    # only) — every call site keeps passing just the sources path, and a
    # redirected registry brings its own axes file or none.
    def self.load(path, axes_path: nil)
      axes = AxisRegistry.load(axes_path || File.join(File.dirname(path.to_s), "axes.yml"))
      data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      unless data.is_a?(Hash)
        raise ValidationError, "sources registry must be a mapping of slug => entry, got #{data.class}"
      end

      entries = data.map { |slug, config| build_entry(slug, config, axis_registry: axes) }
      collisions = axes.names & entries.map(&:slug)
      unless collisions.empty?
        raise ValidationError, "axis name #{collisions.first.inspect} collides with a source slug — " \
                               "axis names must never equal slugs (the resolution guarantee)"
      end

      new(entries, axes: axes)
    end

    def self.build_entry(slug, config, axis_registry: AxisRegistry.new([]))
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

      kind = kind!(slug, config)
      enabled = enabled!(slug, config)
      kind_invariants!(slug, config, kind: kind, enabled: enabled)

      Entry.new(
        slug: slug, adapter_class_name: adapter,
        enabled: enabled, sync_policy: sync_policy!(slug, config), kind: kind,
        translations: boolean!(slug, config, "translations"),
        license_watch: license_watch!(slug, config),
        fuzzy_index: boolean!(slug, config, "fuzzy_index"),
        lemma_tier: lemma_tier!(slug, config),
        classes: classes!(slug, config),
        siblings: siblings!(slug, config),
        axes: axes!(slug, config, axis_registry)
      )
    end
    private_class_method :build_entry

    # The three P35-0 membership rules, at load like every other invariant:
    # once definitions exist, absent/empty axes is an error (every source
    # lands >= 1 desk); names must be defined; duplicates are noise. The
    # slug-collision rule is global and lives in .load.
    def self.axes!(slug, config, registry)
      value = config.fetch("axes", nil)
      if value.nil?
        return [] if registry.empty?

        raise ValidationError, "source #{slug.inspect}: must declare at least one research axis " \
                               "(axes: [...]; definitions in config/axes.yml)"
      end
      unless value.is_a?(Array) && !value.empty? && value.all?(String)
        raise ValidationError, "source #{slug.inspect}: axes must be a non-empty list of axis names, " \
                               "got #{value.inspect}"
      end
      raise ValidationError, "source #{slug.inspect}: axes list has duplicates: #{value.inspect}" if
        value.uniq != value

      unknown = value - registry.names
      return value if unknown.empty?

      raise ValidationError, "source #{slug.inspect}: unknown axis #{unknown.first.inspect} — " \
                             "not defined in the axes registry"
    end
    private_class_method :axes!

    # nil (no siblings), CTS_SIBLINGS, or a non-empty list of "-"-leading
    # tail patterns each compiling as a regex fragment — caught at load,
    # not inside a live --parallel session (P34-0).
    def self.siblings!(slug, config)
      value = config.fetch("siblings", nil)
      return nil if value.nil?
      return value if value == CTS_SIBLINGS

      if value.is_a?(Array) && !value.empty?
        bad = value.find { |tail| !valid_sibling_tail?(tail) }
        return value if bad.nil?

        raise ValidationError, "source #{slug.inspect}: siblings tail #{bad.inspect} must be a " \
                               "\"-\"-leading regex fragment"
      end
      raise ValidationError, "source #{slug.inspect}: siblings must be #{CTS_SIBLINGS.inspect} or a " \
                             "non-empty list of \"-\"-leading tail patterns, got #{value.inspect}"
    end
    private_class_method :siblings!

    def self.valid_sibling_tail?(tail)
      return false unless tail.is_a?(String) && tail.start_with?("-")

      Regexp.new(tail)
      true
    rescue RegexpError
      false
    end
    private_class_method :valid_sibling_tail?

    # nil (adapter default scope) or a non-empty list of non-empty strings;
    # the class VOCABULARY is the adapter's to validate (P33-0).
    def self.classes!(slug, config)
      list = config.fetch("classes", nil)
      return nil if list.nil?
      return list if list.is_a?(Array) && !list.empty? && list.all? { |c| c.is_a?(String) && !c.strip.empty? }

      raise ValidationError,
            "source #{slug.inspect}: classes must be a non-empty list of strings, got #{list.inspect}"
    end
    private_class_method :classes!

    def self.lemma_tier!(slug, config)
      tier = config.fetch("lemma_tier", DEFAULT_LEMMA_TIER)
      return tier if LEMMA_TIERS.include?(tier)

      raise ValidationError,
            "source #{slug.inspect}: lemma_tier must be one of #{LEMMA_TIERS.join(', ')}, got #{tier.inspect}"
    end
    private_class_method :lemma_tier!

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

    # The row's nature (P39-0): source (default) | shelf | module.
    def self.kind!(slug, config)
      kind = config.fetch("kind", DEFAULT_KIND)
      return kind if KINDS.include?(kind)

      raise ValidationError,
            "source #{slug.inspect}: kind must be one of #{KINDS.join(', ')}, got #{kind.inspect}"
    end
    private_class_method :kind!

    # Cross-field kind invariants (P39-0): a shelf declares NO sync_policy (its
    # local fetch strategy is implied by kind), and a module mints no catalog
    # rows so there is nothing to enable.
    def self.kind_invariants!(slug, config, kind:, enabled:)
      if kind == "shelf" && config.key?("sync_policy")
        raise ValidationError,
              "source #{slug.inspect}: a kind: shelf row uses the local fetch strategy — " \
              "drop sync_policy (kind implies it)"
      end
      return unless kind == "module" && enabled

      raise ValidationError,
            "source #{slug.inspect}: a kind: module row mints no catalog rows — must be enabled: false"
    end
    private_class_method :kind_invariants!

    # The research-axes definitions this registry was validated against
    # (AxisRegistry; empty in bootstrap/test mode). P35-1/2 render from it.
    attr_reader :axes

    def initialize(entries, axes: AxisRegistry.new([]))
      @entries = entries.to_h { |entry| [entry.slug, entry] }
      @axes = axes
    end

    # Slugs tagged with +axis_name+, registration order — the membership
    # seam the axis-scoped surfaces (`sync <axis>`, `list --axis`) read.
    # Unknown names return [] (the caller decides how loud to be).
    def axis_members(axis_name)
      @entries.each_value.select { |entry| entry.axes.include?(axis_name) }.map(&:slug)
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

    # { slug => tier } for the NON-gold sources only (P26-0) — absent-is-gold
    # is the wire format the Indexer consumes, mirroring the yaml's own
    # absent-is-gold contract.
    def lemma_tiers
      @entries.each_value
              .reject { |entry| entry.lemma_tier == DEFAULT_LEMMA_TIER }
              .to_h { |entry| [entry.slug, entry.lemma_tier] }
    end

    def empty?
      @entries.empty?
    end

    def size
      @entries.size
    end
  end
end
