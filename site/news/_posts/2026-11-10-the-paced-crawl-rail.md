---
title: "The paced-crawl rail, and a sharper demo image"
date: 2026-11-10 00:00:00 +0000
description: >-
  Long-horizon crawls become a first-class adapter type with a tested
  contract — slice reports that reconcile, zero-yield slices that
  explain themselves, a chain runner that stops loudly. Plus a demo
  image that now carries every search lane, restored special
  characters in the statutes, and a progress ticker that stays on one
  line.
---

**Long-horizon crawls grew a spine.** Sources served one item at a
time over months of polite requests — the National Diet Library's
classical-materials OCR, the Wellcome Collection's cone — previously
each hand-rolled their own slice loops and refusal ledgers. They now
ride a shared paced-crawl engine with a tested contract: every slice
prints a reconciliation (census = held + ledgered + remaining, or a
loud mismatch), its frontier position and movement, refusal evidence
verbatim, and — when a slice yields nothing — a self-classification
that distinguishes a refusal stripe being crawled through from an
upstream block (one automatic re-probe of a held item settles it) or
the cone's honest end. A chain runner drives multi-slice runs and
stops loudly after a declared budget of zero-yield slices. The
architecture document's new §19 describes the rail, including which
crawlers deliberately stay off it and why: one-pass catalog walks
and multi-stage fetches are different shapes, and the engine does
not pretend otherwise.

The first beneficiary was a diagnosis: the NDL crawl had spent forty
minutes "doing nothing" — the new reporting shape shows it was
working invisibly, ledgering its way through a finite stripe of
undownloadable identifiers, with a servable mass of several thousand
books waiting behind it.

**The demo image got sharper twice.** Yesterday's v1.8.0 image
shipped, and the eval pack promptly earned its keep: the ligature
headline ("Matthaeus 1.23 finds the Vulgate's Matthæus") failed
against the published image because demo slices never carried the
clarify index at all — reference resolution ran on fuzzy fallback.
The slice build now derives the clarify, annotation, gloss-line and
translation lanes directly, so the republished image resolves
references exactly and serves the Hebrew Bible's notes and
Achemenet's gloss lines to `--annotations` and `--gloss-lines`
search. The release rail itself was hardened end to end: the publish
refuses a slice cut for a different release, a stopped Docker daemon
gets one plain line instead of a stack trace, and the on-release
smoke now tests the release's own tag rather than whatever `:latest`
held.

**The statutes got their characters back.** British History Online
confirmed our report that a recent update of theirs had been
stripping special characters, and fixed it; a re-fetch of all 661
Statutes of the Realm pages restored the scribal contractions (Dñi,
cõ), currency and section marks (£, §) and ligatures the earlier
window had silently lost — 515 documents revised, searchable
fold-aware. Their editor also settled a dating puzzle: the "1698-9"
session heading is the official print reproduced as-is, not an
error, and the adapter now documents that ruling so the variance is
never re-reported.

**And the terminal stays readable.** The rebuild's progress ticker
rendered its in-place updates without clamping to the terminal
width, so a long stage label soft-wrapped and every tick scrolled a
permanent line — millions of them across a full rebuild. Every
carriage-return progress line now fits the live terminal width, one
physical line per stage, with the label giving way and the moving
count always visible.

As always, the census figures on this site are generated from the
live catalog, not hand-kept.
