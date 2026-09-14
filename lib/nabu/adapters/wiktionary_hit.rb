# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Hittite (P99-7, the Q72-3 deferral): English
    # Wiktionary's Hittite entries via the kaikki.org wiktextract
    # extraction — the wiktionary-sux mold, second occupant of the shared
    # WiktionaryKaikki base. What it adds to the library: sense glosses
    # for the hittite desk's own lexicon — 414 of the 481 records carry
    # PURE-CUNEIFORM headwords (𒉿𒀀𒋻 wātar), so the P65 cuneiform sign
    # card joins senses by glyph beside TLHdig's tablet corpus — plus the
    # borrowing chains riding the descendants trees (𒋻𒌑𒍣 → Akkadian
    # 𒅴𒁄 — the hit→akk lane), minted as dictionary_reflexes. Roughly a
    # fifth of the records are "Broad transcription of …" romanization
    # pointers — kept as entries, the fold's romanized reach.
    #
    # == Upstream (verified 2026-09-13)
    #
    # https://kaikki.org/dictionary/Hittite/ — "466 distinct words", 481
    # records (4,327,281 B at fixture time, one JSON object per line).
    # Deprecation caveat and license: the WiktionaryKaikki class note;
    # fallback = filter the full extract by lang_code == "hit".
    class WiktionaryHit < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-hit",
        name: "Wiktionary Hittite — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Hittite/kaikki.org-dictionary-Hittite.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Hittite.jsonl"
      DICTIONARY_SLUG = "wiktionary-hit"
      LANGUAGE = "hit"
      TITLE = "Wiktionary — Hittite (kaikki.org extract)"
    end
  end
end
