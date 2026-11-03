# wiktionary-et fixture

Trimmed REAL excerpt of the kaikki.org Estonian extraction. Retrieved
2026-11-02 from
https://kaikki.org/dictionary/Estonian/kaikki.org-dictionary-Estonian.jsonl
(56,323,247 bytes, 13,549 lines at snapshot, Last-Modified
2026-10-30, sha256
9a676b8dd13903109c9d8c265a0cf4eb792ae6095824afcb20f5a717a0c785ed;
the index page states "12657 distinct words").

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language). The
site's HTML pages and the full all-languages dump are other deliveries
of the same data, not fetched.

## Cut

The 2 complete JSONL lines whose `word` is aam · sent,
byte-verbatim in upstream order (0-based lines 5, 100 of the
snapshot) — the first record carrying an etymon edge and the first later record carrying a worded descendant
(selected by rule at fixture time).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "et"`.
