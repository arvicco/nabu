# wiktionary-gmh fixture

Trimmed REAL excerpt of the kaikki.org Middle High German extraction. Retrieved
2026-11-02 from
https://kaikki.org/dictionary/Middle%20High%20German/kaikki.org-dictionary-MiddleHighGerman.jsonl
(10,197,573 bytes, 2,142 lines at snapshot, Last-Modified
2026-10-30, sha256
90df174c53b1ad6a8901ebfedd021d0c597f8d5a7dbfc208237c77a89e63ba41;
the index page states "1958 distinct words").

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language). The
site's HTML pages and the full all-languages dump are other deliveries
of the same data, not fetched.

## Cut

The 2 complete JSONL lines whose `word` is name · winter,
byte-verbatim in upstream order (0-based lines 0, 1 of the
snapshot) — the first record carrying an etymon edge and the first later record carrying a worded descendant
(selected by rule at fixture time).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "gmh"`.
