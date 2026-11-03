# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Middle French: English Wiktionary's Middle French entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Middle French text (bfm's later
    # documents, UD Middle French). What it adds: the library's first Middle
    # French dictionary, chained to Old French (1,597 fro etymons) and Latin
    # (1,043).
    #
    # Stored language frm (639-3, the held UD tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Middle%20French/ — "4714 distinct words";
    # 4,956 records (13,336,591 B, Last-Modified 2026-10-30; 763 carry a
    # form_of sense). Census through the house parser: 4,956 entries / 9,141
    # reflex rows / 0 non-NFC / 6 glossless. Deprecation caveat and license:
    # the WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "frm".
    class WiktionaryFrm < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-frm",
        name: "Wiktionary Middle French — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Middle%20French/kaikki.org-dictionary-MiddleFrench.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-MiddleFrench.jsonl"
      DICTIONARY_SLUG = "wiktionary-frm"
      LANGUAGE = "frm"
      TITLE = "Wiktionary — Middle French (kaikki.org extract)"
    end
  end
end
