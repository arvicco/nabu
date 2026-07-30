# nabu-data fixtures (P51-W6 — the two-way loop closes)

Real published samples for **Nabu::FormLemma**, **Nabu::TibetanWords**
and **Nabu::Adapters::NabuData** — the datasets Nabu itself PUBLISHES to
<https://github.com/arvicco/nabu-data> (built by `nabu data build`,
docs/nabu-data.md), registered back as a feature module (kind: module)
and consumed like any upstream. Kept rows are **byte-verbatim** published
lines; only the row SET was trimmed. Layout mirrors the post-fetch
canonical tree (`san/form-lemma/` as in the repo).

- **Retrieved:** 2026-07-29, from the owner's live checkout of the
  published repo (`~/Dev/nabu-data`, clean at commit `c50ef93` = the
  repo's `main`, "First datasets: san/form-lemma, xct/wylie-fold,
  xct/verb-lemma"; dataset v1.0.0 per its datapackage.json).
  - `san/form-lemma/form-lemma.csv` — full published file 428,825 rows,
    sha256 `c4c38ca718c3a78d2b4dfff84b57f070dd76888e5070761c1a3a5f31e1428ec0`.
  - `san/form-lemma/datapackage.json` — the dataset descriptor, WHOLE
    (verbatim copy; carries the upstream attribution chain: Hellwig's
    Digital Corpus of Sanskrit, CC BY 4.0, at DCS commit `04e0778`).
- **License:** CC BY 4.0 (the repo LICENSE is the CC BY 4.0 legalcode;
  per-dataset upstream chains ride each datapackage.json).
- The `lemmas.csv` sidecar and the other `xct/` datasets are NOT
  sampled: Nabu::FormLemma reads only `form-lemma.csv`, Nabu::TibetanWords
  only `xct/segmentation/segmentation.csv` (below).

## xct/segmentation (P54-1 — Nabu::TibetanWords)

- **Retrieved:** 2026-07-30, from the local `~/Dev/nabu-data` working
  tree, clean at commit `4640f73` ("Eleventh dataset: sux/value-signs —
  the Oracc Sign List, flattened").
  - `xct/segmentation/segmentation.csv` — full published file 319,162
    rows, sha256
    `29a17627200cbd58c1277bed75e3738fca9118409bdbc14f2b2a11ebb66c50cc`.
- **Kept:** the header plus the FIRST 300 rows, byte-verbatim — the
  gold segmentation of `urn:nabu:soas-tibetan:buston` passages 1–4
  (Tier=gold throughout, 179 distinct Form spellings). The opening rows
  are the seam test's expectations: rows 1–4 (`བདེ་བ`, `ར་`, `གཤེགས་པ`,
  `འི་` at offsets 0/5/7/14) are exactly the split Nabu::TibetanWords
  must reproduce from the slice's own token counts, clitic splits
  included.
- Refresh: from a clean checkout at the recorded commit,
  `head -301 xct/segmentation/segmentation.csv`. A new dataset release
  changes the full-file sha and MAY reorder rows — re-derive by content
  (the buston opening) and update the commit, sha and counts here and
  in `test/tibetan_words_test.rb`.

## What was kept (269 of 428,825 rows + header)

Line numbers refer to the published file at commit `c50ef93`:

- **Line 2198** — `tapas,96401` with an EMPTY Form and `_` Unsandhied:
  one of the 2,988 lemma-only rows that index nothing (pinned honestly
  unreachable by form lookup).
- **Line 4483** — the `kﾱp` mis-encoding quirk (DCS carries U+FFB1 where
  kḷp is meant): pins the fold's slow path on real bytes.
- **Lines 77828–77855** — the bodhisattva block: the nominative
  `bodhisattvaḥ` the P48-r1 stem rule ALSO reaches, Unsandhied≠Form
  sandhi rows (`bodhisattvair` → `bodhisattvaiḥ`, `bodhisattvo` →
  `bodhisattvaḥ`), and the `bodhisatva` single-t spellings.
- **Lines 317208–317446** — the contiguous tapa/tapana/tapas
  neighborhood: the multi-lemma form `tapa` (→ tap VERB / tapa NOUN /
  tapas NOUN), the full tapas paradigm including the instrumental
  `tapasā` → `tapas` the stem rule CANNOT generate (the D48-a tier-2
  case), and many Unsandhied≠Form rows (`tapo` → `tapaḥ`, `tapaś` →
  `tapaḥ`).

## Refresh recipe

From a clean checkout of the published repo at the recorded commit, keep
the header plus the line ranges above, byte-verbatim (LF endings
upstream, preserved); copy `datapackage.json` whole. A new dataset
release changes the full-file sha and MAY renumber lines — re-derive the
ranges by content (the tapas/bodhisattva blocks) and update the commit,
sha and counts here and in the tests.
