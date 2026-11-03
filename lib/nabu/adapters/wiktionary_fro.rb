# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Old French: English Wiktionary's Old French entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Old French text (bfm, UD Old
    # French). What it adds: the library's first Old French dictionary: Latin
    # etymons (2,621 la, 518 la-vul) and Frankish donors (253 frk), and dense
    # descendant trees into Middle and Modern French, Middle English and
    # Anglo-Norman (46,722 reflex rows).
    #
    # Stored language fro (639-3, bfm's own tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Old%20French/ — "8690 distinct words";
    # 9,280 records (37,234,970 B, Last-Modified 2026-10-30; 901 carry a
    # form_of sense). Census through the house parser: 9,280 entries / 46,722
    # reflex rows / 0 non-NFC / 10 glossless. Deprecation caveat and license:
    # the WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "fro".
    class WiktionaryFro < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-fro",
        name: "Wiktionary Old French — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Old%20French/kaikki.org-dictionary-OldFrench.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-OldFrench.jsonl"
      DICTIONARY_SLUG = "wiktionary-fro"
      LANGUAGE = "fro"
      TITLE = "Wiktionary — Old French (kaikki.org extract)"
    end
  end
end
