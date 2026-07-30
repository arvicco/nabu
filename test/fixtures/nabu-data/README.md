# nabu-data fixtures (P51-W6 — the two-way loop closes)

Real published samples for **Nabu::FormLemma**, **Nabu::VerbLemma** and
**Nabu::Adapters::NabuData** — the datasets Nabu itself PUBLISHES to
<https://github.com/arvicco/nabu-data> (built by `nabu data build`,
docs/nabu-data.md), registered back as a feature module (kind: module)
and consumed like any upstream. Kept rows are **byte-verbatim** published
lines; only the row SET was trimmed. Layout mirrors the post-fetch
canonical tree (`san/form-lemma/`, `xct/verb-lemma/` as in the repo).

## san/form-lemma (Nabu::FormLemma, P51-W6)

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
- The `lemmas.csv` sidecar and the `xct/wylie-fold` dataset are NOT
  sampled: no consumer reads them yet.

### What was kept (269 of 428,825 rows + header)

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

## xct/verb-lemma (Nabu::VerbLemma, P54-3)

- **Retrieved:** 2026-07-30, from the owner's live checkout of the
  published repo (`~/Dev/nabu-data`, clean at commit `4640f73` =
  the repo's `main`, "Eleventh dataset: sux/value-signs — the Oracc
  Sign List, flattened"; dataset v1.0.0 per its datapackage.json).
  - `xct/verb-lemma/verb-lemma.csv` — full published file 3,889 rows,
    sha256 `660a3bff950f333f8b14f624b51de30eaea76d6d21d9d07ccd4a22aad3c29533`.
  - `xct/verb-lemma/datapackage.json` — the dataset descriptor, WHOLE
    (verbatim copy; upstream chain: the Tibetan Verbs Database,
    tibetan-nlp TVD, CC0-1.0, at TVD commit `ca6ba75`).
- The `languages.csv`/`sources.bib` sidecars are NOT sampled:
  Nabu::VerbLemma reads only `verb-lemma.csv`.

### What was kept (72 of 3,889 rows + header)

Line numbers refer to the published file at commit `4640f73`:

- **Lines 2–61** — the head ཀ-block: the multi-source lemmas ཀེར
  (GT/TDC/PH, deliberately uncollapsed analyses) and ཀླུབ (a GT row
  disagreeing with the TDC/PH/GT/KN quartet), three ༼ད༽
  optional-suffix cells (lines 2, 43, 48 — `ཀེར༼ད༽`,
  `དཀྲོལ༼ད༽`, `བཀན༼ད༽`), and the ablauting ཀོང paradigm
  (Past `བཀོངས`) whose past stem ALSO belongs to the བཀོང KN row
  (line 60) — one form, two lemmas.
- **Lines 196–199** — the སྐྱེལ block: the TWO-group cell
  `སྐྱོལ༼ད༽༼སྐྱོལ༽` (optional suffix + alternate form) beside
  three plain-cell analyses of the same lemma.
- **Lines 805–808** — the འགྲོ suppletive paradigm: Past
  `ཕྱིན༼ད༽༼ཕྱིན༽` / Imperative `སོང` — the stems only the table
  can route back to the lemma.
- **Lines 1234–1237** — the འཆོར block: the BRACKETED Lemma spelling
  `འཆོར༼ཤོར༽` and the NESTED group `འཆོར༼ད༽༼ཤོར༼ད༽༽`
  (alternate form carrying its own optional suffix).

## License

CC BY 4.0 (the repo LICENSE is the CC BY 4.0 legalcode; per-dataset
upstream chains ride each datapackage.json).

## Refresh recipe

From a clean checkout of the published repo at the recorded commits,
keep the header plus the line ranges above, byte-verbatim (LF endings
upstream, preserved); copy each `datapackage.json` whole. A new dataset
release changes the full-file sha and MAY renumber lines — re-derive the
ranges by content (the tapas/bodhisattva blocks; the ཀེར/སྐྱེལ/
འགྲོ/འཆོར blocks) and update the commit, sha and counts here and in
the tests.
