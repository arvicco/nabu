# frozen_string_literal: true

module Nabu
  # The ONE place_ref reader (P63-4). Axis place_ref values arrive in every
  # historical spelling — verbatim upstream URLs (edh/ddbdp, often several
  # space-separated per field, http/https/trailing-slash variants), and the
  # P63 namespaced mints (`tm:2788`, `pleiades:433078`, ruling Dp-b). Dp-b
  # keeps upstream bytes verbatim and JOINS via normalization: every consumer
  # (invariants, the place desk, the P63-7 apply/read seam) parses through
  # here, never with its own inline regex. Non-place URLs riding in a place
  # field (the measured `…/text/392592` stray) parse to nothing, honestly.
  module PlaceRefs
    # URL spellings per namespace. Each captures the bare id.
    URL_PATTERNS = {
      "pleiades" => %r{pleiades\.stoa\.org/places/(\d+)},
      "tm" => %r{trismegistos\.org/(?:place|geo/detail)/(\d+)},
      "geonames" => %r{geonames\.org/(\d+)}
    }.freeze

    # The namespaced mint spelling: `namespace:id` as its OWN whole token.
    MINT_PATTERN = /\A([a-z][a-z0-9-]*):([A-Za-z0-9_.-]+)\z/

    # Namespaces a mint may cite — the URL-bearing three plus cigs, whose
    # ids have no per-place URL spelling (site mnemonics, `cigs:GIR`).
    MINT_NAMESPACES = (URL_PATTERNS.keys + %w[cigs]).freeze

    module_function

    # Every (namespace, id) claim in +ref+, in appearance order, deduped.
    # A multi-URL field yields one pair per URL; a mint token yields its
    # pair; anything unrecognized yields nothing (never guessed).
    def ids(ref)
      return [] if ref.nil?

      pairs = []
      ref.to_s.split(/\s+/).each do |token|
        if (m = token.match(MINT_PATTERN)) && MINT_NAMESPACES.include?(m[1])
          pairs << [m[1], m[2]]
          next
        end
        URL_PATTERNS.each do |namespace, pattern|
          token.scan(pattern) { |(id)| pairs << [namespace, id] }
        end
      end
      pairs.uniq
    end

    # The ids claimed in ONE namespace — the common consumer ask.
    def ids_in(ref, namespace)
      ids(ref).filter_map { |ns, id| id if ns == namespace }
    end
  end
end
