---
title: "The instruments phase: meter, places, and asking your model"
date: 2026-07-24 22:30:00 +0000
description: >-
  Phase 44 builds instruments over the library: a metrical scansion
  layer for Latin and Greek verse, a place desk joined to the Pleiades
  gazetteer, twenty million tokens of silver-annotated Greek, Croatian
  Latin — and, for AI assistants, an eleventh MCP tool plus live-verified
  example questions on every desk page.
---

Not everything worth adding to a library is a text. This phase's theme
is the **instrument**: a registry row that mints no documents of its
own but makes the documents already held answer new kinds of
questions. The registry now distinguishes them honestly — 86 corpus
sources, 4 local shelves, and 8 feature modules.

The first new instrument is **meter**. Pedecerto (Udine/Ca' Foscari)
publishes machine-verified scansions of the Latin verse corpus —
227,791 hexameters and more — and David Chamberlain's Hypotactic does
the same for Greek. Both now attach to the library as an enrichment
layer: a scansion is a property of a passage the library already
holds, so it rides beside the canonical text rather than inside it,
and `nabu show` on a scanned line prints its meter, its
dactyl-spondee pattern, and its caesurae. The layer re-derives from
canonical bytes on every rebuild, and an unmatched line is censused,
never guessed. The machinery shipped this phase; the scansions attach
as each producer's first sync lands.

The second is **place**. The Pleiades gazetteer — 42,242 ancient
places with coordinates, types, and periods — now backs a place desk:
`nabu place Segesta` resolves the gazetteer card and counts the
library's holdings at that place, per source, joining on the Pleiades
ids the epigraphic corpora (I.Sicily, EDH, IIP, ItAnt) assert
upstream. Findspots print on `show` for inscriptions that carry them.
Nothing is ever fuzzy-matched: an id the upstream didn't assert is a
labelled text-mention, not a link.

The corpus itself grew two shelves. **GLAUx** brings ~20 million
tokens of Ancient Greek — the whole span from Homer to late antiquity
— automatically annotated for lemma, morphology, and syntax: 968,578
passages that make corpus-scale Greek lemma search real, every hit
labelled `[silver]` because machine annotation is not gold and the
library says so. **CroALa** adds Croatian Latin from 976 CE through
the neo-Latin centuries, the classical desk's medieval edge. And the
LiLa Lemma Bank (215,102 canonical Latin forms) now catches variant
spellings on the dictionary desk: `define lacryma` answers via
*lacrima* instead of missing.

The largest change faces the AI reader. The MCP server was audited
against the command line — a full parity table now lives in the
server documentation, with the gaps pinned rather than papered — and
gained its eleventh tool, `nabu_place`. Then every research desk got
a **user perspective**: each of the twenty axis pages now ends with
"Ask your model" — real questions, the tool calls that answer them,
and what actually came back. Every example was run live against this
library before it was written down, which is how the curation caught
its own lessons: Hittite must be asked syllabified (*ne-pi-ša-aš*),
Old Japanese romanized (*yama*), and a lemma search for *šarru*
resolves the logogram LUGAL straight to the Cyrus Cylinder.

Under the hood, syncing got safer: a fresh acquisition now stages in
a sibling directory and lands by one atomic rename, an interrupted
sync leaves no half-state behind, `sync --redownload` re-acquires a
source from scratch, and a per-source lock keeps two processes from
racing on one canonical tree. The library remains what it was — local,
license-honest, rebuildable — with better instruments on the desk.
