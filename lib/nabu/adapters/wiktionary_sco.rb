# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Scots: English Wiktionary's Scots entries via the kaikki.org
    # wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Older Scots in eebo-tcp. What it
    # adds: the library's first Scots dictionary: etymons through Middle
    # English (888), Old English (750) and Old Norse (196).
    #
    # Stored language sco (639-3).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Scots/ — "5127 distinct words"; 6,042
    # records (8,130,861 B, Last-Modified 2026-10-30; 860 carry a form_of
    # sense). Census through the house parser: 6,042 entries / 3,602 reflex
    # rows / 0 non-NFC / 4 glossless. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "sco".
    class WiktionarySco < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-sco",
        name: "Wiktionary Scots — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Scots/kaikki.org-dictionary-Scots.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Scots.jsonl"
      DICTIONARY_SLUG = "wiktionary-sco"
      LANGUAGE = "sco"
      TITLE = "Wiktionary — Scots (kaikki.org extract)"
    end
  end
end
