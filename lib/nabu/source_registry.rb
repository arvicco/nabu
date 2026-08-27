# frozen_string_literal: true

require "yaml"

module Nabu
  # The source registry (architecture §5, config/sources.yml): the authoritative
  # list of corpora Nabu knows about — which adapter class ingests each, whether
  # it is WIRED (adapter exists and is verified to sync), and its sync policy.
  # NOMENCLATURE (owner ruling 2026-07-24): this registry marker was named
  # `enabled:` before the P44-r3b enablement promotion gave `nabu enable` a
  # different meaning (the box's profile.yml enabled set). The field is now
  # `wired:` — profile enablement says WHICH sources this box works with;
  # wired says the ADAPTER is built and first-sync-verified. Parsed and validated up front; adapter
  # classes resolve *lazily* (per entry, on demand) so `nabu status`/listing
  # never require every adapter to be loadable.
  #
  # Split of authority: the registry owns identity + metadata (name, adapter
  # class, license, upstream URL — all from the adapter manifest) AND
  # the wired marker (revised 2026-07-04; re-affirmed P23-3b: status/list/MCP
  # read `wired` from the registry directly, since the db row only mirrors a
  # sources.yml flip at the source's next sync); the catalog db owns sync
  # history (last_sync_*). #sync_source! reconciles the two, writing metadata
  # + wired into the sources row (the db COLUMN keeps its historical name
  # `enabled` — a frozen mirror, renaming it buys nothing) while preserving
  # db-owned state.
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
    #     mints ZERO catalog rows, so there is nothing to serve and nothing
    #     for `sync --all` to sweep (kind + sync_policy govern that; wired
    #     means the same thing here as everywhere — channel verified, the
    #     2026-08-18 ruling).
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

    # The public-availability posture (P44-r3a). `public` (the default, absent
    # on every ordinary row) means the source is part of the library as a
    # PUBLIC holding — it appears on the generated site axis pages, in
    # docs/axes.md memberships, and its holdings count toward public census
    # surfaces. `blocked` means grant-gated PRIVATE research material (the
    # fetch right is a personal grant, №41-3/№1): the public repo may keep a
    # license/scouting record of it, but must NOT advertise it as a library
    # holding — the public-doc/site generators exclude it and public counts
    # never include it. Orthogonal to `grant_required` (the sync-time gate) and
    # to `wired`: availability governs PUBLIC VISIBILITY of the row, not
    # whether it can be fetched or served locally. Owner ruling 2026-07-24.
    AVAILABILITIES = %w[public blocked].freeze
    DEFAULT_AVAILABILITY = "public"

    # The quickstart starter tag (P44-r3b). `quickstart: true` marks a source as
    # part of the CURATED starter set a fresh box meets first: when
    # config/profile.yml is ABSENT and no library has been built yet, the
    # enablement default is exactly these rows (Profile.default_entries). Absent
    # = false (an ordinary source is not in the starter set). r3c seeds the tags;
    # r3b only parses the field and wires the default seam — with zero rows
    # tagged, the default is the empty set and the honest "no sources enabled"
    # empty-state shows.
    DEFAULT_QUICKSTART = false

    # The multilingual pack marker (P49-r4). `multilingual: true` marks a
    # source whose language list is STRUCTURALLY UNBOUNDED — a pack of
    # per-language sub-corpora (UD's ~40 treebanks, WOLD's 41 vocabularies,
    # the kaikki per-language extracts) where upstream can add any language
    # and the source's whole-grain `axes:` union does not describe any single
    # held language. The count-less membership-attribution surfaces (the
    # language card's `axes:` line, the axis card's gold-lemma language set)
    # EXCLUDE multilingual members: a pack's few hbo documents must not drag
    # its romance/germanic/sinitic desks onto the hbo card. Counts-bearing
    # surfaces (the axis card's `languages:` line) deliberately KEEP pack
    # holdings — there the counts are the honesty mechanism. Absent = false:
    # an ordinary source, even one holding several languages, attributes
    # normally (a bounded spread — a site archive, a script corpus — is its
    # desks' own subject matter, not spillover).
    DEFAULT_MULTILINGUAL = false

    # The fetch-grant block (P42-r1): a permission-bound source whose right to
    # fetch is NOT conveyed by a public license (StarLing's personal e-mail
    # grant to the project author, the future TITUS Avestan). A public clone of
    # nabu must not scrape under someone else's grant, so `grant_required: true`
    # arms the sync-time gate and this block carries what the gate renders — the
    # terms verbatim, who granted them and when, the thread reference, and a
    # request_hint (whom a new user should ask + what to promise). DISTINCT from
    # ordinary public-license obligations (CC BY-NC-SA needs no gate — the
    # license-class machinery handles attribution/redistribution); the gate
    # criterion is solely "the right to FETCH is not conveyed by a public
    # license." All five fields are required, non-empty strings (quote the date
    # in YAML so it stays a String, not a parsed Date).
    Grant = Data.define(:grantor, :date, :terms, :thread, :request_hint)
    GRANT_FIELDS = %w[grantor date terms thread request_hint].freeze

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
    # the flag lives here beside wired/translations — flipped per-source in
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
    # wired/translations, passed to the adapter's `classes:` keyword by
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
    # +grant_required+ / +grant+ (P42-r1): a permission-bound source arms the
    # sync-time grant gate (grant_required: true) and carries the Grant block
    # the gate renders (grantor/date/terms/thread/request_hint). The two travel
    # together — a grant block without the flag, or the flag without a block, is
    # a configuration error caught at load. Absent on every ordinary source.
    # +lemma_dictionary_filter+ (P84-1): arms the silver-lemma epigraphy
    # filter for this source — shelf-projected lemmas land only when the
    # language's reference dictionary attests them or they fold to a
    # surface form (SilverLemmaIndexer's class note carries the argument).
    # An index-time policy flag like fuzzy_index, and the same posture
    # doctrine: declared per source in sources.yml, never hardcoded.
    Entry = Data.define(:slug, :adapter_class_name, :wired, :sync_policy, :kind, :translations,
                        :license_watch, :fuzzy_index, :lemma_tier, :lemma_dictionary_filter,
                        :classes, :siblings, :axes,
                        :grant_required, :grant, :availability, :quickstart, :multilingual,
                        :group, :requires) do
      def initialize(slug:, adapter_class_name:, wired:, sync_policy:, kind: DEFAULT_KIND,
                     translations: false, license_watch: nil, fuzzy_index: false,
                     lemma_tier: DEFAULT_LEMMA_TIER, lemma_dictionary_filter: false,
                     classes: nil, siblings: nil, axes: [],
                     grant_required: false, grant: nil, availability: DEFAULT_AVAILABILITY,
                     quickstart: DEFAULT_QUICKSTART, multilingual: DEFAULT_MULTILINGUAL,
                     group: nil, requires: [])
        super
      end

      # The CORE group (P63 rider, owner ruling 2026-08-09): registry-sibling
      # instruments the library itself depends on (nabu-lects, nabu-places,
      # cigs). Pre-enabled by nature (modules never gate on enablement) and
      # swept together by `nabu sync core` — which quickstart runs
      # automatically.
      def core? = group == "core"

      # kind predicates (P39-0). shelf? drives the local fetch strategy (no
      # network, up=local) at the probe, status, and health-integrity seams;
      # feature_module? is machinery-only (up=module, no holdings, no sweep).
      def shelf? = kind == "shelf"
      def feature_module? = kind == "module"
      def source? = kind == "source"

      # This source's fetch right is not conveyed by a public license, so the
      # sync-time gate (P42-r1) demands a recorded acknowledgment before a first
      # fetch. Predicate spelling mirrors shelf?/source?.
      def grant_required? = grant_required

      # This source is grant-gated PRIVATE research material (P44-r3a): keep
      # its license/scouting record, but never advertise it as a public
      # library holding. The public-doc/site generators exclude it and public
      # census surfaces never count it. Predicate spelling mirrors
      # grant_required?/shelf?; the default (no `availability:` key) is public.
      def blocked? = availability == "blocked"
      def public? = !blocked?

      # In the curated quickstart starter set (P44-r3b)? Drives
      # Profile.default_entries on a fresh, library-less box.
      def quickstart? = quickstart

      # A structurally-unbounded language pack (P49-r4, DEFAULT_MULTILINGUAL
      # note above)? The count-less attribution surfaces exclude this source
      # when mapping languages onto research desks.
      def multilingual? = multilingual

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
      # upstream_url) AND for the wired marker — the owner flips `wired:` in
      # sources.yml with a sign-off comment, and `sync --all` reads the yaml,
      # so the db row mirrors it on every reconcile (revised 2026-07-04; the
      # original db-owns-enabled split left `status` showing stale rows
      # forever). The db COLUMN stays named `enabled` (historical; a frozen
      # mirror of wired). The db stays authoritative for sync history
      # (last_sync_*).
      # Returns the Store::Source row.
      def sync_source!(db)
        attrs = {
          name: manifest.name, adapter_class: adapter_class_name,
          license: manifest.license, license_class: manifest.license_class,
          credit: manifest.credit, upstream_url: manifest.upstream_url, enabled: wired
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
      validate_requires!(entries)

      new(entries, axes: axes)
    end

    # The dependency chain's load-time invariants (P77-r3): every declared
    # requirement names a REGISTERED slug, and the graph is acyclic — a
    # cycle would make enable/sync expansion spin, so it is refused at
    # load with the cycle spelled out, never discovered at runtime.
    def self.validate_requires!(entries)
      by_slug = entries.to_h { |entry| [entry.slug, entry] }
      entries.each do |entry|
        entry.requires.each do |dep|
          next if by_slug.key?(dep)

          raise ValidationError, "source #{entry.slug.inspect}: requires unknown source #{dep.inspect}"
        end
      end
      state = {}
      entries.each { |entry| walk_requires!(entry.slug, by_slug, state, []) }
    end
    private_class_method :validate_requires!

    def self.walk_requires!(slug, by_slug, state, trail)
      return if state[slug] == :done
      raise ValidationError, "requires cycle: #{(trail + [slug]).join(' -> ')}" if state[slug] == :visiting

      state[slug] = :visiting
      by_slug[slug].requires.each { |dep| walk_requires!(dep, by_slug, state, trail + [slug]) }
      state[slug] = :done
    end
    private_class_method :walk_requires!

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
      wired = wired!(slug, config)
      kind_invariants!(slug, config, kind: kind, wired: wired)
      grant_required, grant = grant!(slug, config)

      Entry.new(
        slug: slug, adapter_class_name: adapter,
        wired: wired, sync_policy: sync_policy!(slug, config), kind: kind,
        translations: boolean!(slug, config, "translations"),
        license_watch: license_watch!(slug, config),
        fuzzy_index: boolean!(slug, config, "fuzzy_index"),
        lemma_tier: lemma_tier!(slug, config),
        lemma_dictionary_filter: boolean!(slug, config, "lemma_dictionary_filter"),
        classes: classes!(slug, config),
        siblings: siblings!(slug, config),
        axes: axes!(slug, config, axis_registry),
        grant_required: grant_required, grant: grant,
        availability: availability!(slug, config),
        quickstart: boolean!(slug, config, "quickstart"),
        multilingual: boolean!(slug, config, "multilingual"),
        group: group!(slug, config),
        requires: requires!(slug, config)
      )
    end
    private_class_method :build_entry

    # Source groups (P63 rider; P68-4): closed vocabulary — "core" (the
    # registry-sibling instruments, swept by `nabu sync core` and by
    # quickstart) and "signs" (every shelf the sign/char capability reads:
    # the two identity-spine modules + the Han card's shelves + the
    # Wiktionary sense lane — `nabu enable signs && nabu sync signs`
    # restores the whole capability on a fresh box).
    GROUPS = %w[core signs].freeze

    def self.group!(slug, config)
      value = config["group"]
      return value if value.nil? || GROUPS.include?(value)

      raise ValidationError,
            "source #{slug.inspect}: group must be one of #{GROUPS.join(', ')} (or absent), " \
            "got #{value.inspect}"
    end
    private_class_method :group!

    # The `requires:` key (P77-r3, owner commission 2026-08-13): the slugs
    # this row FUNCTIONALLY depends on — the package-manager rule. Enabling
    # a source enables its whole chain (Focus closes over it); syncing it
    # sweeps never-synced requirements first. Declared for HARD functional
    # dependencies only (the dependent is blind or broken without the
    # requirement — nabu-places resolving refs through the gazetteer
    # slices); soft render-compose edges (a card that merely enriches when
    # a sibling shelf is present) stay undeclared. Existence and
    # acyclicity are load-time invariants (validate_requires!).
    def self.requires!(slug, config)
      value = config.fetch("requires", [])
      unless value.is_a?(Array) && value.all? { |v| v.is_a?(String) && !v.strip.empty? }
        raise ValidationError,
              "source #{slug.inspect}: requires must be a list of source slugs, got #{value.inspect}"
      end
      raise ValidationError, "source #{slug.inspect}: requires itself" if value.include?(slug)

      value.uniq.freeze
    end
    private_class_method :requires!

    # The public-availability posture (P44-r3a). Absent = public (the default);
    # `blocked` marks grant-gated private research material the public surfaces
    # must not advertise. Any other value is a configuration error naming the
    # slug, caught at load like every other vocabulary field.
    def self.availability!(slug, config)
      value = config.fetch("availability", DEFAULT_AVAILABILITY)
      return value if AVAILABILITIES.include?(value)

      raise ValidationError,
            "source #{slug.inspect}: availability must be one of #{AVAILABILITIES.join(', ')}, " \
            "got #{value.inspect}"
    end
    private_class_method :availability!

    # The fetch-grant gate keys (P42-r1). Returns [grant_required, Grant|nil].
    # The flag and the block travel together: grant_required without a grant
    # block is a config error (the gate would have nothing to render), and a
    # grant block without the flag is a config error too (dead config that
    # would gate nothing). A present block must carry every GRANT_FIELDS key as
    # a non-empty String (quote the date in YAML so it is not parsed to a Date).
    def self.grant!(slug, config)
      required = boolean!(slug, config, "grant_required")
      block = config.fetch("grant", nil)

      if required && block.nil?
        raise ValidationError, "source #{slug.inspect}: grant_required: true needs a grant: block " \
                               "(#{GRANT_FIELDS.join('/')})"
      end
      if !required && !block.nil?
        raise ValidationError, "source #{slug.inspect}: a grant: block requires grant_required: true"
      end
      return [false, nil] if block.nil?
      unless block.is_a?(Hash)
        raise ValidationError, "source #{slug.inspect}: grant must be a mapping, got #{block.class}"
      end

      values = GRANT_FIELDS.map { |key| grant_field!(slug, block, key) }
      [true, Grant.new(grantor: values[0], date: values[1], terms: values[2],
                       thread: values[3], request_hint: values[4])]
    end
    private_class_method :grant!

    def self.grant_field!(slug, block, key)
      value = block[key]
      return value if value.is_a?(String) && !value.strip.empty?

      raise ValidationError,
            "source #{slug.inspect}: grant.#{key} must be a non-empty string, got #{value.inspect}"
    end
    private_class_method :grant_field!

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

    def self.wired!(slug, config)
      boolean!(slug, config, "wired")
    end
    private_class_method :wired!

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
    # rows so there is nothing to wire on.
    def self.kind_invariants!(slug, config, kind:, wired:)
      _ = wired # kept in the signature: call sites predate the 2026-08-18 ruling below
      return unless kind == "shelf" && config.key?("sync_policy")

      # The former second invariant — "a kind: module row must be
      # wired: false" — was RETIRED by the owner's wired-semantics ruling
      # (2026-08-18): wired means THE SYNC LINK IS TESTED AND DECLARED
      # WORKING, for every kind; `--all` participation is governed by
      # kind + sync_policy, never by wired. A module with a landed first
      # fetch is wired like any other verified channel.
      raise ValidationError,
            "source #{slug.inspect}: a kind: shelf row uses the local fetch strategy — " \
            "drop sync_policy (kind implies it)"
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

    # The CORE group's members, registration order — the `sync core` sweep
    # set (P63 rider): pre-enabled registry instruments (modules by nature),
    # also run automatically by quickstart.
    def core_members
      group_members("core")
    end

    # Any group's members, registration order (P68-4): the sweep set behind
    # `nabu sync <group>` and the expansion behind `nabu enable <group>`.
    def group_members(name)
      @entries.each_value.select { |entry| entry.group == name }.map(&:slug)
    end

    # Functional sets (P77 rider, owner ruling 2026-08-13): an axis is a
    # TAG over the source list, and the registry's non-desk sets are the
    # same kind of tag — so every `--axis` surface accepts them beside
    # the research desks. The closed vocabulary: the GROUPS ("core" —
    # the auto-enabled minimum of registry instruments; "signs" — the
    # sign/char capability restore set) plus "quickstart" (the starter
    # shelf: core + the quickstart-flagged starter sources — what a
    # fresh box holds after `nabu quickstart`).
    FUNCTIONAL_SETS = (GROUPS + %w[quickstart]).freeze

    def functional_set?(name)
      FUNCTIONAL_SETS.include?(name)
    end

    # A functional set's member slugs, registration order. Unknown names
    # raise — the callers gate on #functional_set? first, so reaching
    # here with a stranger is a wiring bug, not user input.
    def functional_set_members(name)
      return group_members(name) if GROUPS.include?(name)
      raise ValidationError, "unknown functional set #{name.inspect}" unless name == "quickstart"

      (core_members + quickstart_flagged).uniq
    end

    # The quickstart-flagged starter sources (P44-r3c), registration order.
    def quickstart_flagged
      @entries.each_value.select(&:quickstart).map(&:slug)
    end

    # THE membership predicate every --axis surface reads (P77 rider):
    # +name+ may be a research-desk tag or a functional set; a renderer
    # never needs to know which.
    def axis_or_set_member?(name, slug)
      return functional_set_members(name).include?(slug) if functional_set?(name)

      self[slug]&.axes&.include?(name) || false
    end

    # The transitive closure of +slugs+ over `requires:` (P77-r3) — the
    # package-manager expansion: the named slugs plus every requirement
    # down the chain, deduped, discovery order. Unknown slugs pass
    # through untouched (the caller's drift handling owns them).
    def requires_closure(slugs)
      seen = []
      queue = slugs.dup
      until queue.empty?
        slug = queue.shift
        next if seen.include?(slug)

        seen << slug
        queue.concat(self[slug]&.requires || [])
      end
      seen
    end

    # The DIRECT dependents of +slug+, registration order — the "required
    # by" half of the picture (`nabu status <slug>` renders it).
    def required_by(slug)
      @entries.each_value.select { |entry| entry.requires.include?(slug) }.map(&:slug)
    end

    # Axis members MINUS the blocked (grant-gated private) ones (P44-r3a) — the
    # membership seam the PUBLIC surfaces read (the generated site axis pages
    # and docs/axes.md). #axis_members stays the full list for the CLI/sync
    # scopes (a blocked source is still fetchable/servable locally); only the
    # public documentation excludes it.
    def public_axis_members(axis_name)
      axis_members(axis_name).reject { |slug| blocked?(slug) }
    end

    # The blocked (grant-gated private) slugs tagged with +axis_name+ — the
    # complement of #public_axis_members, so a generator can decide whether to
    # render the "private materials not listed" footnote.
    def blocked_axis_members(axis_name)
      axis_members(axis_name).select { |slug| blocked?(slug) }
    end

    # Is +slug+ a grant-gated private-research row (availability: blocked)?
    # Unknown slugs are not blocked. The read path r3b (CLI/MCP visibility)
    # builds on this.
    def blocked?(slug)
      entry = @entries[slug]
      entry ? entry.blocked? : false
    end

    # Is +slug+ a multilingual pack (P49-r4)? Unknown slugs are not — the
    # blocked? mold. The count-less attribution surfaces (language-card
    # `axes:`, axis-card gold-lemma language set) read this to exclude pack
    # spillover.
    def multilingual?(slug)
      entry = @entries[slug]
      entry ? entry.multilingual? : false
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

    # Slugs in the curated quickstart starter set (P44-r3b), registration
    # order — the fresh-box enablement default (Profile.default_entries). Empty
    # until r3c seeds `quickstart: true` tags, so r3b's default is the empty set.
    def quickstart_slugs
      @entries.each_value.select(&:quickstart?).map(&:slug)
    end

    # Slugs opted into the trigram fragment index (search --fuzzy, P16-4) —
    # what the Indexer scopes its trigram pass to. Registration order.
    def fuzzy_slugs
      @entries.each_value.select(&:fuzzy_index).map(&:slug)
    end

    # Slugs under the silver-lemma dictionary filter (P84-1) — what the
    # SilverLemmaIndexer confirms against the reference dictionary.
    def lemma_filter_slugs
      @entries.each_value.select(&:lemma_dictionary_filter).map(&:slug)
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
