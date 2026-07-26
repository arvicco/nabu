# TraCES fixtures — TEI-Ling morphologically annotated Gǝʿǝz (P46-2)

Three whole, real files, snapshotted **2026-07-26** from
`github.com/BetaMasaheft/traces` (branch `master`, commit
`93f4908a4cb9964eef31c47cf5bca844e71bd570`). The repo is the TraCES
project's TEI-Ling export: 15 real `*TEILing.xml` files / 75,440 analyzed
word tokens (Matthew, Kebra nagast prologue, the ʿAmda Ṣeyon chronicle,
Testamentum Domini, "MM", "AK", Gadla Libānos excerpts, and seven Aksumite
royal inscriptions RIE 187–232), plus one stray Alpheios tool export.

- `RIE232TEILing.xml` — the funerary inscription of Giḥo (RIE 232), WHOLE
  (54 KB / 53 graphunits): the flat TEI-Ling stream — one
  `<fs type="graphunit">` per orthographic word carrying `fidäl` (Ethiopic
  script form), `translit`, and an `analysis` of one-or-more tokens, each
  with `morpho` features (pos/tam/person/gender/number/case/state…) and a
  `lex` lemma link `L<dillmann-entry-id>--<lemma fidäl>` into the Dillmann
  entry files (the ሞተ link here anchors the crosswalk test against
  test/fixtures/dillmann/1/L2d417be91261494990015aae6b9b5d81.xml).
  Multi-token graphunits (ba-warḫa → በ + ወርኀ) pin the proclitic split.
- `RIE193IITEILing.xml` — RIE 193 II, WHOLE (22 KB / 27 graphunits): the
  smallest real file; its TEI root `corresp` reads `REI193` — an upstream
  typo, preserved verbatim (canonical means canonical); ids come from the
  adapter's curated filename census, so the typo never reaches a urn.
- `alpheios2021-09-30T120552.85 0200.xml` — the stray Alpheios Alignment
  tool export, WHOLE (1.5 KB): NOT part of the TraCES 15 (no `TEILing`
  suffix, nameless morpho features, `https://`-scheme TEI namespace).
  Discover skips it by rule; the filename's SPACE is real upstream bytes.

Upstream quirks pinned by these fixtures: no `<licence>` anywhere in the
repo (license inherits from the official archive deposit — CC BY-NC-ND 4.0,
fdr.uni-hamburg.de record 707, DOI 10.25592/uhhfdm.707 → class `nc`, D46-b
owner-ratified 2026-07-26); empty teiHeader stubs (title-less); three files
use the nonstandard `https://www.tei-c.org/ns/1.0` TEI namespace, so the
parser matches local names, never the namespace URI.
