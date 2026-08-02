---
title: "v1.4.0 + nabu-data v1.0.0 — the loop closes"
date: 2026-08-01 15:30:00 +0000
description: >-
  A synchronized double release: Nabu v1.4.0 — the signs desk, the
  Tibetan consumers, the granted sources — and the first tagged
  release of nabu-data, twelve published datasets with full
  derivation provenance, three of them consumed back by the library
  that produced them.
---

Two releases, cut together, because they are one story.

**[nabu-data](https://github.com/arvicco/nabu-data) v1.0.0** is the
library's publishing arm made real: **twelve datasets** — Sanskrit
form-to-lemma from DCS gold, the Tibetan Wylie fold and verb paradigms,
a segmented Classical Tibetan slice with its boundary F1 published
in-band, Greek metrical scansions anchored to Perseus CTS, the Han and
kyūjitai orthography folds, the Aozora and Kanripo gaiji censuses, the
Sabellic loanword table, the cuneiform value-to-sign table flattened
from the Oracc Sign List, and — the release's centerpiece — the first
**re-publication**: stable anchors for ACTib's segmented eKangyur,
461,301 rows tying every Derge Kangyur passage to its ACTib line by
citation *and* content fingerprint, with the measured match census
(99.51% letter-exact) in-band and the 2,245 divergent lines published
side-by-side as a proofreading worksheet. Every dataset is plain CSV
with a Frictionless Data Package manifest naming the exact upstream
version, the producing code version, and a re-runnable recipe. CC BY
4.0, three share-alike carve-outs stated per dataset.

**Nabu v1.4.0** is everything since v1.3.0 — six phases in six days:

- **The Elephantine and Tibetan phases** (their own posts below): the
  island's thirteen-language documentary record, and the Tibetan desk
  whole — the Derge Kangyur and Tengyur, the Old Tibetan editions, the
  gold treebanks and lexica, folio-paired parallel reading.
- **The signs desk**: `nabu signs` resolves ATF transliteration —
  a catalog urn or raw pasted text — token by token through the Oracc
  Sign List into sign identities: value → sign name → Unicode
  codepoints, with one honest status per token and every ambiguity
  listed rather than guessed. Built for
  [Edubba](https://arvicco.github.io/nabu-edubba), the scribal-school
  sister project, whose reading panels consume the frozen `--json`
  contract; the twelfth MCP tool serves the same payload.
- **The consumers**: the two-way loop closed in public. The published
  segmentation dataset now trains the library's own segmenter —
  `show --segmented` renders Tibetan word-split, `search --words`
  keeps only word-boundary-aligned hits — and the published verb
  table feeds dictionary lookup, so ཕྱིན finds འགྲོ (suppletion only
  the table knows). Three of the twelve datasets are consumed back
  from the published files; the other nine are one-way by design.
- **The granted sources**: two shelves that exist because coordinators
  answered letters. The complete secular Galician-Portuguese lyric —
  1,676 cantigas at verse grain, under Projeto Littera's written
  any-use grant — and the Ras Shamra Tablet Inventory: 5,075 inventory
  cards with the KTU/CTA concordances the field actually cites,
  published editions at line grain, under U. Chicago CORPUS/OCHRE's
  NC-SA grant, with the project's credit rendered on every surface.
  Sefaria's classical midrash (the ten Rabbah collections and the
  Midrash Halakhah shelf) joined the same week.

The census at the tags: **974,972 documents / 68,381,456 passages in
125 language codes across 108 sources**, 1.4 million dictionary
entries, twenty-three research desks — and, for the first time, a
data repository going the other way.
