# wiktionary-dum fixture

Trimmed REAL excerpt of the kaikki.org Middle Dutch extraction. Retrieved
2026-11-02 from
https://kaikki.org/dictionary/Middle%20Dutch/kaikki.org-dictionary-MiddleDutch.jsonl
(5,989,862 bytes, 2,342 lines at snapshot, Last-Modified
2026-10-30, sha256
142fcd1bf3e9d9e3f6ec299d9bd21b8db192c7324247c71d9304857b372f2995;
the index page states "2031 distinct words").

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language). The
site's HTML pages and the full all-languages dump are other deliveries
of the same data, not fetched.

## Cut

The 2 complete JSONL lines whose `word` is raven · name,
byte-verbatim in upstream order (0-based lines 0, 1 of the
snapshot) — the first record carrying an etymon edge and the first later record carrying a worded descendant
(selected by rule at fixture time).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "dum"`.
