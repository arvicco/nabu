# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Breton: English Wiktionary's Breton entries via the kaikki.org
    # wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Breton text (br-wikisource). What it
    # adds: the library's first Breton dictionary, with Middle Breton (230
    # xbm) and Old Breton (158 obt) etymons and the Proto-Celtic and
    # Proto-Brythonic chains (385 / 381).
    #
    # Stored language bre (639-3, the held br-wikisource tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Breton/ — "2245 distinct words"; 2,336
    # records (3,824,751 B, Last-Modified 2026-10-30; 538 carry a form_of
    # sense). Census through the house parser: 2,336 entries / 1,688 reflex
    # rows / 0 non-NFC / 3 glossless. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "br".
    class WiktionaryBr < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-br",
        name: "Wiktionary Breton — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Breton/kaikki.org-dictionary-Breton.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Breton.jsonl"
      DICTIONARY_SLUG = "wiktionary-br"
      LANGUAGE = "bre"
      TITLE = "Wiktionary — Breton (kaikki.org extract)"
    end
  end
end
