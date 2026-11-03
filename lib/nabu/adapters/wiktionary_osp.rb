# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Old Spanish: English Wiktionary's Old Spanish entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Old Spanish text (osta). What it
    # adds: the library's first Old Spanish dictionary: Latin (640) and Arabic
    # (36) etymons, descendants into Spanish and Ladino.
    #
    # Stored language osp (639-3, osta's tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Old%20Spanish/ — "1429 distinct words";
    # 1,501 records (3,611,593 B, Last-Modified 2026-10-30; 446 carry a
    # form_of sense). Census through the house parser: 1,501 entries / 3,518
    # reflex rows / 0 non-NFC / 9 glossless. Deprecation caveat and license:
    # the WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "osp".
    class WiktionaryOsp < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-osp",
        name: "Wiktionary Old Spanish — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Old%20Spanish/kaikki.org-dictionary-OldSpanish.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-OldSpanish.jsonl"
      DICTIONARY_SLUG = "wiktionary-osp"
      LANGUAGE = "osp"
      TITLE = "Wiktionary — Old Spanish (kaikki.org extract)"
    end
  end
end
