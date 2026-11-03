# wiktionary-fro fixture

Trimmed REAL excerpt of the kaikki.org Old French extraction. Retrieved
2026-11-02 from
https://kaikki.org/dictionary/Old%20French/kaikki.org-dictionary-OldFrench.jsonl
(37,234,970 bytes, 9,280 lines at snapshot, Last-Modified
2026-10-30, sha256
d6cdf8e789c423432c6820f18186ad74c6c0618ba4f49ebedf8a936ed66f892d;
the index page states "8690 distinct words").

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language). The
site's HTML pages and the full all-languages dump are other deliveries
of the same data, not fetched.

## Cut

The 2 complete JSONL lines whose `word` is livre · chien,
byte-verbatim in upstream order (0-based lines 2, 4 of the
snapshot) — the first record carrying an etymon edge and the first later record carrying a worded descendant
(selected by rule at fixture time).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "fro"`.
