# wiktionary-dv fixture

Trimmed REAL excerpt of the kaikki.org Dhivehi extraction. Retrieved
2026-10-21 from
https://kaikki.org/dictionary/Dhivehi/kaikki.org-dictionary-Dhivehi.jsonl
(3,390,132 bytes, 2,047 lines at snapshot, Last-Modified
2026-10-03; the index page states "1882 distinct words").

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
ދިވެހި · ފޮތް · މާލެ, byte-verbatim in upstream order (0-based lines
49, 58, 175 of the snapshot) — covering Thaana headwords; a compound with no typed etymon (ދިވެހި), a Prakrit inheritance in Brāhmī (ފޮތް "book" ← 𑀧𑀼𑀢𑁆𑀣), and a place name lent onward (މާލެ → bn/en/hi).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "dv"`.
