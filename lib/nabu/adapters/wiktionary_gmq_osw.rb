# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Old Swedish: English Wiktionary's Old Swedish entries via the
    # kaikki.org wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held fornsvenska corpus. What it adds: an
    # English-glossed Old Swedish shelf beside the Swedish-language
    # fsv-lexica: Old Norse (871) and Proto-Germanic (791) etymons.
    #
    # Stored language sv — the held fornsvenska text's own tag (kaikki's
    # gmq-osw has no ISO code); the per-source override in
    # config/lect_overrides.yml resolves it to the sv:old stage.
    #
    # == Upstream (verified 2026-11-02)
    #
    # https://kaikki.org/dictionary/Old%20Swedish/ — "1404 distinct words";
    # 1,440 records (8,596,849 B, Last-Modified 2026-10-30; 231 carry a
    # form_of sense). Census through the house parser: 1,440 entries / 2,904
    # reflex rows / 0 non-NFC / 1 glossless. Deprecation caveat and license:
    # the WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "gmq-osw".
    class WiktionaryGmqOsw < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-gmq-osw",
        name: "Wiktionary Old Swedish — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Old%20Swedish/kaikki.org-dictionary-OldSwedish.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-OldSwedish.jsonl"
      DICTIONARY_SLUG = "wiktionary-gmq-osw"
      LANGUAGE = "sv"
      TITLE = "Wiktionary — Old Swedish (kaikki.org extract)"
    end
  end
end
