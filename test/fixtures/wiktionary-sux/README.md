# wiktionary-sux fixture

Trimmed REAL excerpt of the kaikki.org Sumerian extraction. Retrieved
2026-08-10 from
https://kaikki.org/dictionary/Sumerian/kaikki.org-dictionary-Sumerian.jsonl
(2,295,953 bytes, 2,499 lines at snapshot — matching the Q7 scout's
2026-08-09 census byte-for-byte).

Cut: the 16 complete JSONL lines whose `word` is one of 𒊬 · 𒀭 · 𒀊 ·
𒋀 · ab, byte-verbatim in upstream order — covering:

- pure-cuneiform headwords with sense glosses (𒊬 noun "orchard" — the
  P65 sign-card join exemplar; 𒀭 "deity, god/goddess"),
- descendants trees with the sux→akk borrowing chains (𒊬 → Akkadian
  𒊬 kirûm; 𒀊 → aptum, tagged borrowed+uncertain) and an en chain
  (𒀭 → "dingir"),
- multiple pos entries per glyph (𒊬 noun + verbs),
- the "ab" romanization pointer entry (alt-of 𒀊).

## Refresh

Re-fetch the URL above and re-select the same five `word` values
(𒋀 = ŠEŠ, shared with the osl fixture — the sign-card join test).
NOTE the upstream deprecation caveat (adapter class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "sux"`.
