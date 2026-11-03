# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Korean: English Wiktionary's Korean entries via the kaikki.org
    # wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Korean text (okhc, 1.48 million
    # passages, mostly Hanmun records). What it adds: the library's first
    # Korean dictionary: modern hangul headwords, Sino-Korean words with their
    # hanja, and Middle Korean (183 oko) etymons beside the loan lanes.
    #
    # Stored language ko (okhc's own tag; the dictionary-language filter does
    # not widen ko to kor).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Korean/ — "57810 distinct words"; 64,457
    # records (207,649,961 B, Last-Modified 2026-10-30; 15,138 carry a form_of
    # sense). Census through the house parser: 64,457 entries / 5,881 reflex
    # rows / 0 non-NFC / 6,693 glossless. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "ko".
    class WiktionaryKo < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-ko",
        name: "Wiktionary Korean — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Korean/kaikki.org-dictionary-Korean.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Korean.jsonl"
      DICTIONARY_SLUG = "wiktionary-ko"
      LANGUAGE = "ko"
      TITLE = "Wiktionary — Korean (kaikki.org extract)"
    end
  end
end
