# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Ottoman Turkish: English Wiktionary's Ottoman Turkish entries
    # via the kaikki.org wiktextract extraction — the wiktionary-fa mold on the
    # shared WiktionaryKaikki base, for the turkic desk (the held UD Ottoman
    # treebank's language). What it adds: the library's first Ottoman Turkish
    # dictionary: Perso-Arabic-script headwords with Proto-Turkic (987),
    # Arabic (777), Old Anatolian Turkish (266) and Persian etymons, and the
    # descendant trees into Turkish, Armenian and the Balkan languages
    # (Serbo-Croatian, Bulgarian, Albanian, Romanian) — the Ottoman loan lanes.
    #
    # Stored language ota (639-3; kaikki's own lang_code).
    #
    # == Upstream (verified 2026-11-27)
    #
    # https://kaikki.org/dictionary/Ottoman%20Turkish/ — "8848 distinct
    # words"; 10,016 records (34,356,167 B, Last-Modified 2026-10-30; 519
    # carry a form_of sense; 15,251 senses). Census through the house parser:
    # 10,016 entries / 25,882 reflex rows (3,594 etymon + 22,288 descendant)
    # / 0 non-NFC / 2 glossless / 0 headwordless skips. Deprecation caveat
    # and license: the WiktionaryKaikki class note; fallback = filter the full
    # extract by lang_code == "ota".
    class WiktionaryOta < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-ota",
        name: "Wiktionary Ottoman Turkish — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Ottoman%20Turkish/kaikki.org-dictionary-OttomanTurkish.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-OttomanTurkish.jsonl"
      DICTIONARY_SLUG = "wiktionary-ota"
      LANGUAGE = "ota"
      TITLE = "Wiktionary — Ottoman Turkish (kaikki.org extract)"
    end
  end
end
