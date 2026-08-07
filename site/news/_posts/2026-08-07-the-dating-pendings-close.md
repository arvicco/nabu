---
title: "The dating pendings close — three gaps, three different causes"
date: 2026-08-07 14:45:00 +0000
description: >-
  Wave two of the core-layers plan: the three biggest dating gaps in
  the library close, and each turns out to have a different real cause
  than the survey guessed — a directory one level deeper than the
  walker looked, sibling documents that never inherited their stone's
  date, and a period vocabulary nobody had banded. Plus one ruled
  table now answers "when is Ur III?" for every consumer at once.
---

The coverage survey said three sources held dates the library wasn't
reading: ORACC (~82,000 documents), Rundata (~24,000), and eBL
(~23,000). All three closed this wave — and each gap had a cause the
survey didn't predict, which is the argument for scouting before
building.

**ORACC's was one glob depth.** The catalogue files that carry period
labels live at varying depths under each project, and the biggest
project of all — the Ur III administrative corpus, eighty thousand
tablets — unpacks its catalogue three levels down where the extractor
walked two. The fix is a recursive walk and a real triply-nested
fixture pinning it. The same catalogue read now emits each tablet's
period as an ordinary document facet, which means the Akkadian and
Sumerian stage rules — which have mapped period labels to historical
stages since the lect layer landed — reach ORACC's own labels too.

**Rundata's was inheritance.** The undated documents were never
undatable: they are the translation and normalization lanes of stones
whose base inscription parsed its scholarly dating years ago. The
lanes now inherit their stone's band through the shared signum — a
rendering of a dated artifact is dated by the artifact, the same
reasoning the ORACC English witnesses have always used.

**eBL's was vocabulary.** The survey flagged forty Seleucid-era
day/month objects needing era conversion; the real pending was
twenty-three thousand documents carrying plain period labels
("Neo-Assyrian", "Sargonic") that no dating lane read. They band now
— and the Seleucid forty band coarsely under their period, with exact
era conversion recorded as deliberately out of scope.

Under all three sits one new ruled artifact:
**`config/period_bands.yml`**, a single period→band table whose
conventions are cited row by row — CDLI's own parenthetical dates
("Ur III (ca. 2100-2000 BC)") where the field states them, middle
chronology elsewhere, and honest refusals for labels like "Uncertain"
and for "Standard Babylonian", which is a register, not a period, and
would mint an invented date. The timeline extractor's private copy of
that knowledge retired in the table's favor: one answer to "when is
Ur III?", shared by every consumer.
