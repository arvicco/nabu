---
title: "The Japanese phase: Aozora Bunko and the honest-glyph ladder"
date: 2026-07-21 22:00:00 +0000
description: >-
  Phase 38 opens the Japanese reading desk — an adapter for Aozora
  Bunko's 17,000-work public-domain library — and replaces the blank
  rare-character placeholder with a four-rung display ladder that
  shows the most faithful rendering the evidence supports.
---

Phase 38 answers a simple complaint honestly: a rare character shown
as an empty box is honest but unhelpful. The new display ladder gives
every not-yet-encoded character the most faithful rendering the
evidence supports — the real codepoint where one exists, an
ideographic description sequence (⿰氵丐) where only the composition
is known, a visibly marked substitute ⌈…⌉ where the tradition offers
a stand-in, and the placeholder box only as a true last resort, with
a footer that always says what was substituted or left unresolved.
Along the way the audit caught a real bug: 547 of the "faithful"
glyphs shipped in Phase 37 were private-use codepoints — tofu on any
machine without one specific font — and are now honestly demoted.
Visible characters rise from 36% to 82% of rare-glyph occurrences,
and none of them lie.

The phase's second half opens the Japanese desk properly. An adapter
for **Aozora Bunko** — the volunteer-built library of Japanese
literature — covers its ~17,500 public-domain works: ruby (furigana)
readings preserved as annotations rather than flattened into text,
the base-text colophon carried as provenance, and Aozora's own
rare-character notation resolved through the JIS X 0213 standard
mapping — while the fetch pulls the ~210 MB of actual text from a
23 GB upstream mirror by sparse checkout. A 173-pair old-form↔new-form
kanji fold, derived from Unicode's own name-kanji data and composed
with the existing Chinese fold, lets 国 and 國 meet on one search
skeleton, and the character card now cross-references both forms.
Numbers as of 2026-07-21; the first Aozora sync is owner-scheduled.
