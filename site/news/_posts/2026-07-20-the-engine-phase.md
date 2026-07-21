---
title: "The engine phase: rebuilds measured, stamped, and made incremental"
date: 2026-07-20 22:00:00 +0000
description: >-
  Phase 36 gives the derived layer its instruments: a stage profiler in
  every rebuild, derivation stamps that let unchanged sources skip
  re-derivation, and the query constants recalibrated to the settled
  24.4-million-passage corpus.
---

The library tripled in a week, and a full rebuild grew to hours.
Phase 36 answers with measurement before optimization: every rebuild
now times itself per source and per stage, and the first instrumented
run settled the question — the cost is dominated by database insertion,
not parsing.

The deeper change is the derivation stamp. Each source's derived rows
are a pure function of four inputs — its canonical bytes, its parser
code, the fold rules, and the schema — and every load now records a
fingerprint of all four. `nabu rebuild --incremental` skips any source
whose fingerprint is unchanged and re-derives only the dirty ones, with
the full rebuild remaining the reference implementation, pinned
equivalent by test. A frozen source costs nothing to keep; a parser fix
re-derives exactly the shelves it touches.

The recalibration ruled in Phase 35 also executed: the quotation-
detection thresholds in `parallels` are now corpus-relative — the old
absolute cutoffs, tuned when the library held 3.8 million passages,
had drifted to a sixth of their intended strength against 24.4 million.
The reference pages refreshed to the settled census, recording a
changing of the guard: Literary Chinese is now the library's largest
language, at 13.0 million passages. Numbers as of 2026-07-20.
