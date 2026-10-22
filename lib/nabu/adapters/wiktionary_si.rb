# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Sinhala: English Wiktionary's Sinhala entries via the
    # kaikki.org wiktextract extraction (kaikki names the language
    # "Sinhalese") — the wiktionary-akk mold on the shared
    # WiktionaryKaikki base, one of the South Asian dictionary wave's
    # seven shelves. What it adds: a Sinhala dictionary for 1,231 words
    # whose etymons cross the island's two lanes — Indo-Aryan descent
    # through Prakrit and Sanskrit (514 sa / 52 pra edges) and the Tamil
    # borrowings (150 ta edges, landing in the wiktionary-ta headword
    # space). Stored language sin (→ si through the held codemap alias).
    #
    # == Upstream (verified 2026-10-21)
    #
    # https://kaikki.org/dictionary/Sinhalese/ — "1231 distinct words",
    # 1,281 records (1,887,237 B, Last-Modified 2026-10-03; the
    # .../Sinhala/ spelling 404s). Census through the house parser:
    # 1,281 entries / 854 reflex rows / 0 non-NFC. Deprecation caveat and
    # license: the WiktionaryKaikki class note; fallback = filter the full
    # extract by lang_code == "si".
    class WiktionarySi < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-si",
        name: "Wiktionary Sinhala — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Sinhalese/kaikki.org-dictionary-Sinhalese.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Sinhalese.jsonl"
      DICTIONARY_SLUG = "wiktionary-si"
      LANGUAGE = "sin"
      TITLE = "Wiktionary — Sinhala (kaikki.org extract)"
    end
  end
end
