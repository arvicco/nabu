# zoega fixture

Trimmed REAL excerpt of stscoundrel's JSON edition of Geir T. Zoëga,
*A Concise Dictionary of Old Icelandic* (1910). Retrieved 2026-11-02
from https://github.com/stscoundrel/old-icelandic-zoega (default
branch master, pushed 2024-05-25):

- `json/zoega.json` — 4,291,377 bytes, 29,951 records, sha256
  286cfcec43b8124d65b1c8992a6f1f92ebeb8b1d1a863d85816c00615aba60b3
- `json/zoega-no-markup.json` — 3,952,588 bytes, 29,951 records

## Delivery grains

The repo is a Node.js package around ONE dataset served twice:

- `json/zoega.json` — a pretty-printed JSON array of
  `{"word", "definitions": [...]}` records, the book's `<strong>` /
  `<i>` markup kept — **ACCEPTED** as the one dictionary document.
- `json/zoega-no-markup.json` — the same records with the markup
  stripped — **REJECTED** by rule (a lossy twin), skipped and counted
  in discovery_skips with its note. Specimen pinned here.
- `src/`, tests, package files — the package code, not data.

Reconciliation: 29,951 records accepted (README: "29 000+ Old
Icelandic words"; no exact upstream total) + 1 file skipped by rule.

## Cut

- `json/zoega.json`: the 3 records at 0-based array positions 1,
  3887, 3888, byte-verbatim objects in upstream order inside a
  re-closed array — abbadis (a plain entry) and the brýnn homograph
  pair (the one word printed twice; the first opens with a bare
  `<strong>I)</strong>` sense-numeral definition).
- `json/zoega-no-markup.json`: the record at position 1 (abbadis), the
  rejected grain's specimen.

## Refresh

Re-fetch the two files from the repo's master branch and re-select the
same positions (verify the words match).
