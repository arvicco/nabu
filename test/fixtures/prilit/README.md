# PriLit fixtures (CLARIN.SI hdl 11356/1319, CC BY 4.0)

Retrieved 2026-09-04 from the deposit's `PriLit.TEI.zip` (the plain
TEI edition — the annotated `.ana` zip's silver layer is deliberately
not ingested v1). Four members, whole and untrimmed:

- `PriLit.xml` — the corpus-level `<teiCorpus>` header (6.7 KB): NOT
  a work; discover must skip it by root element.
- `Svetokriski_NaNovigaLejtaDan1696.xml` — the earliest-period work
  in the fixture set (Janez Svetokriški, 1696 sermon; 18 `<ab>`
  blocks, 54.8 KB).
- `Cigler_SrecaVNesreci1838_1840.xml` (144 blocks) and
  `Cigler_SrecaVNesreci1984.xml` (339 blocks) — TWO editions of the
  same work (Sreča v nesreči), the deposit's ready collation pair;
  note the segmentations differ across editions.

Structure the trio documents: bodies are PURE `<ab xml:id="Doc.N">`
text blocks (no inline markup censused); the print year lives in
sourceDesc/bibl[@type=printSource]/date (@when + @cert), the digital
source's URN:NBN in bibl[@type=digitalSource]; author carries a viaf:
ref; xml:lang="sl" throughout.
