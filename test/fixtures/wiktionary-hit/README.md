# wiktionary-hit fixture

Trimmed REAL excerpt of the kaikki.org Hittite extraction. Retrieved
2026-09-13 from
https://kaikki.org/dictionary/Hittite/kaikki.org-dictionary-Hittite.jsonl
(4,327,281 bytes, 481 lines at snapshot; upstream page states "466
distinct words", 414 records carry pure-cuneiform headwords).

Cut: the 4 complete JSONL lines whose `word` is one of ekan · 𒉿𒀀𒋻 ·
𒋻𒌑𒍣 · 𒁍𒊒𒌓, byte-verbatim in upstream order — covering:

- pure-cuneiform headwords with sense glosses (𒉿𒀀𒋻 wātar "water" —
  the decipherment exemplar; 𒁍𒊒𒌓 "soil, mud, earth"),
- descendants trees with borrowing chains minted as reflexes (𒋻𒌑𒍣 →
  Akkadian 𒅴𒁄 — the hit→akk chain; 𒁍𒊒𒌓 → Armenian/Kurdish/
  Ottoman purut chain),
- the "ekan" romanization pointer entry ("Broad transcription of
  𒂊𒃷" — kaikki-Hittite's pointer class, 100 of 481 records).

## Refresh

Re-fetch the URL above and re-select the same four `word` values.
NOTE the upstream deprecation caveat (adapter class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "hit"`.
