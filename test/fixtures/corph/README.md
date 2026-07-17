# CorPH fixtures — trimmed `chronhibdev_2020.sql` (P25-0)

A real, structurally intact trim of CorPH's canonical bulk artifact: the
MySQL/phpMyAdmin dump `chronhibdev_2020.sql` (39,102,512 bytes) from the
ChronHib website repository. Retrieved **2026-07-17** from

- repo: `https://github.com/chronhib-MU/Chronhib-Website`
- pinned commit: `e7ef75d5f9a6ea97210f028b7389fa9539fbe8c0`
  (2021-05-11 "new build" — the repo's dormant HEAD, the sha the adapter
  pins and verifies at fetch time)

## License (recorded verbatim)

The repo `LICENSE` file, which covers the repository including the dump:

> MIT License
>
> Copyright (c) 2020 [Chronologicon Hibernicum](https://www.maynoothuniversity.ie/chronologiconhibernicum)

→ `license_class: attribution`. The CorPH site itself publishes no license
of its own; the CC BY-SA 3.0 footer on CODECS is CODECS's site license,
NOT CorPH's — never cite it for this source.

## Trim procedure

`chronhibdev_2020.sql` here is the real dump filtered line-VERBATIM (no
tuple was edited; only statement terminators `),` ↔ `);` adjusted where a
statement's last kept row changed, and the per-table "Dumping data" comment
notes the trim). Kept:

- **TEXT**: rows `0003` (Baile Chuinn — Old Irish poem, mutations,
  onomastics, variation statuses, the ChronHib date-range phrase), `0008`
  (Paris Priscian glosses — the corpus's Problematic_Form flags), `0077`
  (Einsiedeln Computus glosses — Latin-majority code-mixing, the "MS: …,
  Text N-M" date shape), `0067` (Epistle of Jesus — a TEXT row with no
  sentences, the metadata-only skeleton).
- **SENTENCES / MORPHOLOGY**: every row of those texts, plus the REAL
  upstream wart: sentence `S0006-6` carries `Text_ID` `"6"`, which matches
  no TEXT row (the full dump has exactly one such row) — kept so the
  discovery census exercises it.
- **LEMMATA**: every row whose `Lemma` is attested by the kept MORPHOLOGY
  rows (373 rows spanning 23 original INSERT statements — the multi-
  statement chunking the parser must handle).
- **BIBLIOGRAPHY**: the rows whose `Abbreviation` the kept TEXT rows cite.
- **VARIATIONS**: the rows referenced by the kept `Var_Status` values.

Out of scope and dropped entirely: `SEARCH` (a derived concordance),
`TEAM`/`USERS` (personal data — never check in).

Full-dump census at trim time (2026-07-17): 78 TEXT / 17,944 SENTENCES /
136,559 MORPHOLOGY / 10,485 LEMMATA rows; 6,232 lemmata carry dil.ie
headword ids (5,846 distinct); 99.4% of tokens join a LEMMATA row.

## Re-acquiring

There is no raw per-row URL — the delivery unit is the whole dump inside
the git repo. Re-acquiring means cloning the repo at the pinned commit and
re-applying this trim (`refetchable: false` in manifest.yml).
