# wiktionary-te fixture

Trimmed REAL excerpt of the kaikki.org Telugu extraction. Retrieved
2026-10-21 from
https://kaikki.org/dictionary/Telugu/kaikki.org-dictionary-Telugu.jsonl
(32,721,606 bytes, 23,325 lines at snapshot, Last-Modified
2026-10-03; the index page states "21803 distinct words").

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
తెలుగు · నాలుగు · బలపము, byte-verbatim in upstream order (0-based lines
4, 48, 7051 of the snapshot) — covering two Proto-Dravidian inheritance etymons (తెలుగు, నాలుగు "four") and a descendants tree lending into Tamil (బలపము → பலப்பம், பல்பம்).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "te"`.
