# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Middle High German: English Wiktionary's Middle High German entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Middle High German text (rem,
    # 359,326 passages). What it adds: the library's first Middle High German
    # dictionary, with Old High German (460 goh) etymons and descendants into
    # German, Alemannic, Bavarian, Cimbrian and Yiddish.
    #
    # Stored language gmh (639-3, rem's tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Middle%20High%20German/ — "1958 distinct
    # words"; 2,142 records (10,197,573 B, Last-Modified 2026-10-30; 1,330
    # carry a form_of sense). Census through the house parser: 2,142 entries /
    # 7,041 reflex rows / 0 non-NFC / 1 glossless. Deprecation caveat and
    # license: the WiktionaryKaikki class note; fallback = filter the full
    # extract by lang_code == "gmh".
    class WiktionaryGmh < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-gmh",
        name: "Wiktionary Middle High German — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Middle%20High%20German/kaikki.org-dictionary-MiddleHighGerman.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-MiddleHighGerman.jsonl"
      DICTIONARY_SLUG = "wiktionary-gmh"
      LANGUAGE = "gmh"
      TITLE = "Wiktionary — Middle High German (kaikki.org extract)"
    end
  end
end
