# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Old Norse: English Wiktionary's Old Norse entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held West Norse text (menota, menotec,
    # rundata, UD Icelandic). What it adds: a third Old Norse shelf beside
    # Cleasby-Vigfusson and Zoëga, its weight in the descendant trees (38,535
    # reflex rows into Icelandic, Faroese, Norwegian, Swedish, Danish) and the
    # Proto-Germanic etymons (2,736).
    #
    # Stored language non (the registry's undivided Old Norse anchor, the
    # cleasby-vigfusson precedent).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Old%20Norse/ — "10103 distinct words";
    # 11,403 records (38,965,677 B, Last-Modified 2026-10-30; 6,368 carry a
    # form_of sense). Census through the house parser: 11,403 entries / 38,535
    # reflex rows / 0 non-NFC / 7 glossless. Deprecation caveat and license:
    # the WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "non".
    class WiktionaryNon < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-non",
        name: "Wiktionary Old Norse — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Old%20Norse/kaikki.org-dictionary-OldNorse.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-OldNorse.jsonl"
      DICTIONARY_SLUG = "wiktionary-non"
      LANGUAGE = "non"
      TITLE = "Wiktionary — Old Norse (kaikki.org extract)"
    end
  end
end
