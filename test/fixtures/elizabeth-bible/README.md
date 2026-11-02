# elizabeth-bible fixtures

Real upstream data from **getBible** (api.getbible.net), translation
`csielizabeth` — "1757 Church Slavonic Elizabeth Bible", retrieved
2026-11-02 from <https://api.getbible.net/v2/csielizabeth.json>
(HTTP 200, `Last-Modified: Sat, 12 Sep 2026 17:52:37 GMT`, 23,691,163 B,
sha256 `2c59554bbe1d38af3b32324db48c6391fa8242ab4bea5ccc8574bc7b4b107b26`).

The file's own distribution fields, verbatim:

| Field | Value |
|---|---|
| `distribution_license` | `Public Domain` |
| `distribution_about` | `1757 Church Slavonic Elizabeth Bible\\par This electronic edition comes from rusbible.ru and features modernized spelling.` |
| `distribution_source` / `distribution_sourcetype` | `rusbible.ru` / `OSIS` |
| `distribution_versification` | `Synodal` |
| `distribution_version` / `_date` | `1.5.2` / `2011-08-17` (the CrossWire SWORD module's history: 1.0 first release; 1.5 new versification 2010-11-06; 1.5.1 MinimumVersion 2011-08-17; 1.5.2 config typo fix 2022-08-02) |
| `lang` | `cu` |

Census of the whole file (2026-11-02): **76 books / 36,000 verses**, every
verse non-empty and NFC, no verse 0, no duplicate or out-of-order verse,
every verse object's `chapter` equal to its chapter's. 1,339 verses carry
trailing or doubled spaces (whitespace only — collapsed at parse, the usfx
family's rule). The spelling is modern civil-script Cyrillic: no ѣ, і, ѵ,
ѳ, ѡ, ѧ, no titla and no accents anywhere in the file.

## Delivery grains

getBible serves the same text at four grains; the adapter takes the
**translation** as its fetch unit and the **book** as its document:

| Grain | Endpoint | Taken? |
|---|---|---|
| translation | `/v2/csielizabeth.json` (all 76 books + the distribution fields) | **fetched** — the one file the adapter downloads |
| book | `/v2/csielizabeth/<nr>.json` | **the document grain**, carved from the translation file (one document per `books[]` entry); the per-book endpoint itself is rejected (same text, no distribution fields, 4-space indent) — specimen `rejected-grains/32.json` (Jonah) |
| chapter | `/v2/csielizabeth/<nr>/<chapter>.json` | rejected — sub-document; specimen `rejected-grains/32/2.json` (Jonah 2) |
| verse | inside every grain (`verses[]`) | **the passage grain** |

Also served, not text: `/v2/csielizabeth/checksum.json` (per-book sha1s).
The rejected-grain specimens are counted by `discovery_skips` as
skipped by rule, never parsed.

## Files

| File | Shape |
|---|---|
| `csielizabeth.json` | TRIMMED at book boundaries — the whole-translation envelope (every top-level field verbatim) with four of 76 books: Genesis cut to chapter 1 (31 verses), Prayer of Manasses whole (1 ch, 11 vv; getBible nr 79), Jonah whole (4 ch, 48 vv), 2 John whole (1 ch, 13 vv), in upstream order. Re-serialized with `JSON.pretty_generate(data, ascii_only: true) + "\n"`, which reproduces the whole upstream file byte for byte (verified), so each kept book is byte-identical to its upstream slice. |
| `rejected-grains/32.json` | verbatim — the per-book endpoint, Jonah |
| `rejected-grains/32/2.json` | verbatim — the per-chapter endpoint, Jonah 2 |

Text public domain (the 1757 Elizabeth Bible; the electronic edition is
stated `Public Domain` by its distributor).
