# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Old Frisian: English Wiktionary's Old Frisian entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Old Frisian text (corpus-oudfries).
    # What it adds: the library's first Old Frisian dictionary:
    # Proto-West-Germanic (304) and Proto-Germanic (207) etymons, descendants
    # into North, West and Saterland Frisian.
    #
    # Stored language ofs (639-3, corpus-oudfries's tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Old%20Frisian/ — "610 distinct words"; 654
    # records (1,417,023 B, Last-Modified 2026-10-30; 35 carry a form_of
    # sense). Census through the house parser: 654 entries / 1,846 reflex rows
    # / 0 non-NFC / 0 glossless. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "ofs".
    class WiktionaryOfs < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-ofs",
        name: "Wiktionary Old Frisian — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Old%20Frisian/kaikki.org-dictionary-OldFrisian.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-OldFrisian.jsonl"
      DICTIONARY_SLUG = "wiktionary-ofs"
      LANGUAGE = "ofs"
      TITLE = "Wiktionary — Old Frisian (kaikki.org extract)"
    end
  end
end
