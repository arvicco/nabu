# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Persian: English Wiktionary's Persian entries via the
    # kaikki.org wiktextract extraction — the wiktionary-akk mold on the
    # shared WiktionaryKaikki base. What it adds: the library's first New
    # Persian dictionary (the held fas text — OpenITI's Persian slice,
    # perseus-farsilit, the iedc documents — had none): sense glosses for
    # 17,651 words, and an etymon layer reaching back through Middle
    # Persian (746 pal edges) and Old Persian (276 peo) to Proto-Iranian
    # (935 ira-pro), beside the Arabic donor lane (2,532 ar) and the
    # descendant trees into Ottoman Turkish, Hindustani and Armenian. The
    # headword space is mostly modern, with the classical vocabulary
    # riding it (upstream sense tags at census: 792 archaic, 556 obsolete,
    # 138 Classical-Persian, 137 poetic — tags the house parser renders
    # only on gloss-less senses, a family-wide choice, not mined here).
    #
    # Stored language fas (639-3), resolving through the held codemap
    # alias fas → fa (the Persian anchor, parent pal).
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Persian/ — "17651 distinct words"
    # (28,272 senses); 20,350 records (95,770,880 B, Last-Modified
    # 2026-10-30), every record lang_code "fa". Census through the house
    # parser: 20,350 entries / 47,431 reflex rows / 0 non-NFC / 15
    # glossless. Deprecation caveat and license: the WiktionaryKaikki
    # class note; fallback = filter the full extract by lang_code == "fa".
    class WiktionaryFa < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-fa",
        name: "Wiktionary Persian — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Persian/kaikki.org-dictionary-Persian.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Persian.jsonl"
      DICTIONARY_SLUG = "wiktionary-fa"
      LANGUAGE = "fas"
      TITLE = "Wiktionary — Persian (kaikki.org extract)"
    end
  end
end
