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
    # the LinkStamps preimage and the member sources' ingest identities.
    Provenance = Data.define(:stamp, :inputs, :catalog)

    # A layer's staleness reading (health): +changed+ the member slugs
    # whose ingest identity moved since the mine (nil when the layer
    # recorded none — a migrated layer whose stamp no longer matched),
    # +code_moved+ whether the producer's code digest moved.
    Staleness = Data.define(:changed, :code_moved) do
      def stale? = code_moved || !changed.to_a.empty?
    end

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
    # (the cheap identity health compares).
    def provenance(scope, catalog:, config:, registry:)
      unit = LinkStamps.new(catalog: catalog, config: config, registry: registry).unit(scope)
      members = unit.inputs ? unit.inputs.fetch("members", {}).keys : []
      Provenance.new(stamp: unit.stamp, inputs: unit.inputs, catalog: ingest_identities(catalog, members))
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
                                    stamp: prov.stamp, inputs: prov.inputs, catalog: prov.catalog, &producer)
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
    def staleness(layer, catalog:, code_digests: LinkStamps.code_digests)
      code = layer.inputs && layer.inputs["producer_code"]
      code_moved = !code.nil? && code_digests.key?(layer.producer) && code != code_digests[layer.producer]
      changed = if layer.catalog
                  now = ingest_identities(catalog, layer.catalog.keys)
                  layer.catalog.keys.reject { |slug| now[slug] == layer.catalog[slug] }
                end
      Staleness.new(changed: changed, code_moved: code_moved)
    end
  end
end
