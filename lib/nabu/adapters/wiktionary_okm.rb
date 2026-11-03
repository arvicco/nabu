# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Middle Korean: English Wiktionary's Middle Korean entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Middle Korean hangul prints
    # (ko-wikisource-mk). What it adds: the library's first Middle Korean
    # dictionary: hangul headwords with Old Korean (71 oko) etymons and
    # descendants into Korean and Jeju.
    #
    # Stored language okm (639-3, ko-wikisource-mk's tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Middle%20Korean/ — "965 distinct words";
    # 1,033 records (2,250,185 B, Last-Modified 2026-10-30; 4 carry a form_of
    # sense). Census through the house parser: 1,033 entries / 1,249 reflex
    # rows / 0 non-NFC / 0 glossless. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "okm".
    class WiktionaryOkm < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-okm",
        name: "Wiktionary Middle Korean — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Middle%20Korean/kaikki.org-dictionary-MiddleKorean.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-MiddleKorean.jsonl"
      DICTIONARY_SLUG = "wiktionary-okm"
      LANGUAGE = "okm"
      TITLE = "Wiktionary — Middle Korean (kaikki.org extract)"
    end
  end
end
