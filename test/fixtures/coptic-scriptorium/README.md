# Coptic Scriptorium fixtures (P17-1 Phase B, extended P17-10 + P18-1)

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

## The dual-origin pair (P17-10)

`ot.hab.bohairic_ed` is the ONE work urn upstream mints from two origins
(everywhere else standalone editions carry distinct `_ed` urns —
`nt.mark.sahidica_ed` loose vs `nt.mark.sahidica` zip). Both fixtures were
trimmed 2026-07-13 from the LOCAL canonical tree at the pinned v6.2.0 tag
(`canonical/coptic-scriptorium/…`, byte-identical to the raw-URL tag paths
below), verse ranges chosen so the pair exercises the precedence rule and
the historical unzip-exit-9 crash shape:

- `bohairic-habakkuk/bohairic.habakkuk_TT/bohairic.Habakkuk_01.tt` —
  TRIMMED to the meta line + `lb_n` 1–2 + verses 1–2 (upstream lines 1–325
  byte-identical, `</meta>` re-added; 118,874 B → 10,183 B). The standalone
  digital edition: v6.2.0 (2025-11-25), segmentation/tagging/parsing/
  entities/identities all GOLD, `people`/`places` rosters, `lb_n`
  manuscript topology, public-domain text + CC-BY 4.0 annotations →
  `attribution` override. Source: `bohairic-habakkuk/bohairic.habakkuk_TT/
  bohairic.Habakkuk_01.tt` in the canonical tree.
- `bohairic.ot/bohairic.ot_TT.zip` — rebuilt zip (`zip -X`) with 1 of 637
  members: `35_Habacuc_01.tt` cut to the meta line + verses 1–2 (upstream
  member lines 1–316 byte-identical, `</meta>` re-added; 116,894 B →
  9,430 B). The SAME work urn from the bible zip: frozen v6.0.0
  (2024-10-31) automatic snapshot, minimal header, CC-BY-SA. Source:
  `bohairic.ot/bohairic.ot_TT.zip!35_Habacuc_01.tt` in the canonical tree.

The two origins are byte-DIFFERENT (the P17-10 census: revised lemmas,
re-tokenization, the added `lb_n` layer) — the same edition at two
releases, so the standalone corpus wins by precedence and the zip member
is skipped by rule (counted in the discovery accounting).

## The P18-1 offender set (span-inventory + header census)

The first full sync loaded 188 of 465 documents: 277 quarantined on span
types the fixture set never saw, 18 files "unrecognized: no usable TT meta
header". The P18-1 census swept all 2,497 TT chunks in the release and
named 66 unknown span types plus TWO structural findings; one trimmed real
offender per census family was added (all trimmed 2026-07-13 from the
LOCAL canonical tree at the pinned v6.2.0 tag, byte-identical prefixes,
`</meta>` re-added; exact line/byte counts in manifest.yml):

- `helias/helias_TT/helias_martyrdom_part1.tt` — the SPACE-BEFORE-EQUALS
  meta variant (`msItem_title ="…"`) that made 18 files unrecognized
  (helias 5, theodosius 9, acts-pilate 2, lament-mary 2); also
  `ed_page_n`/`ed_line_n` edition topology. Part files carry their own
  range-suffixed cts urns (`helias.martyrdom.sobhy_ed:0-15`) — one
  document per part, the shenoute precedent, no merge.
- `theodosius-alexandria/theodosius.alexandria_TT/
  Encomium_Michael_BL_OR_6781_part1.tt` — same header variant in ORDINAL
  (verse-less) mode, plus the `ed_pg_n` spelling.
- `pistis-sophia/pistis.sophia_TT/pistis.sophia_book_1_part1.tt` —
  Marcion/Petermann ALTERNATE VERSIFICATION spans riding beside the
  primary verse_n (`cit_marcion`/`cit_petermann` lists), the Horner
  translation (`trans_horner` → `translation_horner`), Coptic-numeral
  page ids (`pb_coptic_id` → `page_coptic`).
- `abraham/shenoute.abraham_TT/YA535-540.tt` — `v_id` (vid_n variant) and
  `entity_identity`: the v6.0 attribute-form Wikification wrapping the
  TOKEN (Sarah on ⲥⲁⲣⲣⲁ) → token-anchored entities records.
- `life-aphou/life.aphou_TT/life.aphou.01.tt` — the PATHS-project entity
  markup (`persName_type`/`placeName_ref`+`_type`/`roleName_type`/
  `date_type` merging into their enclosing entities; standalone
  `quote_ref`/`quote_type` biblical-quotation records; `p_source` PATHS
  credit, ignored-counted).
- `sahidica.1corinthians/sahidica.1corinthians_TT/1Cor_14.tt` —
  VERSE-AS-UNIT: `<verse verse="1 Corinthians 14:1">` IS the unit opener
  (no verse_n in the file); citations normalize the fused label to 14.1,
  the verbatim label rides in annotations.
- `AP/apophthegmata.patrum_TT/AP.100.n294.crocodiles.tt` — the editorial
  transcription marks (`gap_reason/unit/quantity`, `supplied_reason/
  unit/quantity`) → `annotations["editorial"]` records.
- `sahidic.jonah/sahidic.jonah_TT/Jonah_01.tt` — fused `verse_n_vid_n`
  (→ vid fold) + `verse_n_vname` ("Jonah 1:1" → `verse_name`) +
  `note_note` (→ `notes`, the attribute-form of `<note>`, both upgraded
  from ignore to annotation in P18-1).
- `besa-letters/besa.letters_TT/on_vigilance.tt` — the German translation
  layer (`<german>` → `translation_de`, 20 spans, one file upstream).
- `magical-papyri/magical.papyri_TT/OCrum_ST_18.tt` (whole, 23 KB) — the
  `copticMag` urn namespace: deliberately NOT stripped (the live catalog
  froze `urn:nabu:coptic-scriptorium:urn:cts:copticMag:kyprianos.
  tm99995.kyp_t_53` at the first sync, so the corpus keeps the full CTS
  urn as its tail); also the final-Amen omitted-verse shape (below).
- `sahidica.nt/sahidica.nt_TT.zip` grew a third member, `41_Mark_07.tt`
  (verses 1–16): the OMITTED-VERSE LACUNA shape — Mark 7:16's `[..]`
  bound group opens BEFORE the verse_n it contains, the verse span
  nesting INSIDE the token (same family: John 5:4, Acts 8:37, Matt 12:47,
  Rom 16:24, Rev 1:1–2 `[--]` — the census's "unsegmented stretches").
  Stray groups/tokens attach FORWARD to the verse that opens inside them;
  a stray that closes with no unit still fails loudly.
- `bohairic.nt/bohairic.nt_TT.zip` (NEW, 1 of 260 members) —
  `05_Acts_24.tt` verses 1–8: the lacuna group `[...]ⲫⲁⲓ` of Acts 24:7
  CROSSES into verse 8; the group attaches whole to the verse it opened
  into, token-level verse attribution stays exact.
- `sahidic.ot/sahidic.ot_TT.zip` (NEW, 1 of 911 members) —
  `01_Genesis_01.tt` verses 1–11: `abbr type="nomSac"` (nomina sacra,
  1,620 spans across the sahidic OT), `<gap reason="lacuna">` and
  `<supplied source= reason=>` in the collapsed dialect.

Rare fold-variants without a dedicated fixture (`vid__n`,
`arabic_translation`, `pb_n`/`pb_id`, `ch_n`, `ed_lb_n`, `section_title`,
gap/supplied typo suffixes, `sup`/`sub`/`hi`/`cb`/`ignore_note`/
`chapter*`) share a fixture-verified handler path; the tag→path mapping is
census-verified (occurrence counts in the parser constants).

## Retrieval URLs

- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/besa-letters/besa.letters_TT/on_lack_of_food.tt
- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/besa-letters/besa.letters_CONLLU/on_lack_of_food.conllu
- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/AP/apophthegmata.patrum_TT/AP.004.poemen.65.tt
- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/doc-papyri/doc.papyri_TT/cpr.2.237.tt
- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/sahidica.nt/sahidica.nt_TT.zip
  (5.5 MB, 259 members; the checked-in zip is REBUILT from the two members
  above — `zip -X` over the trimmed Mark + whole Philemon — so a fresh GET
  can never byte-match it)
- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/bohairic-habakkuk/bohairic.habakkuk_TT/bohairic.Habakkuk_01.tt
  (trimmed, see the dual-origin section)
- https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/bohairic.ot/bohairic.ot_TT.zip
  (10 MB, 637 members; the checked-in zip is REBUILT from the one trimmed
  Habacuc member, so a fresh GET can never byte-match it)
- P18-1 additions (all trimmed unless noted; the two new zips are REBUILT
  with one trimmed member each and can never byte-match a fresh GET):
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/helias/helias_TT/helias_martyrdom_part1.tt
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/theodosius-alexandria/theodosius.alexandria_TT/Encomium_Michael_BL_OR_6781_part1.tt
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/pistis-sophia/pistis.sophia_TT/pistis.sophia_book_1_part1.tt
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/abraham/shenoute.abraham_TT/YA535-540.tt
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/life-aphou/life.aphou_TT/life.aphou.01.tt
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/sahidica.1corinthians/sahidica.1corinthians_TT/1Cor_14.tt
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/AP/apophthegmata.patrum_TT/AP.100.n294.crocodiles.tt
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/sahidic.jonah/sahidic.jonah_TT/Jonah_01.tt
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/besa-letters/besa.letters_TT/on_vigilance.tt
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/magical-papyri/magical.papyri_TT/OCrum_ST_18.tt (whole)
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/bohairic.nt/bohairic.nt_TT.zip (16 MB, 260 members)
  - https://raw.githubusercontent.com/CopticScriptorium/corpora/v6.2.0/sahidic.ot/sahidic.ot_TT.zip (30 MB, 911 members)

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
