# Savelyev & Robbeets 2020 Turkic cognate sets (lexibank/savelyevturkic v2.1) — fixture

Retrieved 2026-11-27 from the Zenodo versioned record of the GitHub release v2.1: https://doi.org/10.5281/zenodo.13163242 — file `lexibank/savelyevturkic-v2.1.zip` (446950 B, md5 `04c65dbbd584d6c09c0c6533b384a4db` as Zenodo publishes it; sha256 `2c40fe6d59db3acbd452756671b993569ac4090b2d380f209e10190cdaf6a440`, the adapter's hard pin). The release tag v2.1 is commit `4a540590580f0981d1c5679668cd08578f856de2`, the default branch's head on the retrieval date (https://github.com/lexibank/savelyevturkic, last pushed 2024-08-02). The zip unpacks under `lexibank-savelyevturkic-4a54059/`; every fixture file below is a byte-verbatim excerpt of that tree (records kept whole, record SET trimmed).

## Delivery grains

- `cldf/` — ACCEPTED: the CLDF Wordlist (forms, languages, parameters, cognates; no cognatesets/borrowings tables). ONE document per dataset.
- `raw/` — REJECTED: upstream's pre-CLDF source material (`turkic_alignment.tsv`, the EDICTOR alignment table the lexibank script converts, and `sources.bib`); specimen `raw/README.md`, whole.
- `turkic.nex` — REJECTED: the NEXUS binary cognate-character matrix derived from the same judgments for the phylogenetic study (top-level file, 38 KB); pinned whole.
- `etc/`, the build script, `test.py`, the python packaging and the `.md` documentation are machinery.

## Kept cognate sets

- `896` — 'with' — Codex Cumanicus birla + Old Turkic birle (root birle)
- `138` — 'child (kin term)' — Codex Cumanicus ogul, Old Turkic oglan, Karaim ulan (root *oglan)
- `377` — 'ask' — North Altay öt-ör-, Kazan Tatar ötün- — a set with TWO roots (ötör- / ötün-); Kazan Tatar carries no ISO code (Glottocode midd1325, display-only)
- `656` — 'spin' — Bashkir, Gagauz, Nogai, Crimean Tatar — two roots (jip / čijrat), Values with upstream's bracketed alternants ("(yep) ilä")

The Cuman row (`CodexCumanicus`) carries no ISO code and no Glottocode upstream.

## Recipe

For the kept set ids: cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments name; languages.csv / parameters.csv rows those forms name. Rows keep upstream's file order and raw bytes (every record is a single line upstream).

## Upstream count reconciliation

README: 32 varieties (31 Glottocodes), 254 concepts, 8,360 lexemes; "8,360 cognates in 905 cognate sets (245 singletons)". Full-scale dry parse (2026-11-27): 905 entries, 8,360 reflex rows (0 loan-flagged — the Loan column is empty throughout; 0 doubtful judgments; 1,282 rows display-only — Baraba, Kazan Tatar, Middle Chulym, Tofa and Turkish carry no ISO), 0 forms outside the CognateTable. accepted 905 = upstream's 905. Old Turkic 262 forms, Cuman 229.

## License

CC BY 4.0 — README "This dataset is licensed under a CC-BY-4.0 license", the LICENSE file (Attribution 4.0 International legal code) and cldf-metadata.json `dc:license` (https://creativecommons.org/licenses/by/4.0/) agree, as does the Zenodo record (cc-by-4.0). Cite: Savelyev, Alexander and Robbeets, Martine (2020): Bayesian phylolinguistics infers the internal structure and the time-depth of the Turkic language family. Journal of Language Evolution 5.1. 39-53.
