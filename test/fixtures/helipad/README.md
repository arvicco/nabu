# HeliPaD fixture (Old Saxon, Penn labeled-bracketing)

Real sample from **HeliPaD: the Heliand Parsed Database** — a syntactically
parsed edition of the *Heliand*, the 9th-century Old Saxon gospel harmony, in
the **Penn Treebank labeled-bracketing (.psd)** format (CLAUDE.md fixture
rules). Trimmed from the single upstream corpus file.

- **Retrieved:** 2026-07-22, from **Zenodo record 4395040**
  (`https://zenodo.org/records/4395040`), file
  `https://zenodo.org/api/records/4395040/files/heliand.psd/content`.
- **Upstream artifact:** `heliand.psd`, version 0.9 (published 2015-12-28),
  3,524,675 B, sha256
  `2f83b2c0bb64b0e4dc8284a0aa56aed937f3a0b26ad9a82440d832bf702bda4d`. A single
  Penn labeled-bracketing file — 3,549 top-level tree blocks. The full file was
  fetched to a scratch dir and is **not** committed. (The 952,046 B
  `HeliPaD-manual.pdf` in the same record was not fetched.)

## File

| File | Bytes | Trees | From |
|---|---|---|---|
| `heliand-head.psd` | 5,809 | 2 | first **2 whole tree blocks** of `heliand.psd` (blocks `OSHeliandC.1.1-5` and `OSHeliandC.2.5-9`); 3,524,675 B / 3,549 trees -> 5,809 B |

## Trim procedure

`heliand.psd` is a stream of Penn trees, each a balanced-parenthesis block
ending in an `(ID …)` node and separated from the next by a blank line. The
trim keeps the **first 2 complete tree blocks in document order, never cutting
mid-tree** (verified: parenthesis balance of the trimmed file is 0). Re-apply
after any refresh (`fixtures:refresh` overwrites the trim with the full 3.4 MB
file).

## Structure notes (for the P40-3 parser)

- One **tree = one sentence/verse passage**; blocks separated by a blank line.
- The top node is `(IP-MAT …)` / `(IP-…)`; the block closes with `(ID <text>.<verse-range>)`
  (e.g. `(ID OSHeliandC.1.1-5)`) — the stable citation id.
- Leaves are `(TAG token-lemma)` pairs: the surface form and its lemma are joined
  by a hyphen (`Manega-manag`, `uuaron-wesan`), so the parser splits on the last
  hyphen to recover form vs lemma. POS/morphology ride the node label, often with
  `^`-separated features (`Q^N^PL`, `BEDI^3^PL`, `GE+VBDI^3^SG`).
- `(CODE <…>)` nodes carry editorial metadata inline: manuscript/edition
  (`<COM:HELIAND_C>`), folio (`<MS_5a>`), fitt/line refs (`<F_1>`, `<R_1>`,
  `<C>`) — not text, and the parser must skip them for the passage string.
- Empty categories appear as `*exp*`, `*ICH*-1`, `0`, and trace indices (`-1`,
  `-2`) — standard Penn conventions.

## License (recorded exactly)

**CC BY 4.0.** The Zenodo record 4395040 metadata declares `license: cc-by-4.0`
(Creative Commons Attribution 4.0 International). The `.psd` file itself carries
no licence header. license_class `attribution`. Cite: Walkden, George (2015).
*HeliPaD: the Heliand Parsed Database*, v0.9, Zenodo,
`https://doi.org/10.5281/zenodo.4395040`.
