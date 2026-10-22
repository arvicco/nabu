# VedaWeb fixture

Real bytes from the VedaWeb project's public data
(github.com/VedaWebProject/vedaweb-data, branch `main`, last upstream push
2025-06-13), retrieved 2026-10-21 by raw GET
(`https://raw.githubusercontent.com/VedaWebProject/vedaweb-data/main/<path>`).
VedaWeb = the Rigveda research platform of the Cologne Center for
eHumanities (vedaweb.uni-koeln.de).

## Delivery grains (the whole repo, censused 2026-10-21)

| grain | upstream | adapter |
| --- | --- | --- |
| `rigveda/TEI/rv_book_NN.tei` — one TEI file per book | 10 files, 222 MB | container, streamed |
| hymn `<div type="hymn">` | 1,028 (with the 11 Vālakhilya, 8.49–59) | **ACCEPTED** — the document |
| stanza `<div type="stanza">` | 10,552 (= `rigveda/info/rv_locations.tsv`'s 10,552 rows) | **ACCEPTED** — the passage |
| pada `<l …_zur_a>` | 39,832 (a 10,552 · b 10,545 · c 10,394 · d 7,585 · e 437 · f 204 · g 112 · h 3) | the passage text, one per line |
| token `<fs type="zurich_info">` | 164,758 | the gold token layer |
| text versions (lubotsky, vnh, aufrecht, padapatha, eichler) + translations, per stanza | 5 + 10 layers | rejected by LICENSE scope (BY-NC-SA) — never read |
| `rigveda/TEI/vedaweb_corpus.tei` — the teiCorpus header (per-source licences, bibliography, xi:includes; no text) | 1 file | rejected: skipped by rule + counted |
| `rigveda/TEI/vedaweb.odd`, `vedaweb.rng`, `README.md` | schema + notes | not content |
| `rigveda/info/*` (addressees/strata/stanza-property JSON, lemma matching), `rigveda/translations/*.csv`, `rigveda/external-resources/*` | sidecars | outside the sparse fetch cone |

## Layout

- `rigveda/TEI/rv_book_01.tei` — TRIMMED: the book's header and opening
  lines, hymn 1.1 (its dedication + stanzas 1–2 of 9) and hymn 1.2 (its
  dedication + stanza 1 of 9), the book's closing lines; every kept line
  byte-verbatim, each hymn's closing `</div>` restored at its own
  indentation.
- `rigveda/TEI/rv_book_02.tei` — TRIMMED the same way: hymn 2.1 stanza 16
  (four padas; the `stanza_properties` flag grassmann=G; the `local
  particle` LP label) and hymn 2.2 stanza 4 (the book's first `<vAlt>`
  alternatives: `pātháḥ` case ACC/GEN, number SG/PL).
- `rigveda/TEI/rv_book_08.tei` — TRIMMED: hymn 8.49 stanza 1 — the first
  Vālakhilya hymn, Grassmann's no. 1018 (`ana="1018"`).
- `rigveda/TEI/vedaweb_corpus.tei` — WHOLE (111,892 B): the REJECTED
  header grain, and the per-layer licence statements the adapter quotes.

## Licence (vedaweb_corpus.tei, per source)

zurich, strata, stanza_properties, addressees: "Distributed under a
Creative Commons Attribution 4.0 International License." → read,
`attribution`. lubotsky, vnh, aufrecht, padapatha, eichler and every
translation: "Distributed under a Creative Commons
Attribution-NonCommercial-ShareAlike 4.0 International License." → not
read. The repo README: "Every source on this repository contains a
specific CC licence. For details see the `<teiHeader>` in
vedawebcorpus.tei".
