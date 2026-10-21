# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Tamil: English Wiktionary's Tamil entries via the
    # kaikki.org wiktextract extraction — the wiktionary-akk mold on the
    # shared WiktionaryKaikki base, one of the South Asian dictionary
    # wave's seven shelves (ta/te/ml/kn/pra/dv/si). What it adds: the
    # first Tamil dictionary beside the library's Tamil text estate
    # (DHARMA epigraphy, Project Madurai's classical cone) — sense glosses
    # for 11,180 words, Sanskrit and Proto-Dravidian etymons (1,803 sa /
    # 773 dra-pro edges at census), and descendants trees (the Sinhala,
    # Malay and English loan lanes). Stored language tam (→ ta through
    # the held codemap alias).
    #
    # == Upstream (verified 2026-10-21)
    #
    # https://kaikki.org/dictionary/Tamil/ — "11180 distinct words",
    # 13,855 records (88,872,672 B, Last-Modified 2026-10-03). Census
    # through the house parser: 13,855 entries / 4,807 reflex rows /
    # 0 non-NFC. Deprecation caveat and license: the WiktionaryKaikki
    # class note; fallback = filter the full extract by lang_code == "ta".
    class WiktionaryTa < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-ta",
        name: "Wiktionary Tamil — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Tamil/kaikki.org-dictionary-Tamil.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Tamil.jsonl"
      DICTIONARY_SLUG = "wiktionary-ta"
      LANGUAGE = "tam"
      TITLE = "Wiktionary — Tamil (kaikki.org extract)"
    end
  end
end
