---
title: "The lect layer goes load-bearing — 408,884 stage assignments"
date: 2026-08-04 17:30:00 +0000
description: >-
  One phase after the nabu-lects registry arrived, the library stops
  merely reading it and starts ruling with it: a rebuild-proof journal
  of per-document stage assignments, compiled from the catalog's own
  period labels and per-inscription dates — Sumerian, Akkadian, Latin
  epigraphy, Egyptian and Vedic Sanskrit staged at scale, every
  assignment carrying its evidence and audited against the documents'
  own dates.
---

A week ago the [nabu-lects](https://arvicco.github.io/nabu-lects)
registry gave the library a vocabulary for historical language stages —
`lat:med`, `akk:ob`, `grc:koi` — and a read seam that resolved codes
through it. This phase makes the vocabulary load-bearing: **408,884
journaled stage assignments** (4 August 2026), derived from evidence the
catalog already held and stored in a journal that survives rebuilds,
rides backups, and states its basis on every row.

Three grains of evidence, in the order they were ruled:

- **Period labels** (279,000 assignments): a CDLI or eBL tablet labeled
  *Old Babylonian (ca. 1900-1600 BC)* IS Old Babylonian — the ratified
  rules compile the catalog's period facets into `akk:ob`, the Ur III
  bureaucracy into `sux:ur3` (111,871 documents), AES corpus slices into
  Old and Middle Egyptian, DCS Vedic school tags into `san:ved`.
  Ambiguous labels (*ED IIIb ; Old Akkadian*) match nothing and stay
  honestly bare — every unmatched value is listed in the compile report.
- **Dates × stage bands** (130,000 assignments): an EDR or EDH
  inscription whose dating interval sits inside exactly one stage's band
  carries that stage — containment, never overlap, so a stone dated
  across a boundary stays unstaged. Latin epigraphy, unstaged at
  collection grain by deliberate ruling, is now staged per inscription:
  Classical Latin holds 88,342 documents.
- **Hand rulings**: single-document refinements through `nabu lect
  assign`, which no rule may ever overwrite.

The registry itself grew to meet the corpus: Sumerian minted its
five-stage ladder, proto-cuneiform (`qpc`) became its own anchor with
the field's genuinely open language-identity question stated in its
note rather than decided, and Akkadian gained the Assyriological
six-way Old/Middle/Neo × Assyrian/Babylonian grid.

Honesty machinery shipped alongside: `nabu lect check-dates` audits
every assignment against its document's own dates. On the very first
live run it caught one — an inscription whose extracted dating interval
ran backwards had slipped through containment — and the inference now
refuses reversed intervals outright. The resolved stage is an ordinary
document facet, so `show` prints it, `search --lect` filters by it at
any grain, and every `nabu language` card ends with a live stage ladder.
