# Zhang, Jacques & Lai 2019 Gyalrong–Old Chinese cognates (lexibank/zhangrgyalrong) — fixture

Retrieved 2026-11-23 from github.com/lexibank/zhangrgyalrong at commit `51cdc51964a9a3c0d194f01b6d1ab89c56db2613` (the default-branch head; the repository has never tagged a release and has no Zenodo record). Every fixture file below is a byte-verbatim excerpt of the raw file at that commit (records kept whole, record SET trimmed).

## Delivery grains

cldf/ (ACCEPTED — forms, languages, parameters, cognates; no cognatesets table). The repository's other paths (raw/ — the paper's tsv tables and concept mappings; etc/; the build script) lie outside the sparse fetch cone (cldf, LICENSE, README.md) and never reach the tree.

## Kept cognate sets

- `1` — 'the axe' (斧) — Middle Chinese pjuX, Old Chinese *praʔ, Cogtse/Brag-bar Situ, Japhug
- `14` — 'the bovine' (牛) — the dataset's only Zbu form
- `22` — 'to protect' (保) — Values with an inner space (Brag-bar "u-pû ka-viɛ̂", Japhug "ɯ-pɯ kɤ-pa")

## Recipe

For the kept set ids: cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments name; languages.csv / parameters.csv rows those forms name. Rows keep upstream's file order and raw bytes (every record is a single line upstream).

## Upstream count reconciliation

README: 7 varieties, 120 concepts, 603 lexemes; "603 cognates in 122 cognate sets (0 singletons)". Full-scale dry parse (2026-11-23): 122 entries, 603 reflex rows (297 display-only — the four Gyalrongic varieties carry no ISO code; 0 loans, 0 doubts); no unjudged forms. accepted 122 = upstream's 122.

## License

CC BY-NC 4.0 — README "This dataset is licensed under a https://creativecommons.org/licenses/by-nc/4.0/ license", the LICENSE file (Attribution-NonCommercial 4.0 International legal code), cldf-metadata.json `dc:license` and metadata.json agree. No ND clause.
