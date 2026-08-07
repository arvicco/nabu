---
title: "Every source answers for its layers"
date: 2026-08-07 00:00:00 +0000
description: >-
  The core-layers frame lands: one posture file where all 77 sources
  answer for dating, places and script; the script projection goes
  live (search a corpus by the script its texts are actually written
  in); the artifact-script field marks where the original differs from
  the held page; and two new standing audits — one of which caught
  twelve dangling gazetteer refs on its first run.
---

The lect layer earned its "core" status by having answers on file:
every source declares what it claims, honest ignorance included. This
phase extends that discipline to three more layers. One consolidated
posture record now holds, for **all 77 passage-serving sources**, a
ruled answer on four axes — lect, dating, places, script — with
`undatable`, `unplaced` and `implied` as first-class honest answers,
and the test suite refusing any source that goes silent. A new front
door, `nabu layer suggest`, reports what a source declares beside what
its upstream carries but doesn't yet serve: date-shaped metadata on
undated documents, gazetteer URLs on unlinked ones, script suffixes
with a byte-check verdict on what the held surface actually is.

The script axis went from grammar to **live projection**. Twenty-seven
codemap rows — every one byte-verified against the held passages
before earning its line — plus a handful of per-source rulings now
mint 3,424 `~script` claims, so the slices are real queries:
`--lect sga~ogam` returns Old Irish as the ogham stones render it,
in actual Ogham codepoints. Where a code's suffix names the
*artifact's* script rather than the page's — the Demotic ostraca held
as Latin transliteration, the Old Italic inscriptions held romanized —
the claim splits honestly: the lect id says `egy~latn` (what you will
read), and a new **artifact-script field** says `egyd` (what the scribe
wrote). One catalog even repaired itself on the way through: eight
Gaulish passages carrying a truncated `xtg-Lat` tag, upstream's typo
beside its own correct `xtg-Latn`, normalized with the offending file
pinned as a regression fixture.

Two standing audits close the loop. The script check re-runs the
byte-census forever: any `~script` claim whose sampled passages
classify to a different writing system is flagged loudly — a claim
that can be checked is a claim that stays true. And the places
analogue — gazetteer refs that no longer resolve against the local
index — caught **twelve genuinely dangling references on its first
live run**, malformed upstream ids that had sat unnoticed in two
hundred thousand rows. That is the whole argument for the layer
discipline, in one health line.
