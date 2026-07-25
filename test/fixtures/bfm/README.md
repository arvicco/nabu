# BFM fixtures — Base de français médiéval, corpus BFM2022 (TEI P5)

Three whole real TEI XML documents plus one documented trim, snapshotted
**2026-07-25** from the NAKALA repository's sha1-addressed file API
(`https://api.nakala.fr/data/<data-DOI>/<file-sha1>`; collection
`https://nakala.fr/collection/10.34847/nkl.93ee3ts1`, BFM2022, published
2022-11-07, 219 texts). The whole files are upstream byte-for-byte, so the
fixtures document BFM's real encoding quirks.

Chosen to cover the four body shapes the `bfm-tei` parser must handle:

- `xml/nabaret.xml` (whole, 10,055 B, data 10.34847/nkl.03afsboc) — plain
  (untokenized) verse: one unnumbered div, one `<ab type="gv">` verse group
  whose lines are `<lb n="1"/>…<lb n="48"/>` MILESTONES (the reason
  croala-tei could not be composed — it folds `<lb>` to a space), `<q>`
  direct speech spanning lines, French-spaced punctuation kept verbatim.
  Anglo-Norman lai, composed "entre 1178 et 1230" (`<date type="compo"
  when="1209-01-01" notBefore="1178-01-01" notAfter="1230-01-01">` — the
  timeline envelope every BFM text carries). Etalab-licensed file.
- `xml/RegleSBenCotton.xml` (whole, 10,587 B, data 10.34847/nkl.879d4s17) —
  plain prose at block grain: `<div type="chapter" n="49">`/`<div n="48">`
  each holding one `<p>` (the div @n IS the citation component: d49.p1),
  `<milestone unit="folio">` folding to a space. Etalab-licensed file.
- `xml/strasbBfm.xml` (whole, 13,304 B, data 10.34847/nkl.f57b23q4) — the
  Serments de Strasbourg (842, the oldest French text): `<w>`-tokenized
  prose WITHOUT lemmas, exercising the token-boundary reconstruction
  (elision `d'` + `ist` → `d'ist`; punctuation tokens attach left) and the
  no-lemmas → no-tokens-annotation rule. One of the corpus's 8 files whose
  NAKALA record and in-file `<licence target>` carry CC BY-NC-SA 3.0 FR for
  the APPARAT CRITIQUE layer, with the reading text + digital supplements
  explicitly "libres de droit" (the D45-c evidence, verbatim in the file's
  `<ab type="availability_file">`).
- `xml/AlexisRaM.xml` (TRIMMED from 971,518 B to ~36 KB, data
  10.34847/nkl.7bbe37x6) — lemmatized verse: `<w type="ADJqua" lemma="bon">`
  morphosyntax (the fro lemma lane, `lemma_tier: silver`), `<lb ed="norm"
  n>` continuous verse numbering across strophes, inline editorial `<note
  resp="#eds">` apparatus BETWEEN word tokens (the CC BY-NC-SA layer the
  parser must drop), `<choice><sic>m</sic><corr>nn</corr></choice>` inside a
  word ("Donnent"), `<milestone unit="lb-facs">` facsimile lines. Trim: the
  full teiHeader + `<text><body>` opening + strophes 1, 2 and 10 (`<ab
  n="1|2|10" rend="strophe">`, lines 1–10 and 46–50) + closing tags —
  structurally intact, upstream bytes untouched within the kept ranges.
  Strophe 10 is kept for the in-word `<choice>` sic/corr pair.

License evidence (P45-4, D45-c): every data record carries dcterms:rights
"Texte : Domaine public" and "Suppléments numériques (balisage XML-TEI,
métadonnées, annotations linguistiques) : Sous licence Etalab" (Licence
Ouverte / Open Licence 2.0 — attribution required, commercial reuse
allowed); the collection description flags exactly 8 files (AlexisRaM,
ChaceOisiiT, eulaliBfm, ImMondePrK, PsArundP, qgraal_cm, QJoyesKa,
strasbBfm) whose apparat critique is "sous licence CC BY-NC-SA 3.0
https://creativecommons.org/licenses/by-nc-sa/3.0/fr/". The parser excludes
that layer from the reading stream, so the source registers class
`attribution`.

NAKALA language metadata reads `fro` on all 219 datas (censused 2026-07-25;
no frm split upstream), matching each file's `<language ident="fro">`.
