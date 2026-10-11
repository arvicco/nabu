# ticha fixtures

Real files from github.com/HCDigitalScholarship/ticha-xml-tei (branch
`master`, HEAD `2d6af302f849257bfdf9f332900ec583e8deaec9`, 2022-03-10),
retrieved 2026-10-11 by `git clone --depth 1`. License: the repository's
`license.txt` (copied here verbatim) — CC BY-SA 4.0.

## Whole files (byte-identical to upstream)

| path | why |
|---|---|
| `Te744/Te744.xml` | the 1744 San Sebastián Teitipac testament in Zapotec — the unmarked-Zapotec default, `<note>`/`<add>` marginalia, the prolog comment that names the document |
| `Te744T/Te744T.xml` | its Spanish translation (the work-directory encoding: `<br/>`, Latin `<foreign>`, `<abbr>/<expan>`, text before the first `<pb/>`) |
| `manuscripts/encoded/Te744T.xml` | the older encoding of the same translation — superseded by the work directory's file (skip rule) |
| `manuscripts/encoded/Al642T.xml` | a translation with two unclosed `<br>` and a truncated end (no `</text></TEI>`) |
| `manuscripts/encoded/Al698T.xml` | a translation whose every `<choice>` is followed by a stray `</head>` |
| `manuscripts/encoded/Fr720T.xml` | unclosed `<br>` throughout; upstream numbers its third page `n="2"` again |
| `manuscripts/encoded/AGEO_Testaments_AGEO42.xml` | an AGEO testament: teiHeader (title, `spa` langUsage), facs-only `<pb/>` breaks |
| `manuscripts/encoded/Tl675T_example doc.xml` | an encoding example (skip rule) |
| `schema/TEISchema_Ticha.xml` | the TEI customization (skip rule) |
| `places.json` | the repo's town gazetteer (names + coordinates) |
| `license.txt` | the repository license, verbatim |

## Trims

- `cordova-arte/cordova-arte.xml` — a STRUCTURAL trim of
  `cordova-arte/cordova-arte.xml` (2,405,203 B → 40,448 B): source lines
  1–350 (the teiHeader, the title page n=4, the Licencia n=6 with its
  catchword `<fw>`), then lines 1956–2245 (folios 1v and 2r, the first
  `xml:lang="cvz"` forms) with their open ancestors re-opened
  (`<body><div xml:id="cordova-arte2"><div xml:id="cordova-arte2.1">`, as
  in the file) and every open element closed at the cut. Well-formed, as
  the original is.
- `levanto-cathecismo/levanto-cathecismo.xml` — a structural trim of
  `levanto-cathecismo/levanto-cathecismo.xml` (258,975 B → 10,188 B):
  source lines 1–59 (the `xml:lang="esp"` front-matter div, the title
  page n=4) then lines 3264–3438 (page 33, the catechism's Spanish and
  Zapotec columns, `<cb/>`), ancestors re-opened and closed as above.
- `aguero-miscelaneo/aguero-miscelaneo.xml` — a VERBATIM line-range cut
  of `aguero-miscelaneo/aguero-miscelaneo.xml` (1,377,045 B → 18,097 B),
  NOT re-balanced (the original is not well-formed and its defects are
  the point): source lines 1–73 (cover pages, the title page n=4),
  21916–21990 (page 345: an `<add>` closed by `</note>`), 23155–23294
  (pages 362–363: a start tag broken mid-attribute, `<add place="above"
  M[?] …`, and a `choice>` that lost its `<`), 25494–25638 (pages
  394–395: a bare `<note>` where `</note>` belongs, a `<reg>` closed as
  `/reg>`), and 28866–28867 (the closing `</text></TEI>`).
