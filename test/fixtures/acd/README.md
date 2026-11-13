# ACD — Austronesian Comparative Dictionary (lexibank/acd v2.0) — fixture

Retrieved 2026-11-13 from the Zenodo versioned record of the GitHub release v2.0: https://doi.org/10.5281/zenodo.14608975 — file `lexibank/acd-v2.0.zip` (30926712 B, md5 `e867ce81354cf82370d2a4fa147f7f5b` as Zenodo publishes it; sha256 `6141f908af0b7e9733176e838b59e586c092e78f405c874b8dff0baaf3447d01`, the adapter's hard pin). The zip unpacks under `lexibank-acd-16085f2/`; every fixture file below is a byte-verbatim excerpt of that tree (records kept whole, record SET trimmed).

## Delivery grains

cldf/ (ACCEPTED — the CLDF bundle, ONE document); raw/ (REJECTED — upstream's pre-CLDF source dumps and update logs; specimen raw/updates/2022-06-14_new_language_merap/metadata.tsv, whole); etc/, acdparser/, acdcommands/, docs/ and the python packaging are machinery.

## Kept cognate sets

- `24748_1` — PPh *abag 'join forces' — a low-level proto head (Proto-Philippines, no registry node)
- `25118_1` — PAN *baNaw — PAn head with a PMP proto member (display-only) and the nonconforming Rukai witness
- `30578_1` — PAN *asaŋ₃ 'village' — both members are borrowings targets (Loan true; three cf.-set records, two on one form)

## Recipe

For the kept set ids: cognatesets.csv rows with those IDs; cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments (and the cognatesets' Form_ID heads) name; languages.csv / parameters.csv rows those forms name; borrowings.csv rows targeting a kept form; etyma.csv rows the kept sets' Etymon_ID name. Rows keep upstream's file order and raw bytes (the CSV reader's own line text, so quoted multi-line cells survive).

## Upstream count reconciliation

README: 1,063 varieties, 86,502 concepts, 146,733 lexemes, 121,682 cognates in 10,857 cognate sets. Full-scale dry parse of the pinned zip: 10,857 entries minted (every set), 110,825 reflex rows; 26,734 forms belong to no cognate set (cf. items, borrowing sources) and mint nothing — counted in the census, never dropped silently. accepted 10,857 + skipped 0 = upstream's 10,857.

## License

CC BY 4.0 — README "This dataset is licensed under a CC-BY-4.0 license", the LICENSE file (the CC BY 4.0 legal code) and cldf-metadata.json `dc:license` agree, as does the Zenodo record.
