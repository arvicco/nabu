# CLICS³ fixtures (P46-6 — the colexification network)

A real trimmed subgraph of the **CLICS³ released network artifact**
(Rzymski, Tresoldi et al. 2019; clics.clld.org). Kept node and edge
blocks are **byte-verbatim** upstream GML (whole blocks, attribute lists
and all — including the bulky per-word `Words`/`wofam` attestation
strings the parser deliberately skips by name); only the block SET was
trimmed, and the `graph [` … `]` wrapper mirrors the original.

- **Retrieved:** 2026-07-26, from the tag-pinned raw blob
  <https://raw.githubusercontent.com/clics/clics3/v1.1/clics3-network.gml.zip>
  (checked into the clics/clics3 repo at release tag v1.1) —
  12,181,049 B, sha256
  `c4b2069b65a06ada8513ee107e398ca41d0f56ba00fa77919755e80a236ccf7d`
  (the adapter's `RELEASE_SHA256` pin), unzipping to
  `graphs/network-3-families.gml` (67 MB). Full-artifact census at
  retrieval: 2,919 nodes / 4,228 edges.
- **License:** CC BY 4.0 — repo README at v1.1 verbatim: "This data is
  licensed under CC BY 4.0". Cite: Rzymski, Tresoldi et al. 2019, DOI
  10.17613/5awv-6w15.
- Layout mirrors the pre-flatten zip shape (`graphs/…`); ZipFetch
  flattens the single top dir in real syncs and discover globs for the
  file, so both shapes resolve identically.

## What was kept — the in-law triangle

Three nodes + the three edges among them (a REAL connected subgraph, so
the symmetric ↔ rendering and the strongest-edge-first sort are pinned
on genuine weights):

- **1060 CHILD-IN-LAW** (graph id 2550; 18 varieties / 12 families /
  26 words — the small hub node),
- **2264 DAUGHTER-IN-LAW (OF WOMAN)** (graph id 1855),
- **2266 SON-IN-LAW (OF WOMAN)** (graph id 1856),
- edges 2264↔2266 (FamilyWeight 10, 21 varieties), 2264↔1060 (6
  families / 7 varieties — families list Atlantic-Congo; Austroasiatic;
  Indo-European; Saharan; Tai-Kadai; Yeniseian), 2266↔1060 (9
  families / 10 varieties).

Chosen over the classic MOON↔MONTH pair deliberately: those node
blocks carry ~140 KB `Words` lists each (the fixture would be 95%
skipped bytes); the kinship triangle pins every parsed attribute —
including family-aware weights — at 30 KB total.

## Refresh recipe

Re-download the tag-pinned zip above (a tagged git blob — byte drift is
an incident, not an update), unzip, and re-extract the node blocks
whose `id` ∈ {1855, 1856, 2550} plus the edge blocks whose source AND
target both fall in that set, wrapped in `graph [` … `]`.
