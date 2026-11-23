---
title: "The consistent tree, the Syriac shelf, and the slow drip"
date: 2026-11-23 00:00:00 +0000
description: >-
  Five development windows: the codebase restructured in one sitting,
  the public name settled as nabu-ancient-texts, Syriac and Estonian
  sources on the shelves, the crawl rail learning to drip politely
  for weeks at a time, and the store hardened under the hood.
---

Five development windows since the last note, most of them spent on
the machine itself — and the shelves still grew.

**The consistent tree.** The codebase was restructured in one
sitting: the fetch, persons and crosswalk modules moved into their
own homes, the two multi-thousand-line registry files split into one
small file per source, and the three largest code files cut along
their natural seams — with reflection proofs that every public
surface survived byte-identical. A one-command gate now runs the
whole verification pipeline with honest per-step exit codes.

**One name on every door.** The public MCP identity is now
**nabu-ancient-texts** everywhere — the registry id, the container
image, the badges and the catalog entries — taking live effect at
the next release. The library's entry in the official MCP Registry
has been live since early November, and the directories that ingest
it inherit the listing for free.

**The Syriac shelf.** Three sources landed in one wave: Beth
Mardutho's SEDRA lexical database (35,891 entries with their Greek
etyma), the ETCBC Syriac New Testament (27 books, verse-aligned into
the alignment hub beside the Greek witnesses), and the Vienna and
Jerusalem handwritten-text-recognition ground truths (273 manuscript
pages, including a colophon whose own date corrects its catalog
record by nine years — reported upstream).

**The Estonian print mass.** The National Library of Estonia's DIGAR
open corpus: 2,877 books, most printed 1900–1949 with an older
Fraktur tail, read from EstNLTK token tables with the national
bibliography's own records supplying dates, places and genres. The
count reconciles against upstream's catalog to the digit.

**The slow drip.** Some collections meter politely: the Wellcome
Library's early-modern medical prints — about 13,000 Latin volumes
among them — serve one request every thirty seconds by their own
robots rule. The crawl rail now has a trickle runner for exactly
this shape: a detached, resumable background drip the owner starts
and stops with one command, logging its progress for weeks if need
be, never faster than the house asks. The first drain is running.

**Under the hood.** The full-text index learned to tell a brand-new
source (a pure append, cheap) from a rewrite (the expensive shape),
per-source accounting now updates as the loaders write, and the
derivation stamps gained a proof-based fast path after pure
refactors. The library stands at {{ site.data.census.documents_display }}
documents and {{ site.data.census.passages_display }} passages across
{{ site.data.census.live_sources }} live sources.
