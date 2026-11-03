# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Aramaic: English Wiktionary's Aramaic entries via the kaikki.org
    # wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Aramaic text (the Sefaria Talmud and
    # Targum layers, dss, elephantine, etcbc-targum). What it adds: a first
    # dedicated Aramaic dictionary (the held BDB/OSHB shelves carry Biblical
    # Aramaic only inside Hebrew lexica): Proto-Semitic (92), Akkadian (44)
    # and Old Persian (17) etymons, descendants into Syriac and Neo-Aramaic.
    #
    # Stored language arc (639-3; inside the NFC exemption list — the extract
    # is NFC already, 0 non-NFC lines).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Aramaic/ — "2072 distinct words"; 2,396
    # records (4,469,385 B, Last-Modified 2026-10-30; 87 carry a form_of
    # sense). Census through the house parser: 2,396 entries / 3,080 reflex
    # rows / 0 non-NFC / 1 glossless. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "arc".
    class WiktionaryArc < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-arc",
        name: "Wiktionary Aramaic — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Aramaic/kaikki.org-dictionary-Aramaic.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Aramaic.jsonl"
      DICTIONARY_SLUG = "wiktionary-arc"
      LANGUAGE = "arc"
      TITLE = "Wiktionary — Aramaic (kaikki.org extract)"
    end
  end
end
