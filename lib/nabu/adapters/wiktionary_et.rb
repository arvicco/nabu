# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Estonian: English Wiktionary's Estonian entries via the kaikki.org
    # wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Old Written Estonian text (vakk).
    # What it adds: the library's first Estonian dictionary: Proto-Finnic
    # (1,532) and Proto-Uralic (138) etymons beside the German and Middle Low
    # German donor lanes (433 de, 226 gml) that shaped the written language
    # vakk holds.
    #
    # Stored language et (vakk's own tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Estonian/ — "12657 distinct words"; 13,549
    # records (56,323,247 B, Last-Modified 2026-10-30; 4,928 carry a form_of
    # sense). Census through the house parser: 13,549 entries / 4,095 reflex
    # rows / 0 non-NFC / 2 glossless. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "et".
    class WiktionaryEt < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-et",
        name: "Wiktionary Estonian — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Estonian/kaikki.org-dictionary-Estonian.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Estonian.jsonl"
      DICTIONARY_SLUG = "wiktionary-et"
      LANGUAGE = "et"
      TITLE = "Wiktionary — Estonian (kaikki.org extract)"
    end
  end
end
