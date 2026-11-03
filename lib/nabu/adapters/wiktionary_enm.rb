# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Middle English: English Wiktionary's Middle English entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Middle English text (cme's Corpus of
    # Middle English Prose and Verse, 1.36 million passages). What it adds:
    # the library's first Middle English dictionary: senses for 49,377 words
    # and an etymon layer back through Old English (4,403 ang edges),
    # Proto-Germanic (2,204) and the Anglo-Norman/Old French donor lane (2,180
    # fro, 652 xno).
    #
    # Stored language enm (639-3, the held cme text's own tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Middle%20English/ — "49377 distinct
    # words"; 56,687 records (72,162,589 B, Last-Modified 2026-10-30; 3,522
    # carry a form_of sense). Census through the house parser: 56,687 entries
    # / 40,589 reflex rows / 0 non-NFC / 17 glossless. Deprecation caveat and
    # license: the WiktionaryKaikki class note; fallback = filter the full
    # extract by lang_code == "enm".
    class WiktionaryEnm < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-enm",
        name: "Wiktionary Middle English — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Middle%20English/kaikki.org-dictionary-MiddleEnglish.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-MiddleEnglish.jsonl"
      DICTIONARY_SLUG = "wiktionary-enm"
      LANGUAGE = "enm"
      TITLE = "Wiktionary — Middle English (kaikki.org extract)"
    end
  end
end
