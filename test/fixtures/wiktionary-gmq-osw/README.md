# wiktionary-gmq-osw fixture

Trimmed REAL excerpt of the kaikki.org Old Swedish extraction. Retrieved
2026-11-02 from
https://kaikki.org/dictionary/Old%20Swedish/kaikki.org-dictionary-OldSwedish.jsonl
(8,596,849 bytes, 1,440 lines at snapshot, Last-Modified
2026-10-30, sha256
272f87ffe88a7c45dbe82b6a385c7be8176c7acd60c2a9cb9de6e5611b958ffa;
the index page states "1404 distinct words").

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language). The
site's HTML pages and the full all-languages dump are other deliveries
of the same data, not fetched.

## Cut

The 2 complete JSONL lines whose `word` is fa · sky,
byte-verbatim in upstream order (0-based lines 0, 2 of the
snapshot) — the first record carrying an etymon edge and the first later record carrying a worded descendant
(selected by rule at fixture time).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "gmq-osw"`.
