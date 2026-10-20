# frozen_string_literal: true

module Nabu
  module MCP
    # The per-result license envelope for REFERENCE data — the one additive
    # seam every non-text MCP payload funnels through. The per-row
    # urn + language + license_class + source contract already covers every
    # TEXT surface; reference datasets (gazetteers, sign lists) answer from
    # feature modules that mint no catalog rows, so their licenses live in
    # the adapters' own SourceManifests. This module reads them there — the
    # verbatim license string the adapter recorded at adoption, never a
    # second hand-copied list that could drift.
    #
    # Everything it returns is ADDITIVE: new keys beside frozen payloads,
    # never a changed one. An adapter constant that is not loaded (a
    # trimmed require graph) degrades to nil and the caller omits the key —
    # absence, never a placeholder.
    module Envelope
      # Reference slug → adapter class name under Nabu::Adapters.
      REFERENCE_ADAPTERS = {
        "pleiades" => "Pleiades",
        "trismegistos-geo" => "TrismegistosGeo",
        "cigs" => "Cigs",
        "osl" => "Osl",
        "unikemet" => "Unikemet"
      }.freeze

      # Place-ref namespace → the gazetteer source that answers it.
      GAZETTEER_SOURCES = {
        "pleiades" => "pleiades",
        "tm" => "trismegistos-geo",
        "cigs" => "cigs"
      }.freeze

      # Per-place upstream URIs for the CC BY attribution line — the URL
      # shapes Nabu::PlaceRefs::URL_PATTERNS already recognises (cigs has
      # no per-place URL; its attribution names the dataset alone).
      PLACE_URIS = {
        "pleiades" => "https://pleiades.stoa.org/places/%s",
        "tm" => "https://www.trismegistos.org/place/%s"
      }.freeze

      module_function

      # { source:, license_class:, license:, upstream_url: } for a reference
      # dataset slug, or nil when the slug is unknown / its adapter unloaded.
      def reference(slug)
        name = REFERENCE_ADAPTERS[slug] or return nil
        return nil unless Nabu.const_defined?(:Adapters) && Nabu::Adapters.const_defined?(name, false)

        manifest = Nabu::Adapters.const_get(name, false).manifest
        { source: slug, license_class: manifest.license_class, license: manifest.license,
          upstream_url: manifest.upstream_url }
      end

      # The attribution object for one gazetteer card: the dataset's
      # license envelope plus the place's own upstream URI where the
      # gazetteer has one. nil when the namespace has no known gazetteer.
      def place_attribution(namespace, id)
        envelope = reference(GAZETTEER_SOURCES[namespace].to_s) or return nil
        pattern = PLACE_URIS[namespace]
        pattern && id ? envelope.merge(uri: format(pattern, id)) : envelope
      end
    end
  end
end
