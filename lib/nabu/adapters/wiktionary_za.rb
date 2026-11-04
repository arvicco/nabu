# frozen_string_literal: true

require_relative "wiktionary_script_forms"

module Nabu
  module Adapters
    # Wiktionary-Zhuang: English Wiktionary's Zhuang entries via the
    # kaikki.org wiktextract extraction, on the WiktionaryScriptShelf base —
    # the library's first Zhuang dictionary and its one structured Sawndip
    # lexicon: Sawcuengh (the 1982 Latin standard) headwords with their
    # Sawndip (古壮字) spellings as `forms` tagged `Sawndip`, unencoded
    # characters written as Ideographic Description Sequences (⿰目荷) and
    # kept verbatim. Proto-Tai etymons and the Chinese loan layer ride the
    # family reflexes.
    #
    # Stored language za — the registry anchor (nabu-lects za, parent tai;
    # the codemap aliases zha → za). za is a MACROLANGUAGE whose sixteen
    # ISO member codes (zyb, zch, zgb …) stay identity: Wiktionary's
    # Zhuang header is Standard Zhuang (Yongbei-based) throughout and the
    # dialect labels ride verbatim in the bodies ("(dialectal, including
    # Wuming)"). Sawndip is a script, not a lect: the registry's za note
    # names it (held text za~hani) — no script node exists or is minted.
    #
    # == Upstream (verified 2026-11-04)
    #
    # https://kaikki.org/dictionary/Zhuang/ — "2981 distinct words";
    # 7,486,225 B (Last-Modified 2026-10-30), 3,579 records, 0 non-NFC;
    # 813 records carry 3,659 Sawndip forms (all on word records). Record
    # grain census (the whole file): 3,575 glossed; 2 glossless kept for
    # their etymology; 2 empty stubs skipped by rule → 3,577 entries
    # expected. Deprecation caveat and license: the WiktionaryKaikki class
    # note; fallback = filter the full extract by lang_code == "za".
    class WiktionaryZa < WiktionaryScriptShelf
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-za",
        name: "Wiktionary Zhuang — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Zhuang/kaikki.org-dictionary-Zhuang.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Zhuang.jsonl"
      DICTIONARY_SLUG = "wiktionary-za"
      LANGUAGE = "za"
      TITLE = "Wiktionary — Zhuang (kaikki.org extract)"
      SCRIPT_FORMS = { "Sawndip" => ["Sawndip forms", "sawndip-form"] }.freeze
    end
  end
end
