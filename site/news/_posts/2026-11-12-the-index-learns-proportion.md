---
title: "The index learns proportion"
date: 2026-11-12 00:00:00 +0000
description: >-
  Two phases of database work before the next full rebuild: search
  index writes that stay proportional to what changed, lanes in their
  own files with crash-honest swaps, rebuild runs that can no longer
  die silently, and a watcher that turns an engine stall into a
  visible, timed event. Plus a new SQLite engine.
---

**The write path now owns its merges.** The full-text engine used to
decide for itself when to pay down its structural debt, and twice it
chose the worst possible moment: a routine refresh landed its rows in
minutes, then sat for nine hours inside a single statement while the
engine reorganized a multi-gigabyte index around it — silent,
unkillable, invisible. A merge governor now meters that work in small,
announced, interruptible chunks on every write path, with a
crisis-distance invariant that keeps the engine's own panic threshold
permanently out of reach. The hours-class stall class is retired at
its source.

**Writes are proportional to the change, and the suite enforces it.**
A small delta used to trigger whole-source recomputations in several
corners: character postings were rebuilt from a full catalog scan on
every sync, the cognate-root closure re-walked the corpus on any
lemma change, and a healed source re-censused everything. Each of
those now moves by exact arithmetic over just the changed rows, with
an honest fallback: where the delta grain cannot be proven sound, the
aggregate is flagged stale and a new maintenance command —
`nabu index maintain` — recomputes it between sessions, consolidates
leftover merge debt to a no-op, and reports the index's structural
gauges. The proportionality law itself is written into the
architecture document, every indexing stage declares its cost class
in code, and a suite invariant times the declared-proportional stages
on two sources sixty times apart in size — a stage whose wall time
follows the source, not the delta, fails the build.

**Big rewrites stopped grinding and started swapping.** Above a
100,000-row budget, an in-place index rewrite becomes a shadow build:
the new content is written append-only into a fresh structure, then
swapped in atomically and the old dropped whole — no tombstones, no
merge debt, nothing for the engine to grind. The same pattern now
protects the substring-search lanes end to end: the CJK bigram and
trigram lanes live in their own database files, each rebuilt by
writing a new file and renaming it over the old, so a build that dies
leaves the previous index serving untouched. That last property was
paid for: a rebuild that crashed mid-reindex this month silently
emptied the CJK lane for thirteen sources, and nothing noticed for a
day.

**Runs can no longer die silently.** That incident had a second
lesson: a killed rebuild left no trace — its only evidence was the
absence of rows. Every rebuild now records its run at start and
stamps completion as its last act, stage timings flush as each stage
finishes, and `nabu status` and `nabu index doctor` say loudly when
the last run never completed. The doctor also audits lane coverage —
configured sources against built scope against actual rows — so an
empty or partial lane is a finding, never a quiet absence. And
because the engine can stall inside a single statement where no
in-process timer can fire, every index-writing command now forks a
small watcher process that reads the writer's heartbeat from outside,
narrates a stall while it lasts, and — for bounded operations — can
kill the writer and restore the engine configuration a crash would
otherwise leave corrupted. Rebuilds themselves are never killed on a
guess: the watcher narrates them and leaves the decision human.

**Under it all, a newer engine.** The bundled SQLite moved from
3.53.2 to 3.54.1 after a side-by-side comparison of compile options,
journaling defaults, index structure records and merge behavior found
no divergence — the upgrade was adopted deliberately, so the next
full rebuild of the library is built by the engine the whole regime
was verified against.
