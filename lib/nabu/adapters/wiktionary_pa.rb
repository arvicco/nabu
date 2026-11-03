# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Punjabi: English Wiktionary's Punjabi entries via the kaikki.org
    # wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Gurbani text (shabados). What it
    # adds: an English-glossed Punjabi shelf beside the Punjabi-language
    # mahan-kosh: Sanskrit (2,192), Classical Persian (1,225), Arabic (702)
    # and Prakrit (612) etymons.
    #
    # Stored language pan (639-3, shabados's tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Punjabi/ — "9533 distinct words"; 10,749
    # records (38,069,877 B, Last-Modified 2026-10-30; 2,663 carry a form_of
    # sense). Census through the house parser: 10,749 entries / 6,165 reflex
    # rows / 0 non-NFC / 4 glossless. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "pa".
    class WiktionaryPa < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-pa",
        name: "Wiktionary Punjabi — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Punjabi/kaikki.org-dictionary-Punjabi.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Punjabi.jsonl"
      DICTIONARY_SLUG = "wiktionary-pa"
      LANGUAGE = "pan"
      TITLE = "Wiktionary — Punjabi (kaikki.org extract)"
    end
  end
end
