# althurayya fixtures

Retrieved 2026-10-10 from the al-Ṯurayyā Gazetteer repository
(https://github.com/althurayya/althurayya.github.io, branch `master`,
HEAD f244e65ddf782baef08e410870c61c8096ff9f90 of 2026-09-22). The
original project datasets are CC BY 4.0 (`DATA-LICENSE.md`, added in that
same commit); the code is Apache-2.0 (`LICENSE`).

- `places_new_structure.geojson` — a trim of
  `master/places_new_structure.geojson` (the file the live map loads via
  `<link rel="points">` in `index.html`; 2,521 features upstream). Ten
  feature blocks kept **byte-verbatim** (line-sliced, only the trailing
  comma of the last kept block adjusted), the FeatureCollection head/tail
  untouched. The selection covers every case the derivation handles:
  - `QAHIRA_312E300N_S` twice: the upstream duplicate URI (a 2017
    maximromanov "metropoles" record + the Cornu "quarters" record) —
    the coalesce case;
  - `IRBIL_440E361N_S`: an English exonym (`Erbil`) in `common_other`,
    empty Arabic `search`;
  - `SARAQUSA_009W416N_R` / `_S`: the region/settlement twin, with
    `، `- and `, `-separated variant lists (سرقوسة، سرقوسطة; Saraqūsṭaŧ);
  - `SIFFIN_384E358N_O` (site), `NAHRDIJLA_436E346N_W` (water),
    `BAGHDAD_443E333N_S`, `MARJWA-ZAHR_509E330N_S` (hyphen in the id);
  - `ROUTPOINT0107_354E318N_O`: an anonymous `xroads` route junction
    (placeholder names) — the skipped class.
- `regions.json` — `master/regions.json`, whole and byte-verbatim (26
  region records, the parent display labels).
