# EDH ↔ EDR same-artifact fixtures

Three physical inscriptions each edited by BOTH the Epigraphic Database
Heidelberg (EDH) and the Epigraphic Database Roma (EDR), joined on the
Trismegistos text number both upstreams record (EDH: `edh_data_text.csv`
column `tm_nr`; EDR: `<idno type="TM">`). They drive
`test/edh_edr_same_artifact_test.rb` (`Nabu::EdhEdrSameArtifact`).

Layout mirrors the canonical root: `edh/` and `edr/` are each a workdir the
adapters discover as-is, so the test loads both through the real adapters
and builds the timeline over this directory.

| TM | EDH record | EDR record | why |
| --- | --- | --- | --- |
| 248008 | `edh/epidoc/HD000001-HD010000/HD002664.xml` (Volaterrae, "Caecina", 1–200) | `edr/075001-100000/aEDR078741.xml` ("Gai Caecinae […]", 1–100) | the hint splits: text and date → EDR, findspot (Pleiades id) → EDH |
| 251503 | `…/HD008415.xml` (Tarracina, "Artemo", undated) | `…/aEDR080335.xml` (five lacunose lines, 1–50) | an undated witness loses the date field |
| 249515 | `…/HD003323.xml` (Pompeii, "Vicimus", 1–79) | `…/aEDR092812.xml` ("Vicimus", 1–79) | full ties fall to EDH; the findspot length rule |

Provenance (all copied 2026-10-20 from the box's canonical trees):

- EDH XML: byte-identical from the `edhEpidocDump_HD000001-HD010000.zip`
  extraction (`https://edh.ub.uni-heidelberg.de/data/download/`, frozen
  2021-12-16). CSVs: header + exactly these records' rows (whole physical
  lines, byte-identical) from `edh_data_text.csv` (3 rows) and
  `edh_data_pers.csv` (1 row — the other two records carry no persons).
  License CC BY-SA 4.0.
- EDR XML: byte-identical from `EDR.zip` (Zenodo record 18468635, v12,
  sha256 `61be8164…`), range dir `075001-100000`. Deposit license CC BY 4.0.

Delivery grains: unchanged from the `edh` and `edr` fixture READMEs — one
record file per inscription is the document on both sides; nothing here is
a new grain.
