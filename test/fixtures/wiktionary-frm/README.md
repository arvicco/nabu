# wiktionary-frm fixture

Trimmed REAL excerpt of the kaikki.org Middle French extraction. Retrieved
2026-11-02 from
https://kaikki.org/dictionary/Middle%20French/kaikki.org-dictionary-MiddleFrench.jsonl
(13,336,591 bytes, 4,956 lines at snapshot, Last-Modified
2026-10-30, sha256
d58515e9ea4cf13af6e86aa7282f84d11d088e295d4bde7e09468e82ed35ec58;
the index page states "4714 distinct words").

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language). The
site's HTML pages and the full all-languages dump are other deliveries
of the same data, not fetched.

## Cut

The 2 complete JSONL lines whose `word` is livre · chien,
byte-verbatim in upstream order (0-based lines 0, 3 of the
snapshot) — the first record carrying an etymon edge and the first later record carrying a worded descendant
(selected by rule at fixture time).

## Refresh

Re-fetch the URL above and re-select the same `word` values. NOTE the
upstream deprecation caveat (WiktionaryKaikki class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "frm"`.
