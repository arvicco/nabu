# EDH (Epigraphic Database Heidelberg) fixtures — P17-2 Phase B

Real EpiDoc records + trimmed CSV siblings for the `edh` adapter
(`Nabu::Adapters::Edh` / `EdhEpidocParser`), per the owner-approved fixture
plan in `docs/edh-survey.md` §5. Retrieved **2026-07-13** from the EDH Open
Data Repository (`https://edh.ub.uni-heidelberg.de/data/download/`): the two
EpiDoc dump zips were downloaded whole and the three records copied out
**byte-identical**; the two corpus-wide CSVs were trimmed to the header plus
exactly these records' rows (rows byte-identical, extracted as whole physical
lines).

- Layout mirrors the canonical workdir the adapter fetches into:
  `epidoc/<zip HD range>/HDnnnnnn.xml` (the zips are FLAT — no top-level
  directory inside), `text/edh_data_text.csv`, `pers/edh_data_pers.csv`.

## EpiDoc records (whole, byte-identical to the zip contents)

| Path (under `epidoc/`) | From zip | Quirks it preserves |
|---|---|---|
| `HD000001-HD010000/HD000001.xml` | `edhEpidocDump_HD000001-HD010000.zip` | Marble tabula epitaph (Cumae, 71–130 CE): `expan/abbr/ex` abbreviation density ("D M" → "Dis Manibus"), **THREE structured persons** in the pers CSV (Nonia Optata, C. Iulius Artemo, C. Iulius Optatus — filiation `P.f.`/`C.f.`, kinship codes), genre `titsep`→epitaph, pleiades ancient-place ref. Exercises the persons annotation join + the genre facet. |
| `HD000001-HD010000/HD000082.xml` | `edhEpidocDump_HD000001-HD010000.zip` | The Homer herm (Roma, 171–230 CE): **bilingual** Latin/Greek `textpart` divs with **per-textpart line-number restarts** (two `lb n="1"`), `del rend="erasure"` (the damnatio of Crassus) **nesting an `expan`** — exercises the ⟦…⟧ keep policy, per-passage language (CSV `nl_text` = `GL` while `langUsage` lies `en/de/lat`), textpart urn segments. |
| `HD080001-HD082828/HD080825.xml` | `edhEpidocDump_HD080001-HD082828.zip` | Votive altar (Germania inferior, 151–250 CE): `expan` + `supplied reason="lost"` + `gap` + **`lb n="0"`** (lost line before the text — extracts gap-marker-only and is skipped as non-citable), EAGLE type/material/objectType LOD refs, the staging-host `<idno type="URI">` quirk (`…/test/edh/…` — why urns mint from HD numbers only). |

## CSVs (header + these records' rows, rows byte-identical)

- `text/edh_data_text.csv` — 75 columns; carries what the EpiDoc LACKS:
  the per-record language `nl_text` (HD000082 = `GL`; the `langUsage` header
  is boilerplate — the trap in `docs/edh-survey.md` §1), the diplomatic
  majuscule `btext`, `tm_nr` (Trismegistos), findspot coordinates, the
  `i_gattung` genre code (raw, `?`-certainty variants), dating
  `dat_jahr_a`/`dat_jahr_e` (signed years, no year 0).
- `pers/edh_data_pers.csv` — 23 columns, one row per attested person:
  the three HD000001 persons with filiation + kinship (`verwandt` BF/AE/G),
  HD000082's Crassus (status code, Leiden brackets inside `name`), HD080825's
  fragmentary `[---](?) Severu[s]` (praenomen/nomen `0?` placeholders).

## License (recorded exactly)

Per-file `<licence>` element, identical in all three records:

> This file is licensed under the Creative Commons Attribution-ShareAlike
> 4.0 license.

(`target="http://creativecommons.org/licenses/by-sa/4.0/"`), agreeing with
the `/data` page's blanket grant — `license_class: attribution`.

## Retrieval record

- Zips: `https://edh.ub.uni-heidelberg.de/data/download/edhEpidocDump_HD000001-HD010000.zip`
  and `…HD080001-HD082828.zip`, Last-Modified 2021-12-16 (frozen corpus;
  all nine zips HEAD-verified 200 on 2026-07-13).
- CSVs: `…/edh_data_text.csv` (Last-Modified 2025-07-31 — a regeneration,
  same 82,450 records) and `…/edh_data_pers.csv` (2021-12-09).
- The `titadnun` genre code (the survey's one unresolved EAGLE mapping,
  3 records corpus-wide) resolves to **"adnuntiatio"** — verified against
  the live record page of HD014570, 2026-07-13. No code-side mapping table
  is needed: the parser reads each record's own EAGLE `<term>`.
