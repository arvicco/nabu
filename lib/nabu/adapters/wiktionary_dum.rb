# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Middle Dutch: English Wiktionary's Middle Dutch entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Middle Dutch text
    # (corpus-gysseling). What it adds: the library's first Middle Dutch
    # dictionary: Old Dutch (1,301 odt) and Proto-Germanic etymons,
    # descendants into Dutch, Afrikaans, Limburgish.
    #
    # Stored language dum (639-3, corpus-gysseling's tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Middle%20Dutch/ — "2031 distinct words";
    # 2,342 records (5,989,862 B, Last-Modified 2026-10-30; 319 carry a
    # form_of sense). Census through the house parser: 2,342 entries / 10,572
    # reflex rows / 0 non-NFC / 5 glossless. Deprecation caveat and license:
    # the WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "dum".
    class WiktionaryDum < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-dum",
        name: "Wiktionary Middle Dutch — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Middle%20Dutch/kaikki.org-dictionary-MiddleDutch.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-MiddleDutch.jsonl"
      DICTIONARY_SLUG = "wiktionary-dum"
      LANGUAGE = "dum"
      TITLE = "Wiktionary — Middle Dutch (kaikki.org extract)"
    end
  end
end
