# GRETIL P11-7 stray fixture (real trimmed slice)

Fixture for P11-7 fix 6 (silent strays), kept in its own tree so the main
`test/fixtures/gretil/` discover assertions (an exact `san-Latn` fixture set)
stay untouched — this edition recovers as `san-Latn` via the `<body>`-lang
fallback and would otherwise perturb that set.

Retrieved **2026-07-10** from the on-disk canonical GRETIL corpus (byte-identical
to the `mmehner/gretil-corpus-tei` mirror). CC BY-NC-SA 4.0 (`nc`).

## File

- `sa_haribhadrasUri-zAstravArttAsamuccaya.xml` — TRIMMED from the real 4059-line
  edition to its teiHeader + the first three `<lg xml:id="HSvs_1.1.N">` verse
  groups (through a complete `</lg>`), with the two open `<div>`s and
  `<body>`/`<text>`/`<TEI>` closed cleanly (well-formed, verified). This is one
  of the two editions whose `<text>` carries NO `@xml:lang` (its teiHeader
  `xml:lang="en"` describes the metadata, not the edition) — `peek_header`
  returned nil and discovery dropped it INVISIBLY. The language now falls back to
  `<body xml:lang="sa-Latn">` → `san-Latn` (then the filename `sa_` prefix as a
  last resort), recovering the edition. Passages: `1.1.1`, `1.1.2`, `1.1.3`
  (xml:id addressing rung).

The larger stray, `sa_vijJAnezvara-mitAkSarA` (the 1.8 MB Mitākṣarā, 4788 prose
passages), shares the same `<text>`-lang-less shape and is recovered identically;
it is not fixtured here (one slice proves the fallback).
