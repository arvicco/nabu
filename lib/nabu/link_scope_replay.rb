# frozen_string_literal: true

module Nabu
  # The links-stage scope replay (P70-3b, extracted from Rebuild;
  # P106-6/Q94 adds the place pair): dispatch one recorded
  # link_scopes.yml entry back through its batch producer, so
  # db/links.sqlite3 stays a pure function of canonical + config + the
  # catalog. The 2026-09-27 rebuild dropped a 3.25M-edge place-mine run
  # because the place CLIs never recorded their scopes and this dispatch
  # did not know the producers — both halves closed here.
  module LinkScopeReplay
    module_function

    # place-link PROMOTES candidate edges place-mine writes: within one
    # replay the mine must land first, whatever order the scopes were
    # recorded in. Stable otherwise (recorded order is replay order).
    def order(scopes)
      scopes.reject { |scope| scope["producer"] == "place-link" } +
        scopes.select { |scope| scope["producer"] == "place-link" }
    end

    # +places+ is the nabu-places registry seam for the place-link
    # producer: :auto loads from canonical (the live path), tests inject
    # a stub; the other producers never touch it. +config+ supplies the
    # alignments path (cognates) and canonical_dir (:auto places).
    def replay!(scope, db:, fulltext:, journal:, config:, places: :auto)
      params = scope["params"] || {}
      case scope["producer"]
      when "parallels"
        BatchParallels.new(catalog: db, fulltext: fulltext, journal: journal)
                      .run(scope["scope"],
                           **{ lang: params["lang"], license: params["license"],
                               min_score: params["min_score"], per_anchor: params["per_anchor"] }.compact)
      when "cognates"
        BatchCognates.new(catalog: db, fulltext: fulltext, journal: journal,
                          registry: AlignmentRegistry.load(config.alignments_path))
                     .run(scope["scope"], langs: params["langs"], all: params.fetch("all", false))
      when "formulas"
        BatchFormulas.new(catalog: db, journal: journal)
                     .run(scope["scope"],
                          **{ gram_size: params["gram_size"], min_count: params["min_count"],
                              lang: params["lang"], max_formulas: params["max_formulas"] }.compact)
      when "place-mine"
        PlaceMine.new(catalog: db, journal: journal,
                      gazetteer: params["gazetteer"] || "chgis")
                 .apply!(source: scope["scope"])
      when "place-link"
        registry = places == :auto ? Places.load_default(canonical_dir: config.canonical_dir) : places
        if registry.nil?
          raise Nabu::Error, "place-link #{scope['scope']}: no nabu-places registry under " \
                             "canonical/ — sync nabu-places, then re-run the links stage"
        end
        PlaceLink.new(catalog: db, journal: journal, registry: registry,
                      gazetteer: params["gazetteer"] || "chgis")
                 .apply!(source: scope["scope"])
      else
        raise Nabu::Error, "unknown batch producer #{scope['producer'].inspect} in link_scopes.yml"
      end
    end
  end
end
