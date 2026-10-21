# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Malayalam: English Wiktionary's Malayalam entries via the
    # kaikki.org wiktextract extraction — the wiktionary-akk mold on the
    # shared WiktionaryKaikki base, one of the South Asian dictionary
    # wave's seven shelves. What it adds: the library's first Malayalam
    # material of any kind — sense glosses for 10,942 words, the densest
    # Sanskrit etymon layer of the wave (2,799 sa edges at census) beside
    # the Syriac, Portuguese and Arabic donor lanes of the Kerala coast.
    #
    # Stored language mal, carried verbatim: the lect registry holds no
    # Malayalam node yet (the ml anchor + mal alias are a named mint
    # candidate). A dictionary shelf resolves at its own grain, so the
    # code rides as-is and resolves once the node lands.
    #
    # == Upstream (verified 2026-10-21)
    #
    # https://kaikki.org/dictionary/Malayalam/ — "10942 distinct words",
    # 11,505 records (23,456,757 B, Last-Modified 2026-10-03). Census
    # through the house parser: 11,505 entries / 5,266 reflex rows /
    # 0 non-NFC. Deprecation caveat and license: the WiktionaryKaikki
    # class note; fallback = filter the full extract by lang_code == "ml".
    class WiktionaryMl < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-ml",
        name: "Wiktionary Malayalam — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Malayalam/kaikki.org-dictionary-Malayalam.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Malayalam.jsonl"
      DICTIONARY_SLUG = "wiktionary-ml"
      LANGUAGE = "mal"
      TITLE = "Wiktionary — Malayalam (kaikki.org extract)"
    end
  end
end
