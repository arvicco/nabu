# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Gothic: English Wiktionary's Gothic entries via the kaikki.org
    # wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Gothic Bible (proiel, UD Gothic).
    # What it adds: the library's first Gothic dictionary: 23,034 entries
    # (Gothic-script headwords, many of them inflected-form entries pointing
    # to their lemma) with Proto-Germanic (1,755) and Greek (166) etymons.
    #
    # Stored language got (639-3, the held proiel/UD tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Gothic/ — "22781 distinct words"; 23,034
    # records (47,421,601 B, Last-Modified 2026-10-30; 7,729 carry a form_of
    # sense). Census through the house parser: 23,034 entries / 3,946 reflex
    # rows / 0 non-NFC / 0 glossless. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "got".
    class WiktionaryGot < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-got",
        name: "Wiktionary Gothic — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Gothic/kaikki.org-dictionary-Gothic.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Gothic.jsonl"
      DICTIONARY_SLUG = "wiktionary-got"
      LANGUAGE = "got"
      TITLE = "Wiktionary — Gothic (kaikki.org extract)"
    end
  end
end
