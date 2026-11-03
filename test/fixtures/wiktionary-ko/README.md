# wiktionary-ko fixture

Trimmed REAL excerpt of the kaikki.org Korean extraction. Retrieved
2026-11-02 from
https://kaikki.org/dictionary/Korean/kaikki.org-dictionary-Korean.jsonl
(207,649,961 bytes, 64,457 lines at snapshot, Last-Modified
2026-10-30, sha256
c160b1dadd49b14109c2c1a29a616cc44064a738f91d2b98c1cdf457b90fde7f;
the index page states "57810 distinct words").

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language). The
site's HTML pages and the full all-languages dump are other deliveries
of the same data, not fetched.

## Cut

The 2 complete JSONL lines whose `word` is OK · 불가사리,
byte-verbatim in upstream order (0-based lines 12, 10229 of the
snapshot) — the first record carrying an etymon edge and the first later record carrying a worded descendant
(selected by rule at fixture time).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "ko"`.
