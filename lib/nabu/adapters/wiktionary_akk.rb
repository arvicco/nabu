# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Akkadian (P99-7, the Q72-3 deferral): English
    # Wiktionary's Akkadian entries via the kaikki.org wiktextract
    # extraction — the wiktionary-sux mold, first occupant of the shared
    # WiktionaryKaikki base. What it adds to the library: sense glosses
    # for the tablet world's lingua franca — 540 of the 1,348 records
    # carry PURE-CUNEIFORM headwords (𒁾 Sumerograms), so the P65
    # cuneiform sign card joins senses by glyph — plus the borrowing
    # chains riding the descendants trees (ṭuppum → Elamite 𒁾 and the
    # Aramaic/Arabic/Hebrew loan lanes), minted as dictionary_reflexes.
    # The stored language is akk — the sux shelf's 43 sux→akk reflex
    # edges point INTO this shelf's headword space.
    #
    # == Upstream (verified 2026-09-13)
    #
    # https://kaikki.org/dictionary/Akkadian/ — "1236 distinct words",
    # 1,348 records (2,865,176 B at fixture time, one JSON object per
    # line). Deprecation caveat and license: the WiktionaryKaikki class
    # note; fallback = filter the full extract by lang_code == "akk".
    class WiktionaryAkk < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-akk",
        name: "Wiktionary Akkadian — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Akkadian/kaikki.org-dictionary-Akkadian.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Akkadian.jsonl"
      DICTIONARY_SLUG = "wiktionary-akk"
      LANGUAGE = "akk"
      TITLE = "Wiktionary — Akkadian (kaikki.org extract)"
    end
  end
end
