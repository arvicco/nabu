# tla-hf fixtures — TLA official Hugging Face datasets (demotic v18 + Late Egyptian v19)

Retrieved 2026-07-18 from the Thesaurus Linguae Aegyptiae's OFFICIAL
Hugging Face org (`huggingface.co/datasets/thesaurus-linguae-aegyptiae`),
via the plain-HTTPS resolve URLs (no hf CLI):

- `demotic-v18/train.jsonl` — byte-verbatim lines **1, 2, 306, 355** of
  <https://huggingface.co/datasets/thesaurus-linguae-aegyptiae/tla-demotic-v18-premium/resolve/main/train.jsonl>
  (full artifact: **7,284,199 bytes, 13,383 records**, sha256
  `787e9ce8b5005a056f4579723ccffeaa5db1ed0bd7f42b7e5d5ec34d6867a63f`).
  Line 306 is the corpus's first non-NFC transliteration (`h` + U+0331
  COMBINING MACRON BELOW, which NFC precomposes to `ẖ` U+1E96 — 118 such
  records censused corpus-wide); line 355 is the first UNDATED record
  (`dateNotBefore`/`dateNotAfter` both empty — 710 corpus-wide, always
  both-empty together).
- `late-egyptian-v19/train.jsonl` — byte-verbatim lines **1, 2, 782** of
  <https://huggingface.co/datasets/thesaurus-linguae-aegyptiae/tla-late_egyptian-v19-premium/resolve/main/train.jsonl>
  (full artifact: **1,904,138 bytes, 3,606 records**, sha256
  `dfded75c7d34bc1f2f12e18af6936394dc0c5cadacd1229dc28d46751d6389df`).
  Line 782 is that corpus's first non-NFC transliteration (9 censused);
  every late-Egyptian record is dated. Line 1 carries a `<g>Ff101</g>`
  JSesh glyph tag inside `hieroglyphs` (glyphs not yet in Unicode v15 ride
  as JSesh codes in `<g>…</g>`, per the dataset card).

Because passage identity is the record's 1-based line NUMBER in the local
canonical file (upstream ships no sentence ids — censused), the trimmed
fixtures mint urns `:1`–`:4` / `:1`–`:3`; the upstream line provenance
above is documentation, not identity.

## Field census (2026-07-18, full artifacts)

Both files: one JSON object per line. Shared fields — `transliteration`
(Leiden Unified Transliteration, space-separated), `lemmatization`
(space-separated `<TLA lemma ID>|<lemma transliteration>` pairs; demotic
IDs carry `d`/`dm` prefixes — 99,102/18,212 tokens; late-Egyptian IDs are
bare numbers — 24,437 tokens), `UPOS`, `glossing`, `translation` (German),
`dateNotBefore`/`dateNotAfter` (strings holding signed integers, historical
years, or empty; no year 0, no inverted range upstream). The four
token-bearing fields split to IDENTICAL counts on every record of both
corpora (censused: 0 misalignments). Demotic only: `authors`
(`;`-separated credit line). Late Egyptian only: `hieroglyphs` (Unicode
v15 + `<g>JSesh</g>` fallbacks).

## License (verbatim from both dataset cards, retrieved 2026-07-18)

YAML frontmatter, both cards: `license: cc-by-sa-4.0`. Prose, both cards:

> **License:** [CC BY-SA 4.0 Int.](https://creativecommons.org/licenses/by-sa/4.0/);
> for required attribution, see citation recommendations below.

Card citation (demotic): "Thesaurus Linguae Aegyptiae, Demotic sentences,
corpus v18, premium ... v1.1, 2/16/2024, ed. by Tonio Sebastian Richter &
Daniel A. Werning on behalf of the Berlin-Brandenburgische Akademie der
Wissenschaften and Hans-Werner Fischer-Elfert & Peter Dils on behalf of
the Sächsische Akademie der Wissenschaften zu Leipzig." The late-Egyptian
card carries the same editors for corpus v19. Card sha256s at retrieval:
demotic `fad2b2d9fcc2d9f710cb155b65a7c91e6b9954a7ece7654bc327dd6612352047`,
late Egyptian `8a72d7f6e0de38289583ef795009786c8246c0a97f40f26c5f476000e6cd3dc1`.

Language: both cards tag the data `egy` (+ `de` for the translations);
card prose says "egy-Egyd" (demotic) / "egy-Egyp, egy-Egyh" (late
Egyptian) — SCRIPT subtags, while the stored passage surface is Latin
transliteration. Nabu ingests both as `egy` with the stage as a document
facet (`stage: demotic` / `late-egyptian`) — the damaskini Norm
precedent; no invented subtags.
