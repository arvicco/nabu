---
title: "The Romance phase: Latin's daughters take a desk"
date: 2026-07-25 18:30:00 +0000
description: >-
  Phase 45 builds the Latin-to-vernacular continuum as a research desk
  of its own: the MGH critical editions, late-antique prose, Old French
  from the Serments de Strasbourg to the fifteenth century, and the
  Romance treebanks — while the meter layer doubles and place lookups
  drop from seconds to milliseconds.
---

The library's Latin has always been classical. This phase follows it
forward — through the late-antique transition band, the medieval
chronicles and charters, into Old French — and gives the continuum a
desk of its own: **romance**, the twenty-first, beside the classical
desk it grows out of. *The Romanist — the Latin-to-vernacular
continuum, charter Latin to Roland to the troubadours.*

Four shelves opened it in one day. **openMGH** brings the critical
edition backbone of medieval Latin — the Monumenta Germaniae
Historica in TEI, CC BY 4.0, texts themselves free of copyright — with
a first wave of the complete *SS rerum Germanicarum* series: Einhard,
the Frankish annals, Widukind, Adam of Bremen, fifty-seven volumes.
**digilibLT** covers the approach: 370 late-antique secular prose
texts, the second through seventh centuries, machine-lemmatized and
honestly labelled `[silver]`. **BFM**, the Base de français médiéval,
carries the vernacular side — 6.4 million words of Old and Middle
French under France's open Etalab license, from the 842 *Serments de
Strasbourg* onward. And the **UD Romance treebank pack** adds the gold
annotation: Tuscan charters of the 770s, Dante's Latin, Old French,
Old Romanian — four new gold-lemma languages in one config change.
CroALa's Croatian Latin, last phase's arrival, dual-tags onto the desk
as the continuum's Latin side.

The phase's riders sharpened two instruments. The **meter layer**
grew its maps from evidence against the live catalog — 82 Latin works
crosswalked and 79 of 88 Greek scansion files matched, which is how a
mismapped seed entry (Lucretius pointed at Catullus) was caught and
its false rows purged — and the layer doubled to **167,732 scanned
lines**, with a first query surface: `nabu search --meter H` filters
hits to hexameters, honestly footnoted with where the scansions come
from. *Iliad* 1.1 now carries its meter line. And the **Pleiades
gazetteer** moved into a derived SQLite index: a place lookup that
cost five seconds and four gigabytes of memory now answers in
milliseconds, byte-identical, rebuilt from canonical bytes like
everything else.

The library stands at 813,257 documents / 65.1 million passages in
115 language codes, 89 sources all wired, gold lemmas in thirty-two
languages. Local, license-honest, rebuildable — now from Sumer to the
troubadours' doorstep.
