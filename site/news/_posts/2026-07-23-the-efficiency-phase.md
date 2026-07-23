---
title: "The efficiency phase: the library rebuilt, and every command flies"
date: 2026-07-23 16:00:00 +0000
description: >-
  Phase 42 rebuilds the doubled library from canonical sources in under
  five hours and retires every slow command: status drops from four
  minutes to two seconds, vocabulary profiles from eighteen seconds to
  half a second, and searches for the commonest words in the corpus
  answer instantly with an honest footer.
---

The Arabic phase doubled the library to 62.8 million passages, and the
commands that had quietly assumed a smaller corpus began to crawl:
`status` took minutes, a vocabulary profile eighteen seconds, a search
for الله ten. Phase 42 is the answer, and it is architectural rather
than heroic. The rule now written into the architecture document:
**anything that costs the whole corpus runs at write time; read time is
for probes.**

The census that `status`, `list`, and every axis and language card
used to recompute on demand is now a derived table the loader maintains
as it writes and every rebuild re-derives from scratch. The
lemma-frequency totals behind `vocab` and `etym` moved to the same
write-time shelf. Search learned two new honesty tricks: a language
column inside the full-text index itself (no more starving pages when a
language filter meets a ranked window), and a ubiquity guard that
serves the commonest words in corpus order with a footer saying so,
instead of asking bm25 to rank six million matches. Term-less browsing
became legal — `nabu search --from 1300 --to 1400 --axis arabic` walks
the fourteenth-century Islamicate shelf with no query term at all, the
mode half our recipes always wanted.

The full rebuild that paid for all of it ran four hours and fifty-one
minutes: 810,180 documents re-derived from canonical bytes alone,
62.8 million passages re-indexed, per-source counts byte-identical
with the previous clean derivation. The after-matrix reads sub-second
where the before-column read minutes; the one measurement that
resisted — bm25's cost turns out to follow the physical locality of a
term's postings, not just its frequency — recalibrated the guard's
threshold with a measured curve rather than a guess.

Permission-bound sources also gained a proper front door this phase: a
source whose fetch right comes from a personal grant rather than a
public license now asks for a typed acknowledgment once, records it
durably, and steps politely out of `sync --all` until it has one.
