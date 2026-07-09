# SBLGNT fixtures

Real upstream samples from Faithlife/SBLGNT — the SBL Greek New Testament
plain-text edition (CLAUDE.md fixture rules; P11-5 fixture plan,
owner-approved 2026-07-09).

- **Retrieved:** 2026-07-09, via ranged/whole-file HTTP reads from
  `https://raw.githubusercontent.com/Faithlife/SBLGNT/c4d241a9c1c479a55b989ba35a4976c1d0b8052c/data/sblgnt/text/`
  (repo HEAD pinned `c4d241a9c1c479a55b989ba35a4976c1d0b8052c`, 2025-01-19).
  `github.com/LogosBible/SBLGNT` redirects to `Faithlife/SBLGNT`.
- **License:** CC BY 4.0 → `license_class: attribution`. Verbatim evidence:
  - GitHub license detection: CC-BY-4.0; repo `LICENSE` is the full CC BY 4.0
    legalcode.
  - repo `README.md`: "The SBLGNT is licensed under a Creative Commons
    Attribution 4.0 International License. Copyright 2010 by the Society of
    Biblical Literature and Logos Bible Software."
  - `sblgnt.com/license/` itself now serves the CC BY 4.0 license text — the
    historically restrictive SBLGNT EULA is superseded.
  - Fixture redistribution is explicit legalcode §2(a)(1): "reproduce and
    Share the Licensed Material, in whole or in part".
  - NB the sibling repo `morphgnt/sblgnt` layers CC-BY-SA-3.0 morphology on
    the text; deliberately NOT used here (plain text only, no copyleft).

## Files (under `data/sblgnt/text/`, mirroring the upstream layout)

| Path | Bytes | Contents |
|---|---|---|
| `Mark.txt` | 12,032 | **Trimmed**: title line (`ΚΑΤΑ ΜΑΡΚΟΝ`) + Mark 1:1–2:12 (the alignment-hub anchor verses MARK 1.1 / MARK 2.3), byte-identical head of the upstream file |
| `John.txt` | 3,005 | **Trimmed**: title line (`ΚΑΤΑ ΙΩΑΝΝΗΝ`) + John 1:1–1:18, byte-identical head of the upstream file |
| `3John.txt` | 2,917 | **WHOLE book** — complete-file round-trip exemplar at negligible size; refs are `3John 1:1`–`3John 1:15` |

## Structure notes (SblgntParser, P11-5)

- Verse-per-line TSV: `Book C:V<TAB>verse text` after a first line carrying
  the Greek book title; lines end with a trailing space before `\n` in the
  upstream files (kept). UTF-8, no BOM.
- `⸀ ⸂ ⸃` textual-apparatus sigla are embedded in the verse text upstream
  (pointers into the separate sblgntapp files, which are not ingested) —
  kept verbatim, canonical means canonical.
- Book file stems (`Matt`, `Mark`, `1Cor`, `3John`, `Phlm`, …) match the
  in-line ref book tokens.
