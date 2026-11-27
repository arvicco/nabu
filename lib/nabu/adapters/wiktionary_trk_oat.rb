# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Old Anatolian Turkish: English Wiktionary's Old Anatolian
    # Turkish entries via the kaikki.org wiktextract extraction — the
    # wiktionary-fa mold on the shared WiktionaryKaikki base, beside
    # wiktionary-ota. What it adds: the Oghuz literary stage before Ottoman
    # (13th–15th c., Perso-Arabic script): headwords with Proto-Turkic (336)
    # and Persian/Arabic etymons, and descendant trees reaching Ottoman
    # Turkish (622 ota rows), Turkish, Azerbaijani and Gagauz — the crosswalk
    # edge that lets the etym walk climb from an Ottoman headword one stage up.
    #
    # Stored language trk-oat — Wiktionary's own etymology-language code,
    # verbatim (no ISO 639-3 code exists; the wiktionary-recon proto-shelf
    # stance: a shape-valid tag passes as itself). The lect registry holds no
    # trk-oat row yet; the posture (config/postures/wiktionary-trk-oat.yml)
    # records the pending claim and its candidate (the early edge of ota).
    #
    # == Upstream (verified 2026-11-27)
    #
    # https://kaikki.org/dictionary/Old%20Anatolian%20Turkish/ — "426
    # distinct words"; 607 records (1,670,030 B, Last-Modified 2026-10-30;
    # 27 carry a form_of sense; 1,013 senses). Census through the house
    # parser: 607 entries / 3,816 reflex rows (438 etymon + 3,378
    # descendant) / 0 non-NFC / 2 glossless / 0 headwordless skips.
    # Deprecation caveat and license: the WiktionaryKaikki class note;
    # fallback = filter the full extract by lang_code == "trk-oat".
    class WiktionaryTrkOat < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-trk-oat",
        name: "Wiktionary Old Anatolian Turkish — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Old%20Anatolian%20Turkish/kaikki.org-dictionary-OldAnatolianTurkish.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-OldAnatolianTurkish.jsonl"
      DICTIONARY_SLUG = "wiktionary-trk-oat"
      LANGUAGE = "trk-oat"
      TITLE = "Wiktionary — Old Anatolian Turkish (kaikki.org extract)"
    end
  end
end
