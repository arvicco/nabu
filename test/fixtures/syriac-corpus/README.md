# Syriac Corpus fixture — Digital Syriac Corpus (srophe, P31-4)

Six byte-verbatim WHOLE TEI files of
[github.com/srophe/syriac-corpus](https://github.com/srophe/syriac-corpus)
(the Digital Syriac Corpus, syriaccorpus.org — BYU/Oxford/Vanderbilt/
Texas A&M).

- **Retrieved:** 2026-07-19, from commit
  `833adc148cc356a6c70c16f81b22df9188df717a` (main), via
  `https://raw.githubusercontent.com/srophe/syriac-corpus/main/data/tei/<n>.xml`.
- **Layout:** mirrors the sparse workdir the adapter fetches
  (`data/tei/<n>.xml`). All six are WHOLE files (sha256 recorded below),
  so `rake fixtures:check[syriac-corpus]` byte-compares and re-runs the
  adapter test against fresh copies.

## Corpus-wide census (all 632 files parsed at the pinned commit)

- **632 numeric TEI files** (ids 1–692 with gaps; 25, 125, 369–371, 390,
  630–649 … absent). All parse cleanly (ElementTree strict).
- **License is per-file and uniform**: every `<availability>` carries
  `licence target="http://creativecommons.org/licenses/by/4.0/"` with
  the text "Creative Commons — Attribution 4.0 International — CC BY
  4.0" and the note "… The Syriac base text is in the public domain. The
  TEI XML edition is copyrighted … under a Creative Commons Attribution
  4.0 International Public License (CC BY 4.0)." → class `attribution`;
  the adapter RE-VERIFIES per file and quarantines drift.
- **Identity**: `publicationStmt idno[@type=URI]` normally equals the
  filename, but TWO files mismatch — `69.xml` says `…/61` (duplicating
  61.xml's idno; 69 is "On the Martyrs", 61 is "On Holy Week") and
  `126.xml` says `…/125` (a filename-space gap) → the FILENAME mints the
  urn; idno rides metadata verbatim.
- **Structure** (the srophe TEI application — NOT EpiDoc): body divs of
  16 types (section 4,412 / text 727 / rubric 447 / title 388 / chapter
  260 / part 256 / body 169 / …), depth ≤ 3; 1,958 of 6,801 divs
  unnumbered; 5 sibling div pairs share (type, n). Blocks: l 115,821
  (113,435 directly under divs — the poetry corpora; 48,327 numbered) /
  p 8,803 (43 numbered) / ab 8,211 (7,958 numbered) / head 4,624 / lg
  520; 1,389 blocks flatten to nothing (skipped). → the ADDRESSABILITY
  VERDICT: no uniform citation scheme; passages mint by document-order
  block ordinal, div path + tag/@n ride annotations.
- `<note>` ×5,417 (apparatus: "sic", MS-siglum variants) inside p/l —
  stripped from text, riding annotations. `<front>` in 63 files
  (editorial summaries) — skipped. langUsage uniformly `syr`; block/div
  xml:lang: syr / en (340 incl. 6 en-titled divs) / eng (4) / ar (12).
  revisionDesc/@status: uncorrectedTranscription 221 /
  UncorrectedTranscription 218 / Edited 101 / UneditedTranscription 79 /
  ProofedDigitalEdition 12 / absent 1.

## The six whole-file fixtures

| file | why |
|---|---|
| 1.xml | Aphrahat, Demonstration 1 — the flagship prose shape: numbered section divs of head+p, title div, full header (author/work/origDate/status) |
| 116.xml | a memra — standalone `l` lines (partly numbered) under rubric/text divs: the poetry line grain |
| 142.xml | 2 John (Peshitta NT) — numbered `ab` verses in a chapter div; English "Chapter 1" head → the eng-block witness |
| 170.xml | a soghitha — `lg` stanzas with heads INSIDE lg (hoisted) and newline-joined lines |
| 250.xml | unnumbered `div[text]`/p shape — the ordinal-fallback witness |
| 687.xml | Letter of Helena — `<front>` (skipped), text+translation sibling divs (en inheritance), 2 apparatus notes |

sha256 at retrieval (whole files; `manifest.yml` re-verifies by byte
comparison against fresh GETs):

```
2a4f9aa70ecd10a51dea3a9a625b0ad5e1f0d15e29123cd2e153861225ae1b1d  1.xml
474388c4619b8cef71307ff658feb569958cdd4f41e8182df3b4ec2abc85f47d  116.xml
052feecfb76460d4e301c70b4a3a14510cd41b57e768d7e3249c93f16f9e1ad7  142.xml
c777df7a9394d67bcaefd9134789b25f94adb44be97ab48544428ecd258dc5ef  170.xml
c0f23b5d5735d970fb0b9a9ba5490a3c69babdcf72c2aabe4eece27b762502d7  250.xml
81ff2a859957ba3492205ff8e69789621aa924d8d9215a798d6324684e2c813b  687.xml
```
