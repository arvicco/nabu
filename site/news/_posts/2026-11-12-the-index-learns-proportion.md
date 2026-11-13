---
title: "Search that stays fast as the library grows"
date: 2026-11-12 00:00:00 +0000
description: >-
  Two phases of foundation work on the search index: no more silent
  stalls, no more silent losses, and syncs that stay quick no matter
  how large the library gets.
---

The library is closing in on three million documents, and this round
of work was about one promise: **search keeps working, at full speed,
while the library grows under it.**

What that means in practice:

- **No more freezes.** The search engine used to pick its own moment
  to reorganize its index — once sitting unresponsive for nine hours
  in the middle of a routine update. That maintenance now happens in
  small, announced, interruptible steps, and the stall class is gone
  at its source.
- **Updates cost what they change.** Adding a small source used to
  trigger recomputations across the whole library. Every index update
  now does work proportional to what actually changed — a test fails
  the build if any stage's time starts following library size instead
  of the size of the change.
- **Nothing vanishes quietly.** A crash during a rebuild once emptied
  the Chinese-Japanese-Korean search lane for thirteen sources, and
  nothing said so for a day. Index builds now swap in atomically — a
  failed build leaves the previous index serving — and `nabu status`
  says loudly when a rebuild never finished or a search lane is
  missing rows it should have.

None of this changes what you type. It changes what you can rely on:
a query against a growing multi-million-document library answers in
the same breath it did when the library was a tenth the size.
