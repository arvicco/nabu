# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Occitan: English Wiktionary's Occitan entries via the kaikki.org
    # wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Occitan text (aranese, lo-congres).
    # What it adds: the library's first Occitan dictionary: Latin (1,714) and
    # Old Occitan (495 pro) etymons.
    #
    # Stored language oci (639-3).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Occitan/ — "7175 distinct words"; 7,521
    # records (32,023,246 B, Last-Modified 2026-10-30; 2,201 carry a form_of
    # sense). Census through the house parser: 7,521 entries / 3,383 reflex
    # rows / 0 non-NFC / 20 glossless. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "oc".
    class WiktionaryOc < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-oc",
        name: "Wiktionary Occitan — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Occitan/kaikki.org-dictionary-Occitan.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Occitan.jsonl"
      DICTIONARY_SLUG = "wiktionary-oc"
      LANGUAGE = "oci"
      TITLE = "Wiktionary — Occitan (kaikki.org extract)"
    end
  end
end
