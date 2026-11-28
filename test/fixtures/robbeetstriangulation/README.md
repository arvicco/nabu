# Robbeets et al. 2021 Transeurasian cognate sets (lexibank/robbeetstriangulation v0.3) — fixture

Retrieved 2026-11-27 from the Zenodo versioned record of the GitHub release v0.3: https://doi.org/10.5281/zenodo.14614177 — file `lexibank/robbeetstriangulation-v0.3.zip` (7192543 B, md5 `9f70faffe6f34ffec125fce4fb707e0a` as Zenodo publishes it; sha256 `647c4f52f32edd5c593030fc18cf00b1b4a32e80e361837ce8856a5388a47193`, the adapter's hard pin). The release tag v0.3 is commit `5f59f1522ed89b2d8fd557ca92c10adf91886cd7`, the default branch's head on the retrieval date (https://github.com/lexibank/robbeetstriangulation, last pushed 2025-01-08). The repository was formerly `lexibank/robbeetsaltaic`: GitHub answers that name with this one, and the release's `setup.py` still names the package `lexibank_robbeetsaltaic`, while `metadata.json` (`"id": "robbeetstriangulation"`) and the CLDF bundle carry the current name. The zip unpacks under `lexibank-robbeetstriangulation-5f59f15/`; every fixture file below is a byte-verbatim excerpt of that tree (records kept whole, record SET trimmed).

## Delivery grains

- `cldf/` — ACCEPTED: the CLDF Wordlist (forms, languages, parameters, cognates; no cognatesets/borrowings tables). ONE document per dataset.
- `raw/` — REJECTED: upstream's source material — the supplementary-information spreadsheet (`16_Eurasia3angle_synthesis_SI 1_BV 254.xls` and its csv export), the BEAST model files (`beast/`), the geodata (`tea3geo.csv`/`.xml`) and `sources.bib`; specimen `raw/sources.bib`, whole.
- `plots/` — REJECTED: three PDF evaluation plots of automatic cognate detection against the expert judgments (B-cubed precision / recall / F-score); specimen `plots/bcubedfscore.pdf`, whole.
- `etc/`, the build script, the python packaging and the `.md` documentation are machinery.

## Kept cognate sets

- `3152` — 'with' — Codex Cumanicus birla + Old Turkic birle (root *birle)
- `529` — 'child (kin term)' — Codex Cumanicus ogul, Karaim ulan, Old Turkic oglan (root *oglan)
- `60` — '2SG pronoun' — (Late) Middle Korean ne + Old Japanese "na ~ nare" (root *ne); upstream tags the Korean row ISO `kor`, Glottocode late1258
- `24` — 'go' — Baoan (Glottocode only), the two Middle Mongolian witnesses (Muqaddimat al-adab "ot- ~ od-", Secret History ot-; no ISO, no Glottocode) and Oirat (neither code) (root *od-)

## Recipe

For the kept set ids: cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments name; languages.csv / parameters.csv rows those forms name. Rows keep upstream's file order and raw bytes.

## Upstream count reconciliation

README: 101 varieties (81 Glottocodes), 253 concepts, 26,224 lexemes; "26,224 cognates in 3,173 cognate sets (812 singletons)". Full-scale dry parse (2026-11-27): 3,173 entries, 26,220 reflex rows (0 loan-flagged, 0 doubtful judgments; 5,451 rows display-only), 0 forms outside the CognateTable. accepted 3,173 = upstream's 3,173; the four-row reflex residue is upstream's own "?" cells (judged forms with no form recorded), which mint nothing by the family's placeholder rule. Old Turkic 261 forms, Codex Cumanicus 228, Middle Mongolian 210 + 228, Old Japanese 258, Late Middle Korean 267, Jurchen 191, Manchu 280.

## License

CC BY 4.0 — README "This dataset is licensed under a CC-BY-4.0 license", the LICENSE file (Attribution 4.0 International legal code), `metadata.json` (`"license": "CC-BY-4.0"`) and cldf-metadata.json `dc:license` (https://creativecommons.org/licenses/by/4.0/) agree, as does the Zenodo record (cc-by-4.0). Cite: Robbeets, M., Bouckaert, R., Conte, M. et al. Triangulation supports agricultural spread of the Transeurasian languages. Nature 599, 616–621 (2021). https://doi.org/10.1038/s41586-021-04108-8
