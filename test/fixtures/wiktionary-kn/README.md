# wiktionary-kn fixture

Trimmed REAL excerpt of the kaikki.org Kannada extraction. Retrieved
2026-10-21 from
https://kaikki.org/dictionary/Kannada/kaikki.org-dictionary-Kannada.jsonl
(8,923,875 bytes, 2,741 lines at snapshot, Last-Modified
2026-10-03; the index page states "2495 distinct words").

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
ನುಡಿ · ಒಂದು · ಬಸವ, byte-verbatim in upstream order (0-based lines
1, 15, 751 of the snapshot) — covering two Proto-Dravidian inheritance etymons (ನುಡಿ, ಒಂದು "one") and a name with a Sanskrit derivation plus a Tamil descendant (ಬಸವ).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "kn"`.
