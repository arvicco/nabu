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

    # Namespaces a mint may cite — the URL-bearing three plus cigs (site
    # mnemonics, no per-place URL) and np (nabu-places' OWN minted records,
    # places.yml — the P63 native lane: not only glue).
    MINT_NAMESPACES = (URL_PATTERNS.keys + %w[cigs np]).freeze

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

    # The SQL-side spelling lane (P75 C-1): GLOB patterns that decide, inside
    # a correlated EXISTS, whether a place_ref field claims (+namespace+,
    # +id+) — the same spellings #ids accepts, so the two lanes never
    # diverge (URL_GLOBS mirrors URL_PATTERNS; consistency is test-pinned
    # against the real glob() engine). CONTRACT: every pattern is matched
    # against the SPACE-PADDED field (' ' || place_ref || ' '), which turns
    # both boundary cases — id at end-of-field, mint at either edge — into
    # the one in-string shape each pattern states. Ids stay glob-safe by
    # construction: MINT_PATTERN's charset carries no glob metacharacters.
    URL_GLOBS = {
      "pleiades" => ["*pleiades.stoa.org/places/%s[^0-9]*"],
      "tm" => ["*trismegistos.org/place/%s[^0-9]*",
               "*trismegistos.org/geo/detail/%s[^0-9]*"],
      "geonames" => ["*geonames.org/%s[^0-9]*"]
    }.freeze

    def ref_globs(namespace, id)
      URL_GLOBS.fetch(namespace, []).map { |glob| format(glob, id) } <<
        "* #{namespace}:#{id} *"
    end
  end
end
