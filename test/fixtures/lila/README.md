# LiLa Lemma Bank — fixture

Source: CIRCSE / LiLa: Linking Latin, the Lemma Bank.
Repository: https://github.com/CIRCSE/LiLa_Lemma-Bank
Zenodo (citable): https://doi.org/10.5281/zenodo.4017229
License: **CC BY-SA 4.0 International** (in-repo `LICENSE`, verbatim first line
"Attribution-ShareAlike 4.0 International"; README `## Copyright` links
creativecommons.org/licenses/by-sa/4.0/). → house class `attribution`.

Retrieved: 2026-07-24 (raw.githubusercontent.com/CIRCSE/LiLa_Lemma-Bank/HEAD).

## What this is

`rdf/lemmaBank.ttl` is a **verbatim trimmed slice** of the upstream 84 MB
`rdf/lemmaBank.ttl` (D2RQ Turtle dump of the relational Lemma Bank). The
prefix header is kept whole; then eight real subject blocks, chosen for
coverage:

- `lilaLemma:83005` subsides — plain Lemma, one writtenRep, noun.
- `lilaLemma:169428` percrebreo — verb.
- `lilaLemma:96403` contutor — word-formation lemma (base/prefix/suffix).
- `lilaLemma:105138` hamiger — two writtenReps "hamiger"/"amiger" (h-drop
  variant, not bridged by the u/v fold).
- `lilaLemma:85300` uirgastrum — two writtenReps "uirgastrum"/"uirgastrom"
  (the u-spelling: "virgastrum" folds v→u onto it).
- `lilaLemma:119692` proeliaris — two writtenReps "praeliaris"/"proeliaris"
  (ae/oe variant).
- `lilaIpoLemma:97523` eclipsans — a Hypolemma, two writtenReps
  "eclypsans"/"eclipsans" (y/i variant), `lila:isHypolemma` → lilaLemma:48631.
- `lilaLemma:152269` tantipliciter — adverb.

Each subject block is byte-verbatim upstream (whitespace as the D2RQ dump
emits it). No triples were invented or edited.

The real distribution lands under `canonical/lila/rdf/lemmaBank.ttl` via
`nabu sync lila` (git-pinned sparse clone; see `lib/nabu/adapters/lila.rb`).
`Nabu::Lila` reads that file directly — no catalog table, no migration (the
Pleiades resolver shape).
