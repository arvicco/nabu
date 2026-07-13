# Date/place axis fixtures (P15-2)

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
