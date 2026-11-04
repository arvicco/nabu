# wiktionary-za fixture

Trimmed REAL excerpt of the kaikki.org Zhuang extraction. Retrieved
2026-11-04 from
https://kaikki.org/dictionary/Zhuang/kaikki.org-dictionary-Zhuang.jsonl
(7,486,225 bytes, Last-Modified 2026-10-30, ETag "6ae5211f-723b11",
sha256 `be49d83f0bf19767288dda8dca3863a9c8c36a91a7d0bbe852a67b28254c757f`;
the index page states "2981 distinct words"). The whole file was read
for the census below; only the six lines listed are kept here.

License, verbatim from kaikki.org/dictionary/ "Copyright and license":
"This data is made available under the same licenses as Wiktionary -
both CC-BY-SA and GFDL." (+ the wiktextract citation request: Ylönen,
LREC 2022.)

## Delivery grains

One per-language JSONL, one wiktextract record per line; the adapter
takes the whole file as its one document and each record as an entry
candidate (HTML pages and the all-languages dump: same data, not
fetched). ONE record shape is rejected by rule: the **empty stub** — no
gloss, no reading, no script form, no etymology text.

## Census (the whole file, through the adapter)

3,579 records, lang_code uniformly `za`, 0 non-NFC, 0 headwordless.

| grain | records |
|---|---:|
| glossed (kept) | 3,575 |
| glossless, etymology text only (kept) | 2 |
| empty stub (skipped by rule: 1 word, 1 character) | 2 |
| **entries** | **3,577** |

The Sawndip layer: **813 records carry 3,659 `forms` tagged
`Sawndip`** (3,653 after per-record repeats fold), all on word records,
every value Han-script — unencoded characters arrive as Ideographic
Description Sequences (⿰目荷) and stay verbatim. The survey's "815
entries" (2026-11-02) reads 813 on this file; the form count is
unchanged. 18 `character` records are the Latin/Cyrillic letters of the
1957–1982 orthography, not Sawndip. 622 reflex rows through the family
parser.

## Cut

6 complete JSONL lines, byte-verbatim in upstream order (0-based
upstream line numbers):

1. de (pron) — line 0: glossed "he, she, it", six Sawndip forms. KEPT.
2. o (adj, etymology 2) — line 2: glossed "blue" (dialectal), three
   Sawndip forms incl. the IDS ⿰目荷. KEPT.
3. ч (character) — line 73: "1957–1982 spelling of x". KEPT.
4. dienh (verb) — line 1066: glossless, etymology text only ("From
   Chinese 電"). KEPT.
5. caenhgag (adj) — line 2859: the empty word stub. SKIPPED by rule.
6. 𱜨 (character) — line 3578: the empty character stub (a sound row
   and a hyphenation only). SKIPPED by rule.

## Refresh

Re-fetch the URL above and re-select the same `word`/`pos`/
`etymology_number` triples. Deprecation caveat: if the per-language
JSONL is gone, filter the full wiktextract dump by `lang_code == "za"`.
