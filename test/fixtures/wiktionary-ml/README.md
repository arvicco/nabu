# wiktionary-ml fixture

Trimmed REAL excerpt of the kaikki.org Malayalam extraction. Retrieved
2026-10-21 from
https://kaikki.org/dictionary/Malayalam/kaikki.org-dictionary-Malayalam.jsonl
(23,456,757 bytes, 11,505 lines at snapshot, Last-Modified
2026-10-03; the index page states "10942 distinct words").

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
പുസ്തകം · കരയുക · കാളൻ, byte-verbatim in upstream order (0-based lines
20, 41, 9590 of the snapshot) — covering a Sanskrit borrowing etymon (പുസ്തകം "book" from पुस्तक), a cognate note that mints nothing (കരയുക), and a descendants tree lending into Tamil (കാളൻ → காளன்).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "ml"`.
