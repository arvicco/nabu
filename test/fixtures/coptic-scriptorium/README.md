# Coptic Scriptorium fixtures (P17-1 Phase B)

Real files from `github.com/CopticScriptorium/corpora` at release tag
**v6.2.0** (commit `6c2acf0ebebf62f40c3834259cf6fd734238e371`, "Late 2025
Release", 2025-12-12 — the pinned sync tag). Retrieved **2026-07-13** via
`raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/<path>`.
Owner-approved fixture plan (survey §9, approved 2026-07-13), including the
optional 4th documentary sample. Layout mirrors the upstream corpus tree so
the adapter's discover walks fixtures exactly as it walks canonical.

## Files and the quirks each preserves

- `besa-letters/besa.letters_TT/on_lack_of_food.tt` (whole, 22 KB)
  — the MODERN TT dialect (v4.5.0: `<translation>` elements inside the
  verse, `vid_n` per-verse CTS urns, expanded `orig_group`/`orig` spans).
  Gold everything; full MS metadata block (MONB.BB codex, Naples,
  `origDate` 0500–0799 precision `medium` → the document_axes assertion,
  Trismegistos 108395); entity spans; morphs — including **the
  morph-split-across-line-break quirk** (ϣⲡ|ϩⲓⲥⲉ: `lb_n` 1 closes and 2
  opens INSIDE one norm token, between its two morphs); Greek `<lang>`
  spans; supralinear strokes (U+FE24–26, combining overlines) live in
  `orig` vs stripped in `norm`; the `⳿` morphological divider (U+2CFF, the
  conventions §9 `cop` fold subject); CC-BY 4.0 license string with HTML
  entities (`&lt;a href=…&gt;`) → per-document `attribution` override.
- `besa-letters/besa.letters_CONLLU/on_lack_of_food.conllu` (whole, 9.7 KB)
  — the CoNLL-U twin, NOT parsed in v1; checked in for the deferred
  UD-FEATS join (survey §4b/v2-3). Discover must never yield it.
- `sahidica.nt/sahidica.nt_TT.zip` — rebuilt zip with two members
  (in-repo-zip discover path; the four big bible corpora ship TT only as
  zips, and their loose CoNLL-U files are 2-byte placeholders upstream):
  - `41_Mark_01.tt` TRIMMED to the meta line + verses 1–12 (upstream lines
    1–2495 byte-identical, `</meta>` re-added; 263,156 B → 72,878 B).
    The OLDER TT dialect (v4.1.0), gold: `<translation>` element OPENS
    BEFORE `<verse_n>` (span overlap — the format is a span stack, not a
    tree); duplicate `segmentation` attribute in the meta line; dense
    `<lang>` loanword spans (37 in the trim); the J. Warren Wells
    "academic use only" license string → the `nc` posture, NO override;
    `people`/`places` rosters; `document_cts_urn` carries the `:1`
    chapter suffix + `chapter="1"` → the chapter→book merge.
  - `57_Philemon_01.tt` (whole, 110,626 B) — the single-chapter-book merge
    edge case (one member still mints the book document, urn without the
    chapter suffix), AND the third, COLLAPSED structural dialect the
    survey's 8 samples did not surface: no `orig_group`/`orig`/`lang`
    spans — `orig_group` rides as an attribute on `norm_group`, `orig` and
    `lang` as attributes on `norm`; `translation` as an attribute on
    `verse_n`. Automatic annotation quality (lemma rows NOT minted by
    default).
- `AP/apophthegmata.patrum_TT/AP.004.poemen.65.tt` (whole, 19.6 KB)
  — `identity="Poemen"` Wikification on gold entities; `Greek_source`
  (Nau-collection citation, metadata only); `Arabic_translation` credit
  AND embedded per-verse `<arabic>` spans (upstream's release notes say
  Arabic ships only in ANNIS — this file disproves that for AP, carried
  as the `translation_ar` annotation); `<note>` damage span; `hi_rend`
  (red ekthetic); multiple `<translation>` units inside one verse (v3).
- `doc-papyri/doc.papyri_TT/cpr.2.237.tt` (whole, 21 KB) — the
  `copticDoc` urn namespace (`papyri_info.tm82127.cpr_2_237`);
  `source="http://papyri.info/ddbdp/cpr;2;237"` alt-edition
  cross-reference (never dedupe, conventions §3); NO `verse_n` at all →
  the translation-unit ordinal fallback (addressing flagged
  non-canonical); documentary span dialect `pb` recto/verso + `p` (vs
  literary `pb_xml_id`/`p_n`) and `source_lang` (vs `lang`);
  `figure`/`figDesc` seal spans that CLOSE out of order (`</figDesc>`
  before `</figure>` — the not-a-tree proof); `origDate` 0700–0799.

## Retrieval URLs

- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/besa-letters/besa.letters_TT/on_lack_of_food.tt
- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/besa-letters/besa.letters_CONLLU/on_lack_of_food.conllu
- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/AP/apophthegmata.patrum_TT/AP.004.poemen.65.tt
- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/doc-papyri/doc.papyri_TT/cpr.2.237.tt
- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/sahidica.nt/sahidica.nt_TT.zip
  (5.5 MB, 259 members; the checked-in zip is REBUILT from the two members
  above — `zip -X` over the trimmed Mark + whole Philemon — so a fresh GET
  can never byte-match it)

## License chain

Per-document `license` field in each TT meta header (the parser's source
of record — never hardcoded, the ORACC precedent): Besa/AP/cpr are
CC-BY 4.0 (verbatim, HTML-entity-encoded anchor to
creativecommons.org/licenses/by/4.0) → `license_override: attribution`;
the sahidica.nt members carry "(c)2000-2006 by J Warren Wells, for
academic use only" (link to copticscriptorium.org/download/corpora/Mark/
coptic_nt_sahidic.html) → the source's own `nc` class, no override.
Source class `nc` = most-restrictive-present (P10-4, inverted proportion:
~87% of upstream docs are CC-BY(-SA) and get the attribution override).
