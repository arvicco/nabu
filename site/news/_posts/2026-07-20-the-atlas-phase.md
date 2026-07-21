---
title: "The atlas phase: research axes, personas, and honest surfaces"
date: 2026-07-20 18:00:00 +0000
description: >-
  Phase 35 stops widening and maps: eighteen research axes with their
  personas over the eighty-source registry, axis-aware listing and
  syncing, and a standing audit that keeps the code's assumptions
  honest as the corpus grows.
---

Phase 35 makes the library's shape visible. Eighty sources now carry
research-axis tags — eighteen desks from the Classicist to the
Japanologist, each with its persona — and `nabu list --axis`,
`status --axis`, and `nabu sync celtic` work the desks directly. Axes
are tags, not folders: a source serves every desk it belongs to, and
the public atlas page ([docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md))
is pinned to the live registry by a drift test, so it can never
quietly go stale.

The phase's second half is less visible and will matter longer. Every
numeric limit and hand-enumerated list in query code is a census claim
about the corpus at the moment it was written, and three ingestion
sprints had silently falsified several — a search page could come back
"no matches" while matches existed beyond a window sized for a corpus
a quarter the size. Phase 35 inventoried every such site, re-measured
each against the live catalog, and converted the class into standing
gates: truncating surfaces must announce what they hid, empty results
under filters must explain themselves, and every era-bound constant
now carries its census and date, machine-checked at every commit.

The nomenclature also settled: "axis" now always means a research
axis; the date-and-place dimension is the timeline. East-Asian-width-
aware rendering landed alongside — the first fix from the newly
CJK-heavy shelves, aligning every concordance column through Han text.
Numbers as of 2026-07-20; the corpus stood at 24.4 million passages
at the phase gate.
