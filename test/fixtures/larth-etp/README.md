# Larth ETP glossary fixtures — P29-0

Trimmed real upstream sample for the `larth-etp` dictionary adapter
(`Nabu::Adapters::LarthEtp` / `FlatCsvParser`). Retrieved **2026-07-18**
from
`https://raw.githubusercontent.com/GianlucaVico/Larth-Etruscan-NLP/daf4972175f45b48188fe36671db3a0e081e5130/Data/ETP_POS.csv`
(the pinned main commit of 2026-07-14). Full artifact: 164,566 B, 1,122
data rows, sha256
`4f9d5875d7ed0899a4d98cc579a08fedb5611825841cfce45f7504dbd48918ce`.

## License (verbatim)

Repo `LICENSE`: *"Attribution 4.0 International"* (CC BY 4.0 full text;
re-verified 2026-07-18) → class `attribution`. Credit: Vico & Spanakis
2023, "Larth: Dataset and Machine Translation for Etruscan", ALP2023 —
the vocabulary descends from the Etruscan Texts Project (Wallace) lists
(`ETPWords/ETPNames/ETPSuff`, same repo — the pre-merge raws, journaled,
not ingested).

## Rows kept (header + 9 records, byte-verbatim; keyed by the upstream
index column = the entry_id)

| index | Etruscan | Why |
|---|---|---|
| 0 | isa | `Is suffix` True + the `(True, 'the')` single-tuple shape |
| 2 | x | enclitic conj — the one-letter headword edge |
| 9 | pi | **empty Translations tuple `()`** — nil gloss, honest body |
| 121 | a | **Abbreviation of** aule — the gloss fallback pin |
| 461 | σ'la | **Is inferred** True + the σ' (ś) transliteration convention in the headword |
| 643 | acil | homograph 1: `((True, ''), (True, 'is necessary'))` — the EMPTY-gloss tuple member dropped |
| 644 | acil | homograph 2: `((True, 'work'), (False, 'product'))` — the **uncertainty flag** → "product (?)" |
| 647 | acnanas | nas-part — the participle grammatical-category line |
| 649 | avil | the canonical "year" — the certain-gloss exemplar |

## Census at fixture time (full artifact)

1,122 rows; translation tuple members 952 certain (`True`) + 59 uncertain
(`False`); 52 rows carry multiple translations; 2 rows use the Python
double-quote repr (`(True, "left'")` — apostrophe in the gloss); 0 blank
headwords. TAG (universal POS): NOUN 709, VERB 90, PRON 58, DET 32, ADP
24, NUM 21, CONJ 20, PRT 18, ADJ 14, ADV 6, blank 130.

Gold-join (censused 2026-07-18 against the OpenEtruscan corpus, folded
both sides with the generic ett search form): **649/992 distinct folded
headwords attested** in corpus word tokens (65.4%); token coverage
2,471/10,783 (22.9%).
