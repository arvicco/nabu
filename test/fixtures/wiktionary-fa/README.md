# wiktionary-fa fixture

Trimmed REAL excerpt of the kaikki.org Persian extraction. Retrieved
2026-11-02 from
https://kaikki.org/dictionary/Persian/kaikki.org-dictionary-Persian.jsonl
(95,770,880 bytes, 20,350 lines at snapshot, Last-Modified
2026-10-30, sha256
c5fda57f5593fc256570a5e146c4ac5b6b239906aae781eca1d02b2022a03482;
the index page states "17651 distinct words", 28,272 senses).

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry; there is no rejected
grain inside the file (every record is the extract's language — the
census found the single lang_code "fa" on all 20,350 lines). The
site's HTML pages and the full all-languages dump are other deliveries
of the same data, not fetched.

## Cut

The 3 complete JSONL lines whose `word` is one of کتاب · دل · شاه,
byte-verbatim in upstream order (0-based lines 188, 542, 747 of the
snapshot; for کتاب the first of its two records, etymology 1) —
covering an Arabic borrowing whose descendants run into Tajik and the
Indic languages (کتاب "book"), an inherited word with its Middle
Persian → Proto-Iranian → PIE etymon chain (دل "heart" ← 𐭣𐭩𐭫), and a
chain through Old Persian (شاه "king; shah").

## Refresh

Re-fetch the URL above and re-select the same `word` values (first
record each). NOTE the upstream deprecation caveat (WiktionaryKaikki
class note): if the per-language JSONL is gone, filter the full
wiktextract dump by `lang_code == "fa"`.
