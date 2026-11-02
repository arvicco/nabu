# cleasby-vigfusson fixture

Trimmed REAL excerpt of stscoundrel's JSON edition of Cleasby &
Vigfusson, *An Icelandic-English Dictionary* (1874). Retrieved
2026-11-02 from
https://github.com/stscoundrel/cleasby-vigfusson-dictionary (default
branch master, pushed 2024-09-07):

- `json/cleasby-vigfusson.json` — 11,742,655 bytes, 35,207 records,
  sha256 7ef2abacc0c98ba4b6f79fc9371ccc786e87974942b5dfc80339a0495f44cbec
- `json/cleasby-vigfusson-no-markup.json` — 10,656,938 bytes, 35,207
  records

## Delivery grains

The repo is a Node.js package around ONE dataset served twice:

- `json/cleasby-vigfusson.json` — a pretty-printed JSON array of
  `{"word", "definitions": [...]}` records, the book's `<strong>` /
  `<i>` markup kept — **ACCEPTED** as the one dictionary document
  (each record an entry; the italics mark the English glosses).
- `json/cleasby-vigfusson-no-markup.json` — the same records with the
  markup stripped — **REJECTED** by rule (a lossy twin), skipped and
  counted in discovery_skips with its note. Specimen pinned here.
- `src/`, tests, `index.js`, package files — the package code, not data.

Reconciliation: 35,207 records accepted (README: "35 000+ Old Norse
words"; upstream advertises no exact total) + 1 file skipped by rule.

## Cut

- `json/cleasby-vigfusson.json`: the 4 records at 0-based array
  positions 1, 10106, 27973, 27974, byte-verbatim objects in upstream
  order inside a re-closed array — abbadís (a plain entry with its
  italic gloss), Gýmir (the regression specimen: its definition
  carries U+0343 COMBINING GREEK KORONIS, non-NFC upstream), and the
  stefja homograph pair (one of the 7 words printed twice).
- `json/cleasby-vigfusson-no-markup.json`: the record at position 1
  (abbadís), the rejected grain's specimen.

## Refresh

Re-fetch the two files from the repo's master branch and re-select the
same positions (verify the words match: the array order is the only
identity upstream carries).
