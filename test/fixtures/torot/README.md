# TOROT treebank fixtures

Real samples from the TOROT (Tromsø Old Russian and OCS) treebank, which uses the
**PROIEL XML** format (CLAUDE.md fixture rules).

- **Retrieved:** 2026-07-03, from `master` of
  [torottreebank/treebank-releases](https://github.com/torottreebank/treebank-releases)
  via `raw.githubusercontent.com`, base
  `https://raw.githubusercontent.com/torottreebank/treebank-releases/master/`.
- **Acquisition plan** approved by owner 2026-07-03 (dev-loop §8; packet P3-1).

## Files

| File | Bytes | Source | Trim |
|---|---|---|---|
| `peter.xml` | 26,417 | `peter.xml` (26,417 B) | **whole file, byte-exact** — *Correspondence of Peter the Great*, `orv` (Old East Slavic); 4 divs, 11 sentences |
| `zogr-head40.xml` | 105,227 | `zogr.xml` (237,070 B) | PROIEL surgery, see below — Codex Zographensis, `chu` (OCS) |

The full 237 KB `zogr.xml` was fetched to a scratch dir and is **not** committed.

## Trim procedure

- **`peter.xml`** — small enough to keep whole; preserved byte-for-byte as fetched.
- **`zogr-head40.xml`** — same PROIEL surgery as the `proiel/` fixture: XML
  declaration + `<proiel>` root + entire `<annotation>` + `<source>` with all
  metadata children, then whole leading `<div>` elements kept intact until the
  cumulative `<sentence>` count reached ≥ 40. The first div has 19 sentences and
  the second has 43, so **2 divs (62 sentences)** were kept. No div/sentence is
  split; the result parses strict.

## Licenses (per-source `<license>` recorded exactly)

- `peter.xml` `<source>`: `<license>CC BY-NC-SA 3.0</license>`,
  `<license-url>http://creativecommons.org/licenses/by-nc-sa/3.0/us/</license-url>`.
- `zogr.xml` `<source>`: `<license>CC BY-NC-SA 3.0</license>`,
  `<license-url>http://creativecommons.org/licenses/by-nc-sa/3.0/us/</license-url>`.
- The repo README carries the same NonCommercial-ShareAlike statement; both
  per-source headers agree on **CC BY-NC-SA 3.0 (US)**. license_class `nc`.
  (The repo README was not fetched — outside the approved URL list; the per-source
  `<license>` values above are authoritative for these documents.)

## Structure notes (for the TOROT adapter, P3-5)

- Identical PROIEL XML shape as the `proiel/` fixture (`<proiel>` → `<annotation>`
  + `<source>` → `<div>` → `<sentence>` → `<token>`), so TOROT is a thin
  composition over the PROIEL parser (P3-4).
- Language tags of interest: `chu` (Old Church Slavonic, zogr — Marianus/Zograph
  family) and `orv` (Old East Slavic, peter). P3-5 asserts the `chu` tag.
- sentence = passage; token `lemma`/`morphology`/`citation-part` → annotations
  and citation ids.
