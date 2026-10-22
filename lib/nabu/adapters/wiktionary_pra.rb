# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Prakrit: English Wiktionary's Prakrit entries via the
    # kaikki.org wiktextract extraction — the wiktionary-akk mold on the
    # shared WiktionaryKaikki base, one of the South Asian dictionary
    # wave's seven shelves. What it adds: the first Prakrit dictionary
    # beside the Prakrit text shelves (prakrit-texts, the Jain Āgamas,
    # suttacentral's pra documents). Wiktionary heads Prakrit in Brāhmī
    # (𑀫𑀳𑀼 mahu "honey"); the Māhārāṣṭrī/Śaurasenī/Ardhamāgadhī variants
    # ride as senses and form-of pointers under the one collective code.
    # The wave's reflex engine: 1,131 of the 2,712 records carry
    # descendants trees into the New Indo-Aryan languages (pa 1,531 ·
    # hi 1,210 · mr 1,040 · ur 993 · sd 944 · gu 911 · omr 721 edges), and
    # the Sanskrit inheritance chains run back to Proto-Indo-European.
    # Stored language pra (the registry's collective anchor, held coarse).
    #
    # == Upstream (verified 2026-10-21)
    #
    # https://kaikki.org/dictionary/Prakrit/ — "2452 distinct words",
    # 2,712 records (16,188,581 B, Last-Modified 2026-10-03). Census
    # through the house parser: 2,712 entries / 20,311 reflex rows /
    # 0 non-NFC. Deprecation caveat and license: the WiktionaryKaikki
    # class note; fallback = filter the full extract by lang_code == "pra".
    class WiktionaryPra < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-pra",
        name: "Wiktionary Prakrit — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Prakrit/kaikki.org-dictionary-Prakrit.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Prakrit.jsonl"
      DICTIONARY_SLUG = "wiktionary-pra"
      LANGUAGE = "pra"
      TITLE = "Wiktionary — Prakrit (kaikki.org extract)"
    end
  end
end
