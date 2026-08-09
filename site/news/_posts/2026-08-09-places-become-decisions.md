---
title: "Places become decisions — the third dimension lights up"
date: 2026-08-09 15:45:00 +0000
description: >-
  Two phases of the places program land: the gazetteers of the ancient
  world held locally under one namespaced index, a sister registry that
  records which place each source's name-string actually means, and a
  3.9× jump in place-linked documents — 151 thousand to 585 thousand.
  Plus a new pattern for data only a human can download, and the
  registry's license to mint places of its own.
---

The library has always known *when* better than *where*: 708,905
documents name a findspot, but until this week only 151,157 carried a
machine-readable place identity. Two phases later the count is
**585,682** — Girsu's 37,000 tablets, Roman Milan's thousand
inscriptions, and the Coptic monasteries of Upper Egypt all answer
`nabu place` now.

Three pieces made it happen. First, the gazetteers themselves came
local: [Pleiades](https://pleiades.stoa.org/) (42,284 places),
[Trismegistos Geo](https://www.trismegistos.org/geo/) (64,857 — of
which more below), and [CIGS](https://zenodo.org/records/14568765), the
Uppsala site index of the cuneiform world, whose `legacy_name` column
turns out to be byte-identical to CDLI's own provenience strings — the
key that unlocked a quarter-million tablets. One namespaced index holds
them all; equivalences between them ride as crosswalk *data* (CIGS's
own columns, plus a Wikidata harvest), never as guesses.

Second, [nabu-places](https://arvicco.github.io/nabu-places/) — the
third sister registry, after the datasets and the lects. It records the
**matching decisions**: that EDR's "Mediolanum" is the Insubrian Milan
and not one of five homonyms, that "Irisagrig (mod. uncertain)" is
*unlocatable* because the site genuinely is, that "Middle Egypt (from
Kairo to Assiut)" is a regional bin and not a place. 550 rows so far,
every one reviewable, and an unlisted name stays visibly unmatched —
coverage claims can't inflate. The registry can also **mint its own
place records** where text-analysis scholarship establishes a place no
gazetteer registers — each with a required evidence trail.

Third, a new acquisition pattern. Trismegistos's dump sits behind a
security check no script should try to defeat — so the library stopped
pretending otherwise: `nabu sync trismegistos-geo` prints the exact
browser steps, and when a human drops the download into `incoming/`, it
validates, archives the previous holding, and stamps full provenance.
High-value data that only a person can fetch is now a first-class
source, not a parked thread.

The census, honestly: twelve upstream references cite Pleiades ids that
don't exist (digit-swapped, mostly — the audit found the real ids), the
long tail below the curated waves stays unmatched, and rundata's Norse
parishes want coordinates, not a classical gazetteer. All of it is on
[the new Places page]({{ '/places/' | relative_url }}).
