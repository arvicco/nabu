# Wiktionary-OCS fixtures (P13-10 — dictionary shelf, fourth occupant)

Real upstream sample from the **kaikki.org machine-readable Old Church
Slavonic dictionary** (wiktextract / Tatu Ylönen's extraction of English
Wiktionary). Every kept line is **byte-verbatim** upstream data — the
selection script picks whole JSONL lines and a post-check asserts each
emitted line is a literal line of the raw download; only the record SET was
trimmed (278 of 4,615 lines; +1 P17-3 golden, §below — 279 total).

- **Page:** https://kaikki.org/dictionary/Old%20Church%20Slavonic/
  ("4548 distinct words"; built from the enwiktionary dump dated
  2026-07-06, extracted 2026-07-09).
- **Retrieved:** 2026-07-11, full download of
  `https://kaikki.org/dictionary/Old%20Church%20Slavonic/kaikki.org-dictionary-OldChurchSlavonic.jsonl`
  (46,091,411 bytes, 4,615 lines, sha256
  `5bd61e747aa7aeb677af92b4e32c65476e5c6ee74bff146269460c962be5456c`).
- **License (verbatim, https://kaikki.org/dictionary/ "Copyright and
  license"):** "This data is made available under the same licenses as
  Wiktionary - both CC-BY-SA and GFDL." Plus the academic citation request
  for wiktextract (Ylönen, LREC 2022, pp. 1317–1325).
- **Deprecation caveat:** the per-language postprocessed JSONL is labelled
  "DEPRECATED, will be removed in the near future" (wiktextract issue
  #1178) but is the artifact the site itself builds on and serves today.
  Durable fallback: filter the full enwiktionary extract
  (~2.6 GB compressed) by `lang_code == "cu"`.

## Upstream format reality (what this fixture preserves)

- One JSON object per line; one record = one WORD × POS × etymology
  section. NO top-level record id — `word` alone is NOT unique (homographs
  split by `pos` and `etymology_number`, and 10 word+pos[+ety] pairs in the
  full file still collide, e.g. боль:noun ×2, ⰿⰾⱑⰽⱁ:noun ×2 — a Glagolitic
  headword).
- Keys always present: `word` (Cyrillic headword — Glagolitic in 2 full-file
  records), `pos` (17 values incl. `character` for single-letter alphabet
  entries — owner-approved KEEP 2026-07-11), `lang` ("Old Church
  Slavonic"), `lang_code` (`"cu"` on all 4,615 records), `senses` (array;
  each has `glosses` [strings], `id`, optional
  `links`/`tags`/`examples`/`categories`/`raw_glosses`), `forms`
  (canonical + romanization + paradigm rows; цар҄ь carries the titlo-like
  palatalization mark U+0484).
- Frequently present: `etymology_text` (2,617 of 4,615 — plain text
  carrying the Proto-Slavic/PIE chains this adapter KEEPS in the body:
  "Inherited from Proto-Slavic *bogъ", "From Proto-Slavic *o(b), from
  Proto-Indo-European *h₃ebʰi"), `etymology_templates`, `etymology_number`
  (homograph disambiguator "1"/"2"/"3"), `head_templates`,
  `related`/`derived`/`synonyms`/`descendants`/`categories`.
- 4 full-file records have no gloss in any sense (all kept here); max
  senses on one record: 18.

## This file — 278 records, 2,252,722 bytes, upstream line order

| Stratum | What | Why |
|---|---|---|
| residual collisions | all 20 records of the 10 word:pos[:ety] collision pairs (блажимъ, блѧдь, боль, видимъ:2, гобина, гобино, начѧтъ, ненавидимъ, привести, ⰿⰾⱑⰽⱁ) | the positional `:n` entry-id suffix path; the Glagolitic headword |
| named plan words | богъ, глаголати, слово, царь, о (×2: character + prep w/ 7 senses + PIE), и (×3), а (×2), е (×2), вода | the `--lang chu` demo lemmas (TOROT zogr gold lemmas богъ/глаголати), homographs, multi-sense linearization, цар҄ь U+0484 fold |
| gloss-less | all 4 records with no glosses in any sense | best-effort nil gloss path |
| max-sense | the 18-sense record | sense numbering at scale |
| POS spread | first 4 of each of the 17 POS values (file order) | incl. 10 `character` entries (KEEP ruling), suffix/prefix/punct oddities |
| etymology | first 25 PIE-bearing + first 40 Proto-Slavic-bearing (file order) | the etymology-KEPT assertion (39 PIE-bearing records land here in total) |
| breadth sweep | every 32nd line of the full file | unbiased tail: rare keys, long paradigms |
| extra homographs | all records of the first 12 multi-record words (file order) | entry-id disambiguation beyond the named set |

Result: 278 records — 124 noun / 54 verb / 18 adj / 15 pron / 10 character
/ …; 177 etymology-bearing (39 PIE); 72 multi-sense; all strata of
docs/backlog.md P13-10 (owner-approved 2026-07-11).

## Extraction recipe (one-shot, run 2026-07-11)

Python over the full download: compute the eight strata above as line-index
sets on the raw lines (JSON-parsed only for *selection*), union, sort by
line index, emit the raw lines unmodified. Post-check: every emitted line
`in set(upstream_lines)` byte-for-byte.

## P17-3 addition (retrieved 2026-07-13)

One golden line appended after the strata (the re-download hashes
IDENTICAL to the 2026-07-11 snapshot, sha256 above, so the append is
same-file): upstream line 98, `страна` — its orv descendant edge carries
raw_tags `["borrowed"]` (the Church-Slavonicism marker: OCS страна loaned
INTO Old East Slavic beside the inherited pleophonic сторона; 83 of the
live shelf's 87 orv edges are so flagged). Pins the borrowed-flag parse on
an attested-shelf edge. Totals become 279 lines / 39 reflex-bearing
entries / 129 edges.
