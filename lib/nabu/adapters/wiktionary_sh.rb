# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Serbo-Croatian: English Wiktionary's Serbo-Croatian entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Serbian and Croatian text
    # (sr-wikisource, hr-wikisource, eltec-srp, elektire, vuk-danicic,
    # gams-zrcalo — 1.27 million passages). What it adds: the library's first
    # Serbo-Croatian dictionary, Latin and Cyrillic headwords both:
    # Proto-Slavic (7,327), German (1,708) and Ottoman Turkish (1,483)
    # etymons.
    #
    # Stored language srp, every entry annotated language hrv — Wiktionary's
    # Serbo-Croatian is the one pluricentric language both held tags write,
    # and the dictionary-language filter's grain fold lets an entry's
    # annotation language answer a second tag.
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Serbo-Croatian/ — "66998 distinct words";
    # 70,466 records (385,655,385 B, Last-Modified 2026-10-30; 10,086 carry a
    # form_of sense). Census through the house parser: 70,466 entries / 18,632
    # reflex rows / 0 non-NFC / 335 glossless. Deprecation caveat and license:
    # the WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "sh".
    class WiktionarySh < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-sh",
        name: "Wiktionary Serbo-Croatian — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Serbo-Croatian/kaikki.org-dictionary-SerboCroatian.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-SerboCroatian.jsonl"
      DICTIONARY_SLUG = "wiktionary-sh"
      LANGUAGE = "srp"
      TITLE = "Wiktionary — Serbo-Croatian (kaikki.org extract)"

      # The second held tag every entry also answers (class note).
      SECOND_LANGUAGE = "hrv"

      def parse(document_ref)
        parsed = super
        document = Nabu::DictionaryDocument.new(
          slug: parsed.slug, language: parsed.language, title: parsed.title, canonical_path: parsed.canonical_path
        )
        parsed.each do |entry|
          document << entry.with(annotations: entry.annotations.merge("language" => SECOND_LANGUAGE))
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{manifest.id}: #{document_ref.id}: #{e.message}"
      end
    end
  end
end
