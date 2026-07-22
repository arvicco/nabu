---
title: "The registry phase: what a thing is, and what it costs"
date: 2026-07-22 20:00:00 +0000
description: >-
  Phase 39 teaches the library to say what each registered thing is —
  source, shelf, or module — makes rebuild stamps language-aware,
  finds two real performance bugs by their names, and recovers all
  1,191 quarantined Aozora works in one census.
---

Phase 39 is the housekeeping a tripled library earns. The registry's
84 rows now declare what they are: 78 upstream sources, 4
owner-written shelves, 2 feature modules — and the status board
groups them honestly, fuses enablement with sync cadence, and shows
upstream freshness from real probe data. It paid for itself on its
first render, flagging both Perseus shelves as behind upstream.

The engine work found two named culprits. Aozora's 49-minute load was
seventeen thousand `unzip` subprocesses — replaced by an in-process
reader, 146× faster at fixture scale. And the Chinese shelf's
slowdown traced to a Ruby standard-library quirk: `String#tr`
rebuilds its 6,050-entry translation table on every call, so every
passage of 13 million paid the setup; the precompiled replacement is
325× faster with byte-identical output. Rebuild stamps also became
language-aware — a Japanese fold tweak now dirties Japanese shelves,
not all 84 rows — with an owner-gated blessing tool so the formula
change itself costs nothing.

The aftercare closed honest gaps. A from-scratch rebuild had quietly
minted one URN three times: three distinct volumes of Diodorus
Siculus sharing a reused catalog number — now disambiguated, with
collisions loud forever after. All 1,191 quarantined Aozora works
turned out to be a single class — plain-text files predating the
header convention — and parse again under their censused legacy
shape; 85% of the remaining rare-glyph boxes resolve through the JIS
standard table they always carried. The character ladder's
composition rung now draws 244 unencoded glyphs by their own recipes
(⿰口斗), refusing everything it cannot prove. Numbers as of
2026-07-22; the recovering re-syncs are owner-scheduled.
