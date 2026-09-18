---
title: "Layers, and the literary family"
date: 2026-09-18 06:00:00 +0000
description: >-
  The classification tree learns depth — literature becomes one family
  with poetry, narrative, drama and their siblings inside it — the
  unmapped worklist shrinks to a quarter of its size, and the site's
  three axis pages merge into one Layers page.
---

Four days after the classification axis went live, its class list got
its first structural lesson. The cuneiform catalogs label thousands of
tablets simply *Literary* — literature, no further claim — and the
original 26-head list had homes for poetry, narrative, drama, essay,
diary and wisdom, but none for their parent. Now it does, the natural
way: **`literary` is a family**, the six literature classes live
inside it (`literary/poetry`, `literary/narrative/epic`, …), and a
document upstream calls just "Literary" honestly carries the bare
family head. Any prefix matches its whole family in queries —
`--kind literary` finds all of it,
`--kind literary/narrative` narrows, and the same deepening works for
every class. The live board:
**{{ site.data.census.kind_class_count }} class families, every one
attested, {{ site.data.census.kind_documents_display }} documents
classified** ({{ site.data.census.kind_coverage_pct }}% of the
kind-eligible library, as of {{ site.data.kinds.as_of }}).

The same pass drained the curation worklist. A full audit of every
unmapped upstream label folded roughly a hundred more values —
Hittite catalog ranges resolved against the corpus's own sub-corpus
tags, the papyri's German documentary tail, stray prayers, curse
tablets and writing exercises that already had homes — and introduced
an honest new category: values **declared not-genre** (a
physical-layout tag, a bare copy marker), reviewed and folded to
nothing, with the reason on record. The worklist now opens by saying
what it is and what to do with a line, and what remains in it is a
quarter of what was there before, all of it genuinely undecided.

And the site learned the lesson a reader taught it: the three axis
pages — dates, places, kinds — told one story in three places. They
are now one [**Layers**]({{ '/layers/' | relative_url }}) page: the
shared doctrine first (every layer extracted, never guessed; honesty
buckets counted, never hidden; everything derived and rebuildable),
then *when*, *where* and *what kind* as sections that compose into
one query:

    nabu search lugal --place cigs:GIR --from -2200 --to -2000 --kind administrative

Old links redirect; nothing is lost but the repetition.
