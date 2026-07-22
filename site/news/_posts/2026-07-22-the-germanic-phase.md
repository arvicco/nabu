---
title: "The Germanic phase: from two languages to all three branches"
date: 2026-07-22 22:00:00 +0000
description: >-
  Phase 40 widens the Germanicist's desk from Gothic and Old English to
  all three Germanic branches — Old Icelandic, Old Norwegian and the
  Poetic Edda, the Old Saxon Heliand, Middle High German, and the runic
  inscriptions — through two new parser families, a sibling, a custom
  reader, and one registry line.
---

The Germanicist's desk began Phase 40 with two languages: Gothic on the
PROIEL treebank and Old English across the ASPR poetry and the ISWOC
prose. It ends with seven language codes and the runic corpus, spanning
all three Germanic branches. The five additions arrive by four different
routes, each the smallest that upstream's shape allowed — proof that a
corpus this varied needs no bespoke engine per source.

Two of the five are **new parser families**. The Old Saxon *Heliand*
comes through HeliPaD's Penn-style labelled bracketing — a `.psd` grammar
of fused form-lemma leaves and in-tree metre and codicology markers, the
first of a Penn-treebank family with YCOE and IcePaHC as planned
siblings. Middle High German comes through ReM's CorA-TEI export, a
diplomatic transcription that keeps the long ſ and its combining
editorial marks exactly as the manuscript carries them, with the
normalised and lemmatised layers riding alongside as gold. The Poetic
Edda of Codex Regius and the Old Norwegian treebanks come through
**Menotec** — reusing the PROIEL token shape as a sibling stream parser,
because Menotec is served only through the CLARINO INESS portal's
ephemeral-session REST API, not a public repository: every fetch opens a
session, lists the treebanks, and pulls their sentences one export at a
time. Old Icelandic needed no adapter at all — IcePaHC is a rule-based UD
conversion, so it joins as **one registry line** on the existing
Universal Dependencies source, filing the 12th-to-21st-century corpus
under the one modern tag `is` (the Middle-Russian-under-`orv` precedent,
recorded not hidden) and opening the library's first Icelandic lemma lane.

The fifth is the runes. **Rundata** — the Scandinavian Runic-text
Database, roughly 6,800 inscriptions — arrives through a custom reader
over the database's own SQLite artifact, and it taught the library two
honest lessons. First, there are **no runic codepoints to display**: the
database records every inscription in the scholarly Latin transliteration,
and that transliteration *is* the canonical text, not a rendering of some
rune layer that was never stored — the notation legend (section marks,
word boundaries, the leading quote that marks a name) is content and
survives untouched. Second, each inscription fans out into up to five
sibling lanes — the transliteration, two Norse normalisations, and
English and Swedish translations — reached with `show --parallel`, the
same surface the Homers and the Assyrian letters use. Rundata is also the
desk's first **dated** lane: its parsed year envelopes and find-spots put
the runestones on the timeline, so `--century` and `--place` will scope
them once synced, with the urnordisk inscriptions tagged `gmq-pro`
(Proto-Norse — no ISO code exists). Its open-data licence, ODbL, is a new
class the store learned this phase.

All five shelves are adapter-ready with their first sync owner-scheduled;
the holdings on the desk page read "not synced yet" until then. The
numbers as of 2026-07-22 are the fixtures' and the database's own —
HeliPaD's single 3,549-passage *Heliand*, Rundata's ~6,800 inscriptions —
not projections; the real counts land the day the owner fires each sync.
