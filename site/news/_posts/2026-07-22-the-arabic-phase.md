---
title: "The Arabic phase: the Islamicate library, staged"
date: 2026-07-22 16:30:00 +0000
description: >-
  Phase 41 opens the Arabist's desk on OpenITI — premodern Arabic and
  Persian at corpus scale, the largest single corpus the library has ever
  staged (~9,106 texts / ~1.12 B words), read through a bespoke mARkdown
  parser, an AH death-year timeline, and a shared Arabic-script search fold
  that makes Arabic and Persian cross-searchable.
---

The library's gap survey had one headline hole: for all its Semitic and
Indo-European reach, it held almost no Arabic and no Persian — a handful
of documentary papyri against a written tradition that runs from the
Quran and the hadith through a thousand years of history, law,
*falsafa*, and the poetry of the dīwāns. Phase 41 executes that headline.
The Arabist's desk opens on **OpenITI** — the Open Islamicate Texts
Initiative — and it arrives as the single largest corpus the library has
ever staged.

OpenITI's texts are written in **OpenITI mARkdown**, a bespoke
structured-plaintext markup: a magic first line, a `#META#` header whose
vocabulary is source-dependent (four distinct schemes appear across the
sampled texts — KITAB-numbered, Shamela-legacy Arabic keys, a minimal
PDL/Ganjoor set, and eScriptorium OCR metadata), then structural section
headers (`### |` through `### |||||`), paragraph and wrapped-line markers,
inline page and milestone references, and — for verse — two different
hemistich notations, the Persian `%~%` form and the legacy Arabic
`# % hemi % hemi % no`. The parser family reads that shape into passages
without cleaning any of it: canonical means canonical, down to the leading
byte-order mark on the one hadith text kept whole and the OCR footnote
digits fused to their words.

The scale is the story. The central metadata index lists **14,107 text
versions / 2.35 billion words**; the first wave takes the primary
versions and sets the documentary MSS sub-corpus aside. The sync ran the
same evening — a ~5.9 GB release archive plus its metadata index, both
md5-pinned before a single tree file was written — and landed **9,079
documents / 34,631,499 passages** (27 malformed upstream files
quarantined honestly, 0.3%). **The library more than doubled in a day**,
and Classical Arabic entered as its largest language: 33.3 million
passages, ahead of Literary Chinese's 13.2 million, with the Persian
shelf at 1.3 million.

Two mechanisms make the shelf usable the day it lands. The first is the
**Arabic-script search fold**: Arabic and Persian are written in the same
script but on different keyboards — Persian uses farsi yeh (U+06CC) and
keheh (U+06A9) where Arabic uses yeh (U+064A) and kaf (U+0643) — so a
naïve search would split the two traditions apart. The fold neutralizes
that split (ی/ي, ک/ك, plus maqsura, taa marbuta, tashkeel, tatweel and
ZWNJ) into one indexed skeleton, symmetrically at index and query time, so
a query typed on either keyboard reaches the stored form whichever
keyboard wrote it. It is search-side only; the stored bytes stay pristine.
So that the fold has a stable tag to key on, Persian is minted as `fas`
from the `-per*` URI suffix — never `per` — the catch that keeps a
Persian document from silently skipping the shared fold. The second
mechanism is the **timeline**: every OpenITI URI opens with the author's
four-digit hijrī death year, so each text lands on the calendar as a CE
terminus (the standard tabular conversion, round(AH × 0.970225 + 621.57)),
and `--from/--to` and `--century` scope the shelf by when its authors
died — Ḥāfiẓ, d. AH 792, resolves to 1390 CE.

The desk is deliberately honest about what it does not have. OpenITI is
**unannotated** — no morphology, no lemmas — so `--lemma`, `vocab` and
`formulas` do not apply here; the Arabist's instruments are full-text
search across the whole Islamicate shelf and the timeline, not the gold
lemma lanes the treebank desks lean on. The license is `nc`
(CC BY-NC-SA 4.0, the Zenodo record's only grant), which means the shelf
is MCP-excluded: the AI server never serves OpenITI passages; the CLI
reads them for local research. And the terminal is honest too — Arabic is
a connected script that a cell-grid terminal cannot fully join, so even
with iTerm2's RTL toggle on, what a reader sees is right-to-left, legible,
*unligatured* Arabic, fine for scanning citations and adequate to no more.
The whole library is staged and waiting on one command.
