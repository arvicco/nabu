# wiktionary-sh fixture

Trimmed REAL excerpt of the kaikki.org Serbo-Croatian extraction. Retrieved
2026-11-02 from
https://kaikki.org/dictionary/Serbo-Croatian/kaikki.org-dictionary-SerboCroatian.jsonl
(385,655,385 bytes, 70,466 lines at snapshot, Last-Modified
2026-10-30, sha256
247f0ec9e8e4d86162c8eff82f840d68204cf05d0f42b651ae7659dca185cd56;
the index page states "66998 distinct words").

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language). The
site's HTML pages and the full all-languages dump are other deliveries
of the same data, not fetched.

## Cut

The 2 complete JSONL lines whose `word` is august · žaba,
byte-verbatim in upstream order (0-based lines 1, 763 of the
snapshot) — the first record carrying an etymon edge and the first later record carrying a worded descendant
(selected by rule at fixture time).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "sh"`.
