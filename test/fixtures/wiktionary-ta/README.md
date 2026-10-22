# wiktionary-ta fixture

Trimmed REAL excerpt of the kaikki.org Tamil extraction. Retrieved
2026-10-21 from
https://kaikki.org/dictionary/Tamil/kaikki.org-dictionary-Tamil.jsonl
(88,872,672 bytes, 13,855 lines at snapshot, Last-Modified
2026-10-03; the index page states "11180 distinct words").

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
கோடி · அம்மா · ரசம், byte-verbatim in upstream order (0-based lines
23, 91, 1517 of the snapshot) — covering a Sanskrit borrowing etymon (கோடி from कोटि), a Proto-Dravidian inheritance stated only in prose (அம்மா — no typed template, so no edge), and a descendants tree carrying the English loan (ரசம் → rasam).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "ta"`.
