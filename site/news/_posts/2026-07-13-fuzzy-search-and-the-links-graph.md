---
title: "Fuzzy search and the links graph"
date: 2026-07-13 09:00:00 +0000
description: >-
  Phase 16 (PR #20): trigram fuzzy search for damaged texts, and a
  persistent citation graph fed by parallels, formulas, and cognates.
---

Phase 16 merged on 2026-07-13 (PR
[#20](https://github.com/arvicco/nabu/pull/20)). Two capabilities
headline it, written up retrospectively as this News section opens.

**`search --fuzzy`** brings trigram matching to the damaged documentary
corpora: a lacuna-riddled papyrus reading can now find its literary
source even mid-word (the demonstration case matches a Berlin papyrus
school exercise to its Odyssey line). The index measured 257 MB and
built in 8.6 seconds on the scratch corpus, with 0.7–6.5 ms queries.

**The links graph** gives the library a third kind of data alongside
canonical files and the rebuildable catalog: a persistent journal of
mined cross-references that survives `nabu rebuild`. Three batch
producers feed it — `parallels --batch` (quotation edges; 5,089 from the
Matthew anchors alone), `formulas --batch` (repeated-phrase stars), and
`cognates --batch` (shared-root edges with the meet shelf recorded on
each edge). `nabu links URN` reads the graph back, every edge carrying
the provenance of the run that produced it. The date/place axis also
grew its second installment: ORACC regnal and eponym dating brought the
dated corpus to 83,233 documents at the subsequent rebuild.
