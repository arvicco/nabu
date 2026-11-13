# Dyen, Kruskal & Black 1992 (lexibank/dyenindoeuropean) — fixture

Retrieved 2026-11-13 from github.com/lexibank/dyenindoeuropean at commit `cd1ad5f8b20e2bf2acd4823cbb93a411809036e9` (the default-branch head; the repository has never tagged a release and has no Zenodo record). Every fixture file below is a byte-verbatim excerpt of the raw file at that commit (records kept whole, record SET trimmed).

## Delivery grains

cldf/ (ACCEPTED). The repository's other paths (raw/, etc/, the python packaging) lie outside the sparse fetch cone (cldf, LICENSE, README.md) and never reach the tree.

## Kept cognate sets

- `001-004` — 'all' — the Germanic class (eleven lists, two Swedish ones without ISO codes)
- `001-005` — 'all' — a singleton (Welsh C, no ISO code)
- plus form 73-001-1 (Ossetic 'all', Cognacy 001-001 in forms.csv but absent from cognates.csv) — the unjudged-form specimen the census counts

## Recipe

For the kept set ids: cognatesets.csv rows with those IDs; cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments (and the cognatesets' Form_ID heads) name; languages.csv / parameters.csv rows those forms name; borrowings.csv rows targeting a kept form; etyma.csv rows the kept sets' Etymon_ID name. Rows keep upstream's file order and raw bytes (the CSV reader's own line text, so quoted multi-line cells survive).

## Upstream count reconciliation

README: 95 varieties, 200 concepts, 21,606 lexemes, 14,752 cognates in 2,388 cognate sets (466 singletons). Full-scale dry parse: 2,388 entries, 14,752 reflex rows; 6,854 forms carry a Cognacy code in forms.csv but no CognateTable judgment and mint nothing (the CognateTable is the dataset's claim) — counted. accepted 2,388 = upstream's 2,388.

## License

CC BY 4.0 — README "This dataset is licensed under a CC-BY-4.0 license", the LICENSE file (the CC BY 4.0 legal code) and cldf-metadata.json `dc:license` agree.
