# ETCBC/bridging fixtures (P34-1)

Trimmed, byte-verbatim slices of the OSHB↔BHSA word-level crosswalk module —
github.com/ETCBC/bridging — retrieved 2026-07-20 at upstream commit
`324598bb3f9cb3a36543e77ac61e4b0f77addf82` (master, 2023-11-14, the latest).

## What the data is

Two Text-Fabric NODE features over the **BHSA tf/2021 slot space** (the same
frozen dataset the bhsa adapter pins, 426,590 word slots):

- `tf/2021/osm.tf` — the OpenScriptures morphhb `morph` tag of the FIRST OSM
  morpheme upstream aligned to each BHSA word (`HC`, `HVqw3ms`, …). Full
  corpus: 420,108 covered slots (98.5%; the gaps are BHSA's surfaceless
  elided-article slots), 259 slots carry the honest `*` problem marker, 874
  distinct tags.
- `tf/2021/osm_sf.tf` — the SECOND morpheme of a two-morpheme word (the
  pronominal suffix / directional he). Full corpus: 49,376 slots, 71 tags.

Headers are machine-readable pins: `@coreData=BHSA`, `@version=2021`,
`@source_url=https://github.com/openscriptures/morphhb`. The OSHB side is NOT
commit-pinned upstream (the notebook read morphhb master ~2021-12-09,
`@dateWritten=2021-12-09`); measured against nabu's canonical morphhb
3d15126 (2024-08-27), 99.05% of verses carry identical per-verse OSM tag
sequences — the residue is 80 verses of in-place single-tag retagging
(HR/HRd mostly), zero ordering drift. `tf/2017` (the 88%-complete-era build
against BHSA 2017's 426,582 slots) is deliberately not fixtured and outside
the fetch cone.

## Trim recipe

Both files keep their upstream headers byte-verbatim; data lines are the
subset of (node, value) pairs whose node is a content slot of the bhsa
fixture slice (the 2,881 slots of test/fixtures/bhsa — Jona + Ruth whole,
Haggai 2:4-5, Daniel 2:4-7), re-anchored gap-wise (explicit `node<TAB>value`
at every run start, implicit increment inside a run — the P30-4 recipe).
Every retained value verified byte-equal to the untrimmed upstream file at
the pinned commit. None of the 259 `*` slots fall inside the slice, so the
marker is documented here, not fixtured.

## License (verbatim, LICENSE at the pinned commit)

"MIT License / Copyright (c) 2019 Dirk Roorda … The above copyright notice
and this permission notice shall be included in all copies or substantial
portions of the Software." The osm values themselves are OSHB morphology
(CC BY 4.0, github.com/openscriptures/morphhb); they surface only on bhsa
passages, whose CC BY-NC 4.0 class governs every serving surface.
