# Date/place axis fixtures (P15-2 + P16-3)

Trimmed-real HGV EpiDoc metadata records for the AxisBuilder extractor tests
(`test/store/axis_builder_test.rb`). Retrieved 2026-07-12 from the local
`canonical/papyri-ddbdp/HGV_meta_EpiDoc/` clone (idp.data), trimmed to the
teiHeader idno + history/origin that the extractor reads — structurally intact
EpiDoc, so the fixtures document actual upstream shapes.

Layout mirrors the canonical tree so `AxisBuilder.rebuild!(canonical_dir: …)`
finds them: `papyri-ddbdp/HGV_meta_EpiDoc/HGV1/<n>.xml`.

The five records cover the date-model shapes the fable review flagged:

| file | ddb-hybrid | shape | why |
|---|---|---|---|
| 56.xml   | bgu;3;994          | `when="-0113"` point       | BCE point, historical numbering (labelled "113 v.Chr.") |
| 9150.xml | bgu;2;402          | `notBefore/notAfter` range | CE range, `precision="low"` (591–602, spans 6th–7th c.) |
| 758.xml  | p.cair.zen;1;59108 | `notAfter` only            | open-ended interval (not_before NULL = −∞) |
| 610.xml  | sb;1;4471          | `<origDate>unbekannt`      | undated but placed (place-only row) |
| 997.xml  | p.cair.zen;3;59354 | two alternative `when`     | multi-origDate ENVELOPE (-244 … -243) |

The Slovene goo300k/IMP corpora carry only a CE year in the urn suffix
(`…:sigil-1584`), so their extractor is tested from catalog rows, no fixture
file needed.

## Part 2 (P16-3): ORACC catalogues + TOROT chronicle annals

Retrieved 2026-07-13 by trimming the local canonical snapshots (same
local-trim provenance as above; see manifest.yml for per-file detail).

`oracc/<project>[/<sub>]/catalogue.json` — real ORACC catalogue.json files
kept to a handful of verbatim members (top-level keys intact, bulky
`summaries` display HTML dropped). The members cover the censused
date shapes for `AxisBuilder::OraccDates`:

| file | member | shape |
|---|---|---|
| saao-saa01/saa01 | P224395 | regnal `Sargon2.000.00.00`, Nimrud + pleiades_id |
| saao-saa02/saa02 | P500551 | eponym `Esarhaddon.limu Nabu-belu-usur.02.16` |
| saao-saa02/saa02 | P336039 | unknown king `00.000.00.00` → period fallback |
| saao-saa02/saa02 | P240211 | regnal `Shamshi-Adad5.000.00.00` |
| rinap-rinap1/rinap1 | Q003414 | absolute BCE range `744-727` |
| riao | Q006693 | century phrase `9th-8th century` |
| riao | Q005837 | ca. range `ca. 1233-1197` |
| riao | Q003700 | mixed `668-ca. 631` |
| dcclt | P212382 | period `Old Babylonian`, Nippur + pleiades_id |
| dcclt | P230009 | period `uncertain` — unmapped, skipped + counted |

`torot/lav.xml` — the Primary Chronicle (Codex Laurentianus) trimmed to four
divs at ≤2 sentences each for `AxisBuilder::ChronicleAnnals`: `Introduction`
(non-annal, skipped + counted), `6360: Mikhail …` (AM point with prose
title), bare `6361`, and the AM range `6369–6370: The Varangians …`.
Annotation block and `<source>` header are intact, so the file stays
structurally real PROIEL 2.0 export XML.
