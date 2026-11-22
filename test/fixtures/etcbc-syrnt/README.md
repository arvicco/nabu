# etcbc-syrnt fixture — the Syriac New Testament (Text-Fabric tf/0.1)

Gap-anchored trimmed slices of the pinned `tf/0.1` Text-Fabric dataset of
[github.com/ETCBC/syrnt](https://github.com/ETCBC/syrnt) (Hannes
Vlaardingerbroek and Dirk Roorda, ETCBC; Zenodo 10.5281/zenodo.1464787) —
a SEDRA database export (George A. Kiraz and James W. Bennett, database
version 3.0, March 1996).

- **Retrieved:** 2026-11-22, from commit
  `dae3eb6ff62b9b272fb503646796c25d248175ce` (master), via a sparse clone of
  `tf/0.1` (raw URLs `https://raw.githubusercontent.com/ETCBC/syrnt/master/tf/0.1/<name>`).
- **Layout:** mirrors the sparse workdir the adapter fetches (`tf/0.1/*`);
  `docs/about.md` (also in the cone, the provenance page) is quoted below,
  not checked in.
- **Trim recipe:** headers byte-verbatim; data lines byte-verbatim for every
  node whose slots lie inside the kept slot ranges below, written
  gap-anchored (`node<TAB>value` after every gap); empty values drop. The
  Matthew book node keeps its `oslots` line CLIPPED to chapter 1 (`1-290`) —
  the one non-verbatim edit. Lexeme nodes (their oslots link a lexeme to
  every occurrence corpus-wide) are not kept: the adapter reads lexemes from
  the word-grain `lexeme` feature only. `otype.tf` and `otext.tf` ride
  WHOLE — the census of record. All 43 feature files are included.

## Upstream delivery grains (enumerated 2026-11-22)

| grain | path | taken? |
|---|---|---|
| Text-Fabric dataset | `tf/0.1/*.tf` (43 features, ≈ 15 MB) | **accepted** — document = book node, passage = verse node |
| TF release bookkeeping | `tf/0.1/__checkout__.txt` (`0.3` / `g72f2ead…`) | inside the cone, **skipped by rule** (pinned here whole; counted in `discovery_skips`) |
| provenance page | `docs/about.md` | fetched (license/provenance), documentation — not content |
| raw SEDRA export | `source/0.1/all-ordered.txt` (6.2 MB) | outside the sparse cone — the TF dataset was built from it |
| plain-text books | `plain/0.1/<Book>.txt` (27 files) | outside the cone — derived renderings of the same text |
| feature docs, app, programs, tutorial | `docs/`, `app/`, `programs/`, `tutorial/` | outside the cone — code and documentation |

Node types (otype.tf): word (slot), book, chapter, lexeme, verse. The
lexeme node type is not a citation grain; its value rides every token.

## Upstream census (at the pin, from otype.tf — checked in WHOLE)

109,640 words / 27 books / 260 chapters / 3,038 lexemes / 7,957 verses.
Full-data census (2026-11-22): every (book, chapter, verse) unique, no
discontiguous verse, verse node order == slot order, zero non-NFC word
forms, no empty word slot. Verses per book: Matt 1,071 · Mark 678 · Luke
1,151 · John 879 · Acts 1,007 · Rom 433 · 1Cor 437 · 2Cor 257 · Gal 149 ·
Eph 155 · Phil 104 · Col 95 · 1Thess 89 · 2Thess 47 · 1Tim 113 · 2Tim 83 ·
Titus 46 · Phlm 25 · Heb 303 · James 108 · 1Peter 105 · 2Peter 61 ·
1John 105 · 2John 13 · 3John 15 · Jude 25 · Rev 403. Upstream advertises
no count of its own; the 27 book nodes are the 27 NT books.

## License (read first-hand 2026-11-22)

- `LICENSE`: the MIT License, "Copyright (c) 2019 Dirk Roorda" — a grant
  over "the Software".
- `README.md` / `docs/about.md`: "The source data in this repo is a SEDRA
  database export made by George A. Kiraz and James W. Bennett." … "The
  data base version is 3.0, March 1996." … "The SEDRA data for the Syriac
  New Testament is based on manuscripts from the Ancient Biblical Manuscript
  Center."
- Feature headers: `@encoders=Ancient Biblical Manuscript Center
  (transcription),George A. Kiraz and James W. Bennett (database)and Hannes
  Vlaardingerbroek and Dirk Roorda (TF)`, `@source=SEDRA`.

No explicit data license → source class `nc`, conservatively (SEDRA's data
is CC BY-NC 4.0 today; the sister ETCBC corpora are CC BY-NC). The fixture
slice follows the held `peshitta`/`etcbc-syriac` precedent: a small
attributed non-commercial sample for testing.

## The slices (1,193 words / 90 verses)

| book | node | kept | verses | why |
|---|---|---|---|---|
| Matt | 109641 | chapter 1 (slots 1–290), clipped | 25 | the known opening "ܟܬܒܐ ܕܝܠܝܕܘܬܗ ܕܝܫܘܥ ܡܫܝܚܐ…" |
| Phlm | 109658 | whole (slots 92379–92655) | 25 | a whole single-chapter epistle |
| 3John | 109665 | whole (slots 102695–102905) | 15 | the digit-led book name (`3john`, title "3 John") |
| Jude | 109666 | whole (slots 102906–103320) | 25 | adjacent to 3John — an implicit-continuation run |
