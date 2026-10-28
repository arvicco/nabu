# PNA fixtures (A Social Network of the Prosopography of the Neo-Assyrian Empire, CC BY-SA 3.0)

Retrieved 2026-10-28 from Zenodo record 6220409 — version 3 of concept
DOI 10.5281/zenodo.5862904 (Heidi Jauhiainen & Tero Alstola, University
of Helsinki; published 2022-01-17), the three files at
`https://zenodo.org/api/records/6220409/files/<name>/content`:

| file | bytes | sha256 |
|---|---|---|
| Networks.zip | 5,661,079 | 4e290e3fcf33a619673865661b926b035a2275261e4d10be1a98874a8fd40f3e |
| SupplementaryData.zip | 2,394,644 | f10ddb6dca062fb5272b201ab2d90b929f10b4e56d36bc32773c5b6b3a6a08f8 |
| README.txt | 6,543 | e2aa0953ab9ab06e068a6e9aad4966577f1e7ee91e462af9e1b8325acebf5385 |

(md5s match the record's own checksums.) License: README.txt, last line,
verbatim — "These files are licensed under a Creative Commons
Attribution-ShareAlike 3.0 Unported License." — repeated at the foot of
Networks/readme.txt, SupplementaryData/README.txt and
SupplementaryData/Lists/readme.md; the record's license field is
cc-by-sa-3.0.

## What is here

The archive MEMBERS, trimmed, under upstream's own member paths (the
tests re-pack them into Networks.zip / SupplementaryData.zip with
`zip`, `test/support/pna_fixture_zips.rb`); every kept line is
byte-verbatim:

- `README.txt` — the record's README, whole (the license carrier).
- `Networks/NodeList.csv` — header + 8 of 17,387 person rows:
  `'Idru_1` (the aleph apostrophe), `Hundāru (Ahundāra)_2` (a
  parenthesised variant), `Aššūr-zāqip_4` (Time `N/A`, the 01/01/2000
  placeholder date), `Ki[...]_2` (a broken name), `Ṣirānû or Ṣērānû_1`
  (two readings), `Mullissu-šāzizinni_1` (fem), `Abbūtā_1` (fem, an
  Origin — Ialunean), `Ahu-ṭāba_1`.
- `Networks/biModal.csv` — header + ALL 11 links of those 8 persons (of
  25,164), over 9 publications covering every crosswalk route: SAA 12 63
  (the concordance's own project), SAA 6 10 (the concordance's first row
  is lacost; the held copy is saao), StAT 2 53 and SAAB 5 58 (designation
  under the zero-pad fold), ABL 458 / ABL 791 / ADD 382 (cdli by
  designation), AAA 20 and GPA 121 (held nowhere — bare citations).
- `SupplementaryData/Lists/oraccConcordances` — the 3 of 36,006 rows
  naming those publications (lacost + saao/saa06 for SAA 6 10, saao/saa12
  for SAA 12 63).
- `SupplementaryData/Lists/personMetadata` — whole (CRLF kept): upstream's
  own definition of the NodeList columns.
- `Networks/EdgeList.csv`, `Networks/EdgeList_NrOfCooccurrences.csv` —
  header + 3 edges each touching the kept persons: the rejected grain's
  specimen.

## Delivery grains

The record serves three files; inside the archives:

- **Persons** — Networks/NodeList.csv, one row per person: TAKEN (one
  "pna" person-index row each).
- **Person–text links** — Networks/biModal.csv, one row per (text,
  person): TAKEN (the person's texts, resolved by the crosswalk).
- **The Oracc concordance** — SupplementaryData/Lists/oraccConcordances:
  TAKEN as the crosswalk's first step (read, not projected).
- **Co-occurrence edges** — Networks/EdgeList.csv and
  EdgeList_NrOfCooccurrences.csv (149,045 edges, two weightings of the
  same network) and the Gephi project PNANetworks.gephi (the same
  network, a visualization container — not pinned; 4.8 MB): REJECTED by
  rule — the person index has no relation lane, and co-presence in one
  text is not a relation PNA asserts. The module census counts them as
  "co-occurrence edges (skipped by rule)", asserted in
  `test/adapters/pna_test.rb` and `test/pna_persons_test.rb` against
  the specimen.
- **The pipeline's working material** — the other SupplementaryData Lists
  (normalization tables), Output/ (intermediate stages), Java sources,
  serialized .bin files: REJECTED (already applied in NodeList/biModal);
  `personMetadata` is pinned as the specimen. Kept verbatim inside the
  fetched archive.

Re-cut recipe: download the three files, unzip, keep the NodeList rows
whose Label is one of the 8 above, every biModal row whose Target is one
of them, the oraccConcordances rows whose designation (field 2) is one of
their publications, and the first 3 EdgeList rows touching their Ids.
