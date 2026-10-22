# meloniromance fixture

Trimmed REAL excerpt of the lexibank CLDF edition of the Meloni,
Ravfogel & Goldberg (2021) Romance cognate dataset, retrieved
2026-10-22 from the default branch of
https://github.com/lexibank/meloniromance (head 08f4ceec, committed
2026-05-31; the repository has no tags, no GitHub releases and no
Zenodo record at retrieval). Raw files at
`https://raw.githubusercontent.com/lexibank/meloniromance/main/<path>`.

## License (verified 2026-10-22)

Read four ways, all agreeing: the repository LICENSE file is the CC BY
4.0 legal code; the GitHub license field is CC-BY-4.0; the README says
"This dataset is licensed under a CC-BY-4.0 license"; and
`cldf/cldf-metadata.json` declares `dc:license`
https://creativecommons.org/licenses/by/4.0/ → `attribution`. Cite
Meloni, Ravfogel & Goldberg 2021 (NAACL-HLT, pp. 4460–4473).
Provenance caveat: the authors' own repository
(shauli-ravfogel/Latin-Reconstruction-NAACL) carries no license file;
the CC BY grant is the lexibank edition's declaration. Its README
states the full Ciobanu & Dinu-based set "is not publicly available …
Here, we publish the entries which we added to the original dataset" —
the 5,419 sets here are those published entries.

## Delivery grains

The repository serves:

- `cldf/` — the CLDF Wordlist (forms.csv 21,350 forms, cognates.csv
  21,350 expert judgments, 5,419 cognate sets, 6 varieties, 5,419
  placeholder concepts `concept_N`): **the accepted grain** — one
  dictionary entry per cognate set, headword the Latin form.
- `raw/data.tsv` — the pre-CLDF upstream table (one row per set, one
  column per language, `-` for absent): the SAME data in the shape the
  lexibank script converts from. **Rejected** (counted skipped-by-rule,
  never parsed); a trimmed specimen is pinned at `raw/data.tsv`.
- `etc/` (orthography profile, language table), the lexibank build
  script, `cldf/.transcription-report.json`, `lingpy-rcParams.json`,
  `requirements.txt` — machinery, not data; not pinned.

Census of the full forms.csv: Latin 5,419 (exactly one per set) ·
Italian 4,012 · Spanish 3,817 · Portuguese 3,442 · French 3,154 ·
Romanian 1,506; set sizes 2–6 (no singletons); no Loan or Comment
values; 75 Portuguese forms are non-NFC upstream (u + U+0303 → NFC ũ).
All forms are broad IPA (Latin with vowel length) — not orthography.

## Cut

Three sets, all rows byte-verbatim in upstream order:

- `concept_1` / set 1 — all six varieties (Latin -aːbɪlɛm → -abil,
  -abl, -abile, -aβle, -avɛl);
- `concept_75` / set 75 — Latin abɪʊŋɡɛrɛ + Portuguese ɐbʒũŋʒiɹ, the
  non-NFC specimen (u + combining tilde);
- `concept_358` / set 358 — the two-member minimum (Latin albeːskɛrɛ +
  Romanian albʲ).

`cldf/forms.csv` and `cldf/cognates.csv` keep the 10 rows of those
sets; `cldf/parameters.csv` the 3 concepts; `cldf/languages.csv`,
`cldf/cldf-metadata.json` and `cldf/sources.bib` are whole.
`raw/data.tsv` keeps its header and data rows 1, 75 and 358.

## Refresh

Re-fetch the raw URLs above and re-select the same Parameter_ID /
Cognateset_ID values.
