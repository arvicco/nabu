# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Dhivehi: English Wiktionary's Dhivehi (Maldivian) entries
    # via the kaikki.org wiktextract extraction — the wiktionary-akk mold
    # on the shared WiktionaryKaikki base, one of the South Asian
    # dictionary wave's seven shelves. What it adds: the library's first
    # Dhivehi material — Thaana headwords for 1,882 words whose etymons
    # read the Insular Indo-Aryan line back through Prakrit and Sanskrit
    # (768 sa / 103 pra edges at census), beside the Arabic and Persian
    # donor lanes of the Maldivian lexicon.
    #
    # Stored language div, carried verbatim: the lect registry holds no
    # Dhivehi node yet (the dv anchor + div alias are a named mint
    # candidate). A dictionary shelf resolves at its own grain, so the
    # code rides as-is and resolves once the node lands.
    #
    # == Upstream (verified 2026-10-21)
    #
    # https://kaikki.org/dictionary/Dhivehi/ — "1882 distinct words",
    # 2,047 records (3,390,132 B, Last-Modified 2026-10-03). Census
    # through the house parser: 2,047 entries / 1,462 reflex rows /
    # 0 non-NFC. Deprecation caveat and license: the WiktionaryKaikki
    # class note; fallback = filter the full extract by lang_code == "dv".
    class WiktionaryDv < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-dv",
        name: "Wiktionary Dhivehi — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Dhivehi/kaikki.org-dictionary-Dhivehi.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Dhivehi.jsonl"
      DICTIONARY_SLUG = "wiktionary-dv"
      LANGUAGE = "div"
      TITLE = "Wiktionary — Dhivehi (kaikki.org extract)"
    end
  end
end
