# LLCT1 fixture (Late Latin Charter Treebank 1, PML)

Real sample from the **Late Latin Charter Treebank 1 (LLCT1), version 1.2**
(Timo Korkiakangas, University of Helsinki): Early Medieval Latin charters from
Tuscany, AD 714–869, with LDT-style lemma, morphology and dependency annotation,
serialized in **PML** (Prague Markup Language, the TrEd `aldt_treebank`
schema). Trimmed from the single upstream file (CLAUDE.md fixture rules).

- **Retrieved:** 2026-11-08, from **Zenodo record 3633607**
  (`https://zenodo.org/records/3633607`), file
  `https://zenodo.org/api/records/3633607/files/LLCT1,%20version%201.2.xml/content`.
- **Upstream artifact:** `LLCT1, version 1.2.xml` (published 2020-02-01),
  42,231,522 B, md5 `ec45ae3a6844fad40a00d2e8050cfc74` (= the record's own
  checksum), sha256
  `88c4b076237b50ca07987d50c6257e9667e4cb76be48945c43a9f431bd79991f`. The full
  file was fetched to a scratch dir and is **not** committed.

## Delivery grains (the whole record, enumerated at fixture time)

The record serves ONE file. Inside it:

| Grain | Count | Taken? |
|---|---|---|
| the file | 1 | fetched whole (`llct1-1.2.xml`) |
| PML `<head>` (schema href — `aldt_schema.xml` is not shipped) | 1 | furniture, no text (kept in the trim) |
| `<aldt_meta>` annotator block (template placeholders) | 1 | furniture, no text (kept in the trim) |
| **charter** — the trees sharing a root `document_id` + `subdoc` | 519 (CDL 180 · CDT 39 · MED 300) | **the document** |
| sentence tree — an `<LM>` child of `<aldt_trees>` | 9,227 | the passage |
| word node — a nested `<LM>` | 225,834 | the token lane |
| trailing TrEd display PIs (`<?tred-pattern?>`, `<?tred-hint?>`) | 6 | furniture (kept in the trim) |

Nothing upstream serves is a rejected document grain: the furniture carries no
text, so no specimen needs pinning beyond the furniture itself, which the trim
keeps verbatim. Every charter's trees are contiguous and carry identical root
metadata (`date`, `place`, `scribe`, `type`, `redaction`) — censused over all
9,227 trees.

## File

| File | Bytes | Charters | Trees | From |
|---|---|---|---|---|
| `llct1-1.2.xml` | 110,832 | 4 | 29 | the upstream header + 4 whole charters + the trailing PIs |

The four charters (every tree of each, byte-identical, in file order):

| Charter | Trees | Why |
|---|---|---|
| CDL 115 | 5 | a **copy** (754, charta dotis), lacunae (`.....`), hedged place "S. Cassiano (di Moriano o a Vico?, Lucca)" |
| CDL 208 | 2 | the smallest charter (767, breve), place "Monte San Quirico (Lucca?)" |
| CDT 63 | 11 | Brunetti's edition — an **Italian** type label ("Locazione", Pisa 804) |
| MED 259 | 11 | the Lucca series — a notitia brevis (797) with formulaic / free / subscription segments and expanded abbreviations |

## Trim procedure

Keep bytes `[0, end of the "<aldt_trees>" line)`, then every line of the chosen
charters' trees (each top-level tree opens on its own line at 4-space indent;
a charter's lines run until the next charter's first tree), then bytes from the
`  </aldt_trees>` line to EOF. Verified well-formed (`xmllint --noout`).
Re-apply after any refresh (`fixtures:refresh` would overwrite the trim with
the full 42 MB file).

## License (recorded exactly)

**CC BY 4.0.** The Zenodo record 3633607 metadata declares `license:
cc-by-4.0`. The file itself carries no licence header. license_class
`attribution`. Cite: Korkiakangas, Timo (2020). *Late Latin Charter Treebank 1
(LLCT1), version 1.2*, Zenodo, `https://doi.org/10.5281/zenodo.3633607`.
