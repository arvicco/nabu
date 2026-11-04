# frozen_string_literal: true

require_relative "wiktionary_script_forms"

module Nabu
  module Adapters
    # Wiktionary-Vietnamese: English Wiktionary's Vietnamese entries via the
    # kaikki.org wiktextract extraction, on the WiktionaryScriptShelf base —
    # the library's first Vietnamese dictionary and its chữ Nôm lexicon:
    # the Han and Nôm character records with their quốc ngữ readings (馬 →
    # ngựa, mã …; Hán-Việt and Nôm readings kept apart), the Hán-Nôm
    # spellings of ordinary words (chó → 㹥, 𤝹, 犬 …), and the
    # Proto-Vietic / Proto-Austroasiatic etymons beside the Chinese loan
    # layer. For the held Vietnamese classical shelf (viet-wikisource) and
    # the Nôm sources the vi registry node anticipates.
    #
    # Stored language vi — the registry anchor itself (nabu-lects vi,
    # parent mkh-vie; the codemap aliases vie → vi). The Nôm script is NOT
    # a lect claim: the vi note stages a Nôm text by date, never by script,
    # and a dictionary shelf has no document date — the readings ride the
    # bare anchor.
    #
    # Script forms: `Hán-Nôm`-tagged forms on character records are the
    # older shape's READINGS (犭 → khuyển, 9,698 rows); `CJK`-tagged forms
    # on word records are the Han-script SPELLINGS (13,537 rows); the
    # nom-/han-viet-reading relations are the current shape (11,299 rows).
    #
    # == Upstream (verified 2026-11-04)
    #
    # https://kaikki.org/dictionary/Vietnamese/ — "45519 distinct words";
    # 83,424,329 B (Last-Modified 2026-10-30), 52,167 records, 0 non-NFC.
    # 9,112 character records carrying 11,850 senses; 3,559 records with
    # reading relations, 11,179 with script forms. Record grain census
    # (the whole file): 46,660 glossed; 5,447 glossless kept (5,435 for
    # readings/script forms, 12 for etymology alone); 60 empty stubs
    # skipped by rule (45 character, 15 word) → 52,107 entries expected.
    # Deprecation caveat and license: the WiktionaryKaikki class note;
    # fallback = filter the full extract by lang_code == "vi".
    class WiktionaryVi < WiktionaryScriptShelf
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-vi",
        name: "Wiktionary Vietnamese — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Vietnamese/kaikki.org-dictionary-Vietnamese.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Vietnamese.jsonl"
      DICTIONARY_SLUG = "wiktionary-vi"
      LANGUAGE = "vi"
      TITLE = "Wiktionary — Vietnamese (kaikki.org extract)"
      SCRIPT_FORMS = {
        "Hán-Nôm" => ["Hán-Nôm readings", "han-nom-reading"],
        "CJK" => ["Hán-Nôm forms", "han-nom-form"]
      }.freeze
    end
  end
end
