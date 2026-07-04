# PROIEL treebank fixture

Real sample from the PROIEL treebank (CLAUDE.md fixture rules), trimmed from one
large source file.

- **Retrieved:** 2026-07-03, from `master` of
  [proiel/proiel-treebank](https://github.com/proiel/proiel-treebank) via
  `raw.githubusercontent.com`.
- **Acquisition plan** approved by owner 2026-07-03 (dev-loop §8; packet P3-1).

## File

| File | Bytes | From |
|---|---|---|
| `cic-off-head15.xml` | 93,767 | trimmed from `cic-off.xml` (Cicero, *De officiis*), source 1,984,040 B — `https://raw.githubusercontent.com/proiel/proiel-treebank/master/cic-off.xml` |

The full 1.98 MB `cic-off.xml` was fetched to a scratch dir and is **not**
committed.

## Trim procedure (PROIEL surgery, Nokogiri DOM, one-off scratch tooling)

Kept, in document order: the XML declaration, the `<proiel>` root, the **entire
`<annotation>` element** (relations / parts-of-speech / morphology /
information-statuses), the `<source>` element with **all its metadata children**
(title, author, citation-part, license, reference-system, editors, etc. — every
child before the first `<div>`), and then **whole leading `<div>` elements kept
intact** up to the one that brings the cumulative `<sentence>` count to ≥ 15.

> **Note on the "first 15 sentences" target.** The approved plan asked for "the
> first `<div>` with its first 15 complete `<sentence>` elements". In this real
> file the first `<div>` holds only **2** sentences, so — following the same
> whole-div accumulation rule the plan spells out for TOROT/zogr — divs were kept
> intact until ≥15 sentences accumulated: **4 divs, 18 sentences**. No `<div>` or
> `<sentence>` is split; the result parses strict.

## License (recorded exactly)

- **Per-source header** (`cic-off`'s `<source>`): `<license>CC BY-NC-SA 4.0</license>`,
  `<license-url>https://creativecommons.org/licenses/by-nc-sa/4.0/</license-url>`.
- **Repo README statement:** CC BY-NC-SA 3.0; the repo has **no LICENSE file**.
- license_class `nc`.

## Structure notes (for the PROIEL parser, P3-4)

- Root `<proiel>` carries `export-time` + `schema-version`.
- `<annotation>` declares the controlled vocabularies (relations, POS, morphology,
  information-statuses) shared by all sentences.
- `<source id="cic-off" language="lat">` holds bibliographic metadata then `<div>`s.
- `<div>` → `<sentence id status>` → `<token …>`; each token carries `form`,
  `lemma`, `part-of-speech`, `morphology`, `head-id`, `relation`,
  `presentation-after`, and a `citation-part` (e.g. `1.1`) used for citation ids.
- **sentence = passage**; token lemma/morphology → annotations (P3-4).
