# Freising Manuscripts (Brižinski spomeniki) fixtures

Trimmed real files from the eZISS electronic critical edition:
*Brižinski spomeniki: Elektronska znanstvenokritična izdaja*, ed. Matija
Ogrin, TEI encoding Tomaž Erjavec (ZRC SAZU / IJS, edition 1.0, 2007-04-06).

- Retrieved: 2026-07-11
- Source: `https://nl.ijs.si/e-zrc/bs/tei/<file>.xml` (browsable TEI dir);
  the sync target is the text-only bundle `https://nl.ijs.si/e-zrc/bs-text.zip`
  (7.5 MB, TEI under `bs/tei/`). NOTE: the zips live under `/e-zrc/`, NOT
  `/e-zrc/bs/` as the landing page's relative links might suggest.
- License (verbatim from `bs.xml` `<availability>`): "Avtorske pravice za
  besedilo te izdaje ureja licenca Creative Commons Priznanje avtorstva-Brez
  predelav 2.5 Slovenija" (`http://creativecommons.org/licenses/by-nd/2.5/si/`)
  = **CC BY-ND 2.5 SI** → `license_class: research_private` (owner ruling
  2026-07-11; the English HTML page's "Share Alike" label is wrong — the
  machine-readable TEI header governs). Facsimiles (© BSB München) and audio
  (© ZRC SAZU/RTVS) are separately copyrighted and excluded entirely.

## Trimming

Done with a Nokogiri script (structure preserved, no hand-written XML):

- Layer files (`bsCT`, `bsDT`, `bsPT`, `bsTR-{slv,eng,ger,ita,lat,pol}`):
  monument I kept COMPLETE (39 lines incl. the famous opening and the Latin
  tail lines 37–39); monuments II and III trimmed to their first `<page>`
  with the first 3 `<line>` elements. All layers stay line-parallel by
  shared id scheme (`bsCT.1.001` ↔ `bsDT.1.001` ↔ `bsTR-eng.1.001` …);
  upstream every layer carries exactly 228 lines.
- `bs.xml` (master): full `<availability>` (license test target), DOCTYPE
  with the external-entity declarations (the P4 quirk — the adapter does NOT
  resolve them), `<langUsage>`, `<charDesc>` reduced to the 25 ZRCola-PUA
  glyphs actually referenced by the trimmed layer files, credit rolls and
  revision log trimmed, `<front>` dropped.

## Upstream quirks documented here

- TEI **P4** (`TEI.2`, `tei2.dtd`), edition composed via external entities
  in `bs.xml`; each layer file is an independently parseable `<div>` fragment.
- ZRCola Private-Use-Area glyphs appear only as `<g corresp="zrcolaXXXX"/>`
  refs (no raw PUA codepoints in text); `bs.xml` `<charDesc>` maps each to
  standard Unicode (`<mapping type="standard">`), flagged exact/lossy.
- Editorial tags: critical/phonetic use `<sic>`+`<corr>` (and critical
  `<abbr>`+`<expan>`); diplomatic uses scribal `<add>`/`<del>` and `<g>`
  refs; translations carry end-`<note>`s inline within `<line>`.
- `<line n>` numbering is per-monument and continuous across pages
  (folio in `page/@n`: 78r … 161v of Clm 6426).
