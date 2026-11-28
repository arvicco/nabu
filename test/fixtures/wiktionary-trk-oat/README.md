# wiktionary-trk-oat fixture

Trimmed REAL excerpt of the kaikki.org Old Anatolian Turkish extraction. Retrieved
2026-11-27 from
https://kaikki.org/dictionary/Old%20Anatolian%20Turkish/kaikki.org-dictionary-OldAnatolianTurkish.jsonl
(1,670,030 bytes, 607 lines at snapshot, Last-Modified
2026-10-30, sha256
02746bea5ae8aa2ade59f29e17426a31eb1f5387aa02f1757cfa303a234e94de;
the index page states "426 distinct words" and labels the
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

The 2 complete JSONL lines whose `word` is میوه · من,
byte-verbatim in upstream order (0-based lines 0, 1 of the
snapshot) — the first record carrying an etymon edge and the first later record carrying a worded descendant
(selected by rule at fixture time).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "trk-oat"`.
