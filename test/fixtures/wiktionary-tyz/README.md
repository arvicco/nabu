# wiktionary-tyz fixture

Trimmed REAL excerpt of the kaikki.org Tày extraction. Retrieved
2026-11-04 from
https://kaikki.org/dictionary/T%C3%A0y/kaikki.org-dictionary-T%C3%A0y.jsonl
(2,024,890 bytes, Last-Modified 2026-10-30, ETag "6ae521ba-1ee5ba",
sha256 `abe402ee05adbadb3874fea413ca9dd4923c9e9c36637d079a6f26e82aa875cc`;
the index page states "1203 distinct words"). The whole file was read
for the census below; only the five lines listed are kept here. The
local file name is ASCII (`…-Tay.jsonl`, the adapter's FILENAME);
upstream's artifact is `kaikki.org-dictionary-Tày.jsonl`.

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

1,515 records, lang_code uniformly `tyz`, 0 non-NFC, 0 headwordless.

| grain | records |
|---|---:|
| glossed (kept) | 1,495 |
| glossless, carrying Nôm Tày spellings (kept) | 1 |
| glossless, etymology text only (kept) | 5 |
| empty stub (skipped by rule, all word records) | 14 |
| **entries** | **1,501** |

The Nôm Tày layer: 138 `character` records carrying **150 senses**
(the survey figure, exact), 149 of them glossed "Nôm form of …" (the
reading is in the gloss; no reading relations upstream); and 100
`forms` tagged `CJK` on 82 word records — the Nôm Tày spellings of
Latin-orthography headwords. 273 reflex rows (Proto-Tai etymons)
through the family parser.

## Cut

5 complete JSONL lines, byte-verbatim in upstream order (0-based
upstream line numbers):

1. nu (noun) — line 2: glossed "mouse", one `CJK` spelling 𮮬, the
   Proto-Tai `inh` etymon. KEPT.
2. 倍 (character) — line 51: "Nôm form of viòi.". KEPT.
3. xá (classifier, etymology 4) — line 261: glossless, two spellings
   赦 舍 and a Proto-Tai etymology. KEPT.
4. nà (noun, etymology 2) — line 330: the empty stub. SKIPPED by rule.
5. náo lo̱ (particle) — line 1104: glossless, etymology text only
   ("From náo + lo̱."). KEPT.

## Refresh

Re-fetch the URL above and re-select the same `word`/`pos`/
`etymology_number` triples. Deprecation caveat: if the per-language
JSONL is gone, filter the full wiktextract dump by `lang_code == "tyz"`.
