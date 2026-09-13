# wiktionary-akk fixture

Trimmed REAL excerpt of the kaikki.org Akkadian extraction. Retrieved
2026-09-13 from
https://kaikki.org/dictionary/Akkadian/kaikki.org-dictionary-Akkadian.jsonl
(2,865,176 bytes, 1,348 lines at snapshot; upstream page states "1236
distinct words", 540 records carry pure-cuneiform headwords).

Cut: the 7 complete JSONL lines whose `word` is one of urdu · 𒁾 ·
šarrum · ṭuppum · šaṭārum, byte-verbatim in upstream order — covering:

- pure-cuneiform Sumerogram headwords (𒁾 — TWO character records,
  "Sumerogram of ṭuppum" / "Sumerogram of kunukkum": the homograph
  entry-id split AND the sign-card join exemplar),
- romanized headwords with sense glosses (šarrum "king"),
- descendants trees with borrowing chains minted as reflexes (ṭuppum →
  Arabic/Hebrew/Syriac and Elamite 𒁾; šaṭārum both pos),
- multiple pos per headword (šaṭārum noun + verb),
- the "urdu" alternative-form pointer entry (alt-of wardum).

## Refresh

Re-fetch the URL above and re-select the same five `word` values.
NOTE the upstream deprecation caveat (adapter class note): if the
per-language JSONL is gone, filter the full wiktextract dump by
`lang_code == "akk"`.
