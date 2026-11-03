# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Catalan: English Wiktionary's Catalan entries via the kaikki.org
    # wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Catalan text (ctilc). What it adds:
    # the library's first Catalan dictionary — modern headwords (most of them
    # inflected-form entries pointing to their lemma) with Latin (9,012),
    # Greek (1,285) and Old Occitan (829) etymons.
    #
    # Stored language cat (639-3, ctilc's tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Catalan/ — "189801 distinct words";
    # 198,685 records (247,179,824 B, Last-Modified 2026-10-30; 162,088 carry
    # a form_of sense). Census through the house parser: 198,685 entries /
    # 18,209 reflex rows / 0 non-NFC / 31 glossless. Deprecation caveat and
    # license: the WiktionaryKaikki class note; fallback = filter the full
    # extract by lang_code == "ca".
    class WiktionaryCa < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-ca",
        name: "Wiktionary Catalan — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Catalan/kaikki.org-dictionary-Catalan.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Catalan.jsonl"
      DICTIONARY_SLUG = "wiktionary-ca"
      LANGUAGE = "cat"
      TITLE = "Wiktionary — Catalan (kaikki.org extract)"
    end
  end
end
