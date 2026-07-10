# ORACC P11-7 defect fixtures (real trimmed slices)

Fixtures for the P11-7 silent-ingestion defects, kept in their OWN tree so the
discover-walked `test/fixtures/oracc/` corpus stays clean (every ref there must
parse to a Document; two of these deliberately do not). All content is real
upstream ORACC JSON, trimmed — never hand-written.

Retrieved **2026-07-10** from the on-disk canonical dcclt (lexical lists) and
saao/saa01 (Sargon II letters) projects (per-project zip over HTTP; CC0, the
statement recorded verbatim in each `metadata.json`).

## Files

- `dcclt/corpusjson/P000725.json` — **no-content shape (fix 3)**: copied
  VERBATIM (779 bytes). An object/surface skeleton with only a `nonx` d-node and
  zero transcribed lines — the catalog-only cousin of the 0-byte case. The
  parser raises `Nabu::DocumentSkipped` (skipped by rule, never quarantined).
- `dcclt/corpusjson/P010104.json` — **label-less line-start (fix 4)**: TRIMMED
  from the real ~300-line P010104 to two sentence c-nodes — one ordinary labeled
  line (`o i' 1`) and the one bare `line-start` (no `@label`/`@n`) whose
  enclosing sentence carries the label `r xi' 10'`. Proves the fallback recovers
  the line (suffix `r.xi'.10'`) instead of quarantining. `project`/`textid` kept
  intact so the urn identity check holds.
- `dcclt/corpusjson/P999999.json` — a 0-byte file, exercising the existing
  discover skip + the `discovery_skips` `skipped_by_rule` count.
- `dcclt/{metadata.json,catalogue.json}` — real dcclt metadata (CC0) + a minimal
  catalogue for the license gate / title resolution.
- `saao-saa01/saa01/corpusjson/P334176.json` — **nested-root (fix 1)**: a real
  saao/saa01 text trimmed to its first two labeled line groups, placed under the
  NESTED layout `saao-saa01/saa01/corpusjson/` the subproject zip actually
  unpacks to. Proves discover finds `corpusjson/` at the second depth.
- `saao-saa01/saa01/{metadata.json,catalogue.json}` — real saao metadata (CC0) +
  minimal catalogue.

No network is ever touched; these are parsed by explicit path (parser tests) and
walked by `discover` over this tree (adapter tests).
