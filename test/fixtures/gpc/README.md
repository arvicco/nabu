# GPC fixtures (Geiriadur Prifysgol Cymru open subset, CC BY 4.0)

`gpc_sample.xlsx` — TRIMMED-REAL cut (2026-09-11) of the
`2020-09-03_GPC_Agored_UTF8.xlsx` subset the GPC editor supplied by
email under CC BY 4.0 (grant 2026-09-04; conditions: no HTML
scraping/republication, link users to GPC Online): the original
workbook members verbatim EXCEPT `xl/worksheets/sheet1.xml` trimmed to
the header row + the first SIX real data rows + the aberth row (gpc122248 — the '@' sense-gloss and '_' plural separators) (cells byte-verbatim,
including the two "a" homographs and a row with variants "ai_y"),
`xl/sharedStrings.xml` rebuilt to only the strings those rows
reference with `<v>` indices remapped accordingly, and `calcChain.xml`
dropped (it indexes rows the trim removed). Structure — shared-string
cells (`t="s"`), the header bilingual labels, the gpc.html?gpcNNNNNN
plain-URL id carrier in column C — is the real file's.

Documents: headword (A), plain entry URL with the stable gpc id (C),
underscore-separated variants (D), Welsh POS abbreviations (E),
plural forms (F), the English first-sense opening with its own
underscore separators (G), and column B present-but-empty (the
"active link" formula column).
