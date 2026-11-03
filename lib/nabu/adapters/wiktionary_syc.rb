# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Classical Syriac: English Wiktionary's Classical Syriac entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Syriac text (syriac-corpus,
    # peshitta, etcbc-syriac). What it adds: the library's first Syriac
    # dictionary: Syriac-script headwords with Akkadian (222), Greek (165),
    # Proto-Semitic (120) and Aramaic (86) etymons, and loans out into
    # Armenian, Arabic and Malayalam.
    #
    # Stored language syc (639-3, the held Syriac corpora's tag).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Classical%20Syriac/ — "2761 distinct
    # words"; 3,911 records (15,429,144 B, Last-Modified 2026-10-30; 272 carry
    # a form_of sense). Census through the house parser: 3,911 entries / 4,315
    # reflex rows / 0 non-NFC / 0 glossless. Deprecation caveat and license:
    # the WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "syc".
    class WiktionarySyc < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-syc",
        name: "Wiktionary Classical Syriac — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Classical%20Syriac/kaikki.org-dictionary-ClassicalSyriac.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-ClassicalSyriac.jsonl"
      DICTIONARY_SLUG = "wiktionary-syc"
      LANGUAGE = "syc"
      TITLE = "Wiktionary — Classical Syriac (kaikki.org extract)"
    end
  end
end
