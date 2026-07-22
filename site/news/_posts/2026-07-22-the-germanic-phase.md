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

Four of the five went live the same day, on owner-verified first syncs
(22 July 2026): Menotec's seven treebanks and the Edda at 20,308
sentences; the *Heliand* at exactly the 3,549 tree blocks the fixture
predicted; ReM at 406 manuscripts and 355,449 diplomatic lines — making
Middle High German the corpus's third-largest gold-lemma pool (2.10
million rows) on day one, after a same-day fix taught the citation
scheme about two-column codices (folio 5r, column a, line 1 is
`5ra.1`); and Rundata at 30,643 lane-documents across its five text
lanes. Old Icelandic followed the same day via the Universal Dependencies
sync — straight in at fourth place among the gold-lemma pools.
The desk page's holdings are read live from the catalog, dated.
