# wiktionary-pra fixture

Trimmed REAL excerpt of the kaikki.org Prakrit extraction. Retrieved
2026-10-21 from
https://kaikki.org/dictionary/Prakrit/kaikki.org-dictionary-Prakrit.jsonl
(16,188,581 bytes, 2,712 lines at snapshot, Last-Modified
2026-10-03; the index page states "2452 distinct words").

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
𑀓𑀇 · 𑀫𑀳𑀼 · 𑀚𑀸𑀬, byte-verbatim in upstream order (0-based lines
102, 186, 204 of the snapshot) — covering Brāhmī headwords; an inheritance chain back to Proto-Indo-European (𑀓𑀇 "poet" ← kavi), and descendants into Konkani, Gujarati and Hindi (𑀫𑀳𑀼 "honey", 𑀚𑀸𑀬 "son").

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "pra"`.
