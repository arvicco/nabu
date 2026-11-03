# wiktionary-pa fixture

Trimmed REAL excerpt of the kaikki.org Punjabi extraction. Retrieved
2026-11-02 from
https://kaikki.org/dictionary/Punjabi/kaikki.org-dictionary-Punjabi.jsonl
(38,069,877 bytes, 10,749 lines at snapshot, Last-Modified
2026-10-30, sha256
9a7b46898d47468c4674ac881ea1729cb1cc8933aa78e8ef0c33af7861cb1b7f;
the index page states "9533 distinct words").

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language). The
site's HTML pages and the full all-languages dump are other deliveries
of the same data, not fetched.

## Cut

The 2 complete JSONL lines whose `word` is زبان · ਵਾਹਿਗੁਰੂ,
byte-verbatim in upstream order (0-based lines 2, 219 of the
snapshot) — the first record carrying an etymon edge and the first later record carrying a worded descendant
(selected by rule at fixture time).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "pa"`.
