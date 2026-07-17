# OG(H)AM (Ogham in 3D) fixtures — P25-1

Real EpiDoc records for the `ogham` adapter (`Nabu::Adapters::Ogham` /
`OghamEpidocParser`). Retrieved **2026-07-17** from the owner-authorized
scratch clone of `https://github.com/lguariento/og-h-am` (HEAD
`bb62ccd146cc3…`, committed 2026-07-02; live site: ogham.celt.dias.ie,
"Ogham in 3D v2.0 (2025)"). All files **byte-identical** to the repo
contents; layout mirrors the cloned tree (`XML/<REGION>/<ID>.xml` +
`XML/charDecl.xml`, the shared glyph table the parser resolves `<g>` refs
through).

## License — the CONFLICT, both readings verbatim (class `nc` PENDING)

- Site about-page: *"the XML files… are freely accessible and
  downloadable under a CC-BY-NC-SA License…"*
- EVERY sampled record's `<availability>`: `<licence
  target="https://creativecommons.org/licenses/by/4.0/">`*"Creative
  Commons Attribution 4.0 International License"*`</licence>`
- The repo has **no LICENSE file**.

The two grants contradict; the restrictive reading governs until upstream
answers the drafted clarification email (unlock registry #14) →
license_class `nc`, relabel-on-reply.

## Records (whole, byte-identical)

| File | Layers | Quirks it preserves |
|---|---|---|
| `XML/I-MAY/I-MAY-010.xml` | ogham, transliteration | The simple base case (Kilgarvan): one line of REAL Ogham codepoints (ᚇᚑᚈᚐᚌᚅᚔ, byte-pinned NFC) + the DOTAGNI transliteration sibling, `name @nymRef`, logainm.ie place ref, `<geo>`, **word-level dil.ie refs in the commentary** (18492, 12667 → reference edges), English translation prose, CISP idno. |
| `XML/S-SHE/S-SHE-001.xml` | ogham, transliteration | The glyph-heavy Pictish case (Bressay, xpi-Ogam): dense `<g>` forfeda/letter-variant refs (angled_*, bound_*, rabbit-eared_D, crosshatched_R → ᚏ‍ᚏ with ZWJ, forfid_OI ᚖ), `@type="interpretation_O"` mapping override, `᛬` punctuation glyphs, `unclear`, and the `<ab type="list">` derived summary (dropped by rule). |
| `XML/E-DEV/E-DEV-001.xml` | ogham, transliteration, roman ×2 | `<choice><corr>ᚅᚅ</corr><sic>ᚊᚊ</sic></choice>` (corr kept whichever order), TWO roman edition divs (textparts n=2, n=3 — one -roman layer document), inline `xml:lang="pgl"` on a word inside the Latin edition (→ per-line languages annotation), a false `pgl-Ogam` tag on the transliteration div (→ the shed--Ogam script-honesty rule). |
| `XML/E-CON/E-CON-X03.xml` | roman only | A companion "X" stone with NO ogham edition (St Clement): the -roman document is the record's only (and metadata-bearing) document; textparts n=1/n=2 with per-textpart `lb n="1"` (suffixes 1:1 / 2:1), la-Latn. |
| `XML/I-WAT/I-WAT-042.xml` | ogham (no `<lb>`), transliteration | The whole-layer `:text` fallback: the ogham edition carries real text but no line milestones; `supplied` inside names. |
| `XML/I-COR/I-COR-L11.xml` | (none) | Both edition divs SELF-CLOSED (empty) — the skip-by-rule census case: discover yields no refs, discovery_skips counts 2. |
| `XML/charDecl.xml` | — | The repo's glyph table: 61 glyphs, `ogham`/`diplomatic`/`interpretation*` mappings (the layer-default + `@type`-override resolution rules). |

## Known upstream defects (documented, not fixed)

- `XML/W-PEM/W-PEM-006.xml` and `W-PEM-012.xml` (not fixtures) carry a
  transliteration `<lb>` with no `@n` → those two layer documents will
  quarantine honestly at first sync (ParseError names the file).
- One `<g ref="bound_Q">` (M-IOM-005) misses its `#` — the parser strips
  the prefix either way.
- `I-COR-L11` (fixture) and `I-WAT-042`'s ogham layer show the two
  empty-ish shapes: fully empty divs (skip-by-rule) vs text-without-lb
  (the `:text` fallback).
