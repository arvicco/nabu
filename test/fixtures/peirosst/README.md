# Peiros 2004 Comparative Sino-Tibetan Wordlists (lexibank/peirosst) — fixture

Retrieved 2026-11-23 from github.com/lexibank/peirosst at commit `4619b46ac0b9cdba83f19debc1108faebccab229` (the default-branch head, last pushed 2020-12-04; never tagged, no Zenodo record). Every fixture file below is a byte-verbatim excerpt of the raw file at that commit (records kept whole, record SET trimmed).

## Delivery grains

cldf/ (ACCEPTED — forms, languages, parameters, cognates; no cognatesets table). The repository's other paths (raw/ — Peiros's st-data.tsv database export; etc/; the build script) lie outside the sparse fetch cone (cldf, LICENSE, README.md) and never reach the tree.

## Kept cognate sets

- `1-2693` — 'all' — a singleton (Bodo)
- `1--1` — 'all' — an upstream NON-POSITIVE class number (concept 1, class -1): eight forms, most carrying Peiros's loan tags in the Value ("TIB", "NEP", "Tib.?"); carried verbatim as the CognateTable states it, no loan flag inferred
- `3-262` — 'bark' — Old Chinese "bhaj 皮" (Value carries the character), Beijing, the CHN variety (no ISO, no Glottocode — namespaced), Fuzhou, Hakka

## Recipe

For the kept set ids: cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments name; languages.csv / parameters.csv rows those forms name. Rows keep upstream's file order and raw bytes (every record is a single line upstream).

## Upstream count reconciliation

README: 128 varieties, 110 concepts, 13,798 lexemes; "13,798 cognates in 1,806 cognate sets (550 singletons)". Full-scale dry parse (2026-11-23): 1,806 entries, 13,798 reflex rows (4,171 display-only — 39 varieties carry no ISO code; 0 loans, 0 doubts); no unjudged forms. 94 of the sets (211 forms) carry non-positive class numbers — 68 of them "-1" classes (175 forms). accepted 1,806 = upstream's 1,806.

## License

CC BY-NC 4.0 — README "This dataset is licensed under a CC-BY-NC-4.0 license", the LICENSE file (Attribution-NonCommercial 4.0 International legal code), cldf-metadata.json `dc:license` and metadata.json agree. No ND clause.
