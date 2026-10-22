# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Telugu: English Wiktionary's Telugu entries via the
    # kaikki.org wiktextract extraction — the wiktionary-akk mold on the
    # shared WiktionaryKaikki base, one of the South Asian dictionary
    # wave's seven shelves. What it adds: the library's first Telugu
    # dictionary (beside the DHARMA Telugu epigraphy) — the wave's largest
    # extract by headwords, with Sanskrit and Proto-Dravidian etymons
    # (1,546 sa / 477 dra-pro edges at census) and Persian/Arabic donor
    # lanes. Stored language tel (→ te through the held codemap alias).
    #
    # == Upstream (verified 2026-10-21)
    #
    # https://kaikki.org/dictionary/Telugu/ — "21803 distinct words",
    # 23,325 records (32,721,606 B, Last-Modified 2026-10-03). Census
    # through the house parser: 23,325 entries / 2,953 reflex rows /
    # 0 non-NFC. Deprecation caveat and license: the WiktionaryKaikki
    # class note; fallback = filter the full extract by lang_code == "te".
    class WiktionaryTe < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-te",
        name: "Wiktionary Telugu — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Telugu/kaikki.org-dictionary-Telugu.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Telugu.jsonl"
      DICTIONARY_SLUG = "wiktionary-te"
      LANGUAGE = "tel"
      TITLE = "Wiktionary — Telugu (kaikki.org extract)"
    end
  end
end
