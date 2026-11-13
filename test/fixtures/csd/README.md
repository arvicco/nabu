# CSD — Comparative Siouan Dictionary (lexibank/csd) — fixture

Retrieved 2026-11-13 from github.com/lexibank/csd at commit `91756e90cee764dcfe96966e5a82a6092eb35f00` (the default-branch head; the repository has never tagged a release and has no Zenodo record). Every fixture file below is a byte-verbatim excerpt of the raw file at that commit (records kept whole, record SET trimmed).

## Delivery grains

cldf/ (ACCEPTED). The repository's other paths lie outside the sparse fetch cone (cldf, LICENSE, README.md) and never reach the tree.

## Kept cognate sets

- `113` — 'trade' — a Pre-Mandan head (Form_ID) with a Mandan member; the set Name only repeats the id
- `13` — 'wrinkle (1), ruffle' — Proto-Siouan *xi head, with a comment
- `73` — 'vermin (6)' — no Form_ID (the comment explains why no PSI form is set up): the set Description heads it

## Recipe

For the kept set ids: cognatesets.csv rows with those IDs; cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments (and the cognatesets' Form_ID heads) name; languages.csv / parameters.csv rows those forms name; borrowings.csv rows targeting a kept form; etyma.csv rows the kept sets' Etymon_ID name. Rows keep upstream's file order and raw bytes (the CSV reader's own line text, so quoted multi-line cells survive).

## Upstream count reconciliation

README (cldf/): 36 varieties, 22,200 lexemes; cognatesets.csv lists 1,204 sets. Full-scale dry parse: 1,193 entries, 17,902 reflex rows; 11 set records carry no judgment at all and mint nothing — skipped by rule, counted. accepted 1,193 + skipped 11 = upstream's 1,204.

## License

CC BY 4.0 — README "This dataset is licensed under a http://creativecommons.org/licenses/by/4.0/ license", the LICENSE file (the CC BY 4.0 legal code) and cldf-metadata.json `dc:license` agree.
