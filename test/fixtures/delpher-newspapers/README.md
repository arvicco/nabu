# delpher-newspapers fixture

Real members of the Delpher open newspaper archive (KB, Nationale
Bibliotheek van Nederland), retrieved 2026-11-13 from
`https://resolver.kb.nl/resolve?urn=DATA:kranten:kranten_pd_16xx.zip`
(→ `https://datasets.kb.nl/kranten/kranten_pd_16xx.zip`, 1,072,874,824 B,
Last-Modified 2017-01-16, md5 8a85d73a0ea97665614821ddb155a5e5 per the
archive page). The members were read out of the remote zip with HTTP
range requests (central directory, then each member's local entry) —
the 1 GB body was never downloaded whole. Every file is byte-identical
to the zip member except the two ALTO pages (trimmed, below); the 1618
and 1685 issues are also byte-identical to their copies in
`kranten_pd_voorbeeld.zip`, the archive's 5-issue sample.

License: the issue texts are public domain; the archive as a whole is
CC BY 4.0 ("Delpher open newspaper archive (1.0), Creative Commons
Attribution 4.0, The Hague, 2017").

## Layout (as it lands in canonical/delpher-newspapers/)

`kranten_pd_16xx/` — the zip's own tree:

| Issue folder | Paper | Date | Why |
|---|---|---|---|
| `1618/06/14/DDD_ddd_010500649_mpeg21/` | Courante uyt Italien, Duytslandt, &c. (Amsterdam) | 1618-06-14 | the archive's first issue; 1 page, 4 articles; hand-corrected OCR (DIDL OCRConfidencelevel 1.00; ALTO "Manual correction ocr", Meertens Instituut 2015) |
| `1631/09/19/KRANTEN_MMKB08_MMKB08_000213603_mpeg21/` | the same Courante | 1631-09-19 | the second folder-id scheme (MMKB08, a Metamorfoze batch; record id `MMKB08:000213603:mpeg21`, language "NL" upper-case); gothic-type uncorrected OCR (confidence 0.33) |
| `1685/12/22/DDD_ddd_011225333_mpeg21/` | Oprechte Haerlemsche courant (Haerlem) | 1685-12-22 | 2 pages, 8 articles (a0004 runs over both pages; a0008, the printer's colophon, is an advertentie whose articletext title is empty — the DIDL's title answers) |
| `1695/03/14/DDD_ddd_011005283_mpeg21/` | Gazette de Rotterdam | 1695-03-14 | a French-language gazette (dc:language fr), 2 pages, 4 articles |

Each issue folder holds its `didl.xml` and every `*_articletext.xml`.

## Delivery grains (the adapter's census)

- **issue** (folder: didl.xml + articletext files) — TAKEN as the document.
- **article** (`*_articletext.xml`, listed by the DIDL) — TAKEN as the passage.
- **page** (`*_alto.xml`) — REJECTED, skipped by rule. Specimens:
  `1618/…/DDD_010500649_001_alto.xml` and
  `1631/…/MMKB08_000213603_001_alto.xml`, trimmed to the header
  (Description/Styles/Tags) and the FIRST TextBlock, then the closing
  `</PrintSpace></Page></Layout></alto>` — structurally intact ALTO v3.
  The ALTO pages of the 1685 and 1695 issues are not pinned.
- **zip root furniture** — REJECTED, skipped by rule:
  `README_newspapers_pd_16xx.txt` and `LEESMIJ_kranten_pd_16xx.txt`
  (whole), `index_kranten_pd_16xx.tsv` trimmed to the four fixture
  issues' rows (the real file: 8,559 rows).

This README.md is the fixture's own furniture, not upstream's.

## Re-cut recipe

Read the zip's central directory by HTTP range (the last ~15 MB), then
range-fetch each wanted member's local header + compressed body and
inflate; or download the zip and `unzip` the listed paths. Trim each
pinned ALTO to its first `</TextBlock>`, keeping the closing tags.
