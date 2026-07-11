# goo300k fixtures — reference corpus of historical Slovene (gold)

Trimmed real slices of the goo300k v1.2 TEI P5 distribution (CLARIN.SI,
Jožef Stefan Institute; Erjavec). Extracted **2026-07-11** from the single
zip the deposit serves (no raw per-file URLs exist):

    https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1025/goo300k-tei.zip
    (handle: http://hdl.handle.net/11356/1025 — auth-free DSpace bitstream)

Trimming = whole pages/surfaces/blocks removed; every retained line is
byte-identical to upstream (closing tags re-added where a file was cut
mid-tree).

## License chain (verified 2026-07-11)

- Deposit page verbatim: "Creative Commons - Attribution 4.0 International
  (CC BY 4.0)"; the record is marked publicly available (no auth).
- Bundle `00README.txt` verbatim: "distributed under the Creative Commons
  Attribution (CC BY 4.0) licence".
- Citation request (README): Tomaž Erjavec. 2015. The IMP historical
  Slovene language resources. Language Resources and Evaluation,
  doi:10.1007/s10579-015-9294-7.

→ CC BY 4.0 → `license_class: attribution`. Attribution: goo300k reference
corpus of historical Slovene, Jožef Stefan Institute / CLARIN.SI.

## Files

| fixture | trimmed to | exercises |
|---|---|---|
| `goo300k-1584-ZRC_00001.xml` | header whole; facsimile cut to surfaces 001–002; body cut to the first TWO `<xi:include>` pages | the corpus's earliest text (Dalmatin, *Biblia*, 1584 — Early Modern Slovene in Bohorič orthography); multi-page xi:include layout |
| `pages/goo168-ZRC_00001-1584.pb.001_Biblia.xml` | `ab.1`–`ab.2` (+ re-added `</div>`) | `<ab type="head">` and `<ab type="p">` blocks; `<choice><orig>/<reg>` token pairs (ſ long s in orig); bare `<w>` tokens; gold `lemma` + `ana` MSDs; the archaic-vocabulary `<desc><gloss>` (joger → "apostol, učenec" [sskj]); sentence `part="I"` |
| `pages/goo168-ZRC_00001-1584.pb.002_Biblia.xml` | `ab.10` only (+ re-added `</div>`) | document-global ab numbering across pages; `<ab part="F">` — a block continuing from the previous page keeps its own id (two passages, never merged) |
| `goo300k-1695-ZRC_00002.xml` | header whole; facsimile cut to surface 001; body cut to the first `<xi:include>` | second document (Janez Svetokriški, *Sacrum promptuarium*, 1695); single-page layout |
| `pages/goo168-ZRC_00002-1695.pb.001_Sacrum_promptuarium.xml` | `ab.1`–`ab.2` (+ re-added `</div>`) | consecutive `type="head"` blocks; `sl-bohoric` xml:lang |

## Format notes (upstream reality, do not "fix")

- TEI P5 in the corpus's own IMP schema (`tei_imp.rng`), NOT EpiDoc/CTS.
- One root file per text: `goo300k-<year>-<SIGIL>.xml` = teiHeader +
  `<facsimile>` (page images on nl.ijs.si) + `<text><body>` of
  `<xi:include href="pages/…">` — the word tokens live in the per-page
  files under `pages/`, one `<div type="pb">` per printed page.
- `goo168-` in xml:ids is a corpus-wide upstream prefix (all documents),
  NOT a document id; document identity is `<SIGIL>-<year>` (ZRC_00001-1584).
- Token layer: historical spelling that differs from modern Slovene is
  `<choice><orig><w>ſvoje</w></orig><reg><w lemma="svoj" ana="#P">svoje</w>
  </reg></choice>`; spelling that already matches is a bare
  `<w lemma="on" ana="#P">on</w>`. `<c>` holds inter-token whitespace,
  `<pc>` punctuation. `ana` is a `#`-prefixed MULTEXT-East-style MSD ref
  (IMP morphosyntactic specification, nl.ijs.si/imp/msd). Archaic words
  carry `<desc><gloss>…</gloss><bibl>[sskj]</bibl></desc>` inside `<reg>`.
- Annotation is GOLD: "fully manualy validated" (README verbatim, sic).
- `<ab>` blocks are numbered document-globally across pages; a paragraph
  split by a page break is two `<ab>` elements (`part="I"`/`part="F"`)
  with distinct ids.
- Corpus: 89 texts / 293,919 words / 1,100 pages, 1584–1899.
