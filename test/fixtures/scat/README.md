# SCAT fixtures

Source: the St. Petersburg Corpus of Hagiographic Texts (SCAT), Saint
Petersburg State University — <https://github.com/vintagentleman/scat-content>,
release **1.2.0** (tag published 2021-10-24), asset
<https://github.com/vintagentleman/scat-content/releases/download/1.2.0/scat-content-120.zip>.
Retrieved 2026-10-20.

License: CC BY-SA 4.0 — the repository LICENSE (Attribution-ShareAlike 4.0
International) and the README's Copyright section ("This corpus is licensed
under CC-BY-SA-4.0."). The release zip is an asset of the same repository.
(`Documentation.jsp` carries a "Corpus binaire TXM sous licence CC BY-NC-SA
3.0" line inside an HTML comment: the TXM demo-portal template's leftover,
commented out, not a statement about SCAT.)

## Upstream grains

| Grain | Where | Taken? |
|---|---|---|
| Unicode TEI, one file per text (`<ID>.xml`, 24) | release zip | **yes: the document** |
| release catalog `metadata.csv` (id, title, century, morphology, text_structure) | release zip | consumed as document metadata |
| TXM portal furniture: `Documentation.jsp`, `css/SCAT.css`, `xsl/**/*.xsl` (5 files) | release zip | rejected: skipped by rule, counted in `discovery_skips` |
| TXM binary corpus (`SCAT-CONTENT-120-2021-10-24.txm`) | separate release asset | not fetched: a concordancer import, not text |
| Windows-866 ASCII-coded transliterations (`raw/*.txt`, 24) | git tree | not fetched: the legacy encoding the release TEI supersedes |
| TSV/XML-injected annotation layers (`annotation/{structural,morphological,combined}`) | git tree | not fetched: carried in the TEI (`@lemma/@pos/@msd`, `<div1>/<div2>/<q>`) |

Inside a TEI text the adapter's passage grain is the **folio side**: one
passage per `<pb>`. `n="371"` is the recto and `n="-371"` the verso (cited
`f.371r` / `f.371v`), and two-column manuscripts add a column letter
(`442a` → `f.442r.a`).

## Files

All files were extracted from the 1.2.0 zip on 2026-10-20.

- `DmPrlc.xml`: Житие Димитрия Прилуцкого (16th c.), from the
  morphology + structure subset. The body is cut before the 4th `<pb>`
  (keeping folios 201, -201, 202), with open elements closed by a DOM trim:
  685,814 B → 47,966 B, well-formed. It pins `<head>`, `<div1>`/`<div2>`,
  `<q source>` (biblical and patristic), `@lemma/@pos/@msd`, and one
  `<note type="corr">`.
- `AKush.xml`: Житие Александра Куштского (17th c.), plain subset. Cut
  before the 4th `<pb>` (371, -371, 372): 423,304 B → 18,802 B. It pins
  `lb`-split words, `<num>` with digit "lemmas", `<name>`, and an
  `<add place="margin">` wrapped in `[ ]` `<c>` marks.
- `ThdTtm.xml`: Житие Феодосия Тотемского (18th c.). Cut before the 6th
  `<pb>` (-51, 52, -52, 53, 53): 387,127 B → 24,212 B. It pins upstream's
  repeated `n="53"` with text on both sides.
- `metadata.csv`: the release catalog cut to the header and these three
  rows.
- `Documentation.jsp`, `css/SCAT.css`, `xsl/3-posttok/txm-posttok-addRef.xsl`:
  whole, one real specimen of the rejected furniture grain each.
