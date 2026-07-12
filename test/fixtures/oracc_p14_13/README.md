# ORACC P14-13 defect fixture (real trimmed slice)

Fixture for the P14-13 defect the owner's 2026-07-12 stage-2 crawl surfaced: of
+3,884 new `-en` documents, 13 quarantined, ALL in `blms` (Bilinguals in Late
Mesopotamian Scholarship), all raising *"prose unit anchored at X resolves to no
line-start row"*. Kept in its OWN tree so the discover-walked
`test/fixtures/oracc/` corpus stays clean. Content is real upstream ORACC
HTML/JSON, trimmed — never hand-written.

Retrieved **2026-07-12** from the on-disk canonical `blms` project. Licenses
(CC0 build files; CC BY-SA 3.0 translation prose) are the canonical statements.

## Root cause — catalog-only skeleton tablet (NOT the P14-9 `:b2` case)

The census refuted the `:b2` suspicion. These 13 tablets are **catalog-only
skeletons**: published with an English translation but never lemmatized, so
their corpusjson `line-start` d-nodes carry **empty `ref` AND empty `label`**
(`{"node":"d","type":"line-start"}`). The `line_labels` map is therefore EMPTY,
and P14-9's forward/backward reattach both scan nothing — the anchors resolve in
NEITHER direction. The render ids the HTML anchors at (`X000003.2l`, the trailing
`l` = an untranscribed line's render id) exist in NO corpusjson `ref`. The
sibling tablet is itself skipped (`DocumentSkipped`, "no transcribed lines"), so
there was never a parallel to align to.

But every prose cell PRINTS its human line label in `span.xtr-label` — the same
`(o 1)`/`(o 2)` the edition cites. The fix falls back to that printed label as
the passage suffix rather than quarantine 13 real translations. The `-en`
document then stands alone (Query::Parallel simply has no tablet to pair it
with, which is correct, not a loss).

## Item — `blms/X000003` (GAAL 2, pl. 14; BM 064377+)

- `html-en/blms/X000003.html` — the per-text translation fragment, TRIMMED to
  the obverse surface row + the first two bilingual line-groups (`o 1`, `o 2`)
  and the trailing `nonl` rows. Each `td.xtr` prose cell anchors at
  `X000003.{2,3}l` (HTML-only render ids) and prints `(o 1)` / `(o 2)`.
- `blms/corpusjson/X000003.json` — the sibling skeleton, TRIMMED to the text
  c-node with its object/surface d-nodes and the first two implicit sentences,
  each kept to its real `line-start` d-node (empty `ref`+`label`) + one `l`-node.
  The skeleton reproduces the empty-labels-map that defeats corpusjson anchoring.

No network is ever touched; parsed by explicit path (parser test).
