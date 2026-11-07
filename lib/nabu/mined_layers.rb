# frozen_string_literal: true

require "yaml"
require_relative "store/mined_links"

module Nabu
  # The cost law for the links instrument (owner ruling 2026-10-20;
  # architecture §15): which batch producers are HEAVY — enrichment-class
  # mined layers in local/mined-links.sqlite3, produced only by their mine
  # command — and the services around them: the classification
  # (config/mined_layers.yml), a layer's provenance at mine time, the mine
  # and the one-time migration (both through the Store::MinedLinks
  # gateway), and the presence/staleness readings the rebuild summary
  # and `nabu health` show.
  module MinedLayers
    CONFIG_PATH = File.expand_path("../../config/mined_layers.yml", __dir__)
    CLASSES = %w[cheap heavy].freeze

    # One layer's identity at mine time (Store::MinedLinks provenance):
    # the LinkStamps preimage, the member sources' ingest identities, and
    # the language-slice identity of the text the run consumed
    # ({"lang", "members" => {slug => [count, max revision]}} —
    # Store::SourceContentIdentity.slices).
    Provenance = Data.define(:stamp, :inputs, :catalog, :slice)

    # A layer's staleness reading (health): +changed+ the member slugs
    # whose identity moved since the mine at the layer's +grain+ (nil when
    # the layer recorded none — a migrated layer whose stamp no longer
    # matched), +code_moved+ whether the producer's code digest moved.
    # +grain+ :slice (the member's language slice moved — the precise
    # reading), :source (its ingest identity moved — the coarse reading of
    # a layer mined before the slice was recorded), nil (unrecorded).
    # +touched+ the members whose ingest identity moved (the slice grain
    # probes exactly these; [] at the other grains).
    Staleness = Data.define(:changed, :code_moved, :grain, :touched) do
      def initialize(changed:, code_moved:, grain: nil, touched: [])
        super
      end

      def stale? = code_moved || !changed.to_a.empty?
    end

    # One recorded heavy scope graded for `nabu links mine --stale`:
    # +status+ :stale | :current | :unmined (no layer in the store).
    Pick = Data.define(:scope, :layer, :staleness, :status)

    module_function

    # { producer => "cheap" | "heavy" }, validated: an unknown class is a
    # loud configuration error, never a silent cheap.
    def classification(path = CONFIG_PATH)
      data = File.file?(path) ? (YAML.safe_load_file(path) || {}) : {}
      (data["producers"] || {}).to_h do |producer, row|
        klass = row.is_a?(Hash) ? row["class"] : nil
        unless CLASSES.include?(klass)
          raise Nabu::Error, "#{path}: producer #{producer} has class #{klass.inspect} — expected cheap or heavy"
        end

        [producer, klass]
      end
    end

    def heavy_producers(path = CONFIG_PATH)
      classification(path).select { |_producer, klass| klass == "heavy" }.keys.sort
    end

    # An unclassified producer reads cheap here (the replay names an
    # unknown producer loudly); mined_layers_test pins that every
    # dispatched producer is classified.
    def heavy?(producer, path = CONFIG_PATH) = heavy_producers(path).include?(producer)

    # The scope string a producer's run rows carry for recorded +scope+
    # (the place pair suffixes the gazetteer; the batch miners use it as is).
    def run_scope(scope)
      case scope["producer"]
      when "place-mine", "place-link" then "#{scope['scope']}:#{(scope['params'] || {})['gazetteer'] || 'chgis'}"
      else scope["scope"]
      end
    end

    # The recorded heavy scopes (local/config/link_scopes.yml entries of a
    # heavy producer) whose scope string is +name+ — what
    # `nabu links mine NAME` re-mines.
    def recorded(link_scopes_path, name = nil)
      LinkScopes.load(link_scopes_path).select do |scope|
        heavy?(scope["producer"]) && (name.nil? || scope["scope"] == name)
      end
    end

    # The layer's identity at mine time: LinkStamps' preimage (code digest,
    # resolved params, member CONTENT identities, producer extras — the
    # self-check's basis) plus the members' sources.last_ingest_identity
    # (the cheap identity health compares) plus the language-slice
    # identity (#slice_lang's lane over those members — the grain health
    # judges staleness at).
    def provenance(scope, catalog:, config:, registry:)
      unit = LinkStamps.new(catalog: catalog, config: config, registry: registry).unit(scope)
      members = unit.inputs ? unit.inputs.fetch("members", {}).keys : []
      lang = slice_lang(scope)
      slice = { "lang" => lang, "members" => Store::SourceContentIdentity.slices(catalog, lang: lang, slugs: members) }
      Provenance.new(stamp: unit.stamp, inputs: unit.inputs, catalog: ingest_identities(catalog, members),
                     slice: slice)
    end

    # The language lane a recorded scope's run reads: its +lang+ param,
    # else (parallels) its reuse profile's language — the resolution
    # BatchParallels::Settings makes; nil = every language.
    def slice_lang(scope)
      params = scope["params"] || {}
      return params["lang"] if params["lang"]

      ReuseProfiles.default.fetch(params["profile"]).lang if scope["producer"] == "parallels" && params["profile"]
    end

    def ingest_identities(catalog, slugs)
      found = catalog[:sources].where(slug: slugs).select_hash(:slug, :last_ingest_identity)
      slugs.sort.to_h { |slug| [slug, found[slug]] }
    end

    # Mine one recorded heavy +scope+ into the store through the gateway;
    # the block runs the producer against the store handle it receives.
    # Returns the Store::MinedLinks::MineResult.
    def mine!(scope, config:, catalog:, registry:, path: config.mined_links_path, &producer)
      unless heavy?(scope["producer"])
        raise Nabu::Error, "#{scope['producer']} is a rebuild lane (config/mined_layers.yml: cheap) — " \
                           "its edges live in db/links.sqlite3"
      end

      prov = provenance(scope, catalog: catalog, config: config, registry: registry)
      Store::MinedLinks.mine!(path, producer: scope["producer"], scope: scope["scope"], run_scope: run_scope(scope),
                                    stamp: prov.stamp, inputs: prov.inputs, catalog: prov.catalog,
                                    slice: prov.slice, &producer)
    end

    # The one-time move of the heavy producers' runs out of the links
    # journal (Store::MinedLinks.migrate!). With a +catalog+ (and the
    # source +registry+), each moved layer whose journal stamp still
    # equals its stamp under the live catalog records the members' ingest
    # identities — it is current as of now; otherwise that stays
    # unrecorded until the layer's next mine.
    def migrate!(config:, dry_run: false, catalog: nil, registry: nil)
      catalog_for = if catalog
                      lambda do |producer, scope, stamp|
                        recorded = recorded(config.link_scopes_path, scope).find { |row| row["producer"] == producer }
                        prov = recorded && provenance(recorded, catalog: catalog, config: config, registry: registry)
                        prov.catalog if prov && stamp && prov.stamp == stamp
                      end
                    end
      Store::MinedLinks.migrate!(config.mined_links_path, journal_path: config.links_path,
                                                          producers: heavy_producers, dry_run: dry_run,
                                                          catalog_for: catalog_for)
    end

    # The links stage's honest-visibility line: the mined layers present
    # and the oldest one's date; recorded heavy scopes never mined; heavy
    # runs still waiting in the journal (+journal+, when given).
    def presence_line(path, heavy_scopes:, journal: nil)
      layers = Store::MinedLinks.layers_at(path)
      parts = [if layers.empty?
                 "mined layers: none present"
               else
                 "mined layers: #{layers.size} present, oldest #{layers.map(&:mined_at).min.strftime('%Y-%m-%d')}"
               end]
      missing = heavy_scopes.reject do |scope|
        layers.any? { |layer| layer.producer == scope["producer"] && layer.scope == scope["scope"] }
      end
      unless missing.empty?
        parts << "not yet mined: #{missing.map { |scope| "#{scope['producer']} #{scope['scope']}" }.join(', ')} " \
                 "(nabu links mine SCOPE)"
      end
      waiting = journal ? Store::LinksJournal.run_ids_for(journal, producers: heavy_producers).size : 0
      parts << "#{waiting} heavy run(s) still in db/links.sqlite3 (nabu links migrate-mined)" if waiting.positive?
      parts.join(" · ")
    end

    # A layer's staleness against the live +catalog+ and the producer's
    # current code (LinkStamps.code_digests — file hashes, cheap).
    #
    # Members first by ingest identity (one indexed read): a member whose
    # identity did not move was not re-ingested, so nothing it holds moved.
    # A layer that recorded its language slice then PROBES each touched
    # member's slice against the live catalog — a touch outside the lane
    # (a reference source, another language's re-parse) stays current; a
    # moved lane is stale. A layer mined before the slice was recorded
    # keeps the coarse per-source verdict (never upgraded after the fact).
    def staleness(layer, catalog:, code_digests: LinkStamps.code_digests)
      code = layer.inputs && layer.inputs["producer_code"]
      code_moved = !code.nil? && code_digests.key?(layer.producer) && code != code_digests[layer.producer]
      return Staleness.new(changed: nil, code_moved: code_moved) unless layer.catalog

      now = ingest_identities(catalog, layer.catalog.keys)
      touched = layer.catalog.keys.reject { |slug| now[slug] == layer.catalog[slug] }
      return Staleness.new(changed: touched, code_moved: code_moved, grain: :source) unless layer.slice

      Staleness.new(changed: slice_moved(layer.slice, catalog, touched), code_moved: code_moved, grain: :slice,
                    touched: touched)
    end

    # The +touched+ members whose live language slice differs from the
    # recorded one (an absent member reads [0, nil] on both sides).
    def slice_moved(slice, catalog, touched)
      return [] if touched.empty?

      recorded = slice.fetch("members", {})
      live = Store::SourceContentIdentity.slices(catalog, lang: slice["lang"], slugs: touched)
      touched.reject { |slug| (live[slug] || [0, nil]) == (recorded[slug] || [0, nil]) }
    end

    # `nabu links mine --stale`'s selection: every recorded heavy +scopes+
    # entry graded against its layer among +layers+ (Store::MinedLinks)
    # by #staleness — stale, current, or never mined. The caller re-mines
    # the stale ones; nothing here mines.
    def stale_selection(scopes, layers:, catalog:, code_digests: LinkStamps.code_digests)
      scopes.map do |scope|
        layer = layers.find { |row| row.producer == scope["producer"] && row.scope == scope["scope"] }
        next Pick.new(scope: scope, layer: nil, staleness: nil, status: :unmined) if layer.nil?

        staleness = staleness(layer, catalog: catalog, code_digests: code_digests)
        Pick.new(scope: scope, layer: layer, staleness: staleness, status: staleness.stale? ? :stale : :current)
      end
    end
  end
end
