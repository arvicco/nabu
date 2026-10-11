# KDSP fixtures (CLARIN.SI hdl 11356/1823, CC BY 4.0)

Retrieved 2026-10-11 from the deposit's `KDSP.TEI.zip`
(https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1823/KDSP.TEI.zip,
28,992,579 bytes, Last-Modified 2025-03-18) — the plain TEI edition;
the `.ana` (CLASSLA silver), txt and vert zips are not ingested.

Whole, verbatim from the zip:

- `KDSP.xml` — the corpus-level `<teiCorpus>` file: the six textClass
  taxonomies and the `listPerson` personography (78 authors: sex,
  birth, death, occupation) that the adapter joins by the work's
  `author/@corresp`; the works are `xi:include`d. NOT a work —
  discover skips it by name pattern and root element.
- `00README.txt` — the deposit's own readme.

Trimmed (header whole; body cut to its first blocks in document order,
divs left empty by the cut removed):

- `KDSP001.xml` — Cigler, *Sreča v nesreči* (1836), digital source
  ELTeC; the corpus's oldest text and the PriLit overlap witness
  (prilit holds seven editions of the same work). First 8 head/p blocks.
- `KDSP003.xml` — Cigler, *Deteljica* (1863), digital source Wikivir;
  overlaps both prilit and sl-wikisource; carries a textSubType
  (poučno_vzgojna). First 6 blocks.
- `KDSP010.xml` — Podmilšak, *Žalost in veselje* (1870), ELTeC; the first
  2 blocks plus the 2 blocks either side of the corpus's
  `<milestone unit="asterisk"/>` section break (with its div's head) —
  pins that a milestone mints nothing.
- `KDSP020.xml` — Holc, *Idealist* (1876), digital source dLib, subtype
  v_pismih; carries `<lg>/<l>` verse inside prose. First 9 blocks.
- `KDSP-meta.tsv` — the deposit's metadata table cut to its header and
  these four rows (note upstream's header names 16 columns over
  17-field rows: the period slot column is unnamed — the adapter reads
  the TEI headers, never this table).

Recipe (re-cut from a fresh `canonical/kdsp/`): keep each work's
teiHeader whole, keep the first N `head|p|lg` descendants of `<body>`
(plus the milestone window for KDSP010), drop divs left without blocks.
