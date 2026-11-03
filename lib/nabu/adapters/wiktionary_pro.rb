# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Old Occitan: English Wiktionary's Old Occitan entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the troubadour and medieval Occitan holdings
    # on the Romance desk. What it adds: the library's first Old Occitan (Old
    # Provençal) dictionary: Latin etymons (398) and descendants into Occitan
    # and Catalan.
    #
    # Stored language pro (639-3 Old Provençal).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Old%20Occitan/ — "675 distinct words"; 695
    # records (1,205,239 B, Last-Modified 2026-10-30; 51 carry a form_of
    # sense). Census through the house parser: 695 entries / 2,004 reflex rows
    # / 0 non-NFC / 1 glossless. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "pro".
    class WiktionaryPro < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-pro",
        name: "Wiktionary Old Occitan — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Old%20Occitan/kaikki.org-dictionary-OldOccitan.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-OldOccitan.jsonl"
      DICTIONARY_SLUG = "wiktionary-pro"
      LANGUAGE = "pro"
      TITLE = "Wiktionary — Old Occitan (kaikki.org extract)"
    end
  end
end
