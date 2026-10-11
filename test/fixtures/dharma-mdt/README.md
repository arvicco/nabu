# dharma-mdt fixtures

Trimmed REAL excerpts of the four DHARMA text-metadata CSVs in
github.com/erc-dharma/mdt-texts (`csv/`), commit
e445bb506666b046a0dc9b8e8e68a1a0e7dc1a40 (2023-10-17), retrieved
2026-10-11 (shallow clone of the default branch).

License: the repo's LICENCE.txt is CC BY 4.0; every data row declares
"Distribution rights of the metadata" = CC0 (all 828 rows, census
2026-10-11) — the row grant is recorded verbatim per document.

Upstream shape these excerpts keep intact: rows 1-2 are field-GROUP
banners, row 3 is the HEADER ("0,Fields,Identifier of the resource,…",
63 columns — "Alternative designation" appears twice, the first and
last columns are a "0" counter), row 4 is the "Description of the
fields" row, data from row 5. Cells escape commas as the literal token
`COMMA`; multi-valued cells separate with `$`, zones with `§`. Line
endings CRLF, no BOM.

Records kept (each a whole, byte-identical upstream line; the four
banner/header/description rows are kept verbatim in every file):

- `DHARMA_mdt_Telugu_v01.csv` — INSTelugu00001 (Date CE 849, evidence
  reign, COMMA-escaped bibliography), INSTelugu00002 (Date range CE
  849-891, certainty low), INSTelugu00004 (undated), INSTelugu00023
  (a RANGE written in the Date CE column, "625-675").
- `DHARMA_mdt_Pallava_v01.csv` — INSPallava00001, INSPallava00002 (the
  sparse Pallava shape: designation + text type only), INSPallava00155
  (the corpus's one dated row, 850-900, Sanskrit + Tamil).
- `DHARMA_mdt_DaksinaKosala_v01.csv` — INSDaksinaKosala00001/00002 and
  INSDaksinaKosala00047, a PLACEHOLDER row (ids + rights only).
- `DHARMA_mdt_Somavamsin_v01.csv` — INSSomavamsin00001/00002 and
  INSSomavamsin00049, a placeholder row.

Recipe: `git clone --depth 1 https://github.com/erc-dharma/mdt-texts`,
then keep CSV records 1-4 plus the records whose "Identifier of the
text" (column 14) is one of the ids above, raw lines untouched.
