# ORACC P14-9 defect fixtures (real trimmed slices)

Fixtures for the P14-9 sync defects the owner's 2026-07-12 big sync surfaced
(20 quarantines across blms + saao-saa08). Kept in their OWN tree so the
discover-walked `test/fixtures/oracc/` corpus stays clean. All content is real
upstream ORACC JSON/HTML, trimmed — never hand-written.

Retrieved **2026-07-12** from the on-disk canonical `blms` (bilingual literary)
and `saao/saa08` (astrological/omen reports) projects, plus `riao` (a proxy
corpus). Licenses (CC0 build files; CC BY-SA 3.0 translation prose) are the
canonical statements, kept verbatim where present.

## Item 1 — duplicate passage urn (collision tolerance, `:b2`)

Both defects are ONE root cause: several label-less `line-start` d-nodes under a
single sentence all take the P11-7 sentence-label fallback, so distinct physical
lines mint the same suffix.

- `blms/corpusjson/P345480.json` — **bilingual interlinear**. TRIMMED to the
  first 16 children of the one sentence (label `o 1'`). The Sumerian line carries
  its own `o 1'`; the Akkadian interlinear line is label-less and falls back to
  `o 1'` → collision. The fix suffixes the second `o.1':b2`.
- `saao-saa08/saa08/corpusjson/P336559.json` — **range-labeled omens**. TRIMMED
  to the first 36 children of the one sentence (label `o 1 - r 6`). Several
  label-less line-starts fall back to `o 1 - r 6` → repeated suffix, disambiguated
  `o.1.-.r.6:b2`. Placed under the NESTED `saao-saa08/saa08/` layout the
  subproject zip unpacks to.

## Item 2 — trailing prose past all line-starts (backward reattach)

- `saao-saa08/saa08/corpusjson/P336145.json` — the sibling tablet, TRIMMED to its
  real `line-start` d-node skeleton (o 1..r 2; l-nodes dropped — the translation
  parser reads only line-start `ref`→`label`). Note: it stops at **r 2** — there
  is no r 3.
- `html-en/saao-saa08/P336145.html` — the per-text translation fragment, TRIMMED
  to the surface rows + the o 1 / r 1 / r 2 / blank / `nonl-final` rows. The final
  prose unit anchors at row `P336145.13` ("traces of a name", print label
  "(r 3)") which the corpusjson never mints. Reattach-forward finds nothing after
  it; the fix reattaches BACKWARD to r 2, so "[From NN]." is not dropped.

## Item 3 — proxy/portal corpus (benign zero, not an unpack error)

- `riao/corpus.json` — TRIMMED to 3 `proxies` entries. A `type:corpus` file with
  a `proxies` map and NO `corpusjson/` dir: riao/ribo/dcclt-jena own no texts
  (they live in out-of-scope sibling subprojects). `discovery_skips` must count
  this a benign skip, NOT flag it as an unpack/layout error.

No network is ever touched; parsed by explicit path (parser tests) and walked by
`discovery_skips` over this tree (adapter test).
