# frozen_string_literal: true

require_relative "wiktionary_script_forms"

module Nabu
  module Adapters
    # Wiktionary-Tày: English Wiktionary's Tày entries via the kaikki.org
    # wiktextract extraction, on the WiktionaryScriptShelf base — the
    # library's first Tày dictionary: Latin-orthography headwords (two
    # dialect pronunciations, Thạch An–Tràng Định and Trùng Khánh) with
    # their Nôm Tày spellings as `forms` tagged `CJK`, the Nôm Tày
    # character records glossed "Nôm form of …", and Proto-Tai etymons.
    #
    # Stored language tyz — the registry anchor (nabu-lects tyz, parent
    # tai; no ISO 639-1 code, so no codemap row). Nôm Tày is a script, not
    # a lect: the tyz note names it, no node is minted.
    #
    # The local FILENAME is ASCII ("Tay") while upstream's artifact name is
    # "kaikki.org-dictionary-Tày.jsonl" (percent-encoded in the URL):
    # FileFetch takes the two separately, and an ASCII name keeps the
    # canonical tree clear of filesystem normalization drift (APFS
    # preserves NFC/NFD bytes, discover's glob would have to match them).
    #
    # == Upstream (verified 2026-11-04)
    #
    # https://kaikki.org/dictionary/T%C3%A0y/ — "1203 distinct words";
    # 2,024,890 B (Last-Modified 2026-10-30), 1,515 records, 0 non-NFC;
    # 138 character records carrying 150 senses (149 "Nôm form of …");
    # 82 word records carry 100 Nôm Tày spellings. Record grain census
    # (the whole file): 1,495 glossed; 6 glossless kept (1 for its
    # spellings, 5 for etymology); 14 empty stubs skipped by rule → 1,501
    # entries expected. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "tyz".
    class WiktionaryTyz < WiktionaryScriptShelf
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-tyz",
        name: "Wiktionary Tày — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/T%C3%A0y/kaikki.org-dictionary-T%C3%A0y.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Tay.jsonl"
      DICTIONARY_SLUG = "wiktionary-tyz"
      LANGUAGE = "tyz"
      TITLE = "Wiktionary — Tày (kaikki.org extract)"
      SCRIPT_FORMS = { "CJK" => ["Nôm Tày forms", "nom-tay-form"] }.freeze
    end
  end
end
