# wiktionary-ar fixture

Trimmed REAL excerpt of the kaikki.org Arabic extraction. Retrieved
2026-11-03 from
https://kaikki.org/dictionary/Arabic/kaikki.org-dictionary-Arabic.jsonl
(868,082,330 bytes per Content-Length, Last-Modified 2026-10-30, ETag
"6ae52a8a-33bde29a"; the index page states "177029 distinct words").
The full file was NOT downloaded at fixture time: the lines below come
from twenty 2 MB byte-range reads spread evenly across the file (offsets
k/20 of the length, k = 0..19), keeping only the complete lines inside
each range — 10,144 whole records, ~40 MB, ~4.6% of the file. No sha256
of the whole artifact is recorded for that reason; the first sync's
`.file-fetch.json` pin carries it.

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry candidate. Inside the
file, ONE record shape is rejected by rule: the **glossless record** —
no sense carries a gloss (the parser's `gloss` comes out nil). The site's
HTML pages and the full all-languages dump are other deliveries of the
same data, not fetched.

## Stub census (the 10,144-record sample, through the house parser)

| shape | sample | share |
|---|---:|---:|
| glossed (kept) | 1,724 | 17.0% |
| glossless, etymology "See the etymology of the corresponding lemma form." (inflected-form stub, sense tags `form-N`, `no-gloss`) | 8,171 | 80.6% |
| glossless, no etymology (bare verb-form stub, sense tags `form-N`, `no-gloss`; plus 4 nouns/adjectives and 2 English-headword thesaurus records) | 249 | 2.5% |

The file is NOT homogeneous: the six ranges from 14/20 to the end hold
0 glossed records (5,694 stubs), ranges 5/20–7/20 are 98% stubs, the
rest ~85% glossed — so the record-count share above is NOT the file's.
Byte-scaled (each range stands for 1/20 of the bytes), the sample
extrapolates to ≈220,000 records of which ≈37,400 glossed (standard
error ≈8,800 over the 20 ranges) — agreeing with the full-file count of
233,417 records / 196,443 glossless = 36,974 glossed taken by an earlier
census of the whole download. The exact number verifies at first sync.

0 non-NFC lines; 0 duplicate entry ids; the glossless records carry 0
descendant or etymon rows (skipping them loses no crosswalk edge). 117
glossed records ALSO carry the "corresponding lemma form" etymology
pointer (glossed form-of entries, "feminine singular of …") — they are
kept: the rule reads the gloss, never the etymology text.

## Cut

5 complete JSONL lines, byte-verbatim in upstream order:

1. أنا (pron) — sample line 1 (upstream 0-based line 1): glossed, with an
   `inh` etymology template (Proto-Afroasiatic) and a descendants tree
   (Egyptian Arabic, Maltese …). KEPT.
2. أنا (verb) — upstream 0-based line 3: the bare no-gloss verb-form stub
   (sense tags `form-i`, `no-gloss`, no etymology). SKIPPED by rule.
3. أدبي (verb) — from the range at 5/20 of the file: the "See the
   etymology of the corresponding lemma form." stub (sense tags
   `form-ii`, `no-gloss`). SKIPPED by rule.
4. حساسية (adj) — from the range at 9/20: a glossed form-of entry
   ("feminine singular of حَسَّاسِيّ") that carries the lemma-pointer
   etymology. KEPT.
5. لبد (noun) — from the range at 12/20: glossed, with a `bor+`
   etymology template (Aramaic donor). KEPT.

Selected by rule at fixture time: the smallest sample record of each
shape (glossed+etymon+descendants, bare stub, lemma-pointer stub,
glossed lemma-pointer, glossed+borrowing etymon).

## Refresh

Re-fetch the URL above and re-select the same `word`/`pos` pairs. NOTE
the upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "ar"`.
