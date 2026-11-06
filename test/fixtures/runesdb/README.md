# RuneS-DB fixtures — RuneSDB.de inscription data (Zenodo 21788307)

Real upstream files extracted **2026-11-02** from the Zenodo deposit
"RunesDB.de inscription data" (record 21788307, v1.0.0, published
2026-08-01 — the latest version that day), artifact
`https://zenodo.org/records/21788307/files/runes_tei.zip` (9,807,753 B,
723 files, flat, no top directory). The Göttingen Academy of Sciences and
Humanities in Lower Saxony, long-term project "Runic writing in the
Germanic languages" (RuneS).

## Delivery grains (census of the whole zip, 2026-11-02)

The zip serves ONE file grain: the runic FIND, `runes_find-<id>.tei.xml`
(723 files). Inside a find: sides (`<div type="side" n="A"|"recto"|
"folio 4 recto"…>`, 874) → sequences (`<ab type="sequence">`, 1,812) →
glyphs (`<g>`, 20,180 including bind-rune components `<g type="ligature">`),
each glyph a graphemic record (transliteration, rune names, deep stroke
geometry). The adapter takes the find as the document and the sequence as
the passage.

- ACCEPTED: finds with at least one transliterated glyph (613 → 1,611
  passages; 11 sequences inside them carry no transliteration and mint no
  passage).
- REJECTED BY RULE: finds whose signs are recorded geometrically only, no
  glyph transliterated (110 — mostly South Germanic brooches). Specimen:
  `runes_find-166.tei.xml`. 613 + 110 = 723.
- Not in the zip: the per-find LIDO records
  (`https://www.runesdb.de/lido/<id>`) — a separate per-find surface,
  harvested since P160 into `lido/<id>.xml` (below).

## The LIDO layer (P160, `lido/`)

Real records fetched **2026-11-05** by direct GET of
`https://www.runesdb.de/lido/<id>` (LIDO v1.1, `application/xml`). One
grain: the find's record (object classification, title, inscription
transcription + translation, repository + workIDs, description,
measurements, a Production and a Finding event, record rights). An
unknown id answers HTTP 302 to the site (no record). Every GET restamps
`recordMetadataDate` with the serving time.

- `lido/1.xml` — Bügelfibel von Himlingøje (Sj 73): en+de translation
  "Harisō.", Production 210–310, found 1835 at Himlingøje with its point,
  the workID concordance Sj 73 / DR232 / KJ9 / DR 232.
- `lido/629.xml` — Stein von Hackness (OE-GB-30): translation "-"
  (none), Production 700–900, found "1848>F" at Hackness, repository
  location "None" with a point.
- `lido/200143.xml` — AM 623 4to, 12r: a manuscript — its Finding event
  names the holding library (never a findspot); translation "m" restates
  the rune (no sibling minted).
- Finds 720 and 9982 have NO record in the fixture tree on purpose: the
  unharvested (TEI-only) path.

Trim (all three, documented): the serving-timestamp
`<lido:recordInfoSet lido:type="…/lido00470">` (its recordMetadataDate)
removed — otherwise byte-intact. The 27-record census of 2026-11-05
(one per siglum family) behind the reader's rules: Production dates are
plain CE years everywhere, `0`/`0` on Kylver and Rö (the unknown
sentinel); Finding dates are discovery dates in free forms ("1840 ca.",
"1588-1654>F", "1857+1890", "-").

Added with the LIDO layer: `runes_find-1.tei.xml` — WHOLE (72,378 B),
from the same zip, the TEI of the Himlingøje translation specimen.

## Files

- `runes_find-1.tei.xml` — WHOLE (72,378 B; added P160, extracted
  2026-11-05 from the same v1.0.0 zip). Bügelfibel von Himlingøje (Sj 73),
  one sequence — the TEI beside the LIDO translation specimen `lido/1.xml`.
- `runes_find-200143.tei.xml` — WHOLE (12,461 B). AM 623 4to, 12r: one
  manuscript rune (runica manuscripta), `m`.
- `runes_find-629.tei.xml` — WHOLE (102,811 B). Stein von Hackness
  (OE-GB-30), Old English corpus: two sequences `?rmcd`, `[...]œn[...]g`
  — runological sigla in the transliteration, uncertain-glyph flags.
- `runes_find-720.tei.xml` — WHOLE (15,877 B). Kamm von Hogebeintum
  (PreOFris/EROFris-NL-19): a bind-rune whose parent glyph carries NO
  transliteration of its own, only its three `<g type="ligature">`
  components (`d`, `*`, `d`).
- `runes_find-9982.tei.xml` — DOCUMENTED TRIM (604,770 B → 37,706 B).
  AM 748 I b 4to, 8r–8v: a rune row encoded as one side per rune, so the
  side and sequence xml:ids REPEAT (`seq-recto-1` twice in the trim — an
  upstream validity error, kept). Trim: the first 481 lines byte-intact
  (header + the first three side divs: recto, verso, recto), then a
  synthetic `</body></text></TEI>` tail.
- `runes_find-166.tei.xml` — WHOLE (12,741 B). The rejected-grain
  specimen: Bügelfibel B von Trossingen (SG-118), every glyph without a transliteration.

## License

Zenodo record license field `cc-by-sa-4.0`; every file's availability
(censused on all 723): `<p xml:lang="en">CC BY-SA 4.0 -
Attribution-ShareAlike 4.0 International</p>` +
`<ref target="https://creativecommons.org/licenses/by-sa/4.0/">` (beside an
`<availability status="restricted">` attribute in every file — the
statement governs). → class `attribution`.

LIDO records (read 2026-11-05 on every fetched record): recordRights
`CC BY-SA 4.0 - Attribution-ShareAlike 4.0 International`
(`rdf:about="https://creativecommons.org/licenses/by-sa/4.0/"`), rights
holder the Göttingen Academy of Sciences and Humanities in Lower Saxony;
runesdb.de/en/data-sources: "The rights to the data are held by the
Göttingen Academy of Sciences and Humanities in Lower Saxony and are
subject to the CC-BY-SA 4.0 law" (with Kiel Runenprojekt, runer.ku.dk and
Rundata data "accessible under the Open Database License (ODbL)"). Same
class: `attribution`.
