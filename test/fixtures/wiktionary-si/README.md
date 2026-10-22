# wiktionary-si fixture

Trimmed REAL excerpt of the kaikki.org Sinhala extraction. Retrieved
2026-10-21 from
https://kaikki.org/dictionary/Sinhalese/kaikki.org-dictionary-Sinhalese.jsonl
(1,887,237 bytes, 1,281 lines at snapshot, Last-Modified
2026-10-03; the index page states "1231 distinct words").

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language — the
census found a single lang_code throughout). The site's HTML pages
and the full all-languages dump are other deliveries of the same
data, not fetched.

## Cut

The 3 complete JSONL lines whose `word` is one of
අම්මා · ගෙය · කන්ද, byte-verbatim in upstream order (0-based lines
2, 15, 134 of the snapshot) — covering a Tamil borrowing etymon (අම්මා "mother" ← அம்மா), a Prakrit inheritance (ගෙය "house" ← 𑀕𑁂𑀳), and a descendants tree lending into Portuguese and English (කන්ද → Candea, Kandy).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "si"`.
