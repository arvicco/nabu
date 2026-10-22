# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Kannada: English Wiktionary's Kannada entries via the
    # kaikki.org wiktextract extraction — the wiktionary-akk mold on the
    # shared WiktionaryKaikki base, one of the South Asian dictionary
    # wave's seven shelves. What it adds: a Kannada dictionary beside the
    # Old Kannada classics (kannada-texts) and the Kalyāṇa Cālukya
    # epigraphy — glosses for 2,495 words with Sanskrit, Proto-Dravidian
    # and Old Kannada etymons (961 sa / 294 dra-pro / 143 dra-okn edges at
    # census). Stored language kan (→ kn through the held codemap alias).
    #
    # == Upstream (verified 2026-10-21)
    #
    # https://kaikki.org/dictionary/Kannada/ — "2495 distinct words",
    # 2,741 records (8,923,875 B, Last-Modified 2026-10-03). Census
    # through the house parser: 2,741 entries / 1,857 reflex rows /
    # 0 non-NFC. Deprecation caveat and license: the WiktionaryKaikki
    # class note; fallback = filter the full extract by lang_code == "kn".
    class WiktionaryKn < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-kn",
        name: "Wiktionary Kannada — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Kannada/kaikki.org-dictionary-Kannada.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Kannada.jsonl"
      DICTIONARY_SLUG = "wiktionary-kn"
      LANGUAGE = "kan"
      TITLE = "Wiktionary — Kannada (kaikki.org extract)"
    end
  end
end
