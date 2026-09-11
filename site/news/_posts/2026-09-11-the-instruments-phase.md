---
title: "The instruments phase: the library learns places and people"
date: 2026-09-11 12:00:00 +0000
description: >-
  Three research instruments enter the library — a historical-China
  gazetteer, a 658,000-person biographical database, and the KITAB
  text-reuse graph — and the first text-mining lane runs: 3.77 million
  place-name candidates over the Chinese canon, plus a dictionary card
  that now says when a word was first written down.
---

The last three phases moved fast — the German print library (the
Deutsches Textarchiv, 5,478 volumes and 729,090 passages of German
from 1473 onward), a Slavic deepening (Slovenian protestant prints,
the Franček dictionary crosswalk, Old Church Slavonic additions), and
a long-tail sweep that carried the shelf past *Beowulf* in facsimile
and Hafez in Persian. The census stands at **2,274,289 documents /
106,877,441 passages across 156 sources and 167 language codes**.

This phase gave the library something different: **instruments** —
reference machinery that mints no texts of its own, but makes the
texts already held answerable in new ways.

**The library now knows where China is.** The fourth gazetteer joins
Pleiades, Trismegistos and the cuneiform site index:
[CHGIS/TGAZ](https://doi.org/10.7910/DVN/H3OB28) (Harvard–Fudan,
CC0), **81,292 historical Chinese placenames** from 221 BCE to 1911,
each carrying its hanzi name, pinyin transcription, valid years and
coordinates. `nabu place chgis:hvd_167661` answers instantly — 大川,
a village-town, coordinates and all.

**And the first text-mining lane ran over the Chinese canon.** With a
gazetteer in hand, the library scanned all 4.57 million passages of
the Kanripo corpus — texts that carry no geographic metadata at all —
for exact Han-character matches against those placenames:
**3,771,151 candidate attestations across 10,055 distinct names**,
each recorded as evidence, never as fact. Precision rules do real
work here (single characters never match, over-common words are
stop-listed by measurement), and the candidates wait for human
review before any document is actually marked as speaking of a
place. The *Yijing* matching 大川 — "the great river" of the hexagram
formulas — is exactly why the review step exists.

**Persons arrive as an instrument too.** The [China Biographical
Database](https://github.com/cbdb-project/cbdb_sqlite) (Harvard /
Academia Sinica / Peking University; CC BY-NC-SA 4.0, confirmed at
first sync) — **some 658,000 persons of Chinese history, 7th–19th
century** — is now held and checksum-verified: names, dates, offices,
kinship, place associations. What surface it grows into (a person
card? person references on documents?) is a decision the library
will take deliberately, the way the places program grew from
gazetteers.

**The Arabic shelf learned its own intertextuality.** From the
[KITAB project](https://kitab-project.org)'s text-reuse statistics
(CC BY-NC-SA 4.0), the library minted **931,943 reuse edges**
between pairs of held OpenITI works — which books quote, excerpt and
rework which, with aligned-passage counts and chronology flags on
every edge. Asking `nabu links` on a held Arabic work now answers
with its textual relatives across eleven centuries.

**And one small, satisfying surface:** the dictionary card now says
when a word was first written down. `nabu define bába --lang sl`
ends the Pleteršnik entry with *"first attested: Primož Trubar,
Katekizem, 1550"* — the crosswalk between a 19th-century dictionary
and the 16th-century corpus it describes, rendered where you look
words up. Alongside it, four more sources joined the dated timeline,
and a batch of era-bound performance assumptions was re-measured
against the hundred-million-passage reality.

As always: everything runs on one machine, every number above is
measured from the live catalog, and the licenses ride each record —
the instruments' non-commercial grants are enforced by the tooling,
not by promise.
