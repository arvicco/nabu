# wiktionary-ota fixture

Trimmed REAL excerpt of the kaikki.org Ottoman Turkish extraction. Retrieved
2026-11-27 from
https://kaikki.org/dictionary/Ottoman%20Turkish/kaikki.org-dictionary-OttomanTurkish.jsonl
(34,356,167 bytes, 10,016 lines at snapshot, Last-Modified
2026-10-30, sha256
dd5562a8ee1b9981217c681d0c7a216d83e5c7d702c70164f1455ca3cadfb66a;
the index page states "8848 distinct words" and labels the
per-language JSONL DEPRECATED).

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language). The
site's HTML pages and the full all-languages dump are other deliveries
of the same data, not fetched.

## Cut

The 2 complete JSONL lines whose `word` is آیا · جهاد,
byte-verbatim in upstream order (0-based lines 0, 1 of the
snapshot) — the first record carrying an etymon edge and the first later record carrying a worded descendant
(selected by rule at fixture time).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "ota"`.
