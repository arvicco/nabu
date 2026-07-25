# openMGH fixtures — Monumenta Germaniae Historica TEI-XML (P45-2)

Three real openMGH volumes, snapshotted **2026-07-25** from
`https://data.mgh.de/openmgh/<bsbid>.zip` (each zip carries exactly one
`<bsbid>.xml`; the fixture layout `<bsbid>/<bsbid>.xml` mirrors the
per-volume unpack the adapter's fetch produces). The volume inventory is
the human index page
`https://www.mgh.de/en/digital-mgh/openmgh/mgh-editions-in-openmgh`
(153 volumes on the retrieval date; the id space is sparse — an
unlisted bsb id 404s, so enumeration comes from the index, never a
sweep).

Chosen to cover the corpus's two dialects and both languages:

- `bsb00000728/bsb00000728.xml` — **whole** (165 KB). Einhardi Vita
  Karoli Magni (MGH SS rer. Germ. 25), ed. Holder-Egger 1911. The
  Scriptores dialect: `<TEI>` root, body `<div type="volume">` →
  `<div type="work" n="…">` (4 works) → optional unnumbered
  `<div type="part">` → one `<ab>` of raw text segmented by `<pb>`/
  `<lb>` milestones. Exercises: hyphenation `<w>` pairs joined across
  a line break (`descrip-`/`sisse` → `descripsisse`) AND across a
  page break (`dili-`/`gitur` → `diligitur`, page XXVIII→XXIX — the
  deferred page-flush case), a work with zero `<pb>` of its own
  (Gerwardi versus rides the open page XXIX), roman AND arabic page
  numbers, `<cb>`/`<anchor>` column-break pairs, `<hi>` rendering.
  55 work-page passages. Latin.
- `bsb00000776/bsb00000776.xml` — **whole** (146 KB). Der Trierer
  Silvester (MGH Dt. Chron. 1,2). Same Scriptores dialect, but the
  text is Middle High German (`gmh` — the Dt. Chron. series; the TEI
  carries NO xml:lang anywhere, so language is the adapter's
  per-series table). Parenthesized page numbers (`n="(46)"` →
  citation token `p46`), combining marks (`Nv̊`, `gůten` — NFC-stable),
  manuscript-column `|` marks kept verbatim. 34 work-page passages.
- `bsb00000361/bsb00000361.xml` — **trimmed** (19 KB of 595 KB). Die
  Urkunden der burgundischen Rudolfinger (MGH DD Rudolf.), ed.
  Schieffer 1977. The Diplomata dialect: `<teiCorpus>` root, corpus
  teiHeader (license + idnos), then one inner `<TEI>` per charter,
  each with its own header — `<idno type="charternum">`, the
  charter's **medieval date verbatim** (`878 März 25.`) in
  `sourceDesc/bibl/date` — and a `<div type="tenor">` body of the
  same pb/lb/w stream. Trim: the corpus header + inner TEI blocks
  1–3 (charters 1, 2, 3) + inner TEI block 13 (charter 13, a
  deperditum whose tenor has NO `<ab>` — pins the empty-charter
  skip) spliced verbatim in file order, `</teiCorpus>` appended;
  no line inside a kept block was altered. Re-apply: download the
  zip, keep the prologue before the first `<TEI>`, inner `<TEI>`
  blocks 1, 2, 3 and 13, close the root.

License, verbatim from every volume's `<availability><licence>`:
"Distributed under the Creative Commons Attribution 4.0 International
(CC BY 4.0) license." … "We do not claim any rights on the text itself
which is believed to be in the public domain." … "please indicate the
source of the file by mentioning the Monumenta Germaniae Historica
(MGH) and the Bavarian State Library, Munich (BSB)." The openMGH page
(www.mgh.de/en/digital-mgh/openmgh, read 2026-07-25): "The resources
are provided under the licence of Creative Commons Attribution 4.0
International (CC BY 4.0). … The edited medieval texts themselves are
free from copyright."
