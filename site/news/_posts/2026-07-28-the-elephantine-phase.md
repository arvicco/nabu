---
title: "Elephantine: one island, four thousand years"
date: 2026-07-28 05:30:00 +0000
description: >-
  Phase 47 crawls the Berlin Elephantine archive — the Judean
  garrison's Imperial Aramaic beside Greek, Demotic, Hieratic and
  Coptic — and turns the incident trail into infrastructure: every
  catalog lane now refreshes at sync and is guarded by health checks.
---

The island fortress at the First Cataract is the richest multilingual
documentary site of the ancient world, and its Berlin edition is now
on the shelves: **15,539 documents / 69,350 passages** crawled
politely from the ERC project's 10,744-object database — the Judean
garrison's **Imperial Aramaic archives** (892 texts in Hebrew script,
with the Imperial Aramaic numeral signs intact), Greek ostraca and
petitions, Demotic and Hieratic in Egyptological transliteration,
Coptic and Arabic — each text under its own in-file CC BY-SA grant,
with the project's English translations riding as parallel documents.
`show --random --source elephantine --parallel` draws a salt-tax
receipt and its translation side by side; `search --century -5
--source elephantine` answers with a petition to the strategos of the
upper districts.

The phase's quieter half may matter more. The first live queries
found lanes the data should have lit but didn't — and the audit that
followed generalized the finding: the **facet** and **timeline**
lanes refreshed only at full rebuild, so every recently synced source
served them stale. All of it is now healed and structural: the
timeline covers **687,393 dated-and-placed documents** (Italy's EDR
inscriptions and BFM's *Vie de saint Alexis* joined in the same
sweep), the facet lane holds 2.35 million rows (IIP's plural-valued
facets included, caught by a brand-new health check *during* the
audit), every sync now refreshes both lanes for its source, and two
standing health invariants make a dark lane loud.

The fragment desk grew to match: the `--fuzzy` trigram index now
covers **3.8 million passages across six documentary shelves** — the
papyri, the cuneiform mass, Heidelberg's provinces, Italy's EDR,
open-etruscan, and Elephantine itself, where a torn `]כספ[` finds
the silver.

Local, license-honest, rebuildable — and now with the island that
wrote home in five scripts.
