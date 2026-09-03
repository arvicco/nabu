# DTA fixtures (Deutsches Textarchiv, BBAW)

Three real DTA-Basisformat (TEI/P5) texts, retrieved 2026-09-03 from
the per-book XML endpoint (`https://www.deutschestextarchiv.de/book/
download_xml/<id>`), chosen for period and genre spread across the
corpus (1473–1969; license CC BY-SA 4.0):

- `luther_elltern_1524.xml` — Luther, *Das Elltern die kinder zur Ehe
  nicht zwingen noch hyndern...* (1524). Gebrauchsliteratur /
  Flugschrift; early print with `<opener>`/`<salute>` and
  `<choice><abbr>/<expan>` abbreviation pairs (`den̄`/`denn`).
  Complete file, untrimmed (37 KB).
- `kant_aufklaerung_1784.xml` — Kant, *Beantwortung der Frage: Was ist
  Aufklärung?* (1784). Fachtext / Philosophie; journal article with
  blank front scan pages, a `place="foot"` authorial footnote,
  `<choice><sic>/<corr>` printing-error pairs, and 147 `¬<lb/>`
  line-break hyphenations. Complete file, untrimmed (48 KB).
- `fontane_stechlin_1899.xml` — Fontane, *Der Stechlin* (1899).
  Belletristik / Roman; TRIMMED to front matter (title pages), the
  first two chapters of the body, and the complete back matter
  (imprint/advertisement divs) — chapters 3+ removed, one `</div>`
  closing the chapter-group div reinstated; everything kept is
  byte-verbatim upstream. Carries `<pb n="...">` printed page
  numbers, `<fw>` running heads, `<cb>`, and a `type="halftitle"`
  title page. (Original 1.17 MB → 66 KB.)

Structural quirks these document (the reason for the trio): the `¬` +
`<lb/>` hyphenation convention, sic/corr and abbr/expan choice pairs
(the printed reading is the sic/abbr half), facs-only vs printed-`@n`
page breaks, blank scan pages (pb with no interleaved text), and the
duplicated titleStmt/date between fileDesc and sourceDesc/biblFull
(the print year lives ONLY under sourceDesc; fileDesc's
publicationStmt date is the digital edition's timestamp).
